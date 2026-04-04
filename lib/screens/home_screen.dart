import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../models/video_item.dart';
import '../services/youtube_service.dart';
import '../services/transcription_service.dart';
import '../widgets/fan_carousel.dart';
import '../widgets/transcript_overlay.dart';
import '../widgets/video_card_row.dart';
import '../widgets/shimmer_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _ytService = YouTubeService();
  final _txService = TranscriptionService();
  final _scrollController = ScrollController();

  List<VideoItem> _videos = [];
  int _currentIndex = 0;
  bool _cinemaMode = false;
  bool _loading = true;
  bool _muted = true;
  Timer? _rotateTimer;

  YoutubePlayerController? _playerController;
  Timer? _progressTimer;
  double _progressFraction = 0.0;
  double _totalDuration = 0.0;

  // Cinema mode controls visibility
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;

  // Double-tap skip feedback
  String? _skipFeedback;
  Timer? _skipFeedbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVideos();
    _txService.addListener(_onTranscriptUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotateTimer?.cancel();
    _progressTimer?.cancel();
    _controlsHideTimer?.cancel();
    _skipFeedbackTimer?.cancel();
    _txService.removeListener(_onTranscriptUpdate);
    _txService.stop();
    _playerController?.close();
    _scrollController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // Detect orientation changes for auto-cinema mode
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      final isLandscape = size.width > size.height;
      if (isLandscape && !_cinemaMode && _videos.isNotEmpty) {
        _enterCinemaMode();
      } else if (!isLandscape && _cinemaMode) {
        _exitCinemaMode();
      }
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
      _initPlayer(0);
      _startRotation();
    }
  }

  Future<void> _refreshVideos() async {
    try {
      final videos = await _ytService.fetchLatestVideos(forceRefresh: true);
      if (mounted) {
        setState(() {
          _videos = videos;
        });
      }
    } catch (_) {
      // RefreshIndicator handles its own loading state
    }
  }

  void _initPlayer(int index) {
    if (_videos.isEmpty) return;
    final video = _videos[index];

    _playerController?.close();
    _playerController = YoutubePlayerController.fromVideoId(
      videoId: video.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: true,
        showControls: false,
        showFullscreenButton: false,
        loop: true,
        playsInline: true,
        enableJavaScript: true,
      ),
    );

    setState(() {
      _currentIndex = index;
      _muted = true;
      _progressFraction = 0.0;
      _totalDuration = 0.0;
    });
    _startProgressPolling();
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_playerController == null || !mounted) return;
      try {
        final current = await _playerController!.currentTime;
        final duration = await _playerController!.duration;
        if (duration > 0 && mounted) {
          setState(() {
            _progressFraction = (current / duration).clamp(0.0, 1.0);
            _totalDuration = duration;
          });
        }
      } catch (_) {}
    });
  }

  void _startRotation() {
    _rotateTimer?.cancel();
    if (_cinemaMode) return;
    _rotateTimer = Timer.periodic(
      const Duration(seconds: AppConstants.heroRotateIntervalSec),
      (_) {
        if (!_cinemaMode && _videos.isNotEmpty) {
          final next = (_currentIndex + 1) % _videos.length;
          _initPlayer(next);
        }
      },
    );
  }

  void _selectVideo(int index) {
    _rotateTimer?.cancel();
    _initPlayer(index);
    if (!_cinemaMode) _startRotation();
  }

  void _toggleMute() {
    if (_playerController == null) return;
    setState(() { _muted = !_muted; });
    if (_muted) {
      _playerController!.mute();
    } else {
      _playerController!.unMute();
    }
  }

  void _enterCinemaMode() {
    _rotateTimer?.cancel();
    setState(() {
      _cinemaMode = true;
      _controlsVisible = true;
    });
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_muted) _toggleMute();
    _startControlsAutoHide();
  }

  void _exitCinemaMode() {
    _progressTimer?.cancel();
    _controlsHideTimer?.cancel();
    setState(() {
      _cinemaMode = false;
      _progressFraction = 0.0;
      _controlsVisible = true;
    });
    _txService.stop();
    _updateWakeLock();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _startRotation();
  }

  void _toggleTranscription() {
    if (_txService.isActive) {
      _txService.stop();
    } else if (_videos.isNotEmpty) {
      _txService.start(_videos[_currentIndex].videoId);
    }
    _updateWakeLock();
    setState(() {});
  }

  /// Keep screen on during cinema mode OR active transcription
  void _updateWakeLock() {
    if (_cinemaMode || _txService.isActive) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  // ─── Cinema Controls Auto-Hide ───

  void _startControlsAutoHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _cinemaMode) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startControlsAutoHide();
    }
  }

  // ─── Seek / Skip ───

  Future<void> _seekTo(double fraction) async {
    if (_playerController == null || _totalDuration <= 0) return;
    final targetSeconds = fraction * _totalDuration;
    await _playerController!.seekTo(seconds: targetSeconds, allowSeekAhead: true);
    setState(() => _progressFraction = fraction.clamp(0.0, 1.0));
  }

  Future<void> _skipSeconds(int seconds) async {
    if (_playerController == null) return;
    try {
      final current = await _playerController!.currentTime;
      final target = (current + seconds).clamp(0.0, _totalDuration);
      await _playerController!.seekTo(seconds: target, allowSeekAhead: true);

      setState(() {
        _skipFeedback = seconds > 0 ? '+${seconds}s' : '${seconds}s';
      });
      _skipFeedbackTimer?.cancel();
      _skipFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _skipFeedback = null);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_cinemaMode) return _buildCinemaMode();
    return _buildDiscoverMode();
  }

  // ─── Discover Mode (normal browsing) ───
  Widget _buildDiscoverMode() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fixed video hero background
          if (_playerController != null)
            Positioned.fill(
              child: YoutubePlayer(controller: _playerController!),
            ),

          // Gradient overlay
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: MediaQuery.of(context).size.height * 0.5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.15, 0.3, 0.45, 0.55, 0.65, 0.75, 0.85, 1.0],
                  colors: [
                    Color(0x00000000),
                    Color(0x05000000),
                    Color(0x0F000000),
                    Color(0x24000000),
                    Color(0x47000000),
                    Color(0x73000000),
                    Color(0x9E000000),
                    Color(0xD1000000),
                    Color(0xF2000000),
                  ],
                ),
              ),
            ),
          ),

          // Pull-to-refresh + scrollable content
          RefreshIndicator(
            onRefresh: _refreshVideos,
            color: TertiusTheme.yellow,
            backgroundColor: TertiusTheme.surface,
            displacement: 80,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          Text(
                            'TERTIUS',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 18,
                              color: TertiusTheme.text,
                              letterSpacing: 18 * 0.05,
                            ),
                          ),
                          const Spacer(),
                          // Live badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: TertiusTheme.live.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6, height: 6,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TertiusTheme.live),
                                ),
                                const SizedBox(width: 6),
                                Text('LIVE', style: TextStyle(fontSize: 10, color: TertiusTheme.live, letterSpacing: 1, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Spacer to show video behind
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(context).size.height * 0.55),
                ),

                // Unmute + Cinema button
                SliverToBoxAdapter(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCircleButton(
                          icon: _muted ? Icons.volume_off : Icons.volume_up,
                          onTap: _toggleMute,
                        ),
                        const SizedBox(width: 16),
                        _buildCircleButton(
                          icon: Icons.fullscreen,
                          onTap: _enterCinemaMode,
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 30)),

                // Card 1: Now Streaming (Fan Carousel) with shimmer loading
                SliverToBoxAdapter(
                  child: _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('NOW STREAMING'),
                        const SizedBox(height: 12),
                        _loading
                            ? const ShimmerCardRow()
                            : FanCarousel(
                                videos: _videos.take(6).toList(),
                                currentIndex: _currentIndex,
                                onSelect: _selectVideo,
                              ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Card 2: Recent Messages with shimmer loading
                SliverToBoxAdapter(
                  child: _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('LETZTE BOTSCHAFTEN'),
                        const SizedBox(height: 12),
                        _loading
                            ? const ShimmerVideoRow()
                            : (_videos.length > 6
                                ? VideoCardRow(videos: _videos.sublist(6))
                                : VideoCardRow(videos: _videos)),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cinema Mode (fullscreen video + transcription) ───
  Widget _buildCinemaMode() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Tap to toggle controls
        onTap: _toggleControlsVisibility,
        // Double-tap left/right to skip 10 seconds
        onDoubleTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _skipSeconds(-10);
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            _skipSeconds(10);
          }
        },
        onDoubleTap: () {}, // Required for onDoubleTapDown to fire
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Fullscreen video
            if (_playerController != null)
              Positioned.fill(
                child: YoutubePlayer(controller: _playerController!),
              ),

            // Skip feedback overlay
            if (_skipFeedback != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _skipFeedback!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

            // Controls overlay with fade animation
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Positioned(
                  top: 0, left: 0, right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          // Transcribe button
                          _buildCinemaButton(
                            icon: Icons.chat_bubble_outline,
                            active: _txService.isActive,
                            onTap: _toggleTranscription,
                          ),
                          const SizedBox(width: 8),

                          // Language selector
                          if (_txService.isActive) ...[
                            _buildLangButton('DE'),
                            const SizedBox(width: 4),
                            _buildLangButton('EN'),
                            const SizedBox(width: 4),
                            _buildLangButton('ZU'),
                          ],

                          const Spacer(),

                          // Mute button
                          _buildCinemaButton(
                            icon: _muted ? Icons.volume_off : Icons.volume_up,
                            onTap: _toggleMute,
                          ),
                          const SizedBox(width: 8),

                          // Close button
                          GestureDetector(
                            onTap: _exitCinemaMode,
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Transcript overlay at bottom
            if (_txService.isActive)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: TranscriptOverlay(
                  lines: _txService.lines,
                  statusText: _txService.statusText,
                  isActive: _txService.isActive,
                ),
              ),

            // Bottom seekable progress bar
            Positioned(
              left: 20, right: 20, bottom: _txService.isActive ? 140 : 40,
              child: _buildSeekableProgressBar(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI Helpers ───

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 28),
      ),
    );
  }

  Widget _buildCinemaButton({required IconData icon, VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active ? TertiusTheme.yellow.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: active ? TertiusTheme.yellowText : Colors.white, size: 20),
      ),
    );
  }

  Widget _buildLangButton(String lang) {
    final isActive = _txService.targetLang == lang.toLowerCase();
    return GestureDetector(
      onTap: () => _txService.setLanguage(lang.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isActive ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
          border: Border.all(color: Colors.white.withValues(alpha: isActive ? 0.4 : 0.15)),
        ),
        child: Text(
          lang,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSeekableProgressBar() {
    return GestureDetector(
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        // Calculate progress bar area (20px padding on each side)
        final barWidth = MediaQuery.of(context).size.width - 40;
        final localX = details.localPosition.dx;
        final fraction = (localX / barWidth).clamp(0.0, 1.0);
        _seekTo(fraction);
      },
      onHorizontalDragUpdate: (details) {
        final barWidth = MediaQuery.of(context).size.width - 40;
        final localX = details.localPosition.dx;
        final fraction = (localX / barWidth).clamp(0.0, 1.0);
        _seekTo(fraction);
      },
      child: Container(
        height: 24, // Enlarged hit area
        alignment: Alignment.center,
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _progressFraction,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: TertiusTheme.yellow,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.45),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, -4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 11 * 0.15,
        color: TertiusTheme.textMuted,
      ),
    );
  }
}
