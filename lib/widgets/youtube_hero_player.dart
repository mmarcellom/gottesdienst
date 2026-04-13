import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;
import 'dart:async';
import 'dart:convert';

/// Custom YouTube player using a single iframe.
/// Supports play/pause, seek, speed control via postMessage API.
class YouTubeHeroPlayer extends StatefulWidget {
  final String videoId;
  final bool muted;
  final bool showCaptions;
  final String captionLang;
  final ValueChanged<bool>? onPlayingChanged;
  final ValueChanged<double>? onProgress;
  final ValueChanged<double>? onDuration;

  const YouTubeHeroPlayer({
    super.key,
    required this.videoId,
    this.muted = true,
    this.showCaptions = false,
    this.captionLang = 'de',
    this.onPlayingChanged,
    this.onProgress,
    this.onDuration,
  });

  @override
  State<YouTubeHeroPlayer> createState() => YouTubeHeroPlayerState();
}

class YouTubeHeroPlayerState extends State<YouTubeHeroPlayer> {
  late String _viewId;
  html.IFrameElement? _mainIframe;
  bool _isPlaying = false;
  bool _isPaused = false;
  Timer? _progressTimer;
  double _duration = 0;
  double _currentTime = 0;

  @override
  void initState() {
    super.initState();
    _viewId = 'yt-hero-${widget.videoId}-${DateTime.now().millisecondsSinceEpoch}';
    _registerView();
    // Listen for messages from YouTube iframe
    html.window.addEventListener('message', _onMessage);
  }

  @override
  void didUpdateWidget(YouTubeHeroPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _loadVideo(widget.videoId);
    }
    if (oldWidget.muted != widget.muted) {
      if (widget.muted) mute(); else unMute();
    }
    if (oldWidget.showCaptions != widget.showCaptions || oldWidget.captionLang != widget.captionLang) {
      setCaptions(widget.showCaptions, lang: widget.captionLang);
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    html.window.removeEventListener('message', _onMessage);
    super.dispose();
  }

  String _buildEmbedUrl(String videoId, {bool? showCaptions, String? captionLang}) {
    final ccPolicy = (showCaptions ?? widget.showCaptions) ? 1 : 0;
    final ccLang = captionLang ?? widget.captionLang;
    return 'https://www.youtube.com/embed/$videoId'
        '?autoplay=1'
        '&mute=1'
        '&controls=0'
        '&showinfo=0'
        '&rel=0'
        '&modestbranding=1'
        '&playsinline=1'
        '&enablejsapi=1'
        '&origin=${html.window.location.origin}'
        '&loop=1'
        '&playlist=$videoId'
        '&iv_load_policy=3'
        '&cc_load_policy=$ccPolicy'
        '&cc_lang_pref=$ccLang';
  }

  /// Enable/disable YouTube's native captions via postMessage
  void setCaptions(bool enabled, {String lang = 'de'}) {
    if (_mainIframe == null) return;
    // Use YouTube IFrame API to toggle captions module
    final cmd = enabled
        ? '{"event":"command","func":"loadModule","args":["captions"]}'
        : '{"event":"command","func":"unloadModule","args":["captions"]}';
    _mainIframe!.contentWindow?.postMessage(cmd, 'https://www.youtube.com');

    if (enabled) {
      // Set caption language
      Future.delayed(const Duration(milliseconds: 500), () {
        final setLang = '{"event":"command","func":"setOption","args":["captions","track",{"languageCode":"$lang"}]}';
        _mainIframe?.contentWindow?.postMessage(setLang, 'https://www.youtube.com');
      });
    }
  }

  void _registerView() {
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final embedUrl = _buildEmbedUrl(widget.videoId);

      final wrapper = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden'
        ..style.position = 'relative';

      wrapper.setAttribute('data-yt-wrapper', _viewId);

      _mainIframe = html.IFrameElement()
        ..src = embedUrl
        ..style.border = 'none'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '50%'
        ..style.transform = 'translateX(-50%)'
        ..style.width = '100vw'
        ..style.height = '56.25vw'
        ..style.minWidth = '100%'
        ..style.minHeight = '100%'
        ..style.pointerEvents = 'none'
        ..allow = 'autoplay; encrypted-media; picture-in-picture'
        ..allowFullscreen = false
        ..setAttribute('frameborder', '0');

      _mainIframe!.onLoad.listen((_) {
        _onIframeLoaded();
      });

      wrapper.append(_mainIframe!);
      return wrapper;
    });
  }

  void _onIframeLoaded() {
    // YouTube postMessage protocol: send "listening" to start receiving events
    // Then poll via postMessage commands
    js.context.callMethod('eval', ['''
      (function() {
        window._ytCT = 0;
        window._ytDUR = 0;
        window._ytST = -1;

        window.addEventListener("message", function(e) {
          try {
            var d;
            if (typeof e.data === "string") {
              if (e.data.indexOf("{") !== 0) return;
              d = JSON.parse(e.data);
            } else {
              d = e.data;
            }
            if (!d) return;
            if (d.event === "infoDelivery" && d.info) {
              if (typeof d.info.currentTime === "number") window._ytCT = d.info.currentTime;
              if (typeof d.info.duration === "number" && d.info.duration > 0) window._ytDUR = d.info.duration;
              if (typeof d.info.playerState === "number") window._ytST = d.info.playerState;
            }
          } catch(ex) {}
        });
      })();
    ''']);

    // Send listening command to iframe after it loads
    Future.delayed(const Duration(milliseconds: 1000), () {
      _sendListening();
    });
    Future.delayed(const Duration(milliseconds: 3000), () {
      _sendListening();
    });

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _readPlayerData();
    });

    // Dynamic cover-fit via ResizeObserver
    js.context.callMethod('eval', ['''
      (function() {
        var wrapper = document.querySelector('[data-yt-wrapper="$_viewId"]');
        if (!wrapper) return;
        var iframes = wrapper.querySelectorAll('iframe');
        var videoAspect = 16 / 9;
        function resize() {
          var w = wrapper.clientWidth;
          var h = wrapper.clientHeight;
          if (w <= 0 || h <= 0) return;
          var containerAspect = w / h;
          iframes.forEach(function(iframe) {
            if (containerAspect > videoAspect) {
              iframe.style.width = w + 'px';
              iframe.style.height = (w / videoAspect) + 'px';
            } else {
              iframe.style.height = h + 'px';
              iframe.style.width = (h * videoAspect) + 'px';
            }
          });
        }
        resize();
        new ResizeObserver(resize).observe(wrapper);
      })();
    ''']);

    // Mark as playing after short delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_isPlaying) {
        setState(() => _isPlaying = true);
        widget.onPlayingChanged?.call(true);
      }
    });
  }

  /// Read player data from JS global (set by the JS listener)
  void _readPlayerData() {
    try {
      final ct = (js.context['_ytCT'] as num?)?.toDouble() ?? 0;
      final dur = (js.context['_ytDUR'] as num?)?.toDouble() ?? 0;
      final state = (js.context['_ytST'] as num?)?.toInt() ?? -1;

      if (dur > 0 && dur != _duration) {
        _duration = dur;
        if (mounted) widget.onDuration?.call(_duration);
      }

      if (ct != _currentTime) {
        _currentTime = ct;
        if (_duration > 0 && mounted) {
          widget.onProgress?.call(ct / _duration);
        }
      }

      if (state == 1 && !_isPlaying) {
        _isPlaying = true;
        _isPaused = false;
        if (mounted) widget.onPlayingChanged?.call(true);
      } else if (state == 2 && !_isPaused) {
        _isPaused = true;
        _isPlaying = false;
        if (mounted) widget.onPlayingChanged?.call(false);
      }
    } catch (_) {}
  }

  /// Request current time and duration from YouTube player (legacy)
  void _requestPlayerInfo() {
    if (_mainIframe?.contentWindow == null) return;
    // Ask YouTube for current time
    _mainIframe!.contentWindow!.postMessage(
      '{"event":"command","func":"getCurrentTime","args":""}',
      '*',
    );
    _mainIframe!.contentWindow!.postMessage(
      '{"event":"command","func":"getDuration","args":""}',
      '*',
    );
    _mainIframe!.contentWindow!.postMessage(
      '{"event":"command","func":"getPlayerState","args":""}',
      '*',
    );
  }

  /// Handle messages from YouTube iframe
  void _onMessage(html.Event event) {
    if (event is! html.MessageEvent) return;
    final data = event.data;
    if (data == null) return;

    try {
      // YouTube sends data as JS object — convert via JSON roundtrip
      Map<String, dynamic>? info;
      if (data is String) {
        if (!data.startsWith('{')) return;
        info = jsonDecode(data) as Map<String, dynamic>?;
      } else {
        // JS object → JSON string → Dart Map
        final jsonStr = js.context.callMethod('eval', ['JSON.stringify(arguments[0])']);
        // Alternative: try direct property access
        try {
          final jsObj = data;
          final eventName = js.JsObject.fromBrowserObject(jsObj)['event'];
          if (eventName == 'infoDelivery') {
            final jsInfo = js.JsObject.fromBrowserObject(jsObj)['info'];
            if (jsInfo != null) {
              final infoObj = js.JsObject.fromBrowserObject(jsInfo);

              // Current time
              final ct = infoObj['currentTime'];
              if (ct != null) {
                _currentTime = (ct as num).toDouble();
                if (_duration > 0 && mounted) {
                  widget.onProgress?.call(_currentTime / _duration);
                }
              }

              // Duration
              final d = infoObj['duration'];
              if (d != null && (d as num).toDouble() > 0) {
                _duration = d.toDouble();
                if (mounted) widget.onDuration?.call(_duration);
              }

              // Player state
              final state = infoObj['playerState'];
              if (state != null) {
                final s = (state as num).toInt();
                if (s == 1 && !_isPlaying) {
                  _isPlaying = true;
                  _isPaused = false;
                  if (mounted) widget.onPlayingChanged?.call(true);
                } else if (s == 2) {
                  _isPaused = true;
                  _isPlaying = false;
                  if (mounted) widget.onPlayingChanged?.call(false);
                }
              }
            }
          }
        } catch (_) {}
        return;
      }
      if (info == null) return;

      // Fallback: parse from JSON string
      final eventName = info['event'];
      if (eventName == 'infoDelivery') {
        final infoData = info['info'];
        if (infoData is Map) {
          // Current time
          if (infoData.containsKey('currentTime')) {
            final ct = (infoData['currentTime'] as num?)?.toDouble() ?? 0;
            _currentTime = ct;
            if (_duration > 0 && mounted) {
              widget.onProgress?.call(ct / _duration);
            }
          }
          // Duration
          if (infoData.containsKey('duration')) {
            final d = (infoData['duration'] as num?)?.toDouble() ?? 0;
            if (d > 0 && d != _duration) {
              _duration = d;
              if (mounted) widget.onDuration?.call(d);
            }
          }
          // Player state: 1=playing, 2=paused, 0=ended
          if (infoData.containsKey('playerState')) {
            final state = infoData['playerState'] as int?;
            if (state == 1 && !_isPlaying) {
              _isPlaying = true;
              _isPaused = false;
              if (mounted) widget.onPlayingChanged?.call(true);
            } else if (state == 2) {
              _isPaused = true;
              _isPlaying = false;
              if (mounted) widget.onPlayingChanged?.call(false);
            }
          }
          // Playback rate
          if (infoData.containsKey('playbackRate')) {
            // Can be used to display current speed
          }
        }
      }
    } catch (_) {
      // Ignore non-JSON messages
    }
  }

  void _loadVideo(String videoId) {
    if (_mainIframe != null) {
      final embedUrl = _buildEmbedUrl(videoId);
      _mainIframe!.src = embedUrl;
      setState(() {
        _isPlaying = false;
        _isPaused = false;
        _currentTime = 0;
        _duration = 0;
      });
    }
  }

  void _postMessage(String command) {
    if (_mainIframe?.contentWindow != null) {
      _mainIframe!.contentWindow!.postMessage(
        '{"event":"command","func":"$command","args":""}',
        '*',
      );
    }
  }

  /// Tell YouTube iframe to start sending events
  void _sendListening() {
    if (_mainIframe?.contentWindow == null) return;
    _mainIframe!.contentWindow!.postMessage(
      '{"event":"listening","id":1,"channel":"widget"}',
      '*',
    );
  }

  // ─── Public API ───
  void mute() => _postMessage('mute');
  void unMute() => _postMessage('unMute');
  void play() => _postMessage('playVideo');
  void pause() => _postMessage('pauseVideo');

  void togglePlayPause() {
    if (_isPaused) {
      play();
      _isPaused = false;
      _isPlaying = true;
    } else {
      pause();
      _isPaused = true;
      _isPlaying = false;
    }
  }

  void seekTo(double seconds) {
    if (_mainIframe?.contentWindow != null) {
      _mainIframe!.contentWindow!.postMessage(
        '{"event":"command","func":"seekTo","args":[$seconds, true]}',
        '*',
      );
      _currentTime = seconds;
    }
  }

  void setPlaybackRate(double rate) {
    if (_mainIframe?.contentWindow != null) {
      _mainIframe!.contentWindow!.postMessage(
        '{"event":"command","func":"setPlaybackRate","args":[$rate]}',
        '*',
      );
    }
  }

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  double get duration => _duration;
  double get currentTime => _currentTime;

  // ─── Fullscreen ───
  static bool _pseudoFullscreen = false;
  static bool get isFullscreen =>
      _pseudoFullscreen || html.document.fullscreenElement != null;

  static void _installPseudoFsStyle() {
    if (html.document.getElementById('tertius-fs-style') != null) return;
    final style = html.StyleElement()
      ..id = 'tertius-fs-style'
      ..text = '''
        html.tertius-fs, html.tertius-fs body, html.tertius-fs flutter-view, html.tertius-fs flt-glass-pane {
          position: fixed !important; inset: 0 !important;
          width: 100vw !important; height: 100vh !important;
          margin: 0 !important; padding: 0 !important; overflow: hidden !important;
        }
        html.tertius-fs { background: #000 !important; }
      ''';
    html.document.head?.append(style);
  }

  static Future<void> enterFullscreen() async {
    final el = html.document.documentElement;
    if (el == null) return;
    try { await el.requestFullscreen(); } catch (_) {}
    try { js.context.callMethod('eval', ["try{screen.orientation.lock('landscape').catch(function(){});}catch(e){}"]); } catch (_) {}
    if (html.document.fullscreenElement == null) {
      _installPseudoFsStyle();
      el.classes.add('tertius-fs');
      _pseudoFullscreen = true;
    }
  }

  static Future<void> exitFullscreen() async {
    try { if (html.document.fullscreenElement != null) html.document.exitFullscreen(); } catch (_) {}
    try { js.context.callMethod('eval', ['try{if(screen.orientation&&screen.orientation.unlock)screen.orientation.unlock();}catch(e){}']); } catch (_) {}
    html.document.documentElement?.classes.remove('tertius-fs');
    _pseudoFullscreen = false;
  }

  static void toggleFullscreen() {
    if (isFullscreen) exitFullscreen(); else enterFullscreen();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
