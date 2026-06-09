import 'package:flutter/foundation.dart';

class CardInfo {
  final String banglaName;
  final String englishName;
  final String banglaFatherName;
  final String banglaMotherName;
  final String dateOfBirth;
  final String age;
  final String idNumber;
  final String address;
  final String bloodGroup;
  final String birthPlace;
  final String issueDate;
  // Images are stored as in-memory bytes so they render identically on mobile
  // and web (Image.memory). Not serialized to JSON.
  final Uint8List? avatarBytes;
  final Uint8List? signatureBytes;
  final Uint8List? authoritySignatureBytes;

  const CardInfo({
    this.banglaName = '',
    this.englishName = '',
    this.banglaFatherName = '',
    this.banglaMotherName = '',
    this.dateOfBirth = '',
    this.age = '',
    this.idNumber = '',
    this.address = '',
    this.bloodGroup = '',
    this.birthPlace = '',
    this.issueDate = '',
    this.avatarBytes,
    this.signatureBytes,
    this.authoritySignatureBytes,
  });

  CardInfo copyWith({
    String? banglaName,
    String? englishName,
    String? banglaFatherName,
    String? banglaMotherName,
    String? dateOfBirth,
    String? age,
    String? idNumber,
    String? address,
    String? bloodGroup,
    String? birthPlace,
    String? issueDate,
    Uint8List? avatarBytes,
    Uint8List? signatureBytes,
    Uint8List? authoritySignatureBytes,
  }) {
    return CardInfo(
      banglaName: banglaName ?? this.banglaName,
      englishName: englishName ?? this.englishName,
      banglaFatherName: banglaFatherName ?? this.banglaFatherName,
      banglaMotherName: banglaMotherName ?? this.banglaMotherName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      age: age ?? this.age,
      idNumber: idNumber ?? this.idNumber,
      address: address ?? this.address,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      birthPlace: birthPlace ?? this.birthPlace,
      issueDate: issueDate ?? this.issueDate,
      avatarBytes: avatarBytes ?? this.avatarBytes,
      signatureBytes: signatureBytes ?? this.signatureBytes,
      authoritySignatureBytes: authoritySignatureBytes ?? this.authoritySignatureBytes,
    );
  }

  bool get isEmpty =>
      banglaName.isEmpty &&
      englishName.isEmpty &&
      banglaFatherName.isEmpty &&
      banglaMotherName.isEmpty &&
      dateOfBirth.isEmpty &&
      age.isEmpty &&
      idNumber.isEmpty &&
      address.isEmpty &&
      bloodGroup.isEmpty &&
      birthPlace.isEmpty &&
      issueDate.isEmpty &&
      avatarBytes == null &&
      signatureBytes == null &&
      authoritySignatureBytes == null;

  /// Text-only JSON (images are excluded — they are runtime byte buffers).
  Map<String, dynamic> toJson() {
    return {
      'banglaName': banglaName,
      'englishName': englishName,
      'banglaFatherName': banglaFatherName,
      'banglaMotherName': banglaMotherName,
      'dateOfBirth': dateOfBirth,
      'age': age,
      'idNumber': idNumber,
      'address': address,
      'bloodGroup': bloodGroup,
      'birthPlace': birthPlace,
      'issueDate': issueDate,
    };
  }

  factory CardInfo.fromJson(Map<String, dynamic> json) {
    return CardInfo(
      banglaName: json['banglaName'] ?? '',
      englishName: json['englishName'] ?? '',
      banglaFatherName: json['banglaFatherName'] ?? '',
      banglaMotherName: json['banglaMotherName'] ?? '',
      dateOfBirth: json['dateOfBirth'] ?? '',
      age: json['age'] ?? '',
      idNumber: json['idNumber'] ?? '',
      address: json['address'] ?? '',
      bloodGroup: json['bloodGroup'] ?? '',
      birthPlace: json['birthPlace'] ?? '',
      issueDate: json['issueDate'] ?? '',
    );
  }
}
