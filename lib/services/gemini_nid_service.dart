import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import '../models/card_info.dart';

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
  static const String _modelName = 'gemini-2.5-flash';

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
        description: 'Date of issue as printed (প্রদানের তারিখ).',
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

Rules:
- Return an empty string "" for any field that is not visible.
- Do NOT translate, transliterate, guess, or invent any value. Only return what is actually printed.
''';

  /// True when Firebase has been initialized and Gemini can be used.
  static bool get isAvailable => Firebase.apps.isNotEmpty;

  /// Scans the NID using the [frontPath] image and, if provided, [backPath].
  /// Returns the extracted [CardInfo] plus an [NidScanResult.error] message when
  /// something goes wrong, so the UI can tell the user exactly what happened
  /// instead of silently showing a blank form.
  static Future<NidScanResult> scanNid({
    required String frontPath,
    String? backPath,
  }) async {
    final bool isMock = frontPath.contains('mock') || (backPath?.contains('mock') ?? false);

    if (isMock) {
      return NidScanResult(info: await _simulatedResult(frontPath));
    }

    if (!isAvailable) {
      return NidScanResult(
        info: await _simulatedResult(frontPath),
        error: 'Firebase is not initialized — showing sample data. '
            'Make sure Firebase.initializeApp() succeeded.',
      );
    }

    try {
      final model = FirebaseAI.googleAI().generativeModel(
        model: _modelName,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _nidSchema,
        ),
        // Reading a government ID is legitimate, but the default filters can
        // occasionally block PII extraction. Relax them so the scan isn't
        // silently refused.
        safetySettings: _safetySettings,
      );

      final parts = <Part>[TextPart(_prompt)];
      parts.add(InlineDataPart('image/jpeg', await File(frontPath).readAsBytes()));
      if (backPath != null) {
        parts.add(InlineDataPart('image/jpeg', await File(backPath).readAsBytes()));
      }

      final response = await model.generateContent([Content.multi(parts)]);

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

      if (info.isEmpty) {
        return NidScanResult(
          info: info,
          error: 'Gemini responded but found no readable fields. '
              'Try clearer, well-lit, straight photos of the card.',
        );
      }

      return NidScanResult(info: info);
    } catch (e) {
      debugPrint('Gemini NID scan error: $e');
      return NidScanResult(info: const CardInfo(), error: _friendlyError(e));
    }
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
    if (lower.contains('not found') || lower.contains('404')) {
      return 'Model "$_modelName" was not found for this backend. '
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

  /// Fallback used on desktop/web or before Firebase is configured, so the NID
  /// template flow can still be previewed with realistic Bangla data.
  static Future<CardInfo> _simulatedResult(String frontPath) async {
    await Future.delayed(const Duration(milliseconds: 1800));

    final bool isFemale = frontPath.contains('female') || frontPath.contains('suraiya');

    final base = isFemale
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

    // Drop a 1x1 placeholder so the template avatar/signature slots render on
    // platforms where ML Kit face cropping is unavailable.
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final bytes = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
        0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
        120, 1, 99, 96, 96, 96, 0, 0, 0, 5, 0, 1, 165, 246, 69, 122, 0, 0, 0, 0,
        73, 69, 78, 68, 174, 66, 96, 130,
      ]);
      final avatarFile = File('${tempDir.path}/mock_avatar.png');
      final sigFile = File('${tempDir.path}/mock_sig.png');
      final authSigFile = File('${tempDir.path}/mock_auth_sig.png');
      if (!avatarFile.existsSync()) await avatarFile.writeAsBytes(bytes);
      if (!sigFile.existsSync()) await sigFile.writeAsBytes(bytes);
      if (!authSigFile.existsSync()) await authSigFile.writeAsBytes(bytes);

      return base.copyWith(
        avatarPath: avatarFile.path,
        signaturePath: sigFile.path,
        authoritySignaturePath: authSigFile.path,
      );
    } catch (_) {
      return base;
    }
  }
}
