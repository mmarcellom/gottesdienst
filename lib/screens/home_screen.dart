import 'dart:async';
import 'dart:ui' as ui;
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
      // NO UniqueKey — keep the iframe alive, just switch video inside it
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
    if (_txService.isActive) {
      _txService.stop();
    } else if (_videos.isNotEmpty) {
      // TODO: detect if video is live → use startLive instead
      _txService.startVod(_videos[_currentIndex].videoId);
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
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      if (_immersive) {
        _exitImmersive();
        return KeyEventResult.handled;
      }
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
                // YouTube iframe player (muted autoplay)
                if (heroVideo != null)
                  Positioned.fill(
                    child: YouTubeHeroPlayer(
                      key: _heroPlayerStateKey,
                      videoId: heroVideo.videoId,
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
          if (_immersive) ...[
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

            // Top controls (close, transcription, language)
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          // Close / ESC
                          _immersiveBtn(Icons.close, onTap: _exitImmersive),
                          const Spacer(),
                          // Transcription toggle
                          _immersiveBtn(
                            Icons.subtitles_outlined,
                            active: _txService.isActive,
                            onTap: _toggleTranscription,
                          ),
                          const SizedBox(width: 8),
                          // Language selector
                          _immersiveBtn(
                            Icons.translate,
                            onTap: () => setState(() => _langMenuOpen = !_langMenuOpen),
                          ),
                          const SizedBox(width: 8),
                          // Mute in immersive
                          _immersiveBtn(
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Language dropdown
            if (_langMenuOpen)
              Positioned(
                top: 70, right: 80,
                child: SafeArea(
                  child: _buildLanguageMenu(),
                ),
              ),

            // Transcript overlay — only when we have our own lines (RTMP/Whisper)
            // YouTube native CC is rendered inside the iframe, no overlay needed
            if (_txService.isActive && _txService.lines.isNotEmpty)
              Positioned(
                left: 0, right: 0, bottom: 60,
                child: TranscriptOverlay(
                  lines: _txService.lines,
                  statusText: _txService.statusText,
                  isActive: _txService.isActive,
                ),
              ),

            // Bottom controls: play/pause + seekbar + time + speed
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Seekbar
                        _buildSeekableProgressBar(),
                        const SizedBox(height: 8),
                        // Controls row
                        Row(
                          children: [
                            // Play/Pause
                            GestureDetector(
                              onTap: () {
                                _heroPlayerStateKey.currentState?.togglePlayPause();
                                setState(() {});
                              },
                              child: Icon(
                                (_heroPlayerStateKey.currentState?.isPaused ?? false)
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: Colors.white, size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Time
                            Text(
                              '${_formatTime(_progressFraction * _totalDuration)} / ${_formatTime(_totalDuration)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const Spacer(),
                            // Speed selector
                            _buildSpeedSelector(),
                          ],
                        ),
                      ],
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
        // Cycle through speeds
        final currentIdx = speeds.indexOf(_playbackSpeed);
        final nextIdx = (currentIdx + 1) % speeds.length;
        setState(() => _playbackSpeed = speeds[nextIdx]);
        _heroPlayerStateKey.currentState?.setPlaybackRate(_playbackSpeed);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withOpacity(0.15),
        ),
        child: Text(
          '${_playbackSpeed}x',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
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
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(videos.length * 2 - 1, (i) {
                if (i.isOdd) return const SizedBox(width: 30);
                final videoIndex = i ~/ 2;
                final video = videos[videoIndex];
                return _buildSingleCard(video, videoIndex, cardWidth, cardHeight);
              }),
          ),
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

  Widget _immersiveBtn(IconData icon, {VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.12),
          border: Border.all(
            color: active ? TertiusTheme.yellow.withOpacity(0.6) : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Icon(icon, color: active ? TertiusTheme.yellow : Colors.white, size: 20),
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
            children: TranscriptionService.availableLanguages.map((lang) {
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
        return GestureDetector(
          onTapDown: (details) {
            _seekTo((details.localPosition.dx / barWidth).clamp(0.0, 1.0));
          },
          onHorizontalDragUpdate: (details) {
            _seekTo((details.localPosition.dx / barWidth).clamp(0.0, 1.0));
          },
          child: Container(
            height: 32,
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
                // Progress fill
                FractionallySizedBox(
                  widthFactor: _progressFraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: TertiusTheme.live,
                    ),
                  ),
                ),
                // Dot at current position
                Positioned(
                  left: (barWidth * _progressFraction.clamp(0.0, 1.0)) - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(double seconds) {
    final m = (seconds / 60).floor();
    final s = (seconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
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
