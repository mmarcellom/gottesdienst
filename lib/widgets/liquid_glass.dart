import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Apple-style frosted glass container.
/// Uses a pre-made frosted glass texture (asset) with blur overlay.
class LiquidGlassContainer extends StatelessWidget {
  final double blurSigma;
  final Color tint;
  final double cornerRadius;
  final double borderOpacity;
  final Widget child;

  // Kept for backward compat — ignored, always uses asset
  final String? imageUrl;

  const LiquidGlassContainer({
    super.key,
    this.imageUrl,
    this.blurSigma = 18.0,
    this.tint = const Color(0x1FFFFFFF),
    this.cornerRadius = 32,
    this.borderOpacity = 0.25,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: Stack(
        children: [
          // Frosted glass texture from asset
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: Image.asset(
                'assets/frosted_glass.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Tint + border overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: tint,
                border: Border.all(
                  color: Colors.white.withOpacity(borderOpacity),
                  width: 0.5,
                ),
              ),
            ),
          ),

          // Content
          child,
        ],
      ),
    );
  }
}
