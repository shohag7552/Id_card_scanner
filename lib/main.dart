import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

void main() {
  // Gemini NID scanning authenticates with an API key supplied at build time
  // (--dart-define=GEMINI_API_KEY=...). When no key is present, the scanner
  // falls back to simulation mode — see GeminiNidService.isAvailable.
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
