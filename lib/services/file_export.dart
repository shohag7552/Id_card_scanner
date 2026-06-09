import 'dart:typed_data';

import 'file_export_types.dart';
export 'file_export_types.dart';

// Resolves to the web backend on Flutter web, the dart:io backend everywhere else.
import 'file_export_io.dart' if (dart.library.html) 'file_export_web.dart' as impl;

/// Cross-platform file export. Saves bytes to the device's Downloads folder on
/// mobile/desktop, or triggers a browser download on web.
class FileExport {
  static Future<SaveResult> saveToDownloads(Uint8List bytes, String filename) =>
      impl.saveToDownloads(bytes, filename);

  static Future<void> openDownloads() => impl.openDownloads();
}
