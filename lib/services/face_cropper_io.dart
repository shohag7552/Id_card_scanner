import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Android/iOS implementation: detects a face with ML Kit and returns the
/// cropped region as JPEG bytes. On desktop (no ML Kit plugin) it returns null,
/// so the caller falls back to Gemini's bounding-box crop.
final FaceDetector _faceDetector = FaceDetector(
  options: FaceDetectorOptions(
    enableContours: false,
    enableLandmarks: false,
    performanceMode: FaceDetectorMode.accurate,
  ),
);

bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

void dispose() {
  if (_supported) {
    _faceDetector.close();
  }
}

/// Detects the first face and returns it cropped (with 15% padding) as JPEG bytes.
Future<Uint8List?> detectAndCropFace(String imagePath) async {
  if (!_supported) return null;

  try {
    final inputImage = InputImage.fromFilePath(imagePath);
    final List<Face> faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      debugPrint('No faces detected in the image');
      return null;
    }

    final Rect boundingBox = faces.first.boundingBox;
    final img.Image? originalImage = img.decodeImage(await File(imagePath).readAsBytes());
    if (originalImage == null) return null;

    final int srcW = originalImage.width;
    final int srcH = originalImage.height;
    final int padX = (boundingBox.width * 0.15).toInt();
    final int padY = (boundingBox.height * 0.15).toInt();

    final int x = (boundingBox.left - padX).toInt().clamp(0, srcW);
    final int y = (boundingBox.top - padY).toInt().clamp(0, srcH);
    final int width = (boundingBox.width + (padX * 2)).toInt().clamp(1, srcW - x);
    final int height = (boundingBox.height + (padY * 2)).toInt().clamp(1, srcH - y);

    final img.Image cropped =
        img.copyCrop(originalImage, x: x, y: y, width: width, height: height);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
  } catch (e) {
    debugPrint('Error detecting or cropping face: $e');
    return null;
  }
}

/// Extracts the holder signature area (below the face) as JPEG bytes.
Future<Uint8List?> detectAndCropSignature(String imagePath) async {
  if (!_supported) return null;

  try {
    final inputImage = InputImage.fromFilePath(imagePath);
    final List<Face> faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    final Rect faceBox = faces.first.boundingBox;
    final img.Image? originalImage = img.decodeImage(await File(imagePath).readAsBytes());
    if (originalImage == null) return null;

    final int srcW = originalImage.width;
    final int srcH = originalImage.height;

    final double sigWidth = faceBox.width * 1.5;
    final double sigHeight = faceBox.height * 0.60;
    final double sigLeft = faceBox.left - (faceBox.width * 0.25);
    final double sigTop = faceBox.bottom + (faceBox.height * 0.15);

    final int x = sigLeft.toInt().clamp(0, srcW);
    final int y = sigTop.toInt().clamp(0, srcH);
    final int w = sigWidth.toInt().clamp(1, srcW - x);
    final int h = sigHeight.toInt().clamp(1, srcH - y);

    final img.Image cropped =
        img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
  } catch (e) {
    debugPrint('Error cropping holder signature: $e');
    return null;
  }
}

/// Extracts the authority signature area (fixed lower-left region) as JPEG bytes.
Future<Uint8List?> cropAuthoritySignature(String imagePath) async {
  if (!_supported) return null;

  try {
    final img.Image? originalImage = img.decodeImage(await File(imagePath).readAsBytes());
    if (originalImage == null) return null;

    final int srcW = originalImage.width;
    final int srcH = originalImage.height;

    final int x = (srcW * 0.05).toInt();
    final int y = (srcH * 0.55).toInt();
    final int w = (srcW * 0.40).toInt().clamp(1, srcW - x);
    final int h = (srcH * 0.28).toInt().clamp(1, srcH - y);

    final img.Image cropped =
        img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
  } catch (e) {
    debugPrint('Error cropping back signature: $e');
    return null;
  }
}
