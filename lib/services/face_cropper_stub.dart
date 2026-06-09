import 'dart:typed_data';

/// Web stub — ML Kit cropping is unavailable in the browser. The caller falls
/// back to Gemini's bounding-box crop.
Future<Uint8List?> detectAndCropFace(String imagePath) async => null;

Future<Uint8List?> detectAndCropSignature(String imagePath) async => null;

Future<Uint8List?> cropAuthoritySignature(String imagePath) async => null;

void dispose() {}
