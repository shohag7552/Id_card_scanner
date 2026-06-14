import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
/// using Gemini 2.5 Flash via the Gemini Developer (Generative Language) REST
/// API, authenticated with an API key passed through --dart-define.
///
/// Gemini reads Bangla script natively, so there is no regex/OCR post-processing:
/// the model returns structured JSON matching [_nidSchema], which maps 1:1 to
/// [CardInfo]. When no API key is configured (e.g. on desktop/web before setup),
/// it falls back to a simulated result so the app still runs.
class GeminiNidService {
  /// Models tried in order. If the primary is overloaded (HTTP 500/503), the
  /// scan automatically falls back to the next one.
  static const List<String> _models = ['gemini-2.5-flash', 'gemini-2.5-flash-lite'];

  /// Retry attempts per model before moving on to the fallback.
  static const int _maxAttemptsPerModel = 3;

  /// API key for the Gemini Developer (Generative Language) API. Injected at
  /// build/run time so it is never hardcoded or committed:
  ///   flutter run --dart-define=GEMINI_API_KEY=xxxx
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Base endpoint for the stable Gemini REST API. The model name and
  /// `:generateContent` action are appended per request.
  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Relaxed safety thresholds (REST `safetySettings`) so legitimate ID
  /// extraction isn't blocked.
  static const List<Map<String, String>> _safetySettings = [
    {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
    {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
    {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_NONE'},
    {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
  ];

  /// JSON schema (OpenAPI subset) Gemini must return via `responseSchema`.
  /// Every field is optional — no `required` list — so each side of the card
  /// can contribute only the fields it actually shows.
  static const Map<String, dynamic> _nidSchema = {
    'type': 'OBJECT',
    'properties': {
      'banglaName': {
        'type': 'STRING',
        'description': 'Full name in Bangla script (নাম), exactly as printed.',
      },
      'englishName': {
        'type': 'STRING',
        'description': 'Full name in English, uppercase, exactly as printed (Name).',
      },
      'banglaFatherName': {
        'type': 'STRING',
        'description': "Father's name in Bangla script (পিতা).",
      },
      'banglaMotherName': {
        'type': 'STRING',
        'description': "Mother's name in Bangla script (মাতা).",
      },
      'dateOfBirth': {
        'type': 'STRING',
        'description': 'Date of Birth as printed, e.g. "20 Dec 2006".',
      },
      'idNumber': {
        'type': 'STRING',
        'description': 'NID / ID number digits only (10, 13 or 17 digits).',
      },
      'address': {
        'type': 'STRING',
        'description': 'Full address in Bangla from the back side (ঠিকানা).',
      },
      'bloodGroup': {
        'type': 'STRING',
        'description': 'Blood group, e.g. "O+", "A+" (রক্তের গ্রুপ).',
      },
      'birthPlace': {
        'type': 'STRING',
        'description': 'Place of birth in Bangla (জন্মস্থান).',
      },
      'issueDate': {
        'type': 'STRING',
        'description': 'The DATE OF ISSUE on the BACK side, labelled "প্রদানের তারিখ" '
            'or "Date of Issue" (usually near the authority signature). Return it '
            'EXACTLY as printed, keeping Bangla digits if shown in Bangla, e.g. '
            '"০৮/০৬/২০২৬". This is NOT the date of birth.',
      },
      'faceBox': {
        'type': 'ARRAY',
        'items': {'type': 'INTEGER'},
        'description': 'TIGHT bounding box around ONLY the holder\'s FACE/HEAD in '
            'the FIRST (front) image — from the TOP of the hair down to the bottom '
            'of the CHIN, and across BOTH ears — as [ymin, xmin, ymax, xmax] '
            'normalized to 0-1000. Include the whole head with a small margin, but '
            'EXCLUDE the shoulders/body, the card background, any printed text and '
            'borders. This is the passport-style portrait used as the holder\'s '
            'avatar, so it must be accurate and well-centered on the face.',
      },
      'photoBox': {
        'type': 'ARRAY',
        'items': {'type': 'INTEGER'},
        'description': 'Fallback only: the FULL holder photograph region (head and '
            'shoulders) in the FIRST (front) image as [ymin, xmin, ymax, xmax] '
            'normalized to 0-1000. Used only when faceBox cannot be determined.',
      },
      'holderSignatureBox': {
        'type': 'ARRAY',
        'items': {'type': 'INTEGER'},
        'description': 'TIGHT bounding box around ONLY the holder\'s handwritten '
            'signature stroke in the FIRST (front) image, as [ymin, xmin, ymax, '
            'xmax] normalized to 0-1000. EXCLUDE any printed label text, the name, '
            'lines or borders — only the signature ink itself.',
      },
      'authoritySignatureBox': {
        'type': 'ARRAY',
        'items': {'type': 'INTEGER'},
        'description': 'TIGHT bounding box around ONLY the issuing authority\'s '
            'handwritten signature/seal mark in the SECOND (back) image, as [ymin, '
            'xmin, ymax, xmax] normalized to 0-1000. EXCLUDE the printed caption '
            '"প্রদানকারী কর্তৃপক্ষের স্বাক্ষর", any dates, lines or other text — '
            'only the signature ink itself.',
      },
    },
  };

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
- faceBox: a TIGHT box around ONLY the holder's FACE/HEAD in the FIRST (front) image —
  from the top of the hair to the bottom of the chin and across both ears, with only a
  small margin. EXCLUDE the shoulders/body, the card background, text and borders. This
  is the cropped portrait used as the avatar, so center it accurately on the face.
- photoBox: the FULL holder photograph (head and shoulders) in the FIRST (front) image.
  This is a fallback for faceBox — still provide it.
- holderSignatureBox: the holder's handwritten signature in the FIRST (front) image.
- authoritySignatureBox: the issuing authority's signature in the SECOND (back) image.

The faceBox must frame the head like a passport photo: do not cut off the hair, chin or
ears, and do not include the body or background beyond a small margin.

Signature boxes must be TIGHT around ONLY the handwritten signature ink / seal mark.
Do NOT include any printed caption text (e.g. "প্রদানকারী কর্তৃপক্ষের স্বাক্ষর"), names,
dates, underlines, boxes or other surrounding text inside the signature boxes.

Rules:
- Return an empty string "" for any text field that is not visible.
- Do NOT translate, transliterate, guess, or invent any value. Only return what is actually printed.
''';

  /// True when a Gemini API key has been provided via --dart-define.
  static bool get isAvailable => _apiKey.isNotEmpty;

  /// Returns a simulated result with realistic Bangla sample data. Used for the
  /// on-screen "Test Simulation" buttons and as a fallback when no API key is
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
        error: 'No Gemini API key configured — showing sample data. '
            'Run with --dart-define=GEMINI_API_KEY=your_key.',
      );
    }

    try {
      // Build the REST request body once; it is identical across model retries.
      final parts = <Map<String, dynamic>>[
        {'text': _prompt},
        {
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(frontBytes),
          }
        },
      ];
      if (backBytes != null) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(backBytes),
          }
        });
      }

      final body = jsonEncode({
        'contents': [
          {'parts': parts}
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': _nidSchema,
        },
        // Reading a government ID is legitimate, but the default filters can
        // occasionally block PII extraction. Relax them so the scan isn't
        // silently refused.
        'safetySettings': _safetySettings,
      });

      // Try each model, retrying transient 500/503 "overloaded" errors with
      // exponential backoff before falling back to the next model.
      Map<String, dynamic>? response;
      Object? lastError;
      outer:
      for (final modelName in _models) {
        for (int attempt = 1; attempt <= _maxAttemptsPerModel; attempt++) {
          try {
            response = await _post(modelName, body);
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
      final blockReason = response['promptFeedback']?['blockReason'];
      if (blockReason != null) {
        return NidScanResult(
          info: const CardInfo(),
          error: 'Gemini blocked the request (reason: $blockReason). '
              'It may be refusing to extract data from an ID document.',
        );
      }

      final candidates = response['candidates'] as List<dynamic>?;
      final text = _textFromCandidates(candidates);
      if (text == null || text.trim().isEmpty) {
        final finish = (candidates != null && candidates.isNotEmpty)
            ? candidates.first['finishReason']
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
        // Prefer Gemini's tight faceBox (AI face detection — works everywhere,
        // including web). Fall back to the looser full-photo box if the model
        // could not isolate the face.
        avatarBytes:
            cropNormalizedBox(frontBytes, boxFromJson(map['faceBox']), padding: 0.15) ??
                cropNormalizedBox(frontBytes, boxFromJson(map['photoBox']), padding: 0.12),
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

  /// POSTs [body] to the [modelName] `:generateContent` endpoint and returns the
  /// decoded JSON. Throws on non-200 responses with a message that includes the
  /// status code and the server's detail, so [_isRetryable] / [_friendlyError]
  /// can classify it.
  static Future<Map<String, dynamic>> _post(String modelName, String body) async {
    final uri = Uri.parse('$_endpoint/$modelName:generateContent?key=$_apiKey');
    final res = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    // Surface the server's error message — it usually carries a clear reason
    // (PERMISSION_DENIED, invalid API key, model not found, overloaded, ...).
    String detail = res.body;
    try {
      detail = (jsonDecode(res.body)['error']?['message'])?.toString() ?? res.body;
    } catch (_) {}
    throw Exception('HTTP ${res.statusCode}: $detail');
  }

  /// Concatenates the text from the first candidate's parts (the JSON payload
  /// Gemini produced), or null if the response has no usable content.
  static String? _textFromCandidates(List<dynamic>? candidates) {
    if (candidates == null || candidates.isEmpty) return null;
    final parts = candidates.first['content']?['parts'] as List<dynamic>?;
    if (parts == null) return null;
    final buffer = StringBuffer();
    for (final part in parts) {
      final t = part['text'];
      if (t is String) buffer.write(t);
    }
    return buffer.toString();
  }

  /// True for transient server errors that are worth retrying (overload /
  /// temporary unavailability), per the message text the API surfaces.
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

  /// Turns raw API errors into actionable hints for the most common setup
  /// problems (bad/invalid key, API not enabled, billing, network, etc.).
  static String _friendlyError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('api_key_invalid') ||
        lower.contains('api key not valid') ||
        lower.contains('unauthenticated') ||
        lower.contains('401')) {
      return 'The Gemini API key is missing or invalid. Check the value passed '
          'via --dart-define=GEMINI_API_KEY.\n\n$msg';
    }
    if (lower.contains('permission_denied') ||
        lower.contains('service_disabled') ||
        lower.contains('has not been used') ||
        lower.contains('403')) {
      return 'Permission denied. In Google Cloud Console for this API key, enable '
          'the "Generative Language API" and make sure billing is active, then retry.\n\n$msg';
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
