import 'dart:typed_data';

import 'web_image_paste_stub.dart'
    if (dart.library.js_interop) 'web_image_paste_web.dart' as impl;

/// Cross-platform facade for capturing images pasted via the browser's native
/// paste event. Active only on web; a harmless no-op everywhere else (desktop
/// and mobile paste go through the `pasteboard` plugin instead).
class WebImagePaste {
  static final impl.WebImagePasteImpl _impl = impl.WebImagePasteImpl();

  /// Starts listening; [onImages] fires with the bytes of all images in a single
  /// paste, in clipboard order (so a front+back copied together arrive as one
  /// list).
  static void start(void Function(List<Uint8List> images) onImages) =>
      _impl.start(onImages);

  /// Stops listening.
  static void stop() => _impl.stop();
}
