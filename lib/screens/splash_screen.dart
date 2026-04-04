import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/theme.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';

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
  late Animation<double> _titleFadeAnim;
  late Animation<double> _subtitleFadeAnim;
  late Animation<double> _buttonsFadeAnim;
  bool _checkingAuth = false;

  @override
  void initState() {
    super.initState();

    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    // Crane flight X (left to center)
    _flightXAnim = Tween<Offset>(
      begin: const Offset(-2.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _flightController,
      curve: Curves.decelerate,
    ));

    // Crane flight Y (top to center) + scale
    _flightYAnim = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _flightController,
      curve: Curves.easeOutCubic,
    ));

    _craneFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flightController, curve: const Interval(0, 0.3, curve: Curves.easeIn)),
    );

    _craneScaleAnim = Tween<double>(begin: 0.35, end: 1).animate(
      CurvedAnimation(parent: _flightController, curve: Curves.easeOutCubic),
    );

    // Title, subtitle, buttons fade in sequentially
    _titleFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.47, 0.72, curve: Curves.easeIn)),
    );

    _subtitleFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.53, 0.78, curve: Curves.easeIn)),
    );

    _buttonsFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.75, 1.0, curve: Curves.easeIn)),
    );

    _flightController.forward();
    _fadeController.forward();

    // Check if already signed in after animation
    Future.delayed(const Duration(milliseconds: 2800), _checkAuth);
  }

  void _checkAuth() {
    if (!mounted) return;
    if (AuthService().isSignedIn) {
      setState(() => _checkingAuth = true);
      // Short delay for the spinner to be visible, then navigate
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      });
    }
  }

  void _navigateToAuth({required bool isSignIn}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => AuthScreen(isSignIn: isSignIn),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
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
    return Scaffold(
      backgroundColor: TertiusTheme.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // ─── Crane Animation ───
                AnimatedBuilder(
                  animation: _flightController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                        _flightXAnim.value.dx * MediaQuery.of(context).size.width * 0.5,
                        _flightYAnim.value.dy * MediaQuery.of(context).size.height * 0.3,
                      ),
                      child: Transform.scale(
                        scale: _craneScaleAnim.value,
                        child: Opacity(
                          opacity: _craneFadeAnim.value,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: SizedBox(
                    width: 200,
                    height: 100,
                    child: _buildCraneSvg(),
                  ),
                ),

                const SizedBox(height: 35),

                // ─── Title ───
                FadeTransition(
                  opacity: _titleFadeAnim,
                  child: Text(
                    'TERTIUS',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 54,
                      fontWeight: FontWeight.w400,
                      color: TertiusTheme.text,
                      letterSpacing: 54 * 0.05,
                      height: 0.85,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ─── Subtitle Row ───
                FadeTransition(
                  opacity: _subtitleFadeAnim,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSubtitlePart('TRANSCRIBED'),
                      const SizedBox(width: 8),
                      _buildWaveBars(),
                      const SizedBox(width: 8),
                      _buildSubtitlePart('MESSAGES'),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ─── Auth Check Spinner or Buttons ───
                if (_checkingAuth)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 80),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: TertiusTheme.yellow,
                      ),
                    ),
                  )
                else
                  FadeTransition(
                    opacity: _buttonsFadeAnim,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: TertiusTheme.btnHeight,
                          child: ElevatedButton(
                            onPressed: () => _navigateToAuth(isSignIn: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TertiusTheme.yellow,
                              foregroundColor: TertiusTheme.yellowText,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TertiusTheme.radiusPill)),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: TertiusTheme.btnHeight,
                          child: OutlinedButton(
                            onPressed: () => _navigateToAuth(isSignIn: false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TertiusTheme.text,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TertiusTheme.radiusPill)),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                            child: const Text('Sign Up'),
                          ),
                        ),
                        // Skip auth — go directly to app
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _navigateToHome,
                          child: Text(
                            'Ohne Anmeldung weiter',
                            style: TextStyle(color: TertiusTheme.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitlePart(String text) {
    return Column(
      children: [
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Helvetica Neue',
            fontSize: 9,
            letterSpacing: 9 * 0.15,
            color: TertiusTheme.gray,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 1,
          width: text.length * 6.5,
          color: TertiusTheme.gray,
        ),
      ],
    );
  }

  Widget _buildWaveBars() {
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [0.4, 0.7, 1.0, 0.7, 0.4].map((h) {
          return Container(
            width: 2,
            height: 14 * h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: TertiusTheme.gray,
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCraneSvg() {
    // Inline SVG of the crane from the web version
    const svgString = '''
<svg viewBox="175 55 270 115">
  <path d="M176.94,157.6c1.55-.37,3.61.88,6.85.76,1.82-.12,3.37-.44,5.31-2.09,1.4,2.04,4.3,2.9,7.35,2.83,3.05-.07,10.44-.61,14.99-.96,4.55-.34,7.4-1.25,10.42-2.99,4.68,3.06,10.13,1.58,13.82,1.58-2.54-1.47-7.3-4.46-8.66-7.96,7.19,1.07,12.75-2.32,17.58-2.69,2.36-.18,6.3-.11,8.33,1.22,0,0,2.35-.61,4.2-.48,7.41,1.99,19.46,1.07,21.26-2.14-7.33,2.32-14.63,2.25-20.01.81-5.38-1.44-7.92-4.05-8.37-6.3,8.84,2.8,21.23,2.03,24.32-.59-7.56,1.14-16.99,1.33-24.8-1.25-3.87-1.51-5.6-4.53-5.86-6.08,13.93,4.61,25.24,1.73,26.46.33-9.91,1.51-18.02.37-21.74-.48-4.18-.95-8.77-3.1-10.39-5.57,9.1,2.36,24.14,2.29,27.2-.55-7.74,1.07-22.15.52-29.19-1.29-1.25-.74-3.13-2.14-3.76-2.95,9.07.66,22.33-.74,25.87-3.54-10.47,1.99-27.86,2.73-37.59,1.18-17.03-2.95-25.5-11.57-29.11-16.95,20.42,7.52,51.67,12.01,61.69,8.7-11.13-.44-30.74-1.84-51.89-7.52-11.94-6.56-20.34-16.58-23.37-24.4,14.3,9.36,36.04,18.87,46.58,21.67,10.54,2.8,21.82,4.94,25.65,3.46-18.43-2.65-39.06-9.14-59.04-20.12-6.12-5.9-11.06-14-12.97-23.07,6.85,5.9,29.19,19.85,41.03,25.85,11.84,5.99,22.6,10.37,29.14,10.17-12.73-4.23-28.06-11.74-43.14-20.54-5.36-5.7-8.45-12.78-9.7-18.72,8.7,7.89,30.15,19.88,46.36,27.17-8.55-9.43-11.15-21.52-7.62-26.93,10.93,21.2,36.88,34.69,53.46,42.51,6.68,3.15,14.5,7.67,16.51,11.45,2.46,4.62,2.07,7.82-2.75,14.94-4.23,6.24-1.82,15.72,1.77,21.96,2.46,1.62,6.73,4.18,10.86,6.88,4.13,2.7,12.43,7.27,21.33,5.8,8.89-1.47,12.44-9.48,14.59-16.36,2.26-7.22,6.04-10.22,10.61-11.2,4.57-.98,10.81.34,14.5,4.03,20.69.44,35.6,6.44,40.76,11.6-17.25-2.99-35.38-1.47-45.37.81-1.95,2.91-4.42,4.42-7.26,4.53-3.65,2.95-7.54,9.5-11.38,14.56-9.93,12.28-23.73,11.55-30.22,8.84-29.46,14.08-53.22.79-62.01-4.42-5.45-1.47-13.03-4.31-20-8.73-6.97-4.42-12.8-3.33-16.76-2.13-2.31-1.06-4.47-1.74-7.49-1.67-3.02.07-15.21.88-26.71,1.87-11.5.98-19.78-.93-22.6-4.4,4.77.96,8.13.27,10.96-.44" fill="#898989"/>
  <path d="M400.96,144.36c-9.47-3.06-22.85-3.15-26.93-2.9-3.59-3.59-8.6-5.27-13.61-3.99-5.01,1.28-6.39,6.25-7.22,9-.84,2.75-3.49,9.61-7.37,13.03-4.13,3.65-8.94,5.98-17.2,5.39-8.26-.59-17.63-7.24-21.52-10.17.91,2.68,3.89,6.36,7.17,9.04-8.33-1.87-12.48-9.68-14.99-14.45-2.51-4.77-5.72-14.14-2.96-22.14,2.06-5.97,4.98-6.44,4.75-10.87-.19-3.84-5.58-8.12-10.44-10.72-4.86-2.6-35.92-16.02-52.48-34.84,3,9.48,13.61,18.87,16.56,21.18,2.95,2.31,11.39,7.06,14.54,8.4-6.03-.09-14.45-5.31-17.79-7.67,2.03,4.96,6.23,9.39,19.42,14.14-2.87.81-9.64-1.46-13.97-3.87,1.36,3.91,5.2,7,9.58,9.24,4.35,2.22,8.16,3.29,9.98,4.28-4.13.2-9.64-1.09-15.58-4.03,3.05,5.65,10.61,10.96,20.49,13.27.1-1.92,1.03-7.13-2.32-11.44-3.02-3.1-4.46-7.22-3.43-9.14,2.8,5.42,10.72,11.83,16.4,13.08-1.77,1.47-6.71.18-7.74-.37,1.07,4.24-.1,11.07,2.51,16.73,2.26,4.9,7.04,9.25,9.14,11.68-2.06-.7-4.42-2.05-5.07-2.62-.09,5.9,7.73,19.14,20.14,22.85-3.39.74-8.64-1.7-10.39-2.78-3.15,1.29-7.7,2.3-11.79,1.79,2.14,3.28,10.5,5.31,15.63,4.46,4.09,2.51,8.84,2.4,11.5,2.14-.48-.74-.92-2.03-.96-2.69,1.92,1.73,13.27,3.65,21.89,1.22,8.62-2.43,18.8-11.54,19.61-21.19-.52-.77-.66-1.81-.42-2.57.86,1.18,4.55,3,7.69-.52,1.43.17,3.39-.29,4.08-2.11-1.4-.49-1.82-2.14-3.76-2.41.54-1.2,2.63-1.87,4.4-1.03,1.06.49,1.38,1.25,3.37,1.13.22,1.11-.98,1.23-1.5,2.83,6.56-1.11,21.93-1.11,30.59-.36" fill="#eaeaea"/>
</svg>
''';
    return SvgPicture.string(svgString, fit: BoxFit.contain);
  }
}
