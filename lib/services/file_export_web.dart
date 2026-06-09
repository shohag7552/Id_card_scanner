// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'file_export_types.dart';

/// Web: hand the bytes to the browser as a download, which lands in the
/// browser's configured download location (usually the Downloads folder).
Future<SaveResult> saveToDownloads(Uint8List bytes, String filename) async {
  final blob = html.Blob(<Object>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return const SaveResult(ok: true, isWeb: true);
}

Future<void> openDownloads() async {
  // No-op on web; the browser surfaces the download itself.
}
