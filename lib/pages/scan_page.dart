import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/card_info.dart';
import '../services/gemini_nid_service.dart';
import '../services/face_cropper.dart';
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
  Uint8List? _frontBytes;
  Uint8List? _backBytes;
  bool _isScanning = false;
  bool _hasScanned = false;

  CardInfo _scannedInfo = const CardInfo();

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
        final Uint8List bytes = await image.readAsBytes();
        setState(() {
          if (isFront) {
            _frontImagePath = image.path;
            _frontBytes = bytes;
          } else {
            _backImagePath = image.path;
            _backBytes = bytes;
          }
          // Re-picking after a scan lets the user run it again with the new image.
          _hasScanned = false;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e')),
        );
      }
    }
  }

  /// Sends the front (and optional back) image to Gemini 2.5 Flash, then crops the
  /// avatar / signatures on-device with ML Kit face detection.
  Future<void> _scanNow() async {
    if (_frontBytes == null) return;

    setState(() => _isScanning = true);
    _laserController.repeat(reverse: true);

    // Gemini extracts the text AND returns photo/signatures cropped from its
    // bounding boxes — this is the baseline used on web and Windows.
    final NidScanResult result = await GeminiNidService.scanNid(
      frontBytes: _frontBytes!,
      backBytes: _backBytes,
    );
    CardInfo info = result.info;

    // On Android/iOS, refine the PHOTO and HOLDER signature with ML Kit (face
    // detection is more accurate), falling back to the Gemini crop if it finds
    // nothing.
    if (!kIsWeb && _frontImagePath != null) {
      final mlAvatar = await FaceCropper.detectAndCropFace(_frontImagePath!);
      final mlHolderSig = await FaceCropper.detectAndCropSignature(_frontImagePath!);
      info = info.copyWith(
        avatarBytes: mlAvatar ?? info.avatarBytes,
        signatureBytes: mlHolderSig ?? info.signatureBytes,
      );
    }
    // Authority signature: ML Kit has no real detection here (it blindly crops a
    // fixed region that includes the caption text), so prefer Gemini's tight box
    // and only fall back to the fixed-region crop when Gemini didn't locate it.
    if (!kIsWeb && _backImagePath != null && info.authoritySignatureBytes == null) {
      final mlAuthSig = await FaceCropper.cropAuthoritySignature(_backImagePath!);
      info = info.copyWith(
        authoritySignatureBytes: mlAuthSig ?? info.authoritySignatureBytes,
      );
    }

    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _hasScanned = true;
      _scannedInfo = info;
    });
    _laserController.stop();

    if (result.hasError) {
      _showScanError(result.error!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NID scanned with Gemini 2.5 Flash!'),
          backgroundColor: AppTheme.secondary,
        ),
      );
    }
  }

  void _showScanError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBg,
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
            SizedBox(width: 8),
            Text('Scan failed', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            message,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppTheme.secondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateMockScan(bool isFemale) async {
    setState(() {
      _frontImagePath = isFemale ? 'mock_nid_female_front.jpg' : 'mock_nid_male_front.jpg';
      _backImagePath = isFemale ? 'mock_nid_female_back.jpg' : 'mock_nid_male_back.jpg';
      _frontBytes = null;
      _backBytes = null;
      _isScanning = true;
      _hasScanned = false;
      _scannedInfo = const CardInfo();
    });
    _laserController.repeat(reverse: true);

    await Future.delayed(const Duration(milliseconds: 1500));
    final NidScanResult result = GeminiNidService.simulated(isFemale: isFemale);

    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _hasScanned = true;
      _scannedInfo = result.info;
    });
    _laserController.stop();
  }

  void _resetScan() {
    setState(() {
      _frontImagePath = null;
      _backImagePath = null;
      _frontBytes = null;
      _backBytes = null;
      _scannedInfo = const CardInfo();
      _hasScanned = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NID SCANNER'),
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

              if (_isScanning) ...[
                _buildScannerProcessingIndicator(),
              ] else if (_hasScanned) ...[
                _buildExtractedInfoForm(),
                const SizedBox(height: 32),
                _buildActionButtons(),
              ] else if (_frontImagePath != null) ...[
                _buildScanCta(),
              ] else ...[
                _buildSimulationOptions(),
              ],
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
    final bytes = isFront ? _frontBytes : _backBytes;
    final hasImage = path != null;
    final isMock = path?.contains('mock') ?? false;

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
                      SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: Column(
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
                        ),
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
                    else if (bytes != null)
                      Image.memory(
                        bytes,
                        fit: BoxFit.contain,
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

  Widget _buildScanCta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderCol),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.secondary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _backImagePath == null
                      ? 'Front side ready. Add the back side for address, blood group & issue date — or scan now.'
                      : 'Front & back ready. Tap scan to extract all NID details with Gemini.',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ElevatedButton.icon(
            onPressed: _scanNow,
            icon: const Icon(Icons.document_scanner, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            label: const Text('SCAN WITH GEMINI 2.5 FLASH'),
          ),
        ),
      ],
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
            'No Firebase configured or testing on desktop? Preview the NID layout flow with realistic Bangla sample data.',
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
              'ANALYZING WITH GEMINI 2.5 FLASH...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Reading Bangla & English fields and detecting the photo',
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
                'EXTRACTED DATA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              if (_scannedInfo.avatarBytes != null)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.secondary, width: 1.5),
                  ),
                  child: ClipOval(
                    child: Image.memory(
                      _scannedInfo.avatarBytes!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Review and correct any field before generating the card.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 16),
          _buildFormRow(Icons.person, 'Name (English)', _scannedInfo.englishName, (val) {
            _scannedInfo = _scannedInfo.copyWith(englishName: val);
          }),
          _buildFormRow(Icons.person, 'নাম (বাংলা)', _scannedInfo.banglaName, (val) {
            _scannedInfo = _scannedInfo.copyWith(banglaName: val);
          }),
          _buildFormRow(Icons.pin, 'ID Number', _scannedInfo.idNumber, (val) {
            _scannedInfo = _scannedInfo.copyWith(idNumber: val);
          }),
          _buildFormRow(Icons.escalator_warning, 'পিতা (বাংলা)', _scannedInfo.banglaFatherName, (val) {
            _scannedInfo = _scannedInfo.copyWith(banglaFatherName: val);
          }),
          _buildFormRow(Icons.escalator_warning_outlined, 'মাতা (বাংলা)', _scannedInfo.banglaMotherName, (val) {
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

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _resetScan,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.errorRed,
              side: const BorderSide(color: AppTheme.errorRed),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Reset Scan'),
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
              child: const Text('Proceed', style: TextStyle(fontSize: 14),),
            ),
          ),
        ),
      ],
    );
  }
}
