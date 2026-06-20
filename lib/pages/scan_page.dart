import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import '../models/card_info.dart';
import '../services/gemini_nid_service.dart';
import '../services/face_cropper.dart';
import '../services/web_image_paste.dart';
import '../theme/app_theme.dart';
import 'card_editor_page.dart';
import '../widgets/card_template_widgets.dart';
import '../widgets/responsive_center.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/model_selector.dart';

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

  /// Web only: which side a user "armed" by tapping Paste. The next Ctrl/⌘+V
  /// drops the image there. null = nothing armed; true = front; false = back.
  bool? _pasteTargetFront;

  /// Currently selected Gemini model id (kept in sync with the shared
  /// [GeminiNidService.selectedModelId]).
  String _selectedModelId = GeminiNidService.selectedModelId;

  CardInfo _scannedInfo = const CardInfo();

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    // On web, capture native Ctrl/⌘+V paste events (handles copied image files
    // and screenshots across all browsers). No-op on other platforms.
    WebImagePaste.start(_onWebPastedImages);
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
    WebImagePaste.stop();
    _laserController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Clipboard paste — mirrors the batch scanner. Copied NID images can be pasted
  // into the FRONT or BACK slot (Ctrl/⌘+V or the "Paste" source option) in
  // addition to camera/gallery. Never throws; existing pick flow is unaffected.
  // ---------------------------------------------------------------------------

  Future<Uint8List?> _clipboardImage() async {
    try {
      return await Pasteboard.image;
    } catch (e) {
      debugPrint('Clipboard image read error: $e');
      return null;
    }
  }

  void _setSideImage(bool isFront, Uint8List bytes) {
    setState(() {
      if (isFront) {
        _frontImagePath = 'pasted_front.png';
        _frontBytes = bytes;
      } else {
        _backImagePath = 'pasted_back.png';
        _backBytes = bytes;
      }
      _hasScanned = false;
      _pasteTargetFront = null;
    });
  }

  /// Pastes a clipboard image into the [isFront] slot. Works directly for copied
  /// image *content* (screenshots) on every platform; on web a copied *file*
  /// can't be read from a tap, so we "arm" the slot for the next Ctrl/⌘+V.
  Future<void> _pasteImage({required bool isFront}) async {
    if (_isScanning) return;
    final bytes = await _clipboardImage();
    if (bytes != null) {
      _setSideImage(isFront, bytes);
      return;
    }
    if (kIsWeb) {
      setState(() => _pasteTargetFront = isFront);
      _toast('Press Ctrl/⌘+V to paste your copied image into the '
          '${isFront ? 'FRONT' : 'BACK'} side.');
      return;
    }
    _toast('No image found in the clipboard. Copy an NID image first.');
  }

  /// The side a plain (un-armed) paste should fill: the armed slot if any, else
  /// the first EMPTY slot (front if empty, otherwise back), so a second paste
  /// naturally lands on the back instead of overwriting the front.
  bool _defaultPasteSide() =>
      _pasteTargetFront ?? (_frontBytes == null ? true : false);

  /// Handles images pasted via the browser (web). If two images are pasted
  /// together (front+back copied at once) they fill both sides; otherwise the
  /// image goes to the armed slot, or the first empty slot.
  void _onWebPastedImages(List<Uint8List> images) {
    if (!mounted || _isScanning || images.isEmpty) return;
    if (_pasteTargetFront == null && images.length > 1) {
      setState(() {
        _frontImagePath = 'pasted_front.png';
        _frontBytes = images[0];
        _backImagePath = 'pasted_back.png';
        _backBytes = images[1];
        _hasScanned = false;
      });
      _toast('Pasted front + back.');
      return;
    }
    final side = _defaultPasteSide();
    _setSideImage(side, images.first);
    _toast('Pasted into the ${side ? 'FRONT' : 'BACK'} side.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  /// Friendly label of the currently selected model (e.g. "Gemini 2.5 Flash").
  String _selectedModelLabel() {
    final m = GeminiNidService.availableModels.firstWhere(
      (m) => m.id == _selectedModelId,
      orElse: () => GeminiNidService.availableModels.first,
    );
    return m.id.replaceAll('gemini-', 'Gemini ').replaceAll('-', ' ');
  }

  /// Sends the front (and optional back) image to the selected Gemini model, then
  /// crops the avatar / signatures on-device with ML Kit face detection.
  Future<void> _scanNow() async {
    if (_frontBytes == null) return;

    setState(() => _isScanning = true);
    _laserController.repeat(reverse: true);

    // Gemini extracts the text AND returns photo/signatures cropped from its
    // bounding boxes — this is the baseline used on web and Windows.
    final NidScanResult result = await GeminiNidService.scanNid(
      frontBytes: _frontBytes!,
      backBytes: _backBytes,
      modelId: _selectedModelId,
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
        SnackBar(
          content: Text('NID scanned with ${_selectedModelLabel()}!'),
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
      // Desktop: Ctrl/⌘+V pastes into the armed side (or FRONT). On web the
      // native paste handler (WebImagePaste) handles Ctrl/⌘+V instead.
      body: CallbackShortcuts(
        bindings: kIsWeb
            ? const <ShortcutActivator, VoidCallback>{}
            : {
                const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
                    _pasteImage(isFront: _defaultPasteSide()),
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
                    _pasteImage(isFront: _defaultPasteSide()),
              },
        child: Focus(
          autofocus: true,
          child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: ResponsiveCenter(
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
              const SizedBox(height: 16),

              // Let the user pick which Gemini model does the extraction.
              ModelSelector(
                selectedId: _selectedModelId,
                onChanged: (id) {
                  setState(() {
                    _selectedModelId = id;
                    GeminiNidService.selectedModelId = id;
                  });
                },
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
      ),
        ), // Focus
      ), // CallbackShortcuts
    );
  }

  void _showImageSourcePicker({required bool isFront}) {
    showAdaptiveSheet(
      context: context,
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
              ListTile(
                leading: const Icon(Icons.content_paste, color: AppTheme.secondary),
                title: const Text('Paste from Clipboard', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Copy an NID image, then paste (or Ctrl/⌘+V)',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  _pasteImage(isFront: isFront);
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
    // Web: this slot is waiting for a Ctrl/⌘+V after the user tapped Paste.
    final armed = _pasteTargetFront == isFront;

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
                  color: armed
                      ? AppTheme.secondary
                      : (hasImage ? AppTheme.secondary : AppTheme.borderCol),
                  width: armed ? 2 : 1.5,
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
                              armed
                                  ? Icons.content_paste_go
                                  : (isFront ? Icons.add_photo_alternate : Icons.flip_to_back),
                              size: 32,
                              color: armed ? AppTheme.secondary : AppTheme.borderCol,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              armed ? 'Press Ctrl/⌘+V' : 'Tap to upload',
                              style: TextStyle(
                                color: armed ? AppTheme.secondary : AppTheme.textSecondary,
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
            label: Text('SCAN WITH ${_selectedModelLabel().toUpperCase()}'),
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
            'No API key configured or testing on desktop? Preview the NID layout flow with realistic Bangla sample data.',
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
