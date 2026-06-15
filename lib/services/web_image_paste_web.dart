import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation: listens for the browser's native `paste` event and hands
/// back the bytes of EVERY pasted image (in clipboard order). Unlike
/// `navigator.clipboard.read()` (what `pasteboard` uses on web), the paste event
/// also captures image *files* copied from the OS file manager — including
/// MULTIPLE files copied together — works in all major browsers, and needs no
/// clipboard-read permission prompt since it rides the user's real Ctrl/⌘+V.
///
/// Returning the full list lets the caller pair a front+back copied together
/// into a single NID pair.
class WebImagePasteImpl {
  StreamSubscription<web.ClipboardEvent>? _sub;

  void start(void Function(List<Uint8List> images) onImages) {
    stop();
    _sub = web.EventStreamProviders.pasteEvent
        .forTarget(web.document)
        .listen((event) {
      final data = event.clipboardData;
      if (data == null) return;

      // getAsFile() is only valid synchronously during the event, so grab the
      // File objects first (in order), then read their bytes asynchronously.
      final items = data.items;
      final files = <web.File>[];
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (!item.type.startsWith('image/')) continue;
        final file = item.getAsFile();
        if (file != null) files.add(file);
      }
      if (files.isEmpty) return;

      event.preventDefault();
      Future.wait(
        files.map((f) =>
            f.arrayBuffer().toDart.then((buf) => buf.toDart.asUint8List())),
      ).then(onImages);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
