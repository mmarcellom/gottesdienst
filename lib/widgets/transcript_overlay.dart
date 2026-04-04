import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Transcription text overlay for cinema mode
/// Features: slide-up animation, auto-scroll, pulsing dot, pinch-to-zoom font size
class TranscriptOverlay extends StatefulWidget {
  final List<String> lines;
  final String statusText;
  final bool isActive;

  const TranscriptOverlay({
    super.key,
    required this.lines,
    required this.statusText,
    this.isActive = true,
  });

  @override
  State<TranscriptOverlay> createState() => _TranscriptOverlayState();
}

class _TranscriptOverlayState extends State<TranscriptOverlay>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  double _fontScale = 1.0;
  double _baseFontScale = 1.0;
  int _lastLineCount = 0;

  // Pulsing dot animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(TranscriptOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll when new lines appear
    if (widget.lines.length > _lastLineCount) {
      _lastLineCount = widget.lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseFontLarge = 20.0 * _fontScale;
    final baseFontSmall = 16.0 * _fontScale;

    return GestureDetector(
      onScaleStart: (_) {
        _baseFontScale = _fontScale;
      },
      onScaleUpdate: (details) {
        setState(() {
          _fontScale = (_baseFontScale * details.scale).clamp(0.6, 2.0);
        });
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
              Colors.black.withValues(alpha: 0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status line with pulsing dot
            if (widget.statusText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isActive)
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withValues(
                                  alpha: _pulseAnimation.value),
                            ),
                          );
                        },
                      ),
                    Flexible(
                      child: Text(
                        widget.statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Transcript lines with slide-up animation
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final isLatest = index == widget.lines.length - 1;
                  return _AnimatedTranscriptLine(
                    key: ValueKey('line_${widget.lines.length}_$index'),
                    text: widget.lines[index],
                    isLatest: isLatest,
                    fontSize: isLatest ? baseFontLarge : baseFontSmall,
                  );
                },
              ),
            ),

            if (widget.lines.isEmpty && widget.statusText.isNotEmpty)
              Text(
                'Warte auf Sprache...',
                style: GoogleFonts.playfairDisplay(
                  fontSize: baseFontSmall,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Individual transcript line that slides up when it first appears
class _AnimatedTranscriptLine extends StatefulWidget {
  final String text;
  final bool isLatest;
  final double fontSize;

  const _AnimatedTranscriptLine({
    super.key,
    required this.text,
    required this.isLatest,
    required this.fontSize,
  });

  @override
  State<_AnimatedTranscriptLine> createState() =>
      _AnimatedTranscriptLineState();
}

class _AnimatedTranscriptLineState extends State<_AnimatedTranscriptLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            widget.text,
            style: GoogleFonts.playfairDisplay(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w400,
              color: Colors.white
                  .withValues(alpha: widget.isLatest ? 1.0 : 0.4),
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}
