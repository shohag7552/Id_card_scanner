import 'dart:typed_data';

import 'face_cropper_stub.dart'
    if (dart.library.io) 'face_cropper_io.dart' as impl;

/// Cross-platform facade for cropping the photo / signatures out of an ID image.
///
/// On Android/iOS this uses ML Kit face detection for a precise crop. On web (no
/// `dart:io`) it resolves to a stub that returns null, and on desktop the ML Kit
/// plugin is unavailable so it also returns null — in both cases the caller falls
/// back to Gemini's bounding-box crop.
class FaceCropper {
  static Future<Uint8List?> detectAndCropFace(String imagePath) =>
      impl.detectAndCropFace(imagePath);

  static Future<Uint8List?> detectAndCropSignature(String imagePath) =>
      impl.detectAndCropSignature(imagePath);

  static Future<Uint8List?> cropAuthoritySignature(String imagePath) =>
      impl.cropAuthoritySignature(imagePath);

  static void dispose() => impl.dispose();
}
