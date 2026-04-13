import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/youtube_hero_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../models/video_item.dart';
import '../services/youtube_service.dart';
import '../services/transcription_service.dart';
import '../widgets/gradient_blur.dart';
import '../widgets/dom_glass_overlay.dart';
import '../widgets/transcript_overlay.dart';
import '../widgets/shimmer_card.dart';
import 'splash_screen.dart';
import 'roadmap_screen.dart';
import 'migration_plan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final _ytService = YouTubeService();
  final _txService = TranscriptionService();
  final _scrollController = ScrollController();

  List<VideoItem> _videos = [];
  int _currentIndex = 0;
  bool _loading = true;
  bool _muted = true;
  Timer? _rotateTimer;
  String _clockText = '';
  Timer? _clockTimer;

  // Immersive mode
  bool _immersive = false;
  bool _playerReady = false;
  double _progressFraction = 0.0;
  double _totalDuration = 0.0;
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;
  String? _skipFeedback;
  Timer? _skipFeedbackTimer;
  bool _seekbarExpanded = false;

  // Apple TV player UI
  static const bool _useAppleTVControls = true;
  bool _subtitleMenuOpen = false;
  bool _settingsMenuOpen = false;

  // Hero player key — changes to force rebuild when switching videos
  Key _heroPlayerKey = UniqueKey();
  final GlobalKey<YouTubeHeroPlayerState> _heroPlayerStateKey = GlobalKey();

  // UI state
  bool _logoutVisible = false;
  bool _searchOpen = false;
  double _playbackSpeed = 1.0;
  final _searchController = TextEditingController();

  // Video crossfade
  late AnimationController _fadeController;
  int? _pendingVideoIndex;
  bool _langMenuOpen = false;
  bool _audioLangMenuOpen = false;
  // Audio-language override for paired streams. When non-null, the hero player
  // plays this videoId instead of the current VideoItem's default videoId.
  String? _audioOverrideVideoId;
  String? _audioOverrideLang;

  // Available YouTube caption tracks for the currently playing video.
  // `null` = not yet loaded, `[]` = no captions available → hide translate UI.
  List<String>? _availableCaptionLangs;
  String? _captionsForVideoId;

  /// True when the user manually turned YouTube native captions off.
  /// Independent of our _txService to allow disabling auto-loaded YT captions.
  bool _ytCaptionsManuallyOff = false;
  int _tabIndex = 0;
  double _scrollOffset = 0.0;

  // Keyboard focus for ESC
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVideos();
    _txService.addListener(_onTranscriptUpdate);
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateClock());
    _scrollController.addListener(_onScroll);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && _pendingVideoIndex != null) {
        // Fade-in complete → swap video → fade-out
        setState(() => _currentIndex = _pendingVideoIndex!);
        _pendingVideoIndex = null;
        _initHeroPlayer();
        _fadeController.reverse();
      }
      if (status == AnimationStatus.dismissed) {
        if (!_immersive) _startRotation();
      }
    });
  }

  void _onScroll() {
    if (!mounted) return;
    final newOffset = _scrollController.offset;
    // Only rebuild if scroll changed significantly
    if ((newOffset - _scrollOffset).abs() > 2.0) {
      setState(() => _scrollOffset = newOffset);
    }
    // Sync glass overlays with current scroll offset
    DomGlassOverlay().onScroll(scrollOffset: newOffset);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotateTimer?.cancel();
    _controlsHideTimer?.cancel();
    _skipFeedbackTimer?.cancel();
    _clockTimer?.cancel();
    _txService.removeListener(_onTranscriptUpdate);
    _txService.stop();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _fadeController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    setState(() {
      _clockText = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    });
  }

  void _onTranscriptUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadVideos() async {
    final videos = await _ytService.fetchLatestVideos();
    if (mounted) {
      setState(() {
        _videos = videos;
        _loading = false;
      });
      _startRotation();
      // Auto-create player for hero video (muted)
      _initHeroPlayer();
    }
  }

  Future<void> _refreshVideos() async {
    try {
      final videos = await _ytService.fetchLatestVideos(forceRefresh: true);
      if (mounted) setState(() => _videos = videos);
    } catch (_) {}
  }

  void _startRotation() {
    _rotateTimer?.cancel();
    if (_immersive) return;
    _rotateTimer = Timer.periodic(
      const Duration(seconds: AppConstants.heroRotateIntervalSec),
      (_) {
        if (!_immersive && _videos.isNotEmpty) {
          final next = (_currentIndex + 1) % _videos.length;
          _selectVideo(next);
        }
      },
    );
  }

  void _selectVideo(int index, {bool quick = false}) {
    if (index == _currentIndex || _fadeController.isAnimating) return;
    _rotateTimer?.cancel();
    _pendingVideoIndex = index;
    // Quick transition for user taps, slow for auto-rotation
    _fadeController.duration = Duration(milliseconds: quick ? 400 : 1800);
    _fadeController.forward();
  }


  // ═══════════════════════════════════════════════════════
  //  HERO PLAYER (YouTube iframe — muted autoplay)
  // ═══════════════════════════════════════════════════════

  void _initHeroPlayer() {
    if (_videos.isEmpty) return;
    setState(() {
      _muted = true;
      _progressFraction = 0.0;
      _totalDuration = 0.0;
      _audioOverrideVideoId = null;
      _audioOverrideLang = null;
      _availableCaptionLangs = null;
      _captionsForVideoId = null;
      // NO UniqueKey — keep the iframe alive, just switch video inside it
    });
    _loadAvailableCaptions(_videos[_currentIndex].videoId);
  }

  /// Fetch the list of YouTube caption tracks available for the current video.
  /// Result drives which languages appear in the transcription target menu,
  /// and whether the transcription button is shown at all.
  Future<void> _loadAvailableCaptions(String videoId) async {
    if (_captionsForVideoId == videoId) return;
    _captionsForVideoId = videoId;
    if (mounted) setState(() => _availableCaptionLangs = null);
    try {
      final res = await http
          .get(Uri.parse('${AppConstants.baseUrl}/api/captions?videoId=$videoId'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final langs = (data['langs'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        if (mounted && _captionsForVideoId == videoId) {
          setState(() => _availableCaptionLangs = langs);
        }
      } else {
        if (mounted && _captionsForVideoId == videoId) {
          setState(() => _availableCaptionLangs = <String>[]);
        }
      }
    } catch (_) {
      if (mounted && _captionsForVideoId == videoId) {
        setState(() => _availableCaptionLangs = <String>[]);
      }
    }
  }

  /// Switch the audio language of the currently playing paired stream.
  /// Preserves playback position so the swap feels like a pure audio switch.
  void _switchAudioLang(String lang) {
    if (_videos.isEmpty) return;
    // TODO: re-enable when audioVariants API is deployed
    return;
    // ignore: dead_code
    final v = _videos[_currentIndex];
    final Map<String, String>? variants = null;
    if (variants == null || !variants.containsKey(lang)) return;
    final newVideoId = variants[lang]!;
    final currentActive = _audioOverrideVideoId ?? v.videoId;
    if (newVideoId == currentActive) return;
    final currentSec = _heroPlayerStateKey.currentState?.currentTime ?? 0;
    setState(() {
      _audioOverrideVideoId = newVideoId;
      _audioOverrideLang = lang;
      _audioLangMenuOpen = false;
    });
    // Captions belong to the new video → refresh the available list
    _loadAvailableCaptions(newVideoId);
    // Seek to the same position once the new video loaded
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (currentSec > 2) {
        _heroPlayerStateKey.currentState?.seekTo(currentSec);
      }
      // The iframe reloads with mute=1 in the URL — restore unmuted state
      // if the user is currently in immersive (audible) mode.
      if (!_muted) {
        _heroPlayerStateKey.currentState?.unMute();
      }
    });
    // Also fire an early unmute attempt in case the player is ready sooner
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (!_muted) _heroPlayerStateKey.currentState?.unMute();
    });
  }

  void _onHeroPlayingChanged(bool playing) {
    if (playing && mounted) {
      setState(() => _playerReady = true);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  IMMERSIVE MODE (unmute → UI slides away)
  // ═══════════════════════════════════════════════════════

  void _enterImmersive() {
    if (_videos.isEmpty) return;
    _rotateTimer?.cancel();

    // Unmute the already-playing video
    _heroPlayerStateKey.currentState?.unMute();
    // Hide DOM glass overlays
    DomGlassOverlay().hideAll();

    setState(() {
      _immersive = true;
      _muted = false;
      _controlsVisible = true;
    });

    WakelockPlus.enable();
    _startControlsAutoHide();
    _focusNode.requestFocus();
  }

  void _exitImmersive() {
    _controlsHideTimer?.cancel();

    // Mute but keep playing
    _heroPlayerStateKey.currentState?.mute();
    // Show DOM glass overlays again
    DomGlassOverlay().showAll();

    // Stop transcription
    _txService.stop();

    setState(() {
      _immersive = false;
      _muted = true;
      _controlsVisible = true;
      _langMenuOpen = false;
      _audioLangMenuOpen = false;
    });

    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _startRotation();
  }

  void _toggleMute() {
    if (_muted) {
      _enterImmersive();
    } else {
      _exitImmersive();
    }
  }

  void _toggleTranscription() {
    // If captions (YT or ours) are currently visible → turn them OFF.
    // Otherwise turn them back ON.
    final currentlyOn = _txService.isActive || !_ytCaptionsManuallyOff;
    if (currentlyOn) {
      if (_txService.isActive) _txService.stop();
      _ytCaptionsManuallyOff = true;
      // Ask the YouTube iframe to unload its captions module
      _heroPlayerStateKey.currentState?.setCaptions(false);
    } else {
      _ytCaptionsManuallyOff = false;
      if (_videos.isNotEmpty) {
        final video = _videos[_currentIndex];
        if (video.isLive) {
          _txService.startLive(video.videoId);
        } else {
          _txService.startVod(video.videoId);
        }
      }
      // Re-enable YT native captions as well
      _heroPlayerStateKey.currentState?.setCaptions(true, lang: _txService.targetLang);
    }
    setState(() {});
  }

  void _startControlsAutoHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _immersive) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _startControlsAutoHide();
  }

  void _seekTo(double fraction) {
    if (_totalDuration <= 0) return;
    final seconds = fraction * _totalDuration;
    _heroPlayerStateKey.currentState?.seekTo(seconds);
    setState(() => _progressFraction = fraction.clamp(0.0, 1.0));
  }

  void _skipSeconds(int seconds) {
    if (_totalDuration <= 0) return;
    final current = _progressFraction * _totalDuration;
    final target = (current + seconds).clamp(0.0, _totalDuration);
    _heroPlayerStateKey.currentState?.seekTo(target);
    setState(() {
      _progressFraction = (target / _totalDuration).clamp(0.0, 1.0);
      _skipFeedback = seconds > 0 ? '+${seconds}s' : '${seconds}s';
    });
    _skipFeedbackTimer?.cancel();
    _skipFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _skipFeedback = null);
    });
  }

  // ═══════════════════════════════════════════════════════
  //  KEYBOARD (ESC to exit immersive)
  // ═══════════════════════════════════════════════════════

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_immersive) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _exitImmersive();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      _heroPlayerStateKey.currentState?.togglePlayPause();
      setState(() {}); _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _skipSeconds(-10); _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _skipSeconds(10); _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      setState(() => _muted = !_muted);
      if (_muted) { _heroPlayerStateKey.currentState?.mute(); }
      else { _heroPlayerStateKey.currentState?.unMute(); }
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      YouTubeHeroPlayerState.toggleFullscreen();
      Future.delayed(const Duration(milliseconds: 150), () { if (mounted) setState(() {}); });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      _toggleTranscription(); _showControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final heroVideo = _videos.isNotEmpty ? _videos[_currentIndex] : null;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;

    return MouseRegion(
      onHover: (_) {
        if (_immersive && !_controlsVisible) _showControls();
      },
      child: GestureDetector(
        onTap: () {
          if (_logoutVisible || _searchOpen) {
            setState(() { _logoutVisible = false; _searchOpen = false; });
            DomGlassOverlay().onScroll(scrollOffset: _scrollOffset);
            Future.delayed(const Duration(milliseconds: 250), () {
              DomGlassOverlay().syncAll();
            });
          }
          if (_immersive) _showControls();
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
        children: [
          // ═══════════════════════════════════════════════
          //  HERO — Thumbnail in browse, Player in immersive
          // ═══════════════════════════════════════════════
          Positioned(
            top: _immersive ? 0 : -_scrollOffset * 0.2,
            left: 0,
            right: 0,
            height: screenH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail background — always visible, prevents gray screen on mobile
                // when the YouTube iframe is slow to load or blocked by the browser.
                if (heroVideo != null)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: 'https://img.youtube.com/vi/${heroVideo.videoId}/maxresdefault.jpg',
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 300),
                      placeholder: (_, __) => Container(color: Colors.black),
                      errorWidget: (_, __, ___) => CachedNetworkImage(
                        imageUrl: heroVideo.thumbnailUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.black),
                        errorWidget: (_, __, ___) => Container(color: Colors.black),
                      ),
                    ),
                  )
                else
                  Positioned.fill(child: Container(color: Colors.black)),

                // YouTube iframe player (muted autoplay) — overlaid on top of thumbnail
                if (heroVideo != null)
                  Positioned.fill(
                    child: YouTubeHeroPlayer(
                      key: _heroPlayerStateKey,
                      videoId: _audioOverrideVideoId ?? heroVideo.videoId,
                      muted: _muted,
                      showCaptions: _txService.isActive,
                      captionLang: _txService.targetLang,
                      onPlayingChanged: _onHeroPlayingChanged,
                      onProgress: (p) {
                        if (mounted) {
                          setState(() => _progressFraction = p);
                          if (_totalDuration > 0) {
                            _txService.updatePlaybackPosition(p * _totalDuration);
                          }
                        }
                      },
                      onDuration: (d) {
                        if (mounted) setState(() => _totalDuration = d);
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ── Cross dissolve overlay (only when animating) ──
          if (_fadeController.isAnimating || _fadeController.value > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fadeController,
                    curve: Curves.easeInOut,
                  ),
                  child: Container(color: Colors.black),
                ),
            ),
          ),

          // ═══════════════════════════════════════════════
          //  SCROLLABLE CONTENT (slides down in immersive)
          // ═══════════════════════════════════════════════
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            top: _immersive ? screenH + 50 : 0,
            left: 0,
            right: 0,
            bottom: _immersive ? -screenH : 0,
            child: IgnorePointer(
              ignoring: _immersive,
              child: RefreshIndicator(
                onRefresh: _refreshVideos,
                color: TertiusTheme.yellow,
                backgroundColor: TertiusTheme.surface,
                displacement: 80,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: screenH * 0.52 + 150)),

                    // ─── Glass Tray with BackdropFilter (blurs the thumbnail canvas behind) ───
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 25),
                          child: GlassSync(
                            overlayId: 'tray',
                            blur: 30,
                            borderRadius: 50,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(25, 30, 25, 30),
                              child: _loading
                                  ? const SizedBox(height: 114, width: 400, child: ShimmerCardRow())
                                  : _buildGlassTrayCards(),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ─── Dark blue gradient transition ───
                    SliverToBoxAdapter(
                      child: Container(
                        height: 75,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.0, 0.6, 1.0],
                            colors: [
                              Color(0x001D263B),
                              Color(0xBB1D263B),
                              Color(0xFF1D263B), // fully opaque at bottom
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Content area — fully opaque dark blue, no transparency
                    SliverToBoxAdapter(
                      child: Container(
                        color: const Color(0xFF1D263B),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildContentSection('Live in This Week', _videos, 200, 275),
                            const SizedBox(height: 49),
                            _buildContentSection('Recommended', _videos.reversed.toList(), 200, 275),
                          ],
                        ),
                      ),
                    ),
                    // Bottom spacer — same opaque dark blue
                    SliverToBoxAdapter(
                      child: Container(
                        height: 120,
                        color: const Color(0xFF1D263B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ═══════════════════════════════════════════════
          //  PLAY / MUTE BUTTON (centered in hero area)
          // ═══════════════════════════════════════════════
          // ═══════════════════════════════════════════════
          //  "TEILNEHMEN" BUTTON (browse) / MUTE BTN (immersive)
          // ═══════════════════════════════════════════════
          if (!_loading && _videos.isNotEmpty && !_immersive)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              top: screenH * 0.38,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: (1.0 - (_scrollOffset / 150).clamp(0.0, 1.0)),
                child: Center(
                  child: GestureDetector(
                    onTap: _enterImmersive,
                    child: GlassSync(
                      overlayId: 'btn',
                      blur: 30,
                      borderRadius: 30,
                      opacity: (1.0 - (_scrollOffset / 150).clamp(0.0, 1.0)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_filled_rounded,
                                color: Colors.white.withOpacity(0.9), size: 22),
                            const SizedBox(width: 10),
                            Text('Teilnehmen',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.95),
                                letterSpacing: 0.3,
                              )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ═══════════════════════════════════════════════
          //  HEADER PILL (slides up in immersive)
          // ═══════════════════════════════════════════════
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            top: _immersive ? -80 : 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Row(
                  children: [
                    // ─── Left: Navigation tabs ───
                    GlassSync(
                      overlayId: 'nav',
                      blur: 30,
                      borderRadius: 20,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildHeaderTabItem(0, 'Discover'),
                            _buildHeaderTabItem(1, 'Upcoming'),
                            _buildHeaderTabItem(2, 'Watchlist'),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // ─── Right: Clock + Profile ───
                    GlassSync(
                      overlayId: 'clock',
                      blur: 30,
                      borderRadius: 20,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() => _searchOpen = !_searchOpen);
                                  // Sync glass during animation
                                  DomGlassOverlay().onScroll(scrollOffset: _scrollOffset);
                                  Future.delayed(const Duration(milliseconds: 250), () {
                                    DomGlassOverlay().syncAll();
                                  });
                                },
                                child: SizedBox(
                                  width: 28, height: 28,
                                  child: Icon(Icons.search, size: 16, color: Colors.white.withOpacity(0.8)),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                child: _searchOpen
                                    ? SizedBox(
                                        width: 140,
                                        height: 28,
                                        child: Center(
                                          child: TextField(
                                            controller: _searchController,
                                            autofocus: true,
                                            textAlignVertical: TextAlignVertical.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.white,
                                              height: 1.0,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Suchen...',
                                              hintStyle: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: Colors.white.withOpacity(0.4),
                                                height: 1.0,
                                              ),
                                              border: InputBorder.none,
                                              contentPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
                                              isDense: true,
                                              isCollapsed: true,
                                              filled: false,
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(_clockText,
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.8),
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  )),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _logoutVisible = true);
                                  DomGlassOverlay().onScroll(scrollOffset: _scrollOffset);
                                  Future.delayed(const Duration(milliseconds: 250), () {
                                    DomGlassOverlay().syncAll();
                                  });
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(width: 28, height: 28,
                                      child: Icon(Icons.person_outline, size: 16, color: Colors.white.withOpacity(0.8))),
                                    AnimatedSize(
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      child: _logoutVisible
                                          ? Padding(
                                              padding: const EdgeInsets.only(left: 6),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Roadmap button
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() => _logoutVisible = false);
                                                      Navigator.push(context,
                                                        PageRouteBuilder(
                                                          pageBuilder: (_, __, ___) => const RoadmapScreen(),
                                                          transitionsBuilder: (_, a, __, child) =>
                                                            FadeTransition(opacity: a, child: child),
                                                          transitionDuration: const Duration(milliseconds: 300),
                                                        ),
                                                      );
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: TertiusTheme.yellow.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: TertiusTheme.yellow.withOpacity(0.25)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.map_outlined, size: 12, color: TertiusTheme.yellow.withOpacity(0.9)),
                                                          const SizedBox(width: 4),
                                                          Text('Roadmap',
                                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: TertiusTheme.yellow.withOpacity(0.9))),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  // Migration button
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() => _logoutVisible = false);
                                                      Navigator.push(context,
                                                        PageRouteBuilder(
                                                          pageBuilder: (_, __, ___) => const MigrationPlanScreen(),
                                                          transitionsBuilder: (_, a, __, child) =>
                                                            FadeTransition(opacity: a, child: child),
                                                          transitionDuration: const Duration(milliseconds: 300),
                                                        ),
                                                      );
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF4F7CFF).withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: const Color(0xFF4F7CFF).withOpacity(0.3)),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.swap_horiz_rounded, size: 12, color: const Color(0xFF4F7CFF).withOpacity(0.9)),
                                                          const SizedBox(width: 4),
                                                          Text('Migration',
                                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF4F7CFF).withOpacity(0.9))),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  // Logout button
                                                  GestureDetector(
                                                    onTap: () async {
                                                      await Supabase.instance.client.auth.signOut();
                                                      if (mounted) {
                                                        Navigator.of(context).pushAndRemoveUntil(
                                                          MaterialPageRoute(builder: (_) => const _LogoutRedirect()),
                                                          (_) => false,
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Text('Logout',
                                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9))),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ═══════════════════════════════════════════════
          //  IMMERSIVE CONTROLS (bottom bar + subtitles)
          // ═══════════════════════════════════════════════
          // ── Apple TV Player UI ──
          if (_immersive && _useAppleTVControls) ...[
            // Double-tap skip zones
            GestureDetector(
              onDoubleTapDown: (details) {
                final sw = screenW;
                if (details.globalPosition.dx < sw / 3) {
                  _skipSeconds(-10);
                } else if (details.globalPosition.dx > sw * 2 / 3) {
                  _skipSeconds(10);
                }
              },
              onDoubleTap: () {},
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),

            // Skip feedback
            if (_skipFeedback != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 140),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_skipFeedback!,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),

            // Top scrim
            Positioned(
              top: 0, left: 0, right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Center controls (Play/Pause + Skip)
            _buildATVCenterControls(),

            // Top bar (PiP, Volume, Close)
            _buildATVTopBar(),

            // Transcript overlay
            if (_txService.isActive && _txService.lines.isNotEmpty)
              Positioned(
                left: 0, right: 0, bottom: 110,
                child: TranscriptOverlay(
                  lines: _txService.lines,
                  statusText: _txService.statusText,
                  isActive: _txService.isActive,
                ),
              ),

            // Menu dismiss zone
            if (_subtitleMenuOpen || _audioLangMenuOpen || _settingsMenuOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _subtitleMenuOpen = false;
                    _audioLangMenuOpen = false;
                    _settingsMenuOpen = false;
                  }),
                  child: Container(color: Colors.transparent),
                ),
              ),

            // Dropdown menus — anchored bottom-right
            if (_subtitleMenuOpen)
              Positioned(bottom: 100, right: 16, child: _buildATVSubtitleMenu()),
            if (_audioLangMenuOpen && _videos.isNotEmpty && false /* hasLanguagePair — needs audioVariants API */)
              Positioned(bottom: 100, right: 60, child: _buildATVAudioMenu()),
            if (_settingsMenuOpen)
              Positioned(bottom: 100, right: 16, child: _buildATVSettingsMenu()),

            // Bottom bar (title + seekbar + icons)
            _buildATVBottomBar(),
          ]

          // ── Netflix-style controls (backup, disabled by flag) ──
          else if (_immersive) ...[
            // Double-tap skip zones
            GestureDetector(
              onDoubleTapDown: (details) {
                final sw = screenW;
                if (details.globalPosition.dx < sw / 3) {
                  _skipSeconds(-10);
                } else if (details.globalPosition.dx > sw * 2 / 3) {
                  _skipSeconds(10);
                }
              },
              onDoubleTap: () {},
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),

            // Skip feedback
            if (_skipFeedback != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_skipFeedback!,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                ),
              ),

            // ── Top scrim (subtle, for close button contrast) ──
            Positioned(
              top: 0, left: 0, right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Close button — top right only ──
            Positioned(
              top: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                      child: _controlIcon(Icons.close, onTap: _exitImmersive),
                    ),
                  ),
                ),
              ),
            ),

            // ── Language dropdown (anchored above bottom bar) ──
            if (_langMenuOpen)
              Positioned(
                bottom: 80, left: 12,
                child: _buildLanguageMenu(),
              ),

            // ── Audio-language dropdown ──
            if (_audioLangMenuOpen && _videos.isNotEmpty && false /* hasLanguagePair — needs audioVariants API */)
              Positioned(
                bottom: 80, left: 60,
                child: _buildAudioLangMenu(_videos[_currentIndex]),
              ),

            // ── Transcript overlay ──
            if (_txService.isActive && _txService.lines.isNotEmpty)
              Positioned(
                left: 0, right: 0, bottom: 90,
                child: TranscriptOverlay(
                  lines: _txService.lines,
                  statusText: _txService.statusText,
                  isActive: _txService.isActive,
                ),
              ),

            // ═══════════════════════════════════════════════
            //  UNIFIED BOTTOM CONTROL BAR (Netflix-style)
            // ═══════════════════════════════════════════════
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                          stops: const [0.0, 0.4],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Seekbar (full width, expands on touch)
                          _buildSeekableProgressBar(),
                          const SizedBox(height: 4),
                          // Controls row
                          Row(
                            children: [
                              // ── LEFT GROUP ──
                              // CC toggle
                              Tooltip(
                                message: (_availableCaptionLangs != null &&
                                        _availableCaptionLangs!.isEmpty)
                                    ? 'Derzeit noch keine automatisch erzeugten Untertitel vorhanden. YouTube stellt diese meist wenige Stunden nach dem Upload bereit.'
                                    : 'Untertitel ein-/ausschalten',
                                waitDuration: const Duration(milliseconds: 300),
                                textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Opacity(
                                  opacity: (_availableCaptionLangs != null &&
                                          _availableCaptionLangs!.isEmpty)
                                      ? 0.55
                                      : 1.0,
                                  child: _controlIcon(
                                    (_availableCaptionLangs != null &&
                                            _availableCaptionLangs!.isEmpty)
                                        ? Icons.subtitles_off_outlined
                                        : Icons.subtitles_outlined,
                                    active: !_ytCaptionsManuallyOff || _txService.isActive,
                                    onTap: _toggleTranscription,
                                  ),
                                ),
                              ),
                              // Audio language pill (if paired)
                              if (_videos.isNotEmpty &&
                                  false /* hasLanguagePair — needs audioVariants API */)
                                _buildAudioLangPill(_videos[_currentIndex]),
                              // Translate language selector
                              if (_availableCaptionLangs != null &&
                                  _availableCaptionLangs!.isNotEmpty)
                                _controlIcon(
                                  Icons.translate,
                                  onTap: () => setState(() => _langMenuOpen = !_langMenuOpen),
                                ),
                              // Mute
                              _controlIcon(
                                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                onTap: () {
                                  setState(() => _muted = !_muted);
                                  if (_muted) {
                                    _heroPlayerStateKey.currentState?.mute();
                                  } else {
                                    _heroPlayerStateKey.currentState?.unMute();
                                  }
                                },
                              ),

                              const Spacer(),

                              // ── CENTER: Play/Pause ──
                              _controlIcon(
                                (_heroPlayerStateKey.currentState?.isPaused ?? false)
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                onTap: () {
                                  _heroPlayerStateKey.currentState?.togglePlayPause();
                                  setState(() {});
                                },
                                size: 36,
                              ),

                              const Spacer(),

                              // ── RIGHT GROUP ──
                              // Time display
                              Text(
                                '${_formatTime(_progressFraction * _totalDuration)} / ${_formatTime(_totalDuration)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Speed
                              _buildSpeedSelector(),
                              const SizedBox(width: 4),
                              // Fullscreen
                              _controlIcon(
                                YouTubeHeroPlayerState.isFullscreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                onTap: () {
                                  YouTubeHeroPlayerState.toggleFullscreen();
                                  Future.delayed(const Duration(milliseconds: 150), () {
                                    if (mounted) setState(() {});
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  UI HELPERS
  // ═══════════════════════════════════════════════════════


  Widget _headerPillButton(IconData icon) {
    return SizedBox(
      width: 28, height: 28,
      child: Icon(icon, size: 16, color: Colors.white.withOpacity(0.8)),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final active = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? TertiusTheme.yellow : Colors.white.withOpacity(0.45)),
            const SizedBox(height: 2),
            Text(label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? TertiusTheme.yellow : Colors.white.withOpacity(0.45),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedSelector() {
    final speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
    return GestureDetector(
      onTap: () {
        final currentIdx = speeds.indexOf(_playbackSpeed);
        final nextIdx = (currentIdx + 1) % speeds.length;
        setState(() => _playbackSpeed = speeds[nextIdx]);
        _heroPlayerStateKey.currentState?.setPlaybackRate(_playbackSpeed);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
        ),
        child: Text(
          '${_playbackSpeed}x',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  /// Compact tab item for the header pill (text only, no icon)
  Widget _buildHeaderTabItem(int index, String label) {
    final active = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: active ? Colors.white.withOpacity(0.15) : Colors.transparent,
        ),
        child: Text(label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : Colors.white.withOpacity(0.55),
          )),
      ),
    );
  }

  Widget _buildGlassTrayCards() {
    final videos = _videos.take(6).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(videos.length, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < videos.length - 1 ? 16 : 0),
            child: _GlassTrayCard(
              video: videos[i],
              isActive: i == _currentIndex,
              onTap: () {
                _selectVideo(i, quick: true);
              },
            ),
          );
        }),
      ),
    );
  }

  /// Section with title + cards — both aligned to same left edge
  Widget _buildContentSection(String title, List<VideoItem> videos, double cardWidth, double cardHeight) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          _buildContentCards(videos: videos, cardWidth: cardWidth, cardHeight: cardHeight),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 0, 25, 12),
      child: Text(title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  Widget _buildContentCards({
    required List<VideoItem> videos,
    required double cardWidth,
    required double cardHeight,
  }) {
    if (_loading) {
      return SizedBox(height: cardHeight, child: const ShimmerCardRow());
    }

    return SizedBox(
      height: cardHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(videos.length * 2 - 1, (i) {
            if (i.isOdd) return const SizedBox(width: 30);
            final videoIndex = i ~/ 2;
            final video = videos[videoIndex];
            return _buildSingleCard(video, videoIndex, cardWidth, cardHeight);
          }),
        ),
      ),
    );
  }

  Widget _buildSingleCard(VideoItem video, int index, double cardWidth, double cardHeight) {
    return GestureDetector(
      onTap: () {
        _selectVideo(index < _videos.length ? index : 0, quick: true);
        _enterImmersive();
      },
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: 'https://img.youtube.com/vi/${video.videoId}/maxresdefault.jpg',
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: video.cardColor.withOpacity(0.2)),
                errorWidget: (_, __, ___) => Container(color: video.cardColor.withOpacity(0.3)),
              ),
              Positioned(
                left: 0, right: 0, bottom: 0, height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12, right: 12, bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(video.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(video.channelName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalCards({required List<VideoItem> videos}) {
    if (_loading) {
      return const SizedBox(height: 200, child: ShimmerCardRow());
    }

    return Column(
      children: List.generate(videos.length, (i) {
        final video = videos[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < videos.length - 1 ? 12 : 0),
          child: GestureDetector(
            onTap: () {
              _selectVideo(i < _videos.length ? i : 0, quick: true);
              _enterImmersive();
            },
            child: Container(
              width: double.infinity,
              height: 143, // minicard 114 * 1.25 = ~143
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: video.cardColor.withOpacity(0.2)),
                    errorWidget: (_, __, ___) => Container(color: video.cardColor.withOpacity(0.3)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, video.cardColor.withOpacity(0.7)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16, right: 16, bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(video.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 3),
                        Text(video.channelName,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHorizontalCards({
    required List<VideoItem> videos,
    required double cardWidth,
    required double cardHeight,
  }) {
    if (_loading) {
      return SizedBox(height: cardHeight, child: const ShimmerCardRow());
    }

    return SizedBox(
      height: cardHeight + 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final video = videos[i];
          return GestureDetector(
            onTap: () {
              _selectVideo(i < _videos.length ? i : 0, quick: true);
              _enterImmersive();
            },
            child: SizedBox(
              width: cardWidth,
              child: Container(
                width: cardWidth,
                height: cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: 'https://img.youtube.com/vi/${video.videoId}/sddefault.jpg',
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: video.cardColor.withOpacity(0.2)),
                      errorWidget: (_, __, ___) => Container(color: video.cardColor.withOpacity(0.3)),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, video.cardColor.withOpacity(0.7)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12, right: 12, bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(video.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(video.channelName,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _controlIcon(IconData icon, {VoidCallback? onTap, bool active = false, double size = 24}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          color: active ? TertiusTheme.yellow : Colors.white,
          size: size,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }

  /// Compact pill showing the currently active audio language for paired streams.
  /// Tap opens the audio-lang menu.
  Widget _buildAudioLangPill(VideoItem v) {
    // TODO: re-enable when audioVariants API is deployed
    return const SizedBox.shrink();
    // ignore: dead_code
    final activeLang =
        _audioOverrideLang ?? 'de';
    return GestureDetector(
      onTap: () => setState(() => _audioLangMenuOpen = !_audioLangMenuOpen),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              activeLang.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded,
                size: 16, color: Colors.white.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioLangMenu(VideoItem v) {
    // TODO: re-enable when audioVariants API is deployed
    return const SizedBox.shrink();
    // ignore: dead_code
    final variants = <String, String>{};
    final activeLang = _audioOverrideLang ?? 'de';
    const labels = {
      'de': 'Deutsch',
      'en': 'English',
      'ro': 'Română',
      'zu': 'isiZulu',
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withOpacity(0.72),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text(
                  'AUDIO',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.5),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ...variants.keys.map((lang) {
                final active = lang == activeLang;
                return GestureDetector(
                  onTap: () => _switchAudioLang(lang),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(lang.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: active ? TertiusTheme.yellow : Colors.white.withOpacity(0.6),
                            )),
                        ),
                        const SizedBox(width: 8),
                        Text(labels[lang] ?? lang,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: active ? Colors.white : Colors.white.withOpacity(0.7),
                          )),
                        if (active) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.check, size: 14, color: TertiusTheme.yellow),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageMenu() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withOpacity(0.7),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: TranscriptionService.availableLanguages
                .where((lang) =>
                    _availableCaptionLangs == null ||
                    _availableCaptionLangs!.contains(lang))
                .map((lang) {
              final active = _txService.targetLang == lang;
              return GestureDetector(
                onTap: () {
                  _txService.setLanguage(lang);
                  setState(() => _langMenuOpen = false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(lang.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: active ? TertiusTheme.yellow : Colors.white.withOpacity(0.6),
                          )),
                      ),
                      const SizedBox(width: 8),
                      Text(TranscriptionService.langLabel(lang),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: active ? Colors.white : Colors.white.withOpacity(0.7),
                        )),
                      if (active) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check, size: 14, color: TertiusTheme.yellow),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekableProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        final trackH = _seekbarExpanded ? 12.0 : 6.0;
        return MouseRegion(
          onEnter: (_) => setState(() => _seekbarExpanded = true),
          onExit: (_) => setState(() => _seekbarExpanded = false),
          child: GestureDetector(
            onTapDown: (d) {
              setState(() => _seekbarExpanded = true);
              _seekTo((d.localPosition.dx / barWidth).clamp(0.0, 1.0));
            },
            onHorizontalDragStart: (_) {
              setState(() => _seekbarExpanded = true);
              _controlsHideTimer?.cancel();
            },
            onHorizontalDragUpdate: (d) {
              _seekTo((d.localPosition.dx / barWidth).clamp(0.0, 1.0));
            },
            onHorizontalDragEnd: (_) {
              setState(() => _seekbarExpanded = false);
              _startControlsAutoHide();
            },
            child: Container(
              height: 40,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  // Background track
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    height: trackH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(trackH / 2),
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  // Progress fill
                  FractionallySizedBox(
                    widthFactor: _progressFraction.clamp(0.0, 1.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: trackH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(trackH / 2),
                        color: TertiusTheme.live,
                      ),
                    ),
                  ),
                  // Thumb — visible only on hover / touch
                  Positioned(
                    left: (barWidth * _progressFraction.clamp(0.0, 1.0)) - 8,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _seekbarExpanded ? 1.0 : 0.0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: TertiusTheme.live,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(double seconds) {
    if (seconds < 0) seconds = 0;
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    final s = (seconds % 60).floor();
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatRemainingTime(double current, double total) {
    final rem = total - current;
    if (rem <= 0) return '-0:00';
    final h = (rem / 3600).floor();
    final m = ((rem % 3600) / 60).floor();
    final s = (rem % 60).floor();
    if (h > 0) return '-$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '-$m:${s.toString().padLeft(2, '0')}';
  }

  // ─── Apple TV Helper: icon button ───
  Widget _atvIcon(IconData icon, {VoidCallback? onTap, double size = 22, double opacity = 0.8}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: Colors.white.withOpacity(opacity), size: size),
      ),
    );
  }

  // ─── Apple TV: Center Controls (Play/Pause + Skip ±10s) ───
  Widget _buildATVCenterControls() {
    final compact = MediaQuery.of(context).size.width < 600;
    final playSize = compact ? 64.0 : 80.0;
    final skipSize = compact ? 40.0 : 50.0;
    final playIconSize = compact ? 36.0 : 44.0;
    final skipIconSize = compact ? 22.0 : 28.0;
    return Center(
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Skip -10s
              GestureDetector(
                onTap: () { _skipSeconds(-10); _showControls(); },
                child: Container(
                  width: skipSize, height: skipSize,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TertiusTheme.atvButtonBg),
                  child: Icon(Icons.replay_10_rounded, size: skipIconSize, color: Colors.white),
                ),
              ),
              SizedBox(width: compact ? 28 : 40),
              // Play/Pause
              GestureDetector(
                onTap: () { _heroPlayerStateKey.currentState?.togglePlayPause(); setState(() {}); _showControls(); },
                child: Container(
                  width: playSize, height: playSize,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TertiusTheme.atvButtonBg),
                  child: Icon(
                    (_heroPlayerStateKey.currentState?.isPaused ?? false) ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: playIconSize, color: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: compact ? 28 : 40),
              // Skip +10s
              GestureDetector(
                onTap: () { _skipSeconds(10); _showControls(); },
                child: Container(
                  width: skipSize, height: skipSize,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TertiusTheme.atvButtonBg),
                  child: Icon(Icons.forward_10_rounded, size: skipIconSize, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Apple TV: Seekbar ───
  Widget _buildATVSeekbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        final trackH = _seekbarExpanded ? 6.0 : 3.0;
        final thumbSize = _seekbarExpanded ? 14.0 : 10.0;
        return MouseRegion(
          onEnter: (_) => setState(() => _seekbarExpanded = true),
          onExit: (_) => setState(() => _seekbarExpanded = false),
          child: GestureDetector(
            onTapDown: (d) {
              setState(() => _seekbarExpanded = true);
              _seekTo((d.localPosition.dx / barWidth).clamp(0.0, 1.0));
            },
            onHorizontalDragStart: (_) {
              setState(() => _seekbarExpanded = true);
              _controlsHideTimer?.cancel();
            },
            onHorizontalDragUpdate: (d) {
              _seekTo((d.localPosition.dx / barWidth).clamp(0.0, 1.0));
            },
            onHorizontalDragEnd: (_) {
              setState(() => _seekbarExpanded = false);
              _startControlsAutoHide();
            },
            child: Container(
              height: 32,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  // Background track
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    height: trackH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(trackH / 2),
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  // Progress fill
                  FractionallySizedBox(
                    widthFactor: _progressFraction.clamp(0.0, 1.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: trackH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(trackH / 2),
                        color: TertiusTheme.live,
                      ),
                    ),
                  ),
                  // Thumb — always visible
                  Positioned(
                    left: (barWidth * _progressFraction.clamp(0.0, 1.0)) - thumbSize / 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Apple TV: Bottom Bar ───
  Widget _buildATVBottomBar() {
    final v = _videos.isNotEmpty ? _videos[_currentIndex] : null;
    final current = _progressFraction * _totalDuration;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                  stops: const [0.0, 0.5],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: metadata left, icons right
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Title + year
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (v?.published != null)
                              Text(
                                v!.published!,
                                style: GoogleFonts.inter(fontSize: 13, color: TertiusTheme.atvTextSecondary),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              v?.title ?? '',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Right icons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Subtitles
                          _atvIcon(
                            (_ytCaptionsManuallyOff && !_txService.isActive)
                                ? Icons.subtitles_off_outlined
                                : Icons.subtitles_outlined,
                            onTap: () => setState(() {
                              _subtitleMenuOpen = !_subtitleMenuOpen;
                              _audioLangMenuOpen = false;
                              _settingsMenuOpen = false;
                            }),
                          ),
                          const SizedBox(width: 4),
                          // Audio / language (if paired)
                          if (v != null && false /* hasLanguagePair */)
                            _atvIcon(Icons.translate, onTap: () => setState(() {
                              _audioLangMenuOpen = !_audioLangMenuOpen;
                              _subtitleMenuOpen = false;
                              _settingsMenuOpen = false;
                            })),
                          const SizedBox(width: 4),
                          // Settings (speed)
                          _atvIcon(Icons.settings_outlined, onTap: () => setState(() {
                            _settingsMenuOpen = !_settingsMenuOpen;
                            _subtitleMenuOpen = false;
                            _audioLangMenuOpen = false;
                          })),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 2: time + seekbar + remaining time
                  Row(
                    children: [
                      Text(
                        _formatTime(current),
                        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7),
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _buildATVSeekbar()),
                      const SizedBox(width: 10),
                      Text(
                        _formatRemainingTime(current, _totalDuration),
                        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7),
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Apple TV: Top Bar ───
  Widget _buildATVTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: IgnorePointer(
          ignoring: !_controlsVisible,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Left: Fullscreen
                  // TODO Sprint 3: PiP + AirPlay when migrating to own video stream
                  // (cross-origin YouTube iframes block PiP/AirPlay JS APIs)
                  // Fullscreen toggle
                  _atvIcon(
                    YouTubeHeroPlayerState.isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onTap: () {
                      YouTubeHeroPlayerState.toggleFullscreen();
                      Future.delayed(const Duration(milliseconds: 150), () {
                        if (mounted) setState(() {});
                      });
                    },
                  ),
                  const Spacer(),
                  // Right: Volume + Close
                  _atvIcon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    onTap: () {
                      setState(() => _muted = !_muted);
                      if (_muted) { _heroPlayerStateKey.currentState?.mute(); }
                      else { _heroPlayerStateKey.currentState?.unMute(); }
                    },
                  ),
                  const SizedBox(width: 4),
                  _atvIcon(Icons.close, onTap: _exitImmersive),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Apple TV: Subtitle Menu ───
  Widget _buildATVSubtitleMenu() {
    final langs = _availableCaptionLangs ?? [];
    const labels = {'de': 'Deutsch', 'en': 'English', 'ru': 'Русский', 'zu': 'isiZulu', 'ro': 'Română'};
    final activeLang = AppConstants.defaultLanguage;
    final captionsOn = !_ytCaptionsManuallyOff || _txService.isActive;
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: TertiusTheme.atvMenuBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Untertitel', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: TertiusTheme.atvTextSecondary)),
          ),
          // On/Off toggle
          _atvMenuItem(
            label: captionsOn ? 'Ein' : 'Aus',
            selected: !captionsOn,
            onTap: () { _toggleTranscription(); setState(() => _subtitleMenuOpen = false); },
          ),
          if (captionsOn && langs.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 1),
            for (final lang in langs)
              _atvMenuItem(
                label: labels[lang] ?? lang.toUpperCase(),
                selected: activeLang == lang,
                onTap: () {
                  _txService.setLanguage(lang);
                  _heroPlayerStateKey.currentState?.setCaptions(true, lang: lang);
                  setState(() => _subtitleMenuOpen = false);
                },
              ),
          ],
        ],
      ),
    );
  }

  // ─── Apple TV: Audio Menu ───
  Widget _buildATVAudioMenu() {
    if (_videos.isEmpty) return const SizedBox.shrink();
    final v = _videos[_currentIndex];
    // TODO: re-enable when audioVariants API is deployed
    return const SizedBox.shrink();
    // ignore: dead_code
    final variants = <String, String>{};
    final activeLang = _audioOverrideLang ?? 'de';
    const labels = {'de': 'Deutsch', 'en': 'English', 'ro': 'Română', 'zu': 'isiZulu'};
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: TertiusTheme.atvMenuBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Audio', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: TertiusTheme.atvTextSecondary)),
          ),
          for (final lang in variants.keys)
            _atvMenuItem(
              label: labels[lang] ?? lang.toUpperCase(),
              selected: lang == activeLang,
              onTap: () { _switchAudioLang(lang); setState(() => _audioLangMenuOpen = false); },
            ),
        ],
      ),
    );
  }

  // ─── Apple TV: Settings / Speed Menu ───
  Widget _buildATVSettingsMenu() {
    final speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: TertiusTheme.atvMenuBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Geschwindigkeit', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: TertiusTheme.atvTextSecondary)),
          ),
          for (final speed in speeds)
            _atvMenuItem(
              label: '${speed}x',
              selected: _playbackSpeed == speed,
              onTap: () {
                setState(() { _playbackSpeed = speed; _settingsMenuOpen = false; });
                _heroPlayerStateKey.currentState?.setPlaybackRate(speed);
              },
            ),
        ],
      ),
    );
  }

  // ─── Apple TV: Menu Item ───
  Widget _atvMenuItem({required String label, required bool selected, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: selected ? TertiusTheme.atvMenuSelected.withOpacity(0.2) : Colors.transparent,
        child: Row(
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.check, size: 16, color: TertiusTheme.atvMenuSelected),
              ),
            Text(label, style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════
//  Glass Tray Mini-Card
// ═══════════════════════════════════════════════════════

class _GlassTrayCard extends StatefulWidget {
  final VideoItem video;
  final VoidCallback onTap;
  final bool isActive;

  const _GlassTrayCard({required this.video, required this.onTap, this.isActive = false});

  @override
  State<_GlassTrayCard> createState() => _GlassTrayCardState();
}

class _GlassTrayCardState extends State<_GlassTrayCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: (_isHovered || widget.isActive) ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 200,
            height: 114,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: (_isHovered || widget.isActive)
                  ? [
                      BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, spreadRadius: 2),
                      if (widget.isActive)
                        BoxShadow(color: TertiusTheme.yellow.withOpacity(0.25), blurRadius: 16, spreadRadius: -4),
                    ]
                  : [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail
                CachedNetworkImage(
                  imageUrl: widget.video.thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: widget.video.cardColor.withOpacity(0.3)),
                  errorWidget: (_, __, ___) => Container(color: widget.video.cardColor.withOpacity(0.3)),
                ),
                // Simple gradient — zero GPU cost
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  height: 65,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          TertiusTheme.bg.withOpacity(0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                // Text
                Positioned(
                  left: 10, right: 10, bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.video.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(widget.video.channelName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withOpacity(0.7))),
                    ],
                  ),
                ),
                // Clean border overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.black.withOpacity(0.4), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Redirect to splash after logout
class _LogoutRedirect extends StatelessWidget {
  const _LogoutRedirect();
  @override
  Widget build(BuildContext context) => const SplashScreen();
}
