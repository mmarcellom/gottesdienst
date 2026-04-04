import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tertius Design Tokens — matches the web CSS tokens exactly
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
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: yellow,
        secondary: yellow,
        surface: surface,
        error: error,
      ),
      textTheme: GoogleFonts.sourceSans3TextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 42, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.02 * 42),
          displayMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.02 * 36),
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.02 * 32),
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: text, letterSpacing: 0.02 * 28),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: text),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: text),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: text),
          bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: textMid),
          labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: yellowText),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: textMuted, letterSpacing: 0.15 * 11),
        ),
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
        hintStyle: const TextStyle(color: Color(0xFF3A4F62), fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
