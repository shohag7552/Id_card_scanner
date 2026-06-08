import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FaceDetectorService {
  static final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  /// Releases resources. Should be called when the service is no longer needed.
  static void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _faceDetector.close();
    }
  }

  /// Detects a face in the ID card image, crops it, and returns the path to the cropped image.
  /// Returns null if no face is detected or if run on an unsupported platform.
  static Future<String?> detectAndCropFace(String imagePath) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      debugPrint('Face detection skipped: Unsupported platform');
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint('No faces detected in the image');
        return null;
      }

      // Crop the first detected face
      final Face face = faces.first;
      final Rect boundingBox = face.boundingBox;

      // Load original image bytes using the 'image' library
      final File file = File(imagePath);
      final Uint8List bytes = await file.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        debugPrint('Failed to decode original image for cropping');
        return null;
      }

      // Ensure coordinates are within bounds
      // ML Kit bounding box coordinates are relative to the image size
      final int srcW = originalImage.width;
      final int srcH = originalImage.height;

      // Sometimes bounding box can have negative values or exceed image bounds
      // Add a slight padding to the face crop (e.g. 15% padding)
      final int padX = (boundingBox.width * 0.15).toInt();
      final int padY = (boundingBox.height * 0.15).toInt();

      final int x = (boundingBox.left - padX).toInt().clamp(0, srcW);
      final int y = (boundingBox.top - padY).toInt().clamp(0, srcH);
      final int width = (boundingBox.width + (padX * 2)).toInt().clamp(1, srcW - x);
      final int height = (boundingBox.height + (padY * 2)).toInt().clamp(1, srcH - y);

      // Crop using the 'image' library
      final img.Image croppedFace = img.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: width,
        height: height,
      );

      // Save the cropped face to a temporary file
      final Uint8List croppedBytes = img.encodeJpg(croppedFace, quality: 90);
      final Directory tempDir = await getTemporaryDirectory();
      final String croppedPath =
          '${tempDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final File croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(croppedBytes);

      debugPrint('Face cropped successfully and saved to: $croppedPath');
      return croppedPath;
    } catch (e) {
      debugPrint('Error detecting or cropping face: $e');
      return null;
    }
  }

  /// Extracts the signature area from the front card image relative to the detected face.
  /// Typically, on Bangladesh NID, the signature is directly below the face photo.
  static Future<String?> detectAndCropSignature(String imagePath) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      debugPrint('Signature detection skipped: Unsupported platform');
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        debugPrint('No faces detected for signature reference');
        return null;
      }

      final Face face = faces.first;
      final Rect faceBox = face.boundingBox;

      final File file = File(imagePath);
      final Uint8List bytes = await file.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        debugPrint('Failed to decode image for signature cropping');
        return null;
      }

      final int srcW = originalImage.width;
      final int srcH = originalImage.height;

      // Define a box below the face box.
      // Width: 1.5 times the face width, centered.
      // Height: 0.6 times the face height.
      // Top: faceBox.bottom + 0.15 * faceBox.height
      final double sigWidth = faceBox.width * 1.5;
      final double sigHeight = faceBox.height * 0.60;
      final double sigLeft = faceBox.left - (faceBox.width * 0.25);
      final double sigTop = faceBox.bottom + (faceBox.height * 0.15);

      final int x = sigLeft.toInt().clamp(0, srcW);
      final int y = sigTop.toInt().clamp(0, srcH);
      final int w = sigWidth.toInt().clamp(1, srcW - x);
      final int h = sigHeight.toInt().clamp(1, srcH - y);

      final img.Image croppedSig = img.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: w,
        height: h,
      );

      final Uint8List croppedBytes = img.encodeJpg(croppedSig, quality: 90);
      final Directory tempDir = await getTemporaryDirectory();
      final String croppedPath =
          '${tempDir.path}/signature_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final File croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(croppedBytes);

      debugPrint('Front signature cropped and saved to: $croppedPath');
      return croppedPath;
    } catch (e) {
      debugPrint('Error cropping holder signature: $e');
      return null;
    }
  }

  /// Extracts the authority signature area from the back card image.
  /// Uses a relative percentage bounding box for the lower-left quadrant:
  /// Left: 5% to 45% of width, Top: 55% to 83% of height.
  static Future<String?> cropAuthoritySignature(String imagePath) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      debugPrint('Authority signature crop skipped: Unsupported platform');
      return null;
    }

    try {
      final File file = File(imagePath);
      final Uint8List bytes = await file.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        debugPrint('Failed to decode back image for signature cropping');
        return null;
      }

      final int srcW = originalImage.width;
      final int srcH = originalImage.height;

      // Define bounding box relative to the card's dimensions.
      // Left: 5% to 45% of width
      // Top: 55% to 83% of height
      final int x = (srcW * 0.05).toInt();
      final int y = (srcH * 0.55).toInt();
      final int w = (srcW * 0.40).toInt().clamp(1, srcW - x);
      final int h = (srcH * 0.28).toInt().clamp(1, srcH - y);

      final img.Image croppedSig = img.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: w,
        height: h,
      );

      final Uint8List croppedBytes = img.encodeJpg(croppedSig, quality: 90);
      final Directory tempDir = await getTemporaryDirectory();
      final String croppedPath =
          '${tempDir.path}/auth_signature_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final File croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(croppedBytes);

      debugPrint('Back authority signature cropped and saved to: $croppedPath');
      return croppedPath;
    } catch (e) {
      debugPrint('Error cropping back signature: $e');
      return null;
    }
  }
}

