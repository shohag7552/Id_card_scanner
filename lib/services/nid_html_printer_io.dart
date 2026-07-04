import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Desktop/mobile: write the HTML to a temp file and open it in the default
/// browser. Returns false on mobile (no browser-open) so the caller can fall
/// back to saving the file.
Future<bool> openForPrint(String html, String filename) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(html);

    if (Platform.isMacOS) {
      // Prefer Chrome — it reliably embeds the web font when you "Save as PDF".
      final r = await Process.run('open', ['-a', 'Google Chrome', file.path]);
      if (r.exitCode != 0) await Process.run('open', [file.path]);
      return true;
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', file.path]);
      return true;
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.path]);
      return true;
    }
    return false; // iOS/Android: caller saves the .html instead
  } catch (_) {
    return false;
  }
}
