import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  /// Sign in with email + password
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    notifyListeners();
  }

  /// Sign up with email + password
  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(email: email, password: password);
    notifyListeners();
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
    notifyListeners();
  }

  /// Listen to auth state changes
  void listen(void Function(AuthState) callback) {
    _client.auth.onAuthStateChange.listen(callback);
  }
}
