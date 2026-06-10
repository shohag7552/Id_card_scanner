import 'package:flutter/foundation.dart';
import 'card_info.dart';

/// Lifecycle of a single NID inside a batch run.
enum BatchStatus {
  /// Waiting in the queue, not yet processed.
  queued,

  /// Currently being read by Gemini.
  scanning,

  /// Scan done; the card is being rendered/captured to PNG.
  rendering,

  /// Scanned but flagged for a human to check/fix before export
  /// (missing key fields or a scan error).
  needsReview,

  /// Rendered successfully and ready to download.
  done,

  /// Could not be processed even after retries.
  failed,
}

/// One NID in a batch: its source images, the extracted [info], the rendered
/// card PNGs and its current [status]. Mutable because a batch item moves
/// through its lifecycle in place as the queue is processed.
class BatchItem {
  /// Position in the batch (0-based), used for stable filenames/labels.
  final int index;

  final Uint8List frontBytes;
  final Uint8List? backBytes;

  BatchStatus status;
  CardInfo info;
  String? error;

  /// Rendered card images, populated once [status] reaches [BatchStatus.done]:
  /// the front side, the back side, and a [combinedPng] with both stacked into
  /// a single image. Keeping all three lets the user download any side, in any
  /// format, instantly without re-rendering.
  Uint8List? frontPng;
  Uint8List? backPng;
  Uint8List? combinedPng;

  /// True once the card has been rendered and is downloadable.
  bool get isRendered => combinedPng != null;

  BatchItem({
    required this.index,
    required this.frontBytes,
    this.backBytes,
    this.status = BatchStatus.queued,
    this.info = const CardInfo(),
    this.error,
  });

  /// Human-friendly label: the extracted English name, or a numbered fallback.
  String get displayName =>
      info.englishName.trim().isNotEmpty ? info.englishName.trim() : 'NID ${index + 1}';

  /// A scan is "low confidence" when the two anchor fields a usable card needs
  /// — the English name and the ID number — are missing. These get held back
  /// for review instead of being auto-exported.
  bool get isLowConfidence =>
      info.englishName.trim().isEmpty || info.idNumber.trim().isEmpty;

  /// Filesystem-safe base name for this item's exported files.
  String get safeBaseName {
    final raw = info.englishName.trim().isNotEmpty ? info.englishName : 'nid_${index + 1}';
    final cleaned = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'nid_${index + 1}' : cleaned.toLowerCase();
  }
}
