import 'package:flutter_test/flutter_test.dart';
import 'package:card_scanner/services/ocr_service.dart';

void main() {
  group('OCR Parser Heuristics Tests', () {
    test('Should parse typical Bangladesh National ID card layout correctly', () {
      final rawLines = [
        'Government of the People\'s Republic of Bangladesh',
        'National ID Card / জাতীয় পরিচয়পত্র',
        'Name: Mohammad Rahim',
        'Date of Birth: 15 Mar 1991',
        'ID NO: 7829103847',
        'Address / ঠিকানা:',
        'Villa 3B, Sector 4, Uttara, Dhaka-1230',
      ];

      final cardInfo = OcrService.parseExtractedText(rawLines);

      expect(cardInfo.englishName, equals('Mohammad Rahim'));
      expect(cardInfo.idNumber, equals('7829103847'));
      expect(cardInfo.dateOfBirth, equals('15 Mar 1991'));
      expect(cardInfo.age, contains('Years')); // Age calculated from year 1991
      expect(cardInfo.address, equals('Villa 3B, Sector 4, Uttara, Dhaka-1230'));
    });

    test('Should parse another card layout with different date formats and headers', () {
      final rawLines = [
        'ELITE CLUB MEMBER CARD',
        'NAME: Sophia Tasnim',
        'DOB: 24/10/1996',
        'NID: 9283748291',
        'Address: House 42, Road 11',
        'Banani, Dhaka-1213',
      ];

      final cardInfo = OcrService.parseExtractedText(rawLines);

      expect(cardInfo.englishName, equals('Sophia Tasnim'));
      expect(cardInfo.idNumber, equals('9283748291'));
      expect(cardInfo.dateOfBirth, equals('24/10/1996'));
      expect(cardInfo.age, contains('Years')); // Age calculated from year 1996
      expect(cardInfo.address, equals('House 42, Road 11, Banani, Dhaka-1213'));
    });

    test('Should fall back to names without Name label using heuristics', () {
      final rawLines = [
        'Identity Document',
        'John Smith', // Capitalized name-like word pattern
        'ID: 123456789',
      ];

      final cardInfo = OcrService.parseExtractedText(rawLines);

      expect(cardInfo.englishName, equals('John Smith'));
      expect(cardInfo.idNumber, equals('123456789'));
    });

    test('Should parse back-side Bangladesh NID card fields correctly', () {
      final rawLines = [
        'রক্তের গ্রুপ/Blood Group: O+',
        'জন্মস্থান: ঝালকাঠী',
        'প্রদানের তারিখ: ০৮/০৬/২০২৬',
        'ঠিকানা: বাসা/হোল্ডিং: ৪২৩, গ্রাম/রাস্তা: কীর্তিপাশা, ডাকঘর: কীর্তিপাশা - ৮৪০০',
        'ঝালকাঠী সদর, ঝালকাঠী',
      ];

      final cardInfo = OcrService.parseExtractedText(rawLines);

      expect(cardInfo.bloodGroup, equals('O+'));
      expect(cardInfo.birthPlace, equals('ঝালকাঠী'));
      expect(cardInfo.issueDate, equals('০৮/০৬/২০২৬'));
      expect(cardInfo.address, equals('বাসা/হোল্ডিং: ৪২৩, গ্রাম/রাস্তা: কীর্তিপাশা, ডাকঘর: কীর্তিপাশা - ৮৪০০, ঝালকাঠী সদর, ঝালকাঠী'));
    });
  });
}
