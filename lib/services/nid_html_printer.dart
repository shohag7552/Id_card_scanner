import 'nid_html_printer_io.dart'
    if (dart.library.js_interop) 'nid_html_printer_web.dart' as impl;

/// Opens a card's HTML in the system/browser so the user can print it to PDF
/// (the HTML self-triggers the print dialog). On desktop it writes a temp file
/// and opens it in the default browser; on web it opens a blob URL in a new tab.
/// Returns true if a browser was opened, false if the caller should instead just
/// save the .html file (e.g. on mobile).
class NidHtmlPrinter {
  static Future<bool> openForPrint(String html, String filename) =>
      impl.openForPrint(html, filename);
}
