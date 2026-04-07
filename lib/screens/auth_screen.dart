import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final _nameCtrl = TextEditingController();
  final _passwordConfirmCtrl = TextEditingController();
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
    _nameCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _error = null; _loading = true; });
    try {
      if (_isSignIn) {
        await AuthService().signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
      } else {
        if (_passwordCtrl.text != _passwordConfirmCtrl.text) {
          throw Exception('Passwords do not match');
        }
        await AuthService().signUp(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // SIGN IN title at top
                          const SizedBox(height: 48),
                          Text(
                            _isSignIn ? 'SIGN IN' : 'SIGN UP',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: TertiusTheme.text,
                              letterSpacing: 2,
                            ),
                          ),

                          // Push fields to vertical center
                          SizedBox(height: _isSignIn ? 120 : 60),

                          // ─── Fields ───
                          if (!_isSignIn) ...[
                            _buildRoundedField(_nameCtrl, 'Name'),
                            const SizedBox(height: 12),
                          ],

                          _buildRoundedField(_emailCtrl, 'Email',
                              type: TextInputType.emailAddress),
                          const SizedBox(height: 12),

                          _buildRoundedField(_passwordCtrl, 'Password',
                              obscure: true, onSubmit: _isSignIn ? _submit : null),

                          if (!_isSignIn) ...[
                            const SizedBox(height: 12),
                            _buildRoundedField(_passwordConfirmCtrl, 'Re-type Password',
                                obscure: true, onSubmit: _submit),
                          ],

                          if (_isSignIn) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Forgot password?',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withOpacity(0.45),
                                ),
                              ),
                            ),
                          ],

                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(_error!,
                              style: GoogleFonts.inter(color: TertiusTheme.error, fontSize: 13),
                              textAlign: TextAlign.center),
                          ],

                          // Space before buttons
                          const SizedBox(height: 32),

                          // ─── Buttons side by side ───
                          Row(
                            children: [
                              // Primary button (yellow)
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TertiusTheme.yellow,
                                      foregroundColor: TertiusTheme.yellowText,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                    child: _loading
                                        ? const SizedBox(width: 18, height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: TertiusTheme.yellowText))
                                        : Text(_isSignIn ? 'Sign In' : 'Sign Up'),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              // Toggle button (ghost)
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: () => setState(() { _isSignIn = !_isSignIn; _error = null; }),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: TertiusTheme.text,
                                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                                    ),
                                    child: Text(_isSignIn ? 'Sign Up' : 'Sign In'),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Rounded field — white bg with opacity, focused = brighter
  Widget _buildRoundedField(
    TextEditingController controller,
    String placeholder, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      autocorrect: false,
      textInputAction: onSubmit != null ? TextInputAction.go : TextInputAction.next,
      onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
      style: GoogleFonts.inter(
        color: TertiusTheme.bg,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: GoogleFonts.inter(color: TertiusTheme.bg.withOpacity(0.4), fontSize: 15),
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.focused)
                ? Colors.white.withOpacity(0.85)
                : Colors.white.withOpacity(0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
