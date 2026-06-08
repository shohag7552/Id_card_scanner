import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/card_info.dart';
import '../theme/app_theme.dart';
import '../widgets/card_template_widgets.dart';

class CardEditorPage extends StatefulWidget {
  final CardInfo initialInfo;
  final CardTemplateType selectedTemplate;

  const CardEditorPage({
    super.key,
    required this.initialInfo,
    required this.selectedTemplate,
  });

  @override
  State<CardEditorPage> createState() => _CardEditorPageState();
}

class _CardEditorPageState extends State<CardEditorPage> {
  late CardInfo _cardInfo;
  late CardTemplateType _selectedTemplate;
  final ImagePicker _picker = ImagePicker();
  
  // Key to capture card as image
  final GlobalKey _frontRepaintKey = GlobalKey();
  final GlobalKey _backRepaintKey = GlobalKey();
  final GlobalKey _repaintKey = GlobalKey(); // Combined key

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _cardInfo = widget.initialInfo;
    _selectedTemplate = widget.selectedTemplate;
  }

  Future<void> _pickNewAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _cardInfo = _cardInfo.copyWith(avatarPath: image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking avatar: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting avatar: $e')),
      );
    }
  }

  Future<void> _pickNewSignature() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _cardInfo = _cardInfo.copyWith(signaturePath: image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking signature: $e');
    }
  }

  Future<void> _pickNewAuthoritySignature() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _cardInfo = _cardInfo.copyWith(authoritySignaturePath: image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking authority signature: $e');
    }
  }

  Future<String?> _captureKeyAsImage(GlobalKey key) async {
    try {
      final RenderRepaintBoundary? boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      
      if (boundary == null) {
        throw Exception("RepaintBoundary render object not found.");
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        throw Exception("Failed to convert image to byte data.");
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final Directory tempDir = await getTemporaryDirectory();
      final String path =
          '${tempDir.path}/id_card_${key.hashCode}_${DateTime.now().millisecondsSinceEpoch}.png';
      
      final File file = File(path);
      await file.writeAsBytes(pngBytes);
      return path;
    } catch (e) {
      debugPrint("Error exporting card image: $e");
      return null;
    }
  }

  Future<void> _shareCard() async {
    if (_selectedTemplate == CardTemplateType.bangladeshNid) {
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
                const ListTile(
                  title: Text(
                    'Share NID Card',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                ),
                const Divider(color: AppTheme.borderCol),
                ListTile(
                  leading: const Icon(Icons.credit_card, color: AppTheme.secondary),
                  title: const Text('Share Front Side Only', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _executeShare(_frontRepaintKey);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flip, color: AppTheme.secondary),
                  title: const Text('Share Back Side Only', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _executeShare(_backRepaintKey);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.view_stream, color: AppTheme.secondary),
                  title: const Text('Share Both Sides (Combined)', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _executeShare(_repaintKey);
                  },
                ),
              ],
            ),
          );
        },
      );
    } else {
      _executeShare(_repaintKey);
    }
  }

  Future<void> _saveCardLocal() async {
    if (_selectedTemplate == CardTemplateType.bangladeshNid) {
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
                const ListTile(
                  title: Text(
                    'Export NID Card',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                ),
                const Divider(color: AppTheme.borderCol),
                ListTile(
                  leading: const Icon(Icons.credit_card, color: AppTheme.secondary),
                  title: const Text('Save Front Side Only', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _executeSave(_frontRepaintKey);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flip, color: AppTheme.secondary),
                  title: const Text('Save Back Side Only', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _executeSave(_backRepaintKey);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.view_stream, color: AppTheme.secondary),
                  title: const Text('Save Both Sides (Combined)', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _executeSave(_repaintKey);
                  },
                ),
              ],
            ),
          );
        },
      );
    } else {
      _executeSave(_repaintKey);
    }
  }

  Future<void> _executeSave(GlobalKey key) async {
    setState(() => _isSaving = true);
    final path = await _captureKeyAsImage(key);
    setState(() => _isSaving = false);

    if (path != null && mounted) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.secondary),
                SizedBox(width: 10),
                Text('CARD EXPORTED', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your card template was rendered and saved successfully.',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderCol),
                  ),
                  child: Text(
                    'Location:\n$path',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: AppTheme.secondary)),
              ),
              if (!kIsWeb)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Share.shareXFiles([XFile(path)]);
                  },
                  child: const Text('Share File'),
                )
            ],
          );
        },
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed.')),
      );
    }
  }

  Future<void> _executeShare(GlobalKey key) async {
    setState(() => _isSaving = true);
    final path = await _captureKeyAsImage(key);
    setState(() => _isSaving = false);

    if (path != null && mounted) {
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Generated ID Card for ${_cardInfo.englishName.isNotEmpty ? _cardInfo.englishName : "Customer"}. Created with Card Scanner Pro.',
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share card. Make sure the preview is visible.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TEMPLATE EDITOR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: AppTheme.secondary),
            onPressed: _isSaving ? null : _shareCard,
            tooltip: 'Share Card',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildRepaintBoundaryPreview(),
              const SizedBox(height: 12),
              
              const Text(
                'Hold and adjust fields using the form below',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 24),

              _buildFormEditor(),
              const SizedBox(height: 24),

              _buildTemplateCarousel(),
              const SizedBox(height: 32),

              _buildExportButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepaintBoundaryPreview() {
    final isNid = _selectedTemplate == CardTemplateType.bangladeshNid;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.borderCol, width: 1.5),
        ),
        child: RepaintBoundary(
          key: _repaintKey,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.all(8.0),
            child: isNid
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RepaintBoundary(
                        key: _frontRepaintKey,
                        child: CardTemplateWidget(
                          cardInfo: _cardInfo,
                          templateType: _selectedTemplate,
                          isBack: false,
                        ),
                      ),
                      const SizedBox(height: 16),
                      RepaintBoundary(
                        key: _backRepaintKey,
                        child: CardTemplateWidget(
                          cardInfo: _cardInfo,
                          templateType: _selectedTemplate,
                          isBack: true,
                        ),
                      ),
                    ],
                  )
                : CardTemplateWidget(
                    cardInfo: _cardInfo,
                    templateType: _selectedTemplate,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorActionButton(String label, VoidCallback onPressed, IconData icon) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 12),
      label: Text(label, style: const TextStyle(fontSize: 10)),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.secondary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _buildFormEditor() {
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
                'EDIT DETAILS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _buildEditorActionButton('Photo', _pickNewAvatar, Icons.add_photo_alternate),
                  _buildEditorActionButton('Holder Sign', _pickNewSignature, Icons.edit),
                  _buildEditorActionButton('Auth Sign', _pickNewAuthoritySignature, Icons.draw),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField('English Name (Name)', _cardInfo.englishName, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(englishName: val);
            });
          }),
          _buildTextField('Bangla Name (নাম)', _cardInfo.banglaName, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(banglaName: val);
            });
          }),
          _buildTextField('ID Number', _cardInfo.idNumber, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(idNumber: val);
            });
          }),
          _buildTextField('Bangla Father\'s Name (পিতা)', _cardInfo.banglaFatherName, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(banglaFatherName: val);
            });
          }),
          _buildTextField('Bangla Mother\'s Name (মাতা)', _cardInfo.banglaMotherName, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(banglaMotherName: val);
            });
          }),
          Row(
            children: [
              Expanded(
                child: _buildTextField('Date of Birth', _cardInfo.dateOfBirth, (val) {
                  setState(() {
                    _cardInfo = _cardInfo.copyWith(dateOfBirth: val);
                  });
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTextField('Age / Label', _cardInfo.age, (val) {
                  setState(() {
                    _cardInfo = _cardInfo.copyWith(age: val);
                  });
                }),
              ),
            ],
          ),
          _buildTextField('Address (বাংলা)', _cardInfo.address, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(address: val);
            });
          }, maxLines: 2),
          Row(
            children: [
              Expanded(
                child: _buildTextField('Blood Group', _cardInfo.bloodGroup, (val) {
                  setState(() {
                    _cardInfo = _cardInfo.copyWith(bloodGroup: val);
                  });
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTextField('Birth Place (বাংলা)', _cardInfo.birthPlace, (val) {
                  setState(() {
                    _cardInfo = _cardInfo.copyWith(birthPlace: val);
                  });
                }),
              ),
            ],
          ),
          _buildTextField('Issue Date (বাংলা)', _cardInfo.issueDate, (val) {
            setState(() {
              _cardInfo = _cardInfo.copyWith(issueDate: val);
            });
          }),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String initialValue,
    Function(String) onChanged, {
    int maxLines = 1,
  }) {
    final controller = TextEditingController(text: initialValue);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTemplateCarousel() {
    final List<Map<String, dynamic>> templates = [
      {
        'type': CardTemplateType.bangladeshNid,
        'name': 'BD NID Card',
        'icon': Icons.credit_card,
      },
      {
        'type': CardTemplateType.corporate,
        'name': 'Corporate',
        'icon': Icons.badge,
      },
      {
        'type': CardTemplateType.vipClub,
        'name': 'VIP Club',
        'icon': Icons.stars,
      },
      {
        'type': CardTemplateType.student,
        'name': 'Student',
        'icon': Icons.school,
      },
      {
        'type': CardTemplateType.glassmorphic,
        'name': 'Tech Pass',
        'icon': Icons.nfc,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT CARD TEMPLATE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 65,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              final isSelected = _selectedTemplate == t['type'];

              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedTemplate = t['type'];
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 105,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : AppTheme.surfaceBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : AppTheme.borderCol,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          t['icon'],
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t['name'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExportButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveCardLocal,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download, size: 18),
              label: const Text('SAVE TEMPLATE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _shareCard,
            icon: const Icon(Icons.share, size: 18),
            label: const Text('SHARE CARD'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.secondary,
              side: const BorderSide(color: AppTheme.secondary, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
