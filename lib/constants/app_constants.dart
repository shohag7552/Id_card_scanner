/// Application run mode.
///
/// - [AppMode.dev]: development build — a notice pops up before every ID scan,
///   and the paid (Pro-tier) Gemini models are DISABLED so no billable premium
///   calls happen while testing.
/// - [AppMode.release]: production behaviour — no notice, all models enabled.
enum AppMode { dev, release }

class AppConstants {
  static const String appName = 'Card Scanner';
  static const String appVersion = '1.0.0';

  /// Current run mode. Flip this to [AppMode.release] for production builds.
  ///
  /// Can also be overridden at build time without editing this file:
  ///   flutter run --dart-define=APP_MODE=release
  /// Anything other than "release" (including unset) is treated as dev.
  static const AppMode appMode =
      _appModeEnv == 'release' ? AppMode.release : AppMode.dev;

  static const String _appModeEnv =
      String.fromEnvironment('APP_MODE', defaultValue: 'dev');

  /// True when running in developer mode (scan notice on, paid models off).
  static bool get isDevMode => appMode == AppMode.dev;

  /// True when running in release mode (everything enabled).
  static bool get isReleaseMode => appMode == AppMode.release;

  /// Gemini API key — injected at build time, NEVER hardcoded or committed:
  ///   flutter run --dart-define-from-file=.env
  /// (.env is git-ignored.) Read via String.fromEnvironment so the secret stays
  /// out of source control.
  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');
}
