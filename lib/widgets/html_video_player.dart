import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';

/// HTML5 Video Player — plays direct YouTube stream URLs.
///
/// Glass overlays are handled separately via HtmlGlass widgets.
/// This player only manages the <video> element.
class HtmlVideoPlayer extends StatefulWidget {
  final String? videoUrl;
  final String? posterUrl;
  final bool muted;
  final ValueChanged<bool>? onPlayingChanged;
  final ValueChanged<double>? onProgress;
  final ValueChanged<double>? onDuration;

  const HtmlVideoPlayer({
    super.key,
    this.videoUrl,
    this.posterUrl,
    this.muted = true,
    this.onPlayingChanged,
    this.onProgress,
    this.onDuration,
  });

  @override
  State<HtmlVideoPlayer> createState() => HtmlVideoPlayerState();
}

class HtmlVideoPlayerState extends State<HtmlVideoPlayer> {
  late String _viewId;
  html.VideoElement? _video;
  Timer? _progressTimer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'video-player-${DateTime.now().millisecondsSinceEpoch}';
    _registerView();
  }

  @override
  void didUpdateWidget(HtmlVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl && widget.videoUrl != null) {
      loadVideo(widget.videoUrl!);
    }
    if (oldWidget.muted != widget.muted) {
      if (widget.muted) mute(); else unMute();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _video?.pause();
    super.dispose();
  }

  void _registerView() {
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final wrapper = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden'
        ..style.position = 'relative'
        ..style.backgroundColor = '#000';

      _video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', '')
        ..setAttribute('webkit-playsinline', '')
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.setProperty('object-fit', 'cover')
        ..style.pointerEvents = 'none';

      if (widget.posterUrl != null) {
        _video!.poster = widget.posterUrl!;
      }
      if (widget.videoUrl != null) {
        _video!.src = widget.videoUrl!;
      }

      // Events
      _video!.onPlaying.listen((_) {
        if (!_isPlaying && mounted) {
          _isPlaying = true;
          widget.onPlayingChanged?.call(true);
        }
      });
      _video!.onPause.listen((_) {
        if (_isPlaying && mounted) {
          _isPlaying = false;
          widget.onPlayingChanged?.call(false);
        }
      });
      _video!.onLoadedMetadata.listen((_) {
        if (mounted) widget.onDuration?.call(_video!.duration.toDouble());
      });
      _video!.onEnded.listen((_) {
        if (mounted) {
          _isPlaying = false;
          widget.onPlayingChanged?.call(false);
        }
      });
      _video!.onError.listen((_) {
        debugPrint('[VideoPlayer] Error: ${_video?.error?.code}');
      });

      // Progress polling
      _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (_video != null && mounted && !_video!.paused) {
          final d = _video!.duration;
          if (d > 0 && !d.isNaN) {
            widget.onProgress?.call(_video!.currentTime / d);
          }
        }
      });

      wrapper.append(_video!);
      return wrapper;
    });
  }

  // ─── Public API ───
  void loadVideo(String url) {
    _video?.src = url;
    _video?.load();
    _video?.play();
    _isPlaying = false;
  }

  void play() => _video?.play();
  void pause() => _video?.pause();
  void mute() { if (_video != null) _video!.muted = true; }
  void unMute() { if (_video != null) _video!.muted = false; }
  void seekTo(double seconds) { if (_video != null) _video!.currentTime = seconds; }

  double get currentTime => _video?.currentTime.toDouble() ?? 0;
  double get duration => _video?.duration.toDouble() ?? 0;
  bool get isPlaying => _isPlaying;

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
