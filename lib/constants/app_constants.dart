class AppConstants {
  static const String appName = 'Card Scanner';
  static const String appVersion = '1.0.0';

  /// Gemini API key — injected at build time, NEVER hardcoded or committed:
  ///   flutter run --dart-define-from-file=.env
  /// (.env is git-ignored.) Read via String.fromEnvironment so the secret stays
  /// out of source control.
  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');
}
