import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Direction of the blur gradient
enum GradientDirection {
  bottomToTop,
  topToBottom,
  leftToRight,
  rightToLeft,
}

/// Reusable gradient blur widget — stacks thin non-overlapping BackdropFilter
/// strips to simulate a smooth blur fade (since Flutter doesn't support
/// gradient masks on BackdropFilter natively).
///
/// Usage:
/// ```dart
/// GradientBlur(
///   maxBlur: 12.0,
///   slices: 25,
///   direction: GradientDirection.bottomToTop,
///   height: 60,
///   child: YourContent(),
/// )
/// ```
class GradientBlur extends StatelessWidget {
  /// Maximum blur sigma at the strong edge
  final double maxBlur;

  /// Minimum blur sigma at the fade edge (usually 0)
  final double minBlur;

  /// Number of slices — more = smoother but heavier on GPU
  /// Recommended: 15-30 for cards, 40-60 for large areas
  final int slices;

  /// Direction of blur: where it's strongest → where it fades out
  final GradientDirection direction;

  /// Size of the blur area (height for vertical, width for horizontal)
  final double size;

  /// Optional dark gradient overlay for text readability
  final double darkOverlayOpacity;

  /// Optional child widget rendered on top of the blur
  final Widget? child;

  const GradientBlur({
    super.key,
    this.maxBlur = 8.0,
    this.minBlur = 0.0,
    this.slices = 25,
    this.direction = GradientDirection.bottomToTop,
    this.size = 60,
    this.darkOverlayOpacity = 0.0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isVertical = direction == GradientDirection.bottomToTop ||
        direction == GradientDirection.topToBottom;
    final isReversed = direction == GradientDirection.topToBottom ||
        direction == GradientDirection.rightToLeft;

    final sliceSize = size / slices;
    final blurRange = maxBlur - minBlur;

    return SizedBox(
      width: isVertical ? double.infinity : size,
      height: isVertical ? size : double.infinity,
      child: Stack(
        children: [
          // Blur strips
          for (int s = 0; s < slices; s++)
            Positioned(
              left: isVertical ? 0 : (isReversed ? s * sliceSize : null),
              right: isVertical ? 0 : (isReversed ? null : s * sliceSize),
              top: !isVertical ? 0 : (isReversed ? s * sliceSize : null),
              bottom: !isVertical ? 0 : (isReversed ? null : s * sliceSize),
              width: isVertical ? null : sliceSize + 0.5, // +0.5 to avoid gaps
              height: isVertical ? sliceSize + 0.5 : null,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: minBlur + blurRange * ((slices - s) / slices),
                    sigmaY: minBlur + blurRange * ((slices - s) / slices),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),

          // Optional dark gradient overlay
          if (darkOverlayOpacity > 0)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: _gradientBegin,
                    end: _gradientEnd,
                    stops: const [0.0, 0.4, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(darkOverlayOpacity * 0.3),
                      Colors.black.withOpacity(darkOverlayOpacity),
                    ],
                  ),
                ),
              ),
            ),

          // Child content
          if (child != null) Positioned.fill(child: child!),
        ],
      ),
    );
  }

  Alignment get _gradientBegin {
    switch (direction) {
      case GradientDirection.bottomToTop:
        return Alignment.topCenter;
      case GradientDirection.topToBottom:
        return Alignment.bottomCenter;
      case GradientDirection.leftToRight:
        return Alignment.centerRight;
      case GradientDirection.rightToLeft:
        return Alignment.centerLeft;
    }
  }

  Alignment get _gradientEnd {
    switch (direction) {
      case GradientDirection.bottomToTop:
        return Alignment.bottomCenter;
      case GradientDirection.topToBottom:
        return Alignment.topCenter;
      case GradientDirection.leftToRight:
        return Alignment.centerLeft;
      case GradientDirection.rightToLeft:
        return Alignment.centerRight;
    }
  }
}
