import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dark status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // Allow portrait + landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize Supabase (sign out any stale web session so splash always shows)
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );
  // Session persists via browser localStorage — user stays logged in after refresh

  runApp(const TertiusApp());
}

class TertiusApp extends StatelessWidget {
  const TertiusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tertius',
      debugShowCheckedModeBanner: false,
      theme: TertiusTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
