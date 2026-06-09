import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Crops a region from [bytes] given a Gemini-style bounding [box], expressed as
/// `[ymin, xmin, ymax, xmax]` normalized to 0..1000. Returns JPEG bytes, or null
/// if the box is missing/invalid. Pure Dart — works on mobile, web and Windows.
Uint8List? cropNormalizedBox(
  Uint8List? bytes,
  List<int>? box, {
  double padding = 0.08,
}) {
  if (bytes == null || box == null || box.length != 4) return null;

  double ymin = box[0] / 1000.0;
  double xmin = box[1] / 1000.0;
  double ymax = box[2] / 1000.0;
  double xmax = box[3] / 1000.0;

  if (xmax <= xmin || ymax <= ymin) return null;

  try {
    final img.Image? image = img.decodeImage(bytes);
    if (image == null) return null;
    final int w = image.width;
    final int h = image.height;

    // Expand slightly so the crop isn't tight against the subject.
    final double padX = (xmax - xmin) * padding;
    final double padY = (ymax - ymin) * padding;
    xmin = (xmin - padX).clamp(0.0, 1.0);
    ymin = (ymin - padY).clamp(0.0, 1.0);
    xmax = (xmax + padX).clamp(0.0, 1.0);
    ymax = (ymax + padY).clamp(0.0, 1.0);

    final int x = (xmin * w).round().clamp(0, w - 1);
    final int y = (ymin * h).round().clamp(0, h - 1);
    final int cw = ((xmax - xmin) * w).round().clamp(1, w - x);
    final int ch = ((ymax - ymin) * h).round().clamp(1, h - y);

    final img.Image cropped = img.copyCrop(image, x: x, y: y, width: cw, height: ch);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
  } catch (e) {
    debugPrint('cropNormalizedBox error: $e');
    return null;
  }
}

/// Parses a Gemini bounding box (`[ymin, xmin, ymax, xmax]`) from JSON.
List<int>? boxFromJson(dynamic value) {
  if (value is List && value.length == 4) {
    try {
      return value.map((e) => (e as num).round()).toList();
    } catch (_) {
      return null;
    }
  }
  return null;
}
