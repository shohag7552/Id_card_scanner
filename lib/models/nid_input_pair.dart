import 'package:flutter/foundation.dart';

/// One NID's source images during the *setup* stage, before scanning. Mutable so
/// the user can swap the front or back image of a single pair in the review list
/// without disturbing the others.
class NidInputPair {
  /// Front side — required for a pair to be scannable.
  Uint8List front;

  /// Back side — optional (front-only scans are allowed).
  Uint8List? back;

  NidInputPair({required this.front, this.back});
}
