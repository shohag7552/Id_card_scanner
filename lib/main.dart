import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  // Gemini NID scanning authenticates with an API key supplied at build time
  // (--dart-define=GEMINI_API_KEY=...). When no key is present, the scanner
  // falls back to simulation mode — see GeminiNidService.isAvailable.
  WidgetsFlutterBinding.ensureInitialized();
  // Preload Noto Serif Bengali (regular + bold) so the off-screen NID→PNG
  // capture never races the runtime font fetch. After the first download the
  // font is cached; a cold offline first-run falls back to the system Bengali.
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.notoSerifBengali(),
      GoogleFonts.notoSerifBengali(fontWeight: FontWeight.bold),
    ]);
  } catch (_) {
    // Offline / fetch failure: fall back to the system Bengali font.
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
