import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import '../models/card_info.dart';

class RecognizedLineInfo {
  final String text;
  final Rect boundingBox;

  const RecognizedLineInfo({
    required this.text,
    required this.boundingBox,
  });
}

class OcrResult {
  final CardInfo parsedInfo;
  final List<RecognizedLineInfo> lines;

  const OcrResult({
    required this.parsedInfo,
    required this.lines,
  });
}

class OcrService {
  static final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Releases resources. Should be called when the service is no longer needed.
  static void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _textRecognizer.close();
    }
  }

  /// Scans the card image and extracts details.
  /// If run on desktop or web, it falls back to a simulated scan.
  static Future<OcrResult> scanCardImage(String imagePath) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      // Simulate scanning for unsupported platforms
      await Future.delayed(const Duration(milliseconds: 2000));
      final result = _generateSimulatedOcrResult(imagePath);

      final Directory tempDir = await getTemporaryDirectory();
      final avatarFile = File('${tempDir.path}/mock_avatar.png');
      final sigFile = File('${tempDir.path}/mock_sig.png');
      final authSigFile = File('${tempDir.path}/mock_auth_sig.png');

      final bytes = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
        0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
        120, 1, 99, 96, 96, 96, 0, 0, 0, 5, 0, 1, 165, 246, 69, 122, 0, 0, 0, 0,
        73, 69, 78, 68, 174, 66, 96, 130
      ]);

      if (!avatarFile.existsSync()) await avatarFile.writeAsBytes(bytes);
      if (!sigFile.existsSync()) await sigFile.writeAsBytes(bytes);
      if (!authSigFile.existsSync()) await authSigFile.writeAsBytes(bytes);

      final updatedInfo = result.parsedInfo.copyWith(
        avatarPath: avatarFile.path,
        signaturePath: sigFile.path,
        authoritySignaturePath: authSigFile.path,
      );

      return OcrResult(parsedInfo: updatedInfo, lines: result.lines);
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      final List<RecognizedLineInfo> lines = [];
      final List<String> allLinesText = [];

      for (final TextBlock block in recognizedText.blocks) {
        for (final TextLine line in block.lines) {
          lines.add(
            RecognizedLineInfo(
              text: line.text,
              boundingBox: line.boundingBox,
            ),
          );
          allLinesText.add(line.text);
        }
      }

      final parsedInfo = parseExtractedText(allLinesText);
      return OcrResult(parsedInfo: parsedInfo, lines: lines);
    } catch (e) {
      debugPrint('OCR Scanning Error: $e');
      return const OcrResult(
        parsedInfo: CardInfo(),
        lines: [],
      );
    }
  }

  /// Parsed text block lines and attempts to extract fields using regex / heuristics.
  static CardInfo parseExtractedText(List<String> lines) {
    String englishName = '';
    String idNumber = '';
    String dob = '';
    String ageStr = '';
    String address = '';
    String bloodGroup = '';
    String birthPlace = '';
    String issueDate = '';

    // Join all text with newlines for debugging
    final fullText = lines.join('\n');
    debugPrint('OCR RAW TEXT:\n$fullText');

    // 1. Extract ID Number
    final idRegExs = [
      RegExp(r'(?:id\s*no|nid|national\s*id|identity\s*no|card\s*no)[:\s]+([a-zA-Z0-9\s-]{8,20})', caseSensitive: false),
      RegExp(r'\b\d{4}\s\d{4}\s\d{4}\b'), // Indian Aadhaar format
      RegExp(r'\b\d{10}\b'),              // 10 digits
      RegExp(r'\b\d{13}\b'),              // 13 digits
      RegExp(r'\b\d{17}\b'),              // 17 digits
      RegExp(r'\b[A-Z0-9]{9,12}\b'),      // Alpha-numeric passport/ID (uppercase only)
    ];

    for (final line in lines) {
      for (final regex in idRegExs) {
        final match = regex.firstMatch(line);
        if (match != null) {
          final candidate = match.group(0)!;
          String potentialId = match.groupCount >= 1 && match.group(1) != null
              ? match.group(1)!
              : candidate;
          potentialId = potentialId.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
          if (potentialId.length >= 6) {
            idNumber = potentialId;
            break;
          }
        }
      }
      if (idNumber.isNotEmpty) break;
    }

    // 2. Extract Date of Birth and Age
    final dobRegExs = [
      RegExp(r'(?:date\s*of\s*birth|dob|d\.o\.b|birth\s*date)[:\s]+([^\n]+)', caseSensitive: false),
      RegExp(r'\b\d{2}[-/\s]\d{2}[-/\s]\d{4}\b'), // DD/MM/YYYY
      RegExp(r'\b\d{4}[-/\s]\d{2}[-/\s]\d{2}\b'), // YYYY/MM/DD
      RegExp(r'\b\d{2}\s+[A-Za-z]{3,9}\s+\d{4}\b'), // 12 Oct 1990
    ];

    for (final line in lines) {
      for (final regex in dobRegExs) {
        final match = regex.firstMatch(line);
        if (match != null) {
          final potentialDob = match.groupCount >= 1 && match.group(1) != null
              ? match.group(1)!
              : match.group(0)!;
          dob = potentialDob.replaceAll(RegExp(r'[^\w\s-/,]'), '').trim();
          
          // Try to calculate age from DOB
          ageStr = _calculateAgeFromDob(dob);
          break;
        }
      }
      if (dob.isNotEmpty) break;
    }

    // 3. Extract English Name
    final nameRegExs = [
      RegExp(r'(?:full\s*name|english\s*name|name)[:\s]+([^\n]+)', caseSensitive: false),
    ];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.toLowerCase().contains('father') ||
          line.toLowerCase().contains('mother') ||
          line.toLowerCase().contains('husband') ||
          line.toLowerCase().contains('wife') ||
          line.contains('পিতা') ||
          line.contains('মাতা')) {
        continue;
      }
      bool matchFound = false;
      for (final regex in nameRegExs) {
        final match = regex.firstMatch(line);
        if (match != null) {
          matchFound = true;
          if (match.group(1) != null && match.group(1)!.trim().isNotEmpty) {
            englishName = match.group(1)!.trim();
          } else if (i + 1 < lines.length) {
            englishName = lines[i + 1].trim();
          }
          break;
        }
      }
      if (matchFound && englishName.isNotEmpty) break;
    }

    // Heuristic fallback for English Name
    if (englishName.isEmpty) {
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.toLowerCase().contains('government') ||
            trimmed.toLowerCase().contains('card') ||
            trimmed.toLowerCase().contains('identity') ||
            trimmed.toLowerCase().contains('republic') ||
            trimmed.toLowerCase().contains('national') ||
            trimmed.toLowerCase().contains('father') ||
            trimmed.toLowerCase().contains('mother') ||
            trimmed.toLowerCase().contains('husband') ||
            trimmed.toLowerCase().contains('wife') ||
            trimmed.contains('পিতা') ||
            trimmed.contains('মাতা') ||
            trimmed.isEmpty) {
          continue;
        }
        final nameWordsPattern = RegExp(r'^[A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3}$');
        if (nameWordsPattern.hasMatch(trimmed)) {
          englishName = trimmed;
          break;
        }
      }
    }

    // 4. Extract Blood Group
    final bloodRegEx = RegExp(r'(?:blood\s*group|রক্তের\s*গ্রুপ|group)[:\s]+([a-zA-Z\d+-]+)', caseSensitive: false);
    for (final line in lines) {
      final match = bloodRegEx.firstMatch(line);
      if (match != null && match.group(1) != null) {
        bloodGroup = match.group(1)!.trim().toUpperCase();
        break;
      }
    }

    // 5. Extract Birth Place
    final birthPlaceRegEx = RegExp(r'(?:birth\s*place|place\s*of\s*birth|জন্মস্থান)[:\s]+([^\n\s]+)', caseSensitive: false);
    for (final line in lines) {
      final match = birthPlaceRegEx.firstMatch(line);
      if (match != null && match.group(1) != null) {
        birthPlace = match.group(1)!.trim();
        break;
      }
    }

    // 6. Extract Issue Date
    final issueDateRegEx = RegExp(r'(?:date\s*of\s*issue|issue\s*date|প্রদানের\s*তারিখ)[:\s]+([^\n\s]+)', caseSensitive: false);
    for (final line in lines) {
      final match = issueDateRegEx.firstMatch(line);
      if (match != null && match.group(1) != null) {
        issueDate = match.group(1)!.trim();
        break;
      }
    }

    // 7. Extract Address (including back-side বাংলা ঠিকানা)
    final addressRegExs = [
      RegExp(r'(?:permanent\s*address|present\s*address|address|addr|ঠিকানা)[:\s]+([^\n]+)', caseSensitive: false),
    ];

    int addressStartIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      bool matchFound = false;
      for (final regex in addressRegExs) {
        final match = regex.firstMatch(line);
        if (match != null) {
          matchFound = true;
          addressStartIndex = i;
          if (match.group(1) != null && match.group(1)!.trim().isNotEmpty) {
            final val = match.group(1)!.trim();
            final cleanedVal = val.replaceAll(RegExp(r'^(?:ঠিকানা|address|addr|permanent|present)?[:\s\-/]*', caseSensitive: false), '').trim();
            if (cleanedVal.isNotEmpty) {
              address = cleanedVal;
            }
          }
          break;
        }
      }
      if (matchFound) break;
    }

    if (addressStartIndex != -1) {
      for (int i = addressStartIndex + 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        if (line.toLowerCase().contains('father') ||
            line.toLowerCase().contains('mother') ||
            line.toLowerCase().contains('dob') ||
            line.toLowerCase().contains('id') ||
            line.toLowerCase().contains('signature') ||
            line.toLowerCase().contains('date') ||
            line.toLowerCase().contains('blood') ||
            line.toLowerCase().contains('birth') ||
            line.contains('পিতা') ||
            line.contains('মাতা') ||
            line.contains('রক্তের') ||
            line.contains('জন্মস্থান') ||
            line.contains('প্রদানকারী')) {
          break;
        }
        final cleanedLine = line.replaceAll(RegExp(r'^(?:ঠিকানা|address|addr|permanent|present)?[:\s\-/]*', caseSensitive: false), '').trim();
        if (cleanedLine.isEmpty) continue;
        if (address.isEmpty) {
          address = cleanedLine;
        } else {
          address += ', $cleanedLine';
        }
      }
    }

    return CardInfo(
      englishName: englishName,
      idNumber: idNumber,
      dateOfBirth: dob,
      age: ageStr,
      address: address,
      bloodGroup: bloodGroup,
      birthPlace: birthPlace,
      issueDate: issueDate,
    );
  }

  /// Calculates age based on birth year
  static String _calculateAgeFromDob(String dob) {
    try {
      final yearMatch = RegExp(r'\b(19\d{2}|20[0-2]\d)\b').firstMatch(dob);
      if (yearMatch != null) {
        final birthYear = int.parse(yearMatch.group(1)!);
        final currentYear = DateTime.now().year;
        final age = currentYear - birthYear;
        return '$age Years';
      }
    } catch (_) {}
    return '';
  }

  /// Generates simulated result (useful for desktop/web testing or mock scan selections)
  static OcrResult _generateSimulatedOcrResult(String imagePath) {
    final bool isFemale = imagePath.contains('female') || imagePath.contains('suraiya');

    final parsedInfo = isFemale
        ? const CardInfo(
            banglaName: 'ছাবরিনা তাবাচ্ছুম সুরাইয়া',
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

    final List<RecognizedLineInfo> lines = [
      const RecognizedLineInfo(
        text: 'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার',
        boundingBox: Rect.fromLTWH(40, 20, 320, 25),
      ),
      const RecognizedLineInfo(
        text: 'Government of the People\'s Republic of Bangladesh',
        boundingBox: Rect.fromLTWH(40, 45, 320, 15),
      ),
      const RecognizedLineInfo(
        text: 'National ID Card / জাতীয় পরিচয় পত্র',
        boundingBox: Rect.fromLTWH(80, 65, 240, 18),
      ),
      RecognizedLineInfo(
        text: 'নাম: ${parsedInfo.banglaName}',
        boundingBox: const Rect.fromLTWH(110, 95, 180, 20),
      ),
      RecognizedLineInfo(
        text: 'Name: ${parsedInfo.englishName}',
        boundingBox: const Rect.fromLTWH(110, 120, 180, 20),
      ),
      RecognizedLineInfo(
        text: 'পিতা: ${parsedInfo.banglaFatherName}',
        boundingBox: const Rect.fromLTWH(110, 145, 200, 20),
      ),
      RecognizedLineInfo(
        text: 'মাতা: ${parsedInfo.banglaMotherName}',
        boundingBox: const Rect.fromLTWH(110, 170, 200, 20),
      ),
      RecognizedLineInfo(
        text: 'Date of Birth: ${parsedInfo.dateOfBirth}',
        boundingBox: const Rect.fromLTWH(110, 195, 150, 20),
      ),
      RecognizedLineInfo(
        text: 'ID NO: ${parsedInfo.idNumber}',
        boundingBox: const Rect.fromLTWH(110, 220, 160, 20),
      ),
      const RecognizedLineInfo(
        text: 'রক্তের গ্রুপ/Blood Group: O+',
        boundingBox: Rect.fromLTWH(40, 250, 120, 20),
      ),
      const RecognizedLineInfo(
        text: 'জন্মস্থান: ঝালকাঠী',
        boundingBox: Rect.fromLTWH(180, 250, 100, 20),
      ),
    ];

    return OcrResult(parsedInfo: parsedInfo, lines: lines);
  }
}
