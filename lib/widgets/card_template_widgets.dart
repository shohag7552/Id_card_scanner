import 'dart:io';
import 'package:flutter/material.dart';
import '../models/card_info.dart';

enum CardTemplateType {
  corporate,
  vipClub,
  student,
  glassmorphic,
  bangladeshNid,
}

class CardTemplateWidget extends StatelessWidget {
  final CardInfo cardInfo;
  final CardTemplateType templateType;
  final bool isBack;

  const CardTemplateWidget({
    super.key,
    required this.cardInfo,
    required this.templateType,
    this.isBack = false,
  });

  @override
  Widget build(BuildContext context) {
    if (templateType == CardTemplateType.bangladeshNid && isBack) {
      return _buildBangladeshNidBackTemplate(context);
    }
    
    switch (templateType) {
      case CardTemplateType.corporate:
        return _buildCorporateTemplate(context);
      case CardTemplateType.vipClub:
        return _buildVipClubTemplate(context);
      case CardTemplateType.student:
        return _buildStudentTemplate(context);
      case CardTemplateType.glassmorphic:
        return _buildGlassmorphicTemplate(context);
      case CardTemplateType.bangladeshNid:
        return _buildBangladeshNidTemplate(context);
    }
  }

  // Helper widget to display Avatar (either from cropped file or a placeholder)
  Widget _buildAvatar({required double size, double borderRadius = 0, bool isCircular = true, double? height}) {
    final hasImage = cardInfo.avatarPath != null && cardInfo.avatarPath!.isNotEmpty;
    final imageFile = hasImage ? File(cardInfo.avatarPath!) : null;
    final exists = imageFile != null && imageFile.existsSync();

    return Container(
      width: size,
      height: height ?? size,
      decoration: BoxDecoration(
        color: const Color(0xFF2E2E3E),
        borderRadius: isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withAlpha(204), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: isCircular ? BorderRadius.circular(size / 2) : BorderRadius.circular(borderRadius),
        child: exists
            ? Image.file(
                imageFile,
                fit: BoxFit.cover,
              )
            : Container(
                color: const Color(0xFF2C2E3B),
                child: Icon(
                  Icons.person,
                  size: size * 0.6,
                  color: Colors.grey[400],
                ),
              ),
      ),
    );
  }

  // 1. Corporate ID Badge (Vertical: 230 x 360)
  Widget _buildCorporateTemplate(BuildContext context) {
    return Container(
      width: 230,
      height: 360,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(64),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.only(top: 15),
                child: Column(
                  children: [
                    Text(
                      'INNOVATE CORP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'SECURE ACCESS',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.bold,
                        fontSize: 8,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 85,
            left: 0,
            right: 0,
            child: Container(
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: 75,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildAvatar(size: 80, isCircular: true),
                  const SizedBox(height: 12),
                  Text(
                    cardInfo.englishName.toUpperCase().isNotEmpty ? cardInfo.englishName.toUpperCase() : 'JOHN DOE',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Text(
                    'SYSTEM INTEGRATOR',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('ID NUMBER', cardInfo.idNumber.isNotEmpty ? cardInfo.idNumber : '7283910291'),
                  _buildInfoRow('DOB', cardInfo.dateOfBirth.isNotEmpty ? cardInfo.dateOfBirth : '12 May 1990'),
                  _buildInfoRow('FATHER', cardInfo.banglaFatherName.isNotEmpty ? cardInfo.banglaFatherName : 'ROBERT DOE'),
                  _buildInfoRow('ADDRESS', cardInfo.address.isNotEmpty ? cardInfo.address : '123 Tech Lane, NY', isLong: true),
                  const Spacer(),
                  _buildFakeBarcode(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isLong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 7,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 7, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: isLong ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFakeBarcode() {
    return Container(
      height: 30,
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(24, (index) {
                final widths = [1.0, 2.0, 3.0, 1.5];
                final w = widths[index % widths.length];
                return Container(
                  width: w,
                  color: index % 3 == 0 ? Colors.transparent : Colors.black,
                );
              }),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '*920183749*',
            style: TextStyle(fontSize: 5, color: Colors.black, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  // 2. Elite Club VIP Card (Horizontal: 340 x 215)
  Widget _buildVipClubTemplate(BuildContext context) {
    return Container(
      width: 340,
      height: 215,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111115), Color(0xFF1C1C24), Color(0xFF0C0C0F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withAlpha(38),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(340, 215),
            painter: CardGridPainter(color: const Color(0xFFFFB300).withAlpha(25)),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.stars, color: Color(0xFFFFB300), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'ELITE CLUB VIP',
                          style: TextStyle(
                            color: Color(0xFFFFB300),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300).withAlpha(51),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFB300), width: 0.8),
                      ),
                      child: const Text(
                        'PLATINUM',
                        style: TextStyle(
                          color: Color(0xFFFFB300),
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildAvatar(size: 85, borderRadius: 12, isCircular: false),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cardInfo.englishName.toUpperCase().isNotEmpty ? cardInfo.englishName : 'SARAH JENKINS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MEMBER ID: ${cardInfo.idNumber.isNotEmpty ? cardInfo.idNumber : '9876543210'}',
                            style: const TextStyle(
                              color: Color(0xFFFFB300),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Divider(color: Color(0xFF2C2C35), height: 12),
                          _buildHorizontalInfoRow('DOB', cardInfo.dateOfBirth.isNotEmpty ? cardInfo.dateOfBirth : '25 Nov 1998'),
                          _buildHorizontalInfoRow('Father', cardInfo.banglaFatherName.isNotEmpty ? cardInfo.banglaFatherName : 'MICHAEL JENKINS'),
                          _buildHorizontalInfoRow('Address', cardInfo.address.isNotEmpty ? cardInfo.address : '742 Evergreen Terr, Springfield', isLong: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFakeQrCode(),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'EXP: 12/2030',
                      style: TextStyle(color: Colors.grey[500], fontSize: 7, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'AUTHORISED SIGNATURE',
                      style: TextStyle(color: Colors.grey[500], fontSize: 7, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalInfoRow(String label, String value, {bool isLong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: isLong ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFakeQrCode() {
    return Container(
      width: 45,
      height: 45,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFB300), width: 1),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          crossAxisSpacing: 1.0,
          mainAxisSpacing: 1.0,
        ),
        itemCount: 49,
        itemBuilder: (context, index) {
          final isBlack = (index % 3 == 0) ||
              (index < 7 && index % 2 == 0) ||
              (index > 42 && index % 2 == 0) ||
              (index % 7 == 0) ||
              (index % 7 == 6) ||
              (index == 24 || index == 25 || index == 17);
          return Container(
            color: isBlack ? Colors.black : Colors.white,
          );
        },
      ),
    );
  }

  // 3. Modern Student Pass (Vertical: 230 x 360)
  Widget _buildStudentTemplate(BuildContext context) {
    return Container(
      width: 230,
      height: 360,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0083B0).withAlpha(102),
            blurRadius: 15,
            offset: const Offset(0, 6),
          )
        ],
        border: Border.all(color: Colors.white.withAlpha(76), width: 1.5),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: CircleAvatar(
              radius: 90,
              backgroundColor: Colors.white.withAlpha(25),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Column(
              children: [
                const Text(
                  'METRO TECH INSTITUTE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                const Text(
                  'KNOWLEDGE IS POWER',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontWeight: FontWeight.bold,
                    fontSize: 7,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildAvatar(size: 85, isCircular: true),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            cardInfo.englishName.toUpperCase().isNotEmpty ? cardInfo.englishName : 'MOHAMMAD RAHIM',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Center(
                          child: Text(
                            'COMPUTER SCIENCE DEPT',
                            style: TextStyle(
                              color: Color(0xFF0083B0),
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Divider(height: 14, color: Color(0xFFE2E8F0)),
                        _buildStudentInfoRow('STUDENT ID', cardInfo.idNumber.isNotEmpty ? cardInfo.idNumber : 'CS-2026-9281'),
                        _buildStudentInfoRow('DOB', cardInfo.dateOfBirth.isNotEmpty ? cardInfo.dateOfBirth : '15 Mar 1991'),
                        _buildStudentInfoRow('GUARDIAN', cardInfo.banglaFatherName.isNotEmpty ? cardInfo.banglaFatherName : 'ABDUL KARIM'),
                        _buildStudentInfoRow('ADDRESS', cardInfo.address.isNotEmpty ? cardInfo.address : 'Dhanmondi, Dhaka', isLong: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'STUDENT PASS 2026/27',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 8,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfoRow(String label, String value, {bool isLong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 6.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            maxLines: isLong ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // 4. Glassmorphic Tech Pass (Horizontal: 340 x 215)
  Widget _buildGlassmorphicTemplate(BuildContext context) {
    return Container(
      width: 340,
      height: 215,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(51), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8F00FF).withAlpha(25),
            blurRadius: 15,
            spreadRadius: 1,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              left: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8F00FF).withAlpha(102),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              right: 10,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00F5FF).withAlpha(76),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E26).withAlpha(191),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            CustomPaint(
              size: const Size(340, 215),
              painter: TechLinesPainter(),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.nfc, color: Color(0xFF00F5FF), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'TECH METROPOLIS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5FF).withAlpha(38),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'VISITOR PASS',
                          style: TextStyle(
                            color: Color(0xFF00F5FF),
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cardInfo.englishName.isNotEmpty ? cardInfo.englishName : 'SOPHIA TASNIM',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'ACCESS KEY: ${cardInfo.idNumber.isNotEmpty ? cardInfo.idNumber : '9283748291'}',
                              style: const TextStyle(
                                color: Color(0xFF00F5FF),
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildTechRow('DOB', cardInfo.dateOfBirth.isNotEmpty ? cardInfo.dateOfBirth : '24 Oct 1996'),
                            _buildTechRow('SPONSOR', cardInfo.banglaFatherName.isNotEmpty ? cardInfo.banglaFatherName : 'KAMRUL HASAN'),
                            _buildTechRow('LOCATIONS', cardInfo.address.isNotEmpty ? cardInfo.address : 'Banani, Dhaka', isLong: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildAvatar(size: 80, borderRadius: 40, isCircular: true),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                          const SizedBox(width: 4),
                          const Text(
                            'SECURED BY NFC-V2',
                            style: TextStyle(color: Colors.grey, fontSize: 6.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const Text(
                        'TEMPORARY VISITOR',
                        style: TextStyle(color: Colors.grey, fontSize: 6.5, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechRow(String label, String value, {bool isLong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: isLong ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 5. Bangladesh National ID Card Template (Horizontal: 340 x 215)
  Widget _buildBangladeshNidTemplate(BuildContext context) {
    return Container(
      width: 350,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Stack(
        children: [
          // Background Gov Seal watermark
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40.0, left: 20),
              child: Opacity(
                opacity: 0.3,
                child: Image.asset(
                  'assets/images/sapla_logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.zero,
            // padding: const EdgeInsets.only(left: 10, top: 8.0, right: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, right: 5, top: 5, bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Government Seal Logo representation
                      Image.asset(
                        'assets/images/gov_seal.png',
                        width: 30,
                        height: 30,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      // Header Texts (Bangla & English)
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার',
                              style: TextStyle(
                                color: Color(0xFF1B5E20),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            Text(
                              'Government of the People\'s Republic of Bangladesh',
                              style: TextStyle(
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600,
                                fontSize: 8,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'National ID Card',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 8.0,
                                  ),
                                ),
                                Text(
                                  ' / জাতীয় পরিচয় পত্র',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 8.0,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8), // balance width of seal
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const Divider(color: Colors.black87, height: 4, thickness: 1.2),
                const SizedBox(height: 8),
                // Main Content Row
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(width: 5),
                      // Left Side: Profile Picture and Signature
                      Column(
                        children: [
                          _buildAvatar(size: 60, height: 70, borderRadius: 2, isCircular: false),
                          const SizedBox(height: 5),
                          // Signature image or text fallback
                          Builder(
                            builder: (context) {
                              final hasSig = cardInfo.signaturePath != null &&
                                  cardInfo.signaturePath!.isNotEmpty;
                              final sigFile = hasSig ? File(cardInfo.signaturePath!) : null;
                              final exists = sigFile != null && sigFile.existsSync();
                              
                              if (exists) {
                                return Image.file(
                                  sigFile,
                                  height: 20,
                                  width: 60,
                                  fit: BoxFit.contain,
                                );
                              } else {
                                return Text(
                                  cardInfo.banglaName.isNotEmpty 
                                      ? cardInfo.banglaName.replaceAll('মো: ', '').replaceAll('মোছা: ', '').trim()
                                      : 'তাবাচ্ছুম',
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Right Side: Bangla and English Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildNidRow('নাম:', cardInfo.banglaName.isNotEmpty ? cardInfo.banglaName : 'ছাবরিনা তাবাচ্ছুম সুরাইয়া', isBanglaValue: true, fontSize: 11),
                            _buildNidRow('Name:', cardInfo.englishName.isNotEmpty ? cardInfo.englishName : 'SUBRINA TABASSUM SURAIYA', fontSize: 10.5, isBoldValue: false),
                            _buildNidRow('পিতা:', cardInfo.banglaFatherName.isNotEmpty ? cardInfo.banglaFatherName : 'মোঃ মাহবুবুর রহমান', isBanglaValue: true),
                            _buildNidRow('মাতা:', cardInfo.banglaMotherName.isNotEmpty ? cardInfo.banglaMotherName : 'খাতুনে জান্নাত শাহানাজ পারভীন', isBanglaValue: true),
                            
                            // Date of Birth Row
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                children: [
                                  const Text(
                                    'Date of Birth: ',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 8.0,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    cardInfo.dateOfBirth.isNotEmpty ? cardInfo.dateOfBirth : '20 Dec 2006',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            // ID Number Row
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: Row(
                                children: [
                                  const Text(
                                    'ID NO: ',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    cardInfo.idNumber.isNotEmpty ? cardInfo.idNumber : '8279557295',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 6. Bangladesh National ID Card Template - Back Side (Horizontal: 340 x 215)
  Widget _buildBangladeshNidBackTemplate(BuildContext context) {
    return Container(
      width: 350,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Property declaration text
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 5),
            child: Text(
              'এই কার্ডটি গণপ্রজাতন্ত্রী বাংলাদেশ সরকারের সম্পত্তি। কার্ডটি ব্যবহারকারী ব্যতীত অন্য কোথাও পাওয়া গেলে নিকটস্থ পোস্ট অফিসে জমা দেবার জন্য অনুরোধ করা হলো।',
              // textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 7.0,
                height: 1.3,
              ),
            ),
          ),
          const Divider(color: Colors.black87, height: 4, thickness: 1.2),

          // Section 2: Bangla Address
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(5.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ঠিকানা: ',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 7.5,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      cardInfo.address.isNotEmpty
                          ? cardInfo.address
                          : 'বাসা/হোল্ডিং: ৪২৩, গ্রাম/রাস্তা: কীর্তিপাশা, ডাকঘর: কীর্তিপাশা - ৮৪০০, ঝালকাঠী সদর, ঝালকাঠী',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 7.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Section 3: Blood Group & Place of Birth
          Padding(
            padding: const EdgeInsets.only(left: 5.0),
            child: Row(
              children: [
                const Text(
                  'রক্তের গ্রুপ/Blood Group: ',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 8.0,
                  ),
                ),
                Text(
                  cardInfo.bloodGroup.isNotEmpty ? cardInfo.bloodGroup : 'O+',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 9.0,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'জন্মস্থান: ',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 8.0,
                  ),
                ),
                Text(
                  cardInfo.birthPlace.isNotEmpty ? cardInfo.birthPlace : 'ঝালকাঠী',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 8.0,
                  ),
                ),
                const Spacer(),
                const Text(
                  'মুদ্রণ: ০১',
                  style: TextStyle(
                    color: Colors.white,
                    backgroundColor: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 7.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.black87, height: 4, thickness: 1.0),

          // Section 4: Authorized Sign, Issue Date & PDF417 Barcode
          Padding(
            padding: const EdgeInsets.only(left: 5.0, right: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Authorized Signature
                    // Signature Image or doodle
                Column(
                  children: [
                    Builder(
                      builder: (context) {
                        final hasSig = cardInfo.authoritySignaturePath != null &&
                            cardInfo.authoritySignaturePath!.isNotEmpty;
                        final sigFile = hasSig ? File(cardInfo.authoritySignaturePath!) : null;
                        final exists = sigFile != null && sigFile.existsSync();

                        if (exists) {
                          return Image.file(
                            sigFile,
                            height: 20,
                            width: 60,
                            fit: BoxFit.contain,
                          );
                        } else {
                          return CustomPaint(
                            size: const Size(60, 20),
                            painter: SignaturePainter(),
                          );
                        }
                      },
                    ),

                    const Text(
                      'প্রদানকারী কর্তৃপক্ষের স্বাক্ষর',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 8.0,
                      ),
                    ),
                  ],
                ),

                const Spacer(),
                // Date of Issue
                Row(
                  children: [
                    const Text(
                      'প্রদানের তারিখ: ',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 8.0,
                      ),
                    ),
                    Text(
                      cardInfo.issueDate.isNotEmpty ? cardInfo.issueDate : '০৮/০৬/২০২৬',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 8.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // PDF417 Barcode
          Padding(
            padding: const EdgeInsets.only(left: 5.0, bottom: 5, right: 3),
            child: CustomPaint(
              size: const Size(320, 24),
              painter: PDF417BarcodePainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNidRow(
    String label,
    String value, {
    bool isBanglaValue = false,
    bool isBoldValue = false,
    double fontSize = 9.0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isBanglaValue ? const Color(0xFF111827) : Colors.black87,
                fontSize: fontSize,
                fontWeight: (isBoldValue || isBanglaValue) ? FontWeight.w800 : FontWeight.w600,
                fontFamily: isBanglaValue ? 'Roboto' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter to draw a simulated handwritten authorized signature
class SignaturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(5, size.height * 0.9)
      ..quadraticBezierTo(size.width * 0.2, size.height * 0.1, size.width * 0.4, size.height * 0.6)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.9, size.width * 0.6, size.height * 0.3)
      ..lineTo(size.width * 0.7, size.height * 0.9)
      ..quadraticBezierTo(size.width * 0.8, size.height * 0.1, size.width * 0.95, size.height * 0.05);

    canvas.drawPath(path, paint);

    // Cross-ticks signature accents
    canvas.drawLine(Offset(size.width * 0.35, size.height * 0.7), Offset(size.width * 0.45, size.height * 0.4), paint);
    canvas.drawLine(Offset(size.width * 0.38, size.height * 0.75), Offset(size.width * 0.48, size.height * 0.45), paint);
    canvas.drawLine(Offset(size.width * 0.41, size.height * 0.8), Offset(size.width * 0.51, size.height * 0.5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom Painter to draw a highly authentic PDF417 2D Barcode representation
class PDF417BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;

    // Draw PDF417 start patterns (thick bar, thin space, etc.)
    canvas.drawRect(Rect.fromLTWH(0, 0, 4, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(6, 0, 1.5, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(9, 0, 1.5, size.height), paint);

    // Draw PDF417 end patterns
    canvas.drawRect(Rect.fromLTWH(size.width - 4, 0, 4, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - 7, 0, 1.5, size.height), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - 10, 0, 1.5, size.height), paint);

    // Draw grid of randomized barcode blocks in the middle (PDF417 columns)
    const columnsCount = 14;
    const rowsCount = 4;
    final columnWidth = (size.width - 24) / columnsCount;
    final rowHeight = size.height / rowsCount;

    for (int r = 0; r < rowsCount; r++) {
      for (int c = 0; c < columnsCount; c++) {
        // Semi-randomly render sub-bars inside each cell
        final xStart = 12 + (c * columnWidth);
        final yStart = r * rowHeight;

        // Generate stable seed based on row and column index
        final val = (r * 7 + c * 13) % 5;
        if (val == 0) {
          canvas.drawRect(Rect.fromLTWH(xStart + 1, yStart, columnWidth - 2, rowHeight), paint);
        } else if (val == 1) {
          canvas.drawRect(Rect.fromLTWH(xStart + 1, yStart, columnWidth * 0.4, rowHeight), paint);
          canvas.drawRect(Rect.fromLTWH(xStart + columnWidth * 0.6, yStart, columnWidth * 0.3, rowHeight), paint);
        } else if (val == 2) {
          canvas.drawRect(Rect.fromLTWH(xStart + columnWidth * 0.3, yStart, columnWidth * 0.5, rowHeight), paint);
        } else if (val == 3) {
          canvas.drawRect(Rect.fromLTWH(xStart + 2, yStart, columnWidth * 0.2, rowHeight), paint);
          canvas.drawRect(Rect.fromLTWH(xStart + columnWidth * 0.5, yStart, columnWidth * 0.4, rowHeight), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Background Grid lines painter for VIP Card
class CardGridPainter extends CustomPainter {
  final Color color;
  CardGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 15.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Futuristic technical accents painter for Glassmorphism Card
class TechLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F5FF).withAlpha(51)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..lineTo(size.width * 0.15, size.height * 0.7)
      ..lineTo(size.width * 0.22, size.height * 0.82)
      ..lineTo(size.width * 0.5, size.height * 0.82);

    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..color = const Color(0xFF8F00FF)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.5 - 2, size.height * 0.82 - 2, 4, 4), dotPaint);

    final cyanDotPaint = Paint()
      ..color = const Color(0xFF00F5FF)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.22 - 2, size.height * 0.82 - 2, 4, 4), cyanDotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
