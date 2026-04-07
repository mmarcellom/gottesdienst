import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _flightController;
  late AnimationController _fadeController;
  late Animation<Offset> _flightXAnim;
  late Animation<Offset> _flightYAnim;
  late Animation<double> _craneFadeAnim;
  late Animation<double> _craneScaleAnim;
  late Animation<double> _craneBlurAnim;
  late Animation<double> _titleFadeAnim;
  late Animation<double> _subtitleFadeAnim;
  late Animation<double> _buttonsFadeAnim;

  @override
  void initState() {
    super.initState();

    _flightController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

    // Diagonal flight from top-left corner
    _flightXAnim = Tween<Offset>(begin: const Offset(-1.5, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _flightController, curve: Curves.decelerate));
    _flightYAnim = Tween<Offset>(begin: const Offset(0, -2.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _flightController, curve: Curves.easeOutCubic));
    _craneFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _flightController, curve: const Interval(0, 0.3, curve: Curves.easeIn)));
    _craneScaleAnim = Tween<double>(begin: 0.4, end: 1).animate(
        CurvedAnimation(parent: _flightController, curve: Curves.easeOutCubic));
    // Blur: starts at 5.0, clears quickly — sharp by 50% of flight
    _craneBlurAnim = Tween<double>(begin: 5.0, end: 0.0).animate(
        CurvedAnimation(parent: _flightController, curve: const Interval(0, 0.5, curve: Curves.easeOut)));

    _titleFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeController, curve: const Interval(0.47, 0.72, curve: Curves.easeIn)));
    _subtitleFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeController, curve: const Interval(0.53, 0.78, curve: Curves.easeIn)));
    _buttonsFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeController, curve: const Interval(0.75, 1.0, curve: Curves.easeIn)));

    _flightController.forward();
    _fadeController.forward();

    // If user is already logged in, skip to home
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && mounted) {
      // Small delay so splash is briefly visible
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
          (_) => false,
        );
      }
    }
  }

  void _navigateToAuth({required bool isSignIn}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => AuthScreen(isSignIn: isSignIn),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _flightController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    // Responsive font sizes matching Paper specs
    final titleSize = isDesktop ? 84.0 : 54.0;
    final craneW = isDesktop ? 320.0 : 180.0;
    final craneH = isDesktop ? 155.0 : 88.0;
    final subtitleFontSize = isDesktop ? 16.0 : 9.0;
    final waveBarW = isDesktop ? 3.0 : 2.0;
    final waveBarH = isDesktop ? 20.0 : 14.0;

    return Scaffold(
      backgroundColor: TertiusTheme.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // ─── Logo Group (crane + title + subtitle) ───
            // ─── Crane Animation ───
            AnimatedBuilder(
              animation: _flightController,
              builder: (context, child) {
                final blur = _craneBlurAnim.value;
                return Transform.translate(
                  offset: Offset(
                    _flightXAnim.value.dx * MediaQuery.of(context).size.width * 0.4,
                    _flightYAnim.value.dy * MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: Transform.scale(
                    scale: _craneScaleAnim.value,
                    child: Opacity(
                      opacity: _craneFadeAnim.value,
                      child: blur > 0.1
                          ? ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: blur,
                                sigmaY: blur,
                                tileMode: TileMode.decal,
                              ),
                              child: child,
                            )
                          : child,
                    ),
                  ),
                );
              },
              child: SizedBox(width: craneW, height: craneH, child: _buildCraneSvg()),
            ),

            SizedBox(height: isDesktop ? 16 : 16),

            // ─── Title: TĒRTIUS — Rokkitt (Google Fonts equivalent of Rockwell) ───
            FadeTransition(
              opacity: _titleFadeAnim,
              child: Text(
                'T\u0112RTIUS',
                style: GoogleFonts.rokkitt(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFF2F2F2),
                  letterSpacing: titleSize * 0.07,
                  height: 0.85,
                ),
              ),
            ),

            SizedBox(height: isDesktop ? 0 : 8),

            // ─── Subtitle Row — Galvji on desktop, smaller on mobile ───
            FadeTransition(
              opacity: _subtitleFadeAnim,
              child: Padding(
                padding: EdgeInsets.only(top: isDesktop ? 4 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSubtitlePart('TRANSCRIBED', subtitleFontSize),
                    SizedBox(width: isDesktop ? 14 : 8),
                    _buildWaveBars(waveBarW, waveBarH),
                    SizedBox(width: isDesktop ? 14 : 8),
                    _buildSubtitlePart('MESSAGES', subtitleFontSize),
                  ],
                ),
              ),
            ),

            // ─── 103px gap between logo group and buttons (Paper spec) ───
            SizedBox(height: isDesktop ? 103 : 0),
            if (!isDesktop) const Spacer(flex: 3),

            // ─── Buttons ───
            FadeTransition(
              opacity: _buttonsFadeAnim,
              child: isDesktop ? _buildDesktopButtons() : _buildMobileButtons(),
            ),

            SizedBox(height: isDesktop ? 0 : 40),
            if (isDesktop) const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  /// Desktop: buttons side by side, 220×52 each, gap 16
  Widget _buildDesktopButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sign in — ghost
        _buildButton(
          label: 'Sign in',
          onTap: () => _navigateToAuth(isSignIn: true),
          filled: false,
        ),
        const SizedBox(width: 16),
        // Sign Up — yellow
        _buildButton(
          label: 'Sign Up',
          onTap: () => _navigateToAuth(isSignIn: false),
          filled: true,
        ),
      ],
    );
  }

  /// Mobile: buttons stacked, full width
  Widget _buildMobileButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: _buildButton(
                label: 'Sign in',
                onTap: () => _navigateToAuth(isSignIn: true),
                filled: false,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _buildButton(
                label: 'Sign Up',
                onTap: () => _navigateToAuth(isSignIn: false),
                filled: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({required String label, required VoidCallback onTap, required bool filled}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: filled ? const Color(0xFFF5C518) : Colors.transparent,
          border: filled ? null : Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.sourceSans3(
            fontSize: 16,
            fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
            color: filled ? const Color(0xFF1D2B3A) : const Color(0xFFF2F2F2),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitlePart(String text, double fontSize) {
    return Column(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            letterSpacing: fontSize * 0.05,
            color: const Color(0xFFE0E0E0),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 1,
          width: text.length * (fontSize < 12 ? 6.5 : 10.5),
          color: const Color(0xFFE0E0E0),
        ),
      ],
    );
  }

  Widget _buildWaveBars(double barWidth, double barHeight) {
    return SizedBox(
      height: barHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [0.4, 0.7, 1.0, 0.7, 0.4].map((h) {
          return Container(
            width: barWidth,
            height: barHeight * h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCraneSvg() {
    const svgString = '''
<svg viewBox="115 30 350 155">
  <path d="M176.94,157.6c1.55-.37,3.61.88,6.85.76,1.82-.12,3.37-.44,5.31-2.09,1.4,2.04,4.3,2.9,7.35,2.83,3.05-.07,10.44-.61,14.99-.96,4.55-.34,7.4-1.25,10.42-2.99,4.68,3.06,10.13,1.58,13.82,1.58-2.54-1.47-7.3-4.46-8.66-7.96,7.19,1.07,12.75-2.32,17.58-2.69,2.36-.18,6.3-.11,8.33,1.22,0,0,2.35-.61,4.2-.48,7.41,1.99,19.46,1.07,21.26-2.14-7.33,2.32-14.63,2.25-20.01.81-5.38-1.44-7.92-4.05-8.37-6.3,8.84,2.8,21.23,2.03,24.32-.59-7.56,1.14-16.99,1.33-24.8-1.25-3.87-1.51-5.6-4.53-5.86-6.08,13.93,4.61,25.24,1.73,26.46.33-9.91,1.51-18.02.37-21.74-.48-4.18-.95-8.77-3.1-10.39-5.57,9.1,2.36,24.14,2.29,27.2-.55-7.74,1.07-22.15.52-29.19-1.29-1.25-.74-3.13-2.14-3.76-2.95,9.07.66,22.33-.74,25.87-3.54-10.47,1.99-27.86,2.73-37.59,1.18-17.03-2.95-25.5-11.57-29.11-16.95,20.42,7.52,51.67,12.01,61.69,8.7-11.13-.44-30.74-1.84-51.89-7.52-11.94-6.56-20.34-16.58-23.37-24.4,14.3,9.36,36.04,18.87,46.58,21.67,10.54,2.8,21.82,4.94,25.65,3.46-18.43-2.65-39.06-9.14-59.04-20.12-6.12-5.9-11.06-14-12.97-23.07,6.85,5.9,29.19,19.85,41.03,25.85,11.84,5.99,22.6,10.37,29.14,10.17-12.73-4.23-28.06-11.74-43.14-20.54-5.36-5.7-8.45-12.78-9.7-18.72,8.7,7.89,30.15,19.88,46.36,27.17-8.55-9.43-11.15-21.52-7.62-26.93,10.93,21.2,36.88,34.69,53.46,42.51,6.68,3.15,14.5,7.67,16.51,11.45,2.46,4.62,2.07,7.82-2.75,14.94-4.23,6.24-1.82,15.72,1.77,21.96,2.46,1.62,6.73,4.18,10.86,6.88,4.13,2.7,12.43,7.27,21.33,5.8,8.89-1.47,12.44-9.48,14.59-16.36,2.26-7.22,6.04-10.22,10.61-11.2,4.57-.98,10.81.34,14.5,4.03,20.69.44,35.6,6.44,40.76,11.6-17.25-2.99-35.38-1.47-45.37.81-1.95,2.91-4.42,4.42-7.26,4.53-3.65,2.95-7.54,9.5-11.38,14.56-9.93,12.28-23.73,11.55-30.22,8.84-29.46,14.08-53.22.79-62.01-4.42-5.45-1.47-13.03-4.31-20-8.73-6.97-4.42-12.8-3.33-16.76-2.13-2.31-1.06-4.47-1.74-7.49-1.67-3.02.07-15.21.88-26.71,1.87-11.5.98-19.78-.93-22.6-4.4,4.77.96,8.13.27,10.96-.44" fill="#898989"/>
  <path d="M400.96,144.36c-9.47-3.06-22.85-3.15-26.93-2.9-3.59-3.59-8.6-5.27-13.61-3.99-5.01,1.28-6.39,6.25-7.22,9-.84,2.75-3.49,9.61-7.37,13.03-4.13,3.65-8.94,5.98-17.2,5.39-8.26-.59-17.63-7.24-21.52-10.17.91,2.68,3.89,6.36,7.17,9.04-8.33-1.87-12.48-9.68-14.99-14.45-2.51-4.77-5.72-14.14-2.96-22.14,2.06-5.97,4.98-6.44,4.75-10.87-.19-3.84-5.58-8.12-10.44-10.72-4.86-2.6-35.92-16.02-52.48-34.84,3,9.48,13.61,18.87,16.56,21.18,2.95,2.31,11.39,7.06,14.54,8.4-6.03-.09-14.45-5.31-17.79-7.67,2.03,4.96,6.23,9.39,19.42,14.14-2.87.81-9.64-1.46-13.97-3.87,1.36,3.91,5.2,7,9.58,9.24,4.35,2.22,8.16,3.29,9.98,4.28-4.13.2-9.64-1.09-15.58-4.03,3.05,5.65,10.61,10.96,20.49,13.27.1-1.92,1.03-7.13-2.32-11.44-3.02-3.1-4.46-7.22-3.43-9.14,2.8,5.42,10.72,11.83,16.4,13.08-1.77,1.47-6.71.18-7.74-.37,1.07,4.24-.1,11.07,2.51,16.73,2.26,4.9,7.04,9.25,9.14,11.68-2.06-.7-4.42-2.05-5.07-2.62-.09,5.9,7.73,19.14,20.14,22.85-3.39.74-8.64-1.7-10.39-2.78-3.15,1.29-7.7,2.3-11.79,1.79,2.14,3.28,10.5,5.31,15.63,4.46,4.09,2.51,8.84,2.4,11.5,2.14-.48-.74-.92-2.03-.96-2.69,1.92,1.73,13.27,3.65,21.89,1.22,8.62-2.43,18.8-11.54,19.61-21.19-.52-.77-.66-1.81-.42-2.57.86,1.18,4.55,3,7.69-.52,1.43.17,3.39-.29,4.08-2.11-1.4-.49-1.82-2.14-3.76-2.41.54-1.2,2.63-1.87,4.4-1.03,1.06.49,1.38,1.25,3.37,1.13.22,1.11-.98,1.23-1.5,2.83,6.56-1.11,21.93-1.11,30.59-.36" fill="#eaeaea"/>
  <path d="M281.26,129.22c.05,1.03.22,3.12.76,4.35-5.75-1.18-13.32-4.5-14.5-9.39,4.3,2.46,10.64,4.55,13.73,5.04" fill="#eaeaea"/>
  <path d="M288.06,141.02c-1.62-1.23-3.73-3.39-4.45-4.45-4.13-.66-8.55-2.36-10.98-3.66,1.13,3.83,6.95,8.5,15.4,9.24,0-.32.01-.68.02-1.13" fill="#eaeaea"/>
  <path d="M288.22,144.04c-2.52-.17-8.11-1.68-10.25-3.04,1.38,3.48,6.78,6.71,10.98,7.48-.44-1.6-.74-3.46-.74-4.44" fill="#eaeaea"/>
  <path d="M289.61,150.45c-2.38-.32-5.28-1.3-7.15-2.51.81,3.27,5.11,6.51,9.75,7.52-1.3-1.79-2.16-3.81-2.6-5.01" fill="#eaeaea"/>
  <path d="M293.81,157.63c-2.92-.52-5.82-1.52-7.27-2.41,1.15,3.51,7.86,5.97,11.08,6.22-1.47-1.15-3.32-3.1-3.81-3.81" fill="#eaeaea"/>
  <path d="M236.85,151.25c4.39-2.06,9.25-4.24,16.07-3.94,0,0,2.35-.61,4.2-.48,1.36,2.1,5.2,5.01,9.77,5.75,4.57.74,11.31-.26,14.7-1.29-2.76,2.95-11.9,3.83-18.35,1.73,1.33,2.4,6.04,6.78,17.06,7.44-4.02,1.33-11.72.88-16.55-2.99-2.1.96-5.53,1.22-7.92,0,1.88-.55,3.59-1.6,4.18-3.15-3.96-.39-9.18-2.71-10.58-3.81-.26,1.22.7,4.16,2.58,5.8-2.56.24-6.53-1.54-8.89-5.37-.59,1.11-.49,2.37.47,3.62-2.36-.26-5.49-1.7-6.74-3.32" fill="#eaeaea"/>
</svg>
''';
    return SvgPicture.string(svgString, fit: BoxFit.contain);
  }
}
