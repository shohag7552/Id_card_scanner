/// Outcome of saving an exported file, shared by the mobile and web backends.
class SaveResult {
  /// The file reached a user-accessible location (Downloads on mobile, the
  /// browser's download on web).
  final bool ok;

  /// True when the file was handed to the browser's download mechanism.
  final bool isWeb;

  /// True when the device's Downloads folder can be opened (mobile only).
  final bool canOpenDownloads;

  /// Local path of a staged copy that can be shared (mobile only).
  final String? sharePath;

  const SaveResult({
    required this.ok,
    this.isWeb = false,
    this.canOpenDownloads = false,
    this.sharePath,
  });
}
