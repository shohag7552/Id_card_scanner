import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
// Hide `context` (re-exported from package:path) to avoid shadowing.
import 'package:downloadsfolder/downloadsfolder.dart' hide context;
import 'file_export_types.dart';

/// Mobile/desktop: stage the bytes to a temp file, then copy into the device's
/// public Downloads folder (MediaStore on Android 10+).
Future<SaveResult> saveToDownloads(Uint8List bytes, String filename) async {
  String tempPath;
  try {
    final Directory dir = await getTemporaryDirectory();
    tempPath = '${dir.path}/$filename';
    await File(tempPath).writeAsBytes(bytes);
  } catch (e) {
    debugPrint('Error staging file: $e');
    return const SaveResult(ok: false);
  }

  bool saved = false;
  try {
    final bool? ok = await copyFileIntoDownloadFolder(tempPath, filename);
    saved = ok ?? false;
  } catch (e) {
    debugPrint('Downloads copy failed: $e');
  }

  return SaveResult(ok: saved, canOpenDownloads: saved, sharePath: tempPath);
}

Future<void> openDownloads() async {
  try {
    await openDownloadFolder();
  } catch (e) {
    debugPrint('Could not open Downloads: $e');
  }
}
