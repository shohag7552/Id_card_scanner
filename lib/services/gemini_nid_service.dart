import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/card_info.dart';
import 'image_crop_util.dart';

/// Outcome of a Gemini NID scan: the extracted [info], plus an optional
/// [error] message describing why extraction failed (null on success).
class NidScanResult {
  final CardInfo info;
  final String? error;

  const NidScanResult({required this.info, this.error});

  bool get hasError => error != null;
}

/// Extracts Bangladesh National ID (NID) details from front/back card photos
/// using Gemini 2.5 Flash via Firebase AI (Gemini Developer API backend).
///
/// Gemini reads Bangla script natively, so there is no regex/OCR post-processing:
/// the model returns structured JSON matching [_nidSchema], which maps 1:1 to
/// [CardInfo]. When Firebase is not configured (e.g. before `flutterfire
/// configure`, or on desktop/web), it falls back to a simulated result so the
/// app still runs.
class GeminiNidService {
  /// Models tried in order. If the primary is overloaded (HTTP 500/503), the
  /// scan automatically falls back to the next one.
  static const List<String> _models = ['gemini-2.5-flash', 'gemini-2.5-flash-lite'];

  /// Retry attempts per model before moving on to the fallback.
  static const int _maxAttemptsPerModel = 3;

  /// Relaxed safety thresholds so legitimate ID extraction isn't blocked.
  static final List<SafetySetting> _safetySettings = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none, null),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none, null),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none, null),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none, null),
  ];

  /// JSON schema Gemini must return. Every field is optional so each side of the
  /// card can contribute only the fields it actually shows.
  static final Schema _nidSchema = Schema.object(
    properties: {
      'banglaName': Schema.string(
        description: 'Full name in Bangla script (নাম), exactly as printed.',
      ),
      'englishName': Schema.string(
        description: 'Full name in English, uppercase, exactly as printed (Name).',
      ),
      'banglaFatherName': Schema.string(
        description: "Father's name in Bangla script (পিতা).",
      ),
      'banglaMotherName': Schema.string(
        description: "Mother's name in Bangla script (মাতা).",
      ),
      'dateOfBirth': Schema.string(
        description: 'Date of Birth as printed, e.g. "20 Dec 2006".',
      ),
      'idNumber': Schema.string(
        description: 'NID / ID number digits only (10, 13 or 17 digits).',
      ),
      'address': Schema.string(
        description: 'Full address in Bangla from the back side (ঠিকানা).',
      ),
      'bloodGroup': Schema.string(
        description: 'Blood group, e.g. "O+", "A+" (রক্তের গ্রুপ).',
      ),
      'birthPlace': Schema.string(
        description: 'Place of birth in Bangla (জন্মস্থান).',
      ),
      'issueDate': Schema.string(
        description: 'The DATE OF ISSUE on the BACK side, labelled "প্রদানের তারিখ" '
            'or "Date of Issue" (usually near the authority signature). Return it '
            'EXACTLY as printed, keeping Bangla digits if shown in Bangla, e.g. '
            '"০৮/০৬/২০২৬". This is NOT the date of birth.',
      ),
      'photoBox': Schema.array(
        items: Schema.integer(),
        description: 'Bounding box of the holder PHOTO in the FIRST (front) image '
            'as [ymin, xmin, ymax, xmax] normalized to 0-1000.',
      ),
      'holderSignatureBox': Schema.array(
        items: Schema.integer(),
        description: 'TIGHT bounding box around ONLY the holder\'s handwritten '
            'signature stroke in the FIRST (front) image, as [ymin, xmin, ymax, '
            'xmax] normalized to 0-1000. EXCLUDE any printed label text, the name, '
            'lines or borders — only the signature ink itself.',
      ),
      'authoritySignatureBox': Schema.array(
        items: Schema.integer(),
        description: 'TIGHT bounding box around ONLY the issuing authority\'s '
            'handwritten signature/seal mark in the SECOND (back) image, as [ymin, '
            'xmin, ymax, xmax] normalized to 0-1000. EXCLUDE the printed caption '
            '"প্রদানকারী কর্তৃপক্ষের স্বাক্ষর", any dates, lines or other text — '
            'only the signature ink itself.',
      ),
    },
    optionalProperties: const [
      'banglaName',
      'englishName',
      'banglaFatherName',
      'banglaMotherName',
      'dateOfBirth',
      'idNumber',
      'address',
      'bloodGroup',
      'birthPlace',
      'issueDate',
      'photoBox',
      'holderSignatureBox',
      'authoritySignatureBox',
    ],
  );

  static const String _prompt = '''
You are an expert at reading Bangladesh National ID (NID / জাতীয় পরিচয়পত্র) cards.
You are given the FRONT and (optionally) BACK images of one NID card.

Extract these fields and return them as JSON matching the provided schema:
- Bangla fields (name, father, mother, address, birth place, issue date) MUST be in Bangla script, exactly as printed.
- The English name must be uppercase, exactly as printed.
- The ID number must be digits only.
- The front side usually holds: name (Bangla + English), father, mother, date of birth, ID number.
- The back side usually holds: address, blood group, birth place, date of issue.

Dates — read very carefully and do NOT mix them up:
- dateOfBirth is on the FRONT, labelled "Date of Birth" (in English digits, e.g. "20 Dec 2006").
- issueDate is on the BACK, labelled "প্রদানের তারিখ" or "Date of Issue", usually at the bottom near the issuing authority's signature.
- Read each digit one by one. Bangla digit map: ০=0, ১=1, ২=2, ৩=3, ৪=4, ৫=5, ৬=6, ৭=7, ৮=8, ৯=9.
- Return issueDate in the SAME script it is printed in (if printed in Bangla digits, keep Bangla digits), exactly as shown including the "/" separators. Double-check each digit against the image before answering.
- If you cannot read the issue date clearly, return "" rather than guessing.

Also locate these regions and return their bounding boxes as [ymin, xmin, ymax, xmax]
normalized to 0-1000 (omit a box if that region is not visible):
- photoBox: the holder's photograph in the FIRST (front) image.
- holderSignatureBox: the holder's handwritten signature in the FIRST (front) image.
- authoritySignatureBox: the issuing authority's signature in the SECOND (back) image.

Signature boxes must be TIGHT around ONLY the handwritten signature ink / seal mark.
Do NOT include any printed caption text (e.g. "প্রদানকারী কর্তৃপক্ষের স্বাক্ষর"), names,
dates, underlines, boxes or other surrounding text inside the signature boxes.

Rules:
- Return an empty string "" for any text field that is not visible.
- Do NOT translate, transliterate, guess, or invent any value. Only return what is actually printed.
''';

  /// True when Firebase has been initialized and Gemini can be used.
  static bool get isAvailable => Firebase.apps.isNotEmpty;

  /// Returns a simulated result with realistic Bangla sample data. Used for the
  /// on-screen "Test Simulation" buttons and as a fallback when Firebase is not
  /// configured (e.g. on desktop/web before setup).
  static NidScanResult simulated({required bool isFemale}) {
    return NidScanResult(info: _simulatedInfo(isFemale));
  }

  /// Scans the NID from the [frontBytes] image and, if provided, [backBytes].
  /// Returns the extracted [CardInfo] plus an [NidScanResult.error] message when
  /// something goes wrong, so the UI can tell the user exactly what happened
  /// instead of silently showing a blank form.
  static Future<NidScanResult> scanNid({
    required Uint8List frontBytes,
    Uint8List? backBytes,
  }) async {
    if (!isAvailable) {
      return NidScanResult(
        info: _simulatedInfo(false),
        error: 'Firebase is not initialized — showing sample data. '
            'Make sure Firebase.initializeApp() succeeded.',
      );
    }

    try {
      final parts = <Part>[TextPart(_prompt)];
      parts.add(InlineDataPart('image/jpeg', frontBytes));
      if (backBytes != null) {
        parts.add(InlineDataPart('image/jpeg', backBytes));
      }

      // Try each model, retrying transient 500/503 "overloaded" errors with
      // exponential backoff before falling back to the next model.
      GenerateContentResponse? response;
      Object? lastError;
      outer:
      for (final modelName in _models) {
        final model = FirebaseAI.googleAI().generativeModel(
          model: modelName,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _nidSchema,
          ),
          // Reading a government ID is legitimate, but the default filters can
          // occasionally block PII extraction. Relax them so the scan isn't
          // silently refused.
          safetySettings: _safetySettings,
        );

        for (int attempt = 1; attempt <= _maxAttemptsPerModel; attempt++) {
          try {
            response = await model.generateContent([Content.multi(parts)]);
            break outer;
          } catch (e) {
            lastError = e;
            if (!_isRetryable(e)) {
              // Permanent error (bad key, permission, etc.) — report it now.
              return NidScanResult(info: const CardInfo(), error: _friendlyError(e));
            }
            debugPrint('Gemini "$modelName" attempt $attempt failed (retryable): $e');
            if (attempt < _maxAttemptsPerModel) {
              await Future.delayed(Duration(milliseconds: 600 * (1 << (attempt - 1))));
            }
          }
        }
      }

      if (response == null) {
        return NidScanResult(
          info: const CardInfo(),
          error: _friendlyError(lastError ?? 'Unknown error'),
        );
      }

      // 1. Whole prompt rejected (e.g. safety) before any output.
      final blockReason = response.promptFeedback?.blockReason;
      if (blockReason != null) {
        return NidScanResult(
          info: const CardInfo(),
          error: 'Gemini blocked the request (reason: $blockReason). '
              'It may be refusing to extract data from an ID document.',
        );
      }

      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        final finish = response.candidates.isNotEmpty
            ? response.candidates.first.finishReason
            : null;
        return NidScanResult(
          info: const CardInfo(),
          error: 'Gemini returned no text (finishReason: $finish). '
              'A SAFETY finishReason means it declined to read the ID.',
        );
      }

      debugPrint('Gemini NID raw JSON: $text');
      final map = jsonDecode(text) as Map<String, dynamic>;
      final info = _cardInfoFromMap(map);

      // Crop the photo / signatures locally from Gemini's bounding boxes. Pure
      // Dart cropping, so it works identically on mobile, web and Windows.
      final infoWithImages = info.copyWith(
        avatarBytes: cropNormalizedBox(frontBytes, boxFromJson(map['photoBox']), padding: 0.12),
        // No padding on signatures: the box is already meant to be tight, and
        // expanding it pulls in the surrounding printed caption text.
        signatureBytes: cropNormalizedBox(frontBytes, boxFromJson(map['holderSignatureBox']), padding: 0.0),
        authoritySignatureBytes: cropNormalizedBox(backBytes, boxFromJson(map['authoritySignatureBox']), padding: 0.0),
      );

      if (infoWithImages.isEmpty) {
        return NidScanResult(
          info: infoWithImages,
          error: 'Gemini responded but found no readable fields. '
              'Try clearer, well-lit, straight photos of the card.',
        );
      }

      return NidScanResult(info: infoWithImages);
    } catch (e) {
      debugPrint('Gemini NID scan error: $e');
      return NidScanResult(info: const CardInfo(), error: _friendlyError(e));
    }
  }

  /// True for transient server errors that are worth retrying (overload /
  /// temporary unavailability), per the message text the SDK surfaces.
  static bool _isRetryable(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('500') ||
        m.contains('503') ||
        m.contains('internal') ||
        m.contains('unavailable') ||
        m.contains('overloaded') ||
        m.contains('high demand') ||
        m.contains('try again');
  }

  /// Turns raw SDK exceptions into actionable hints for the most common setup
  /// problems (API not enabled, billing, network, etc.).
  static String _friendlyError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('permission_denied') ||
        lower.contains('service_disabled') ||
        lower.contains('has not been used') ||
        lower.contains('403')) {
      return 'Permission denied. Open Firebase Console → Build → Firebase AI '
          'Logic and enable the Gemini Developer API for this project, then retry.\n\n$msg';
    }
    if (_isRetryable(e)) {
      return 'Gemini is temporarily overloaded (high demand). We retried '
          'automatically but it is still busy. Please wait a moment and tap '
          'scan again.\n\n$msg';
    }
    if (lower.contains('not found') || lower.contains('404')) {
      return 'Model "${_models.first}" was not found for this backend. '
          'It may not be available yet on the Gemini Developer API.\n\n$msg';
    }
    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('failed host lookup')) {
      return 'Network error reaching Gemini. Check the device internet '
          'connection.\n\n$msg';
    }
    return msg;
  }

  static CardInfo _cardInfoFromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] as String?)?.trim() ?? '';

    final dob = s('dateOfBirth');
    return CardInfo(
      banglaName: s('banglaName'),
      englishName: s('englishName'),
      banglaFatherName: s('banglaFatherName'),
      banglaMotherName: s('banglaMotherName'),
      dateOfBirth: dob,
      age: _calculateAgeFromDob(dob),
      idNumber: s('idNumber'),
      address: s('address'),
      bloodGroup: s('bloodGroup').toUpperCase(),
      birthPlace: s('birthPlace'),
      issueDate: s('issueDate'),
    );
  }

  /// Derives an age string ("26 Years") from any 4-digit year inside [dob].
  static String _calculateAgeFromDob(String dob) {
    final yearMatch = RegExp(r'\b(19\d{2}|20[0-2]\d)\b').firstMatch(dob);
    if (yearMatch == null) return '';
    final birthYear = int.parse(yearMatch.group(1)!);
    final age = DateTime.now().year - birthYear;
    return age > 0 ? '$age Years' : '';
  }

  /// Realistic Bangla sample data used for previews / fallback. Images are left
  /// null so the templates render their built-in placeholders.
  static CardInfo _simulatedInfo(bool isFemale) {
    return isFemale
        ? const CardInfo(
            banglaName: 'ছাবরিনা তাবাচ্ছুম সুরাইয়া',
            englishName: 'SUBRINA TABASSUM SURAIYA',
            banglaFatherName: 'মোঃ মাহবুবুর রহমান',
            banglaMotherName: 'খাতুনে জান্নাত শাহানাজ পারভীন',
            idNumber: '8279557295',
            dateOfBirth: '20 Dec 2006',
            age: '19 Years',
            address: 'বাসা/হোল্ডিং: ৪২৩, গ্রাম/রাস্তা: কীর্তিপাশা, ডাকঘর: কীর্তিপাশা - ৮৪০০, ঝালকাঠী সদর, ঝালকাঠী',
            bloodGroup: 'O+',
            birthPlace: 'ঝালকাঠী',
            issueDate: '০৮/০৬/২০২৬',
          )
        : const CardInfo(
            banglaName: 'মো: আব্দুল মমিন',
            englishName: 'MD. ABDUL MOMIN',
            banglaFatherName: 'মো: নুরুল ইসলাম',
            banglaMotherName: 'মোছা: ফেরদৌছি খাতুন',
            idNumber: '5110034286',
            dateOfBirth: '14 Mar 2000',
            age: '26 Years',
            address: 'বাসা/হোল্ডিং: ১২, গ্রাম/রাস্তা: ধানমন্ডি, ডাকঘর: ঢাকা - ১২০৯',
            bloodGroup: 'A+',
            birthPlace: 'লালমনিরহাট',
            issueDate: '১২/০৫/২০২২',
          );
  }
}
