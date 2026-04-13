import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tertius Design Tokens — Inter as base font (like SF Pro on iOS)
class TertiusTheme {
  TertiusTheme._();

  // ─── Colors ───
  static const Color bg = Color(0xFF1D2B3A);
  static const Color bgDeep = Color(0xFF151F2B);
  static const Color surface = Color(0xFF243447);
  static const Color surface2 = Color(0xFF2A3C52);
  static const Color border = Color(0xFF334863);

  // Brand
  static const Color yellow = Color(0xFFF5C518);
  static const Color yellowHover = Color(0xFFE3B616);
  static const Color yellowText = Color(0xFF1D2B3A);

  // Gray
  static const Color gray = Color(0xFF898989);
  static const Color grayLight = Color(0xFFEAEAEA);

  // Text
  static const Color text = Color(0xFFF2F2F2);
  static const Color textMid = Color(0xFFE0E0E0);
  static const Color textMuted = Color(0x59FFFFFF); // 35%
  static const Color textPlaceholder = Color(0x59FFFFFF);

  // Semantic
  static const Color live = Color(0xFFE05252);
  static const Color green = Color(0xFF52C07A);
  static const Color error = Color(0xFFE05252);

  // Cinema / video
  static const Color cinema = Colors.black;

  // Apple TV Player
  static const Color atvButtonBg = Color(0xB3323232);
  static const Color atvMenuBg = Color(0xE6252525);
  static const Color atvMenuSelected = Color(0xFF007AFF);
  static const Color atvTextSecondary = Color(0x99FFFFFF);

  // ─── Radii ───
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 28;

  // ─── Button ───
  static const double btnHeight = 52;

  // ─── Card Colors (for fan carousel) ───
  static const List<Color> cardColors = [
    Color(0xD18B5CF6), // purple
    Color(0xD1EC4899), // pink
    Color(0xD10EA5E9), // sky
    Color(0xD1F59E0B), // amber
    Color(0xD110B981), // emerald
    Color(0xD1DC2626), // red
  ];

  // ─── Theme Data ───
  static ThemeData get darkTheme {
    final base = ThemeData(brightness: Brightness.dark);
    final interTextTheme = GoogleFonts.interTextTheme(base.textTheme);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: const ColorScheme.dark(
        primary: yellow,
        secondary: yellow,
        surface: surface,
        error: error,
      ),
      textTheme: interTextTheme.copyWith(
        // Page Title — 30px w700
        displayLarge: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.8),
        // Card Title / Headline — 17px w600
        displayMedium: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.4),
        // Section heading — 28px w700
        headlineLarge: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.5),
        // Auth heading — 22px w600
        headlineMedium: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: text),
        // Title — 16px w600
        titleLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        titleMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: text),
        // Body — 13-16px
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: text),
        bodyMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: text),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: textMid),
        // Labels / Captions — 11px
        labelLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: yellowText),
        labelMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: text),
        labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: textMuted, letterSpacing: 0.1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        hintStyle: GoogleFonts.inter(color: const Color(0xFF3A4F62), fontWeight: FontWeight.w400, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
