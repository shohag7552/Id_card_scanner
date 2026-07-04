import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web: open the HTML in a new browser tab via a blob URL. The page's own script
/// pops the print dialog once fonts are ready, so the user just "Save as PDF".
Future<bool> openForPrint(String html, String filename) async {
  try {
    final blob = web.Blob(
      [html.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    final url = web.URL.createObjectURL(blob);
    final win = web.window.open(url, '_blank');
    return win != null;
  } catch (_) {
    return false;
  }
}
