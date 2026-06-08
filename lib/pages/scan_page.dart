import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/card_info.dart';
import '../services/ocr_service.dart';
import '../services/face_detector_service.dart';
import '../theme/app_theme.dart';
import 'card_editor_page.dart';
import '../widgets/card_template_widgets.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  
  String? _frontImagePath;
  String? _backImagePath;
  bool _isScanning = false;
  
  CardInfo _scannedInfo = const CardInfo();
  List<RecognizedLineInfo> _detectedLines = [];
  
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _laserAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source, {required bool isFront}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          if (isFront) {
            _frontImagePath = image.path;
          } else {
            _backImagePath = image.path;
          }
          _isScanning = true;
        });
        _laserController.repeat(reverse: true);
        
        await _processCardImage(image.path, isFront: isFront);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  Future<void> _processCardImage(String path, {required bool isFront}) async {
    final ocrResult = await OcrService.scanCardImage(path);
    String? croppedFacePath;
    String? croppedSigPath;

    if (isFront) {
      croppedFacePath = await FaceDetectorService.detectAndCropFace(path);
      croppedSigPath = await FaceDetectorService.detectAndCropSignature(path);
    } else {
      croppedSigPath = await FaceDetectorService.cropAuthoritySignature(path);
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        if (isFront) {
          _scannedInfo = _scannedInfo.copyWith(
            englishName: ocrResult.parsedInfo.englishName.isNotEmpty ? ocrResult.parsedInfo.englishName : _scannedInfo.englishName,
            banglaName: ocrResult.parsedInfo.banglaName.isNotEmpty ? ocrResult.parsedInfo.banglaName : _scannedInfo.banglaName,
            banglaFatherName: ocrResult.parsedInfo.banglaFatherName.isNotEmpty ? ocrResult.parsedInfo.banglaFatherName : _scannedInfo.banglaFatherName,
            banglaMotherName: ocrResult.parsedInfo.banglaMotherName.isNotEmpty ? ocrResult.parsedInfo.banglaMotherName : _scannedInfo.banglaMotherName,
            idNumber: ocrResult.parsedInfo.idNumber.isNotEmpty ? ocrResult.parsedInfo.idNumber : _scannedInfo.idNumber,
            dateOfBirth: ocrResult.parsedInfo.dateOfBirth.isNotEmpty ? ocrResult.parsedInfo.dateOfBirth : _scannedInfo.dateOfBirth,
            age: ocrResult.parsedInfo.age.isNotEmpty ? ocrResult.parsedInfo.age : _scannedInfo.age,
            avatarPath: croppedFacePath ?? _scannedInfo.avatarPath,
            signaturePath: croppedSigPath ?? _scannedInfo.signaturePath,
          );
        } else {
          _scannedInfo = _scannedInfo.copyWith(
            address: ocrResult.parsedInfo.address.isNotEmpty ? ocrResult.parsedInfo.address : _scannedInfo.address,
            bloodGroup: ocrResult.parsedInfo.bloodGroup.isNotEmpty ? ocrResult.parsedInfo.bloodGroup : _scannedInfo.bloodGroup,
            birthPlace: ocrResult.parsedInfo.birthPlace.isNotEmpty ? ocrResult.parsedInfo.birthPlace : _scannedInfo.birthPlace,
            issueDate: ocrResult.parsedInfo.issueDate.isNotEmpty ? ocrResult.parsedInfo.issueDate : _scannedInfo.issueDate,
            authoritySignaturePath: croppedSigPath ?? _scannedInfo.authoritySignaturePath,
          );
        }
        _detectedLines = [..._detectedLines, ...ocrResult.lines];
      });
      _laserController.stop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isFront ? "Front" : "Back"} Side scanned successfully!'),
          backgroundColor: AppTheme.secondary,
        ),
      );
    }
  }

  Future<void> _simulateMockScan(bool isFemale) async {
    setState(() {
      _frontImagePath = isFemale ? 'mock_nid_female_front.jpg' : 'mock_nid_male_front.jpg';
      _backImagePath = isFemale ? 'mock_nid_female_back.jpg' : 'mock_nid_male_back.jpg';
      _isScanning = true;
      _scannedInfo = const CardInfo();
      _detectedLines = [];
    });
    _laserController.repeat(reverse: true);

    await Future.delayed(const Duration(milliseconds: 2500));

    final ocrFront = await OcrService.scanCardImage(_frontImagePath!);
    final ocrBack = await OcrService.scanCardImage(_backImagePath!);

    if (mounted) {
      setState(() {
        _isScanning = false;
        _scannedInfo = ocrFront.parsedInfo.copyWith(
          address: ocrBack.parsedInfo.address,
          bloodGroup: ocrBack.parsedInfo.bloodGroup,
          birthPlace: ocrBack.parsedInfo.birthPlace,
          issueDate: ocrBack.parsedInfo.issueDate,
          avatarPath: ocrFront.parsedInfo.avatarPath,
          signaturePath: ocrFront.parsedInfo.signaturePath,
          authoritySignaturePath: ocrFront.parsedInfo.authoritySignaturePath,
        );
        _detectedLines = [...ocrFront.lines, ...ocrBack.lines];
      });
      _laserController.stop();
    }
  }

  void _assignLineToField(String text, String fieldName) {
    setState(() {
      switch (fieldName) {
        case 'banglaName':
          _scannedInfo = _scannedInfo.copyWith(banglaName: text);
          break;
        case 'englishName':
          _scannedInfo = _scannedInfo.copyWith(englishName: text);
          break;
        case 'banglaFatherName':
          _scannedInfo = _scannedInfo.copyWith(banglaFatherName: text);
          break;
        case 'banglaMotherName':
          _scannedInfo = _scannedInfo.copyWith(banglaMotherName: text);
          break;
        case 'idNumber':
          _scannedInfo = _scannedInfo.copyWith(idNumber: text);
          break;
        case 'dateOfBirth':
          _scannedInfo = _scannedInfo.copyWith(dateOfBirth: text);
          final yearMatch = RegExp(r'\b(19\d{2}|20[0-2]\d)\b').firstMatch(text);
          if (yearMatch != null) {
            final age = DateTime.now().year - int.parse(yearMatch.group(1)!);
            _scannedInfo = _scannedInfo.copyWith(age: '$age Years');
          }
          break;
        case 'address':
          _scannedInfo = _scannedInfo.copyWith(address: text);
          break;
        case 'bloodGroup':
          _scannedInfo = _scannedInfo.copyWith(bloodGroup: text);
          break;
        case 'birthPlace':
          _scannedInfo = _scannedInfo.copyWith(birthPlace: text);
          break;
        case 'issueDate':
          _scannedInfo = _scannedInfo.copyWith(issueDate: text);
          break;
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mapped to ${fieldName.toUpperCase()}: "$text"'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showMappingMenu(String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Map text: "$text"',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.borderCol),
                  _buildMappingOption(context, text, 'banglaName', Icons.person, 'Bangla Name (নাম)'),
                  _buildMappingOption(context, text, 'englishName', Icons.person_outline, 'English Name (Name)'),
                  _buildMappingOption(context, text, 'banglaFatherName', Icons.escalator_warning, 'Bangla Father\'s Name (পিতা)'),
                  _buildMappingOption(context, text, 'banglaMotherName', Icons.escalator_warning_outlined, 'Bangla Mother\'s Name (মাতা)'),
                  _buildMappingOption(context, text, 'idNumber', Icons.pin, 'ID Card Number (ID NO)'),
                  _buildMappingOption(context, text, 'dateOfBirth', Icons.cake, 'Date of Birth'),
                  _buildMappingOption(context, text, 'address', Icons.home, 'Home Address'),
                  _buildMappingOption(context, text, 'bloodGroup', Icons.bloodtype, 'Blood Group'),
                  _buildMappingOption(context, text, 'birthPlace', Icons.location_city, 'Place of Birth'),
                  _buildMappingOption(context, text, 'issueDate', Icons.date_range, 'Date of Issue'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMappingOption(
    BuildContext context,
    String text,
    String field,
    IconData icon,
    String title,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.secondary),
      title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
      onTap: () {
        Navigator.pop(context);
        _assignLineToField(text, field);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _frontImagePath != null || _backImagePath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CARD SCANNER'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildViewport(isFront: true),
                  const SizedBox(width: 14),
                  _buildViewport(isFront: false),
                ],
              ),
              const SizedBox(height: 24),

              if (!hasImage && !_isScanning) ...[
                const SizedBox(height: 20),
                _buildSimulationOptions(),
              ] else if (_isScanning) ...[
                _buildScannerProcessingIndicator(),
              ] else ...[
                _buildExtractedInfoForm(),
                const SizedBox(height: 20),
                _buildDetectedTextMapper(),
                const SizedBox(height: 32),
                _buildActionButtons(),
              ]
            ],
          ),
        ),
      ),
    );
  }

  void _showImageSourcePicker({required bool isFront}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Upload ${isFront ? "Front" : "Back"} Side Card',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                ),
              ),
              const Divider(color: AppTheme.borderCol),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.secondary),
                title: const Text('Capture using Camera', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera, isFront: isFront);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppTheme.secondary),
                title: const Text('Select from Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery, isFront: isFront);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewport({required bool isFront}) {
    final path = isFront ? _frontImagePath : _backImagePath;
    final hasImage = path != null;
    final isMock = path?.endsWith('.jpg') ?? false;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isFront ? 'FRONT SIDE' : 'BACK SIDE',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isScanning ? null : () => _showImageSourcePicker(isFront: isFront),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasImage ? AppTheme.secondary : AppTheme.borderCol,
                  width: 1.5,
                ),
                boxShadow: [
                  if (_isScanning && hasImage)
                    BoxShadow(
                      color: AppTheme.secondary.withAlpha(25),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!hasImage)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isFront ? Icons.add_photo_alternate : Icons.flip_to_back,
                            size: 32,
                            color: AppTheme.borderCol,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap to upload',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    else if (isMock)
                      Container(
                        color: const Color(0xFF1E293B),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isFront ? Icons.person : Icons.contact_mail,
                                color: Colors.white30,
                                size: 36,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isFront ? 'Mock Front NID' : 'Mock Back NID',
                                style: const TextStyle(color: Colors.white54, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    
                    if (_isScanning && hasImage)
                      AnimatedBuilder(
                        animation: _laserAnimation,
                        builder: (context, child) {
                          return Positioned(
                            top: 120 * _laserAnimation.value,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppTheme.secondary,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.secondary,
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationOptions() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.computer, color: AppTheme.secondary, size: 18),
              SizedBox(width: 8),
              Text(
                'TEST SIMULATION MODE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Testing on simulator/desktop? Scan custom mock cards with real Bangla texts to preview the NID layout flow.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _simulateMockScan(false),
                  icon: const Icon(Icons.male, size: 16, color: Colors.blueAccent),
                  label: const Text('MD. ABDUL MOMIN'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.borderCol),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _simulateMockScan(true),
                  icon: const Icon(Icons.female, size: 16, color: Colors.pinkAccent),
                  label: const Text('FERDOUSI KHATUN'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.borderCol),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScannerProcessingIndicator() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.secondary),
            ),
            const SizedBox(height: 16),
            const Text(
              'EXTRACTING CARD DETAILS...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Running OCR & Face detection engines',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedInfoForm() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AUTO-EXTRACTED DATA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              if (_scannedInfo.avatarPath != null)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.secondary, width: 1.5),
                  ),
                  child: ClipOval(
                    child: (_frontImagePath?.startsWith('mock_') ?? false)
                        ? Container(
                            color: AppTheme.primary,
                            child: const Icon(Icons.check, size: 16, color: Colors.white),
                          )
                        : Image.file(
                            File(_scannedInfo.avatarPath!),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFormRow(Icons.person, 'Name (English)', _scannedInfo.englishName, (val) {
            _scannedInfo = _scannedInfo.copyWith(englishName: val);
          }),
          _buildFormRow(Icons.person, 'নাম (বাংলা) - Type or map below', _scannedInfo.banglaName, (val) {
            _scannedInfo = _scannedInfo.copyWith(banglaName: val);
          }),
          _buildFormRow(Icons.pin, 'ID Number', _scannedInfo.idNumber, (val) {
            _scannedInfo = _scannedInfo.copyWith(idNumber: val);
          }),
          _buildFormRow(Icons.escalator_warning, 'পিতা (বাংলা) - Type or map below', _scannedInfo.banglaFatherName, (val) {
            _scannedInfo = _scannedInfo.copyWith(banglaFatherName: val);
          }),
          _buildFormRow(Icons.escalator_warning_outlined, 'মাতা (বাংলা) - Type or map below', _scannedInfo.banglaMotherName, (val) {
            _scannedInfo = _scannedInfo.copyWith(banglaMotherName: val);
          }),
          _buildFormRow(Icons.cake, 'Date of Birth', _scannedInfo.dateOfBirth, (val) {
            _scannedInfo = _scannedInfo.copyWith(dateOfBirth: val);
          }),
          _buildFormRow(Icons.home, 'Address (বাংলা)', _scannedInfo.address, (val) {
            _scannedInfo = _scannedInfo.copyWith(address: val);
          }, maxLines: 2),
          _buildFormRow(Icons.bloodtype, 'Blood Group', _scannedInfo.bloodGroup, (val) {
            _scannedInfo = _scannedInfo.copyWith(bloodGroup: val);
          }),
          _buildFormRow(Icons.location_city, 'Birth Place (বাংলা)', _scannedInfo.birthPlace, (val) {
            _scannedInfo = _scannedInfo.copyWith(birthPlace: val);
          }),
          _buildFormRow(Icons.date_range, 'Issue Date (বাংলা)', _scannedInfo.issueDate, (val) {
            _scannedInfo = _scannedInfo.copyWith(issueDate: val);
          }),
        ],
      ),
    );
  }

  Widget _buildFormRow(
    IconData icon,
    String label,
    String value,
    Function(String) onChanged, {
    int maxLines = 1,
  }) {
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary),
          labelText: label,
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDetectedTextMapper() {
    if (_detectedLines.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Row(
          children: [
            Icon(Icons.edit_road, color: AppTheme.secondary, size: 16),
            SizedBox(width: 6),
            Text(
              'INTERACTIVE OCR TEXT RE-ASSIGNMENT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap any text snippet below to assign it directly to a specific field. (Note: standard mobile OCR will extract English text; please type Bangla fields manually if not automatically mapped.)',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _detectedLines.map((line) {
            final cleaned = line.text.trim();
            if (cleaned.length < 2) return const SizedBox();
            return ActionChip(
              backgroundColor: AppTheme.surfaceBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppTheme.borderCol),
              ),
              avatar: const Icon(Icons.add, size: 12, color: AppTheme.secondary),
              label: Text(
                cleaned,
                style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
              ),
              onPressed: () => _showMappingMenu(cleaned),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _frontImagePath = null;
                _backImagePath = null;
                _scannedInfo = const CardInfo();
                _detectedLines = [];
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.errorRed,
              side: const BorderSide(color: AppTheme.errorRed),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('RESET SCAN'),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CardEditorPage(
                      initialInfo: _scannedInfo,
                      selectedTemplate: CardTemplateType.bangladeshNid,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('PROCEED TO TEMPLATE'),
            ),
          ),
        ),
      ],
    );
  }
}
