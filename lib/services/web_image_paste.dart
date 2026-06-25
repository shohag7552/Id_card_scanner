import 'dart:typed_data';

import 'web_image_paste_stub.dart'
    if (dart.library.js_interop) 'web_image_paste_web.dart' as impl;

/// Cross-platform facade for capturing images pasted via the browser's native
/// paste event. Active only on web; a harmless no-op everywhere else (desktop
/// and mobile paste go through the `pasteboard` plugin instead).
class WebImagePaste {
  static final impl.WebImagePasteImpl _impl = impl.WebImagePasteImpl();

  /// Active paste handlers, most-recent last. Handlers stack so a transient
  /// surface (e.g. the card-editor dialog opened over the batch page) can take
  /// over paste while it's open and hand control back to the page beneath it
  /// when it closes — there's only ever one real DOM listener, pointed at the
  /// top handler.
  static final List<void Function(List<Uint8List> images)> _handlers = [];

  /// Registers [onImages] as the active handler. It fires with the bytes of all
  /// images in a single paste, in clipboard order (so a front+back copied
  /// together arrive as one list). Pair every [start] with a later [stop].
  static void start(void Function(List<Uint8List> images) onImages) {
    _handlers.add(onImages);
    _rebind();
  }

  /// Removes the most-recently started handler, restoring the previous one (or
  /// stopping entirely when none remain).
  static void stop() {
    if (_handlers.isNotEmpty) _handlers.removeLast();
    _rebind();
  }

  static void _rebind() {
    if (_handlers.isEmpty) {
      _impl.stop();
    } else {
      _impl.start(_handlers.last);
    }
  }
}
