import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase so Gemini (firebase_ai) is available for NID scanning.
  // Wrapped in try/catch so the app still launches before `flutterfire configure`
  // has generated the native config / firebase_options.dart. When Firebase is not
  // ready, the scanner falls back to simulation mode.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase not configured yet — scanner runs in simulation mode: $e');
  }

  runApp(const CardScannerApp());
}

class CardScannerApp extends StatelessWidget {
  const CardScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Scanner Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
