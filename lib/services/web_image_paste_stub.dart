import 'dart:typed_data';

/// Non-web implementation: there is no browser paste event, so this is a no-op.
/// Desktop/mobile paste is handled separately via the `pasteboard` plugin.
class WebImagePasteImpl {
  void start(void Function(List<Uint8List> images) onImages) {}
  void stop() {}
}
