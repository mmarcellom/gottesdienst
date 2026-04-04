import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  final bool isSignIn;
  const AuthScreen({super.key, this.isSignIn = true});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _isSignIn;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _isSignIn = widget.isSignIn;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _error = null; _loading = true; });
    try {
      if (_isSignIn) {
        await AuthService().signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
      } else {
        await AuthService().signUp(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TertiusTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 80),
              Text(
                _isSignIn ? 'Sign In' : 'Sign Up',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.02 * 32,
                  color: TertiusTheme.text,
                ),
              ),
              const SizedBox(height: 40),

              // Email
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 8),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(hintText: 'Password'),
              ),

              if (_isSignIn) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Forgot password?',
                    style: TextStyle(fontSize: 13, color: TertiusTheme.textMuted),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: TertiusTheme.error, fontSize: 13), textAlign: TextAlign.center),
              ],

              const SizedBox(height: 24),

              // Primary button
              SizedBox(
                width: double.infinity,
                height: TertiusTheme.btnHeight,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TertiusTheme.yellow,
                    foregroundColor: TertiusTheme.yellowText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TertiusTheme.radiusPill)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: TertiusTheme.yellowText))
                      : Text(_isSignIn ? 'Sign In' : 'Sign Up'),
                ),
              ),

              const SizedBox(height: 12),

              // Toggle
              SizedBox(
                width: double.infinity,
                height: TertiusTheme.btnHeight,
                child: OutlinedButton(
                  onPressed: () => setState(() { _isSignIn = !_isSignIn; _error = null; }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TertiusTheme.text,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TertiusTheme.radiusPill)),
                  ),
                  child: Text(_isSignIn ? 'Sign Up' : 'Sign In'),
                ),
              ),

              const SizedBox(height: 16),

              // Skip
              TextButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const HomeScreen(),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    transitionDuration: const Duration(milliseconds: 500),
                  ),
                  (_) => false,
                ),
                child: Text(
                  'Ohne Anmeldung weiter',
                  style: TextStyle(color: TertiusTheme.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
