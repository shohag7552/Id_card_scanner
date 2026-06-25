import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/card_info.dart';
import '../services/file_export.dart';
import '../services/nid_pdf_builder.dart';
import '../services/web_image_paste.dart';
import '../theme/app_theme.dart';
import '../widgets/card_template_widgets.dart';
import '../widgets/responsive_center.dart';
import '../widgets/adaptive_sheet.dart';

/// The two editable card images that support paste (and gallery pick).
enum _ImageSlot {
  photo,
  signature;

  String get label => this == _ImageSlot.photo ? 'Photo' : 'Signature';
}

class CardEditorPage extends StatefulWidget {
  final CardInfo initialInfo;
  final CardTemplateType selectedTemplate;

  /// When true, the page pops with the (possibly edited) [CardInfo] as its
  /// result so a caller can pick up the changes — e.g. the batch list opens
  /// this editor for a finished card and re-renders it with the edits. Existing
  /// callers leave this false and pop with no result exactly as before.
  final bool returnInfoOnPop;

  const CardEditorPage({
    super.key,
    required this.initialInfo,
    required this.selectedTemplate,
    this.returnInfoOnPop = false,
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

  /// Web only: the image slot "armed" by tapping its paste icon. The next
  /// Ctrl/⌘+V drops the pasted image here. Null when nothing is armed.
  _ImageSlot? _armedSlot;

  @override
  void initState() {
    super.initState();
    _cardInfo = widget.initialInfo;
    _selectedTemplate = widget.selectedTemplate;
    // On web, capture native Ctrl/⌘+V paste events for the armed image slot.
    // No-op on other platforms (they read the clipboard directly).
    WebImagePaste.start(_onWebPastedImages);
  }

  @override
  void dispose() {
    WebImagePaste.stop();
    super.dispose();
  }

  Future<void> _pickNewAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _cardInfo = _cardInfo.copyWith(avatarBytes: bytes);
        });
      }
    } catch (e) {
      debugPrint('Error picking avatar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting avatar: $e')),
        );
      }
    }
  }

  Future<void> _pickNewSignature() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _cardInfo = _cardInfo.copyWith(signatureBytes: bytes);
        });
      }
    } catch (e) {
      debugPrint('Error picking signature: $e');
    }
  }

  /// Reads an image off the system clipboard (Ctrl/⌘+C'd screenshot or image).
  /// Returns null — and never throws — when there is nothing usable.
  Future<Uint8List?> _clipboardImage() async {
    try {
      return await Pasteboard.image;
    } catch (e) {
      debugPrint('Clipboard image read error: $e');
      return null;
    }
  }

  /// Stores a pasted/picked image into the right field for [slot].
  void _applyImage(_ImageSlot slot, Uint8List bytes) {
    if (slot == _ImageSlot.photo) {
      _cardInfo = _cardInfo.copyWith(avatarBytes: bytes);
    } else {
      _cardInfo = _cardInfo.copyWith(signatureBytes: bytes);
    }
  }

  /// Pastes a clipboard image into [slot] — same flow as the Batch scanner.
  ///
  /// First tries a direct clipboard read (works on every platform for copied
  /// image *content* like screenshots). On web, a copied image *file* can't be
  /// read from a button tap — only from a real paste event — so we "arm" this
  /// slot and let the user press Ctrl/⌘+V to drop the image exactly here.
  Future<void> _pasteImage(_ImageSlot slot) async {
    final bytes = await _clipboardImage();
    if (bytes != null) {
      setState(() {
        _applyImage(slot, bytes);
        _armedSlot = null;
      });
      return;
    }

    if (kIsWeb) {
      setState(() => _armedSlot = slot);
      _toast('Press Ctrl/⌘+V to paste your copied image into the ${slot.label}.');
      return;
    }

    _toast('No image found in the clipboard. Copy an image first.');
  }

  /// Web paste-event sink: drops the first pasted image into the armed slot.
  void _onWebPastedImages(List<Uint8List> images) {
    if (!mounted || images.isEmpty) return;
    final slot = _armedSlot;
    if (slot == null) return; // nothing armed — ignore so we don't hijack.
    setState(() {
      _applyImage(slot, images.first);
      _armedSlot = null;
    });
    _toast('Pasted into the ${slot.label}.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Small icon button used inside an image tile (paste / copy).
  Widget _tileMiniButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: AppTheme.secondary),
        ),
      ),
    );
  }

  /// Renders the widget behind [key] to PNG bytes. Returns null on failure.
  Future<Uint8List?> _capturePngBytes(GlobalKey key) async {
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

      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint("Error rendering card image: $e");
      return null;
    }
  }

  Future<void> _shareCard() async {
    if (_selectedTemplate == CardTemplateType.bangladeshNid) {
      showAdaptiveSheet(
        context: context,
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

  void _downloadCard() {
    final isNid = _selectedTemplate == CardTemplateType.bangladeshNid;
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Download Card',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  subtitle: Text(
                    'Choose a format and side to export',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
                const Divider(color: AppTheme.borderCol),
                _sheetSectionLabel('PNG IMAGE'),
                if (isNid) ...[
                  _downloadTile(Icons.credit_card, 'Front Side (PNG)',
                      () => _downloadPng([_frontRepaintKey], 'front')),
                  _downloadTile(Icons.flip, 'Back Side (PNG)',
                      () => _downloadPng([_backRepaintKey], 'back')),
                  _downloadTile(Icons.view_stream, 'Both Sides (PNG)',
                      () => _downloadPng([_repaintKey], 'both')),
                ] else
                  _downloadTile(Icons.image, 'Download as PNG',
                      () => _downloadPng([_repaintKey], 'card')),
                const Divider(color: AppTheme.borderCol),
                _sheetSectionLabel('PDF DOCUMENT'),
                if (isNid) ...[
                  _downloadTile(Icons.picture_as_pdf, 'Front & Back (PDF)',
                      () => _downloadPdf([_frontRepaintKey, _backRepaintKey], 'front-back')),
                  _downloadTile(Icons.picture_as_pdf_outlined, 'Front Side (PDF)',
                      () => _downloadPdf([_frontRepaintKey], 'front')),
                  _downloadTile(Icons.picture_as_pdf_outlined, 'Back Side (PDF)',
                      () => _downloadPdf([_backRepaintKey], 'back')),
                ] else
                  _downloadTile(Icons.picture_as_pdf, 'Download as PDF',
                      () => _downloadPdf([_repaintKey], 'card')),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetSectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _downloadTile(IconData icon, String title, Future<void> Function() onTap) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.secondary),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.download, color: AppTheme.textSecondary, size: 18),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  String _safeName() {
    final raw = _cardInfo.englishName.isNotEmpty ? _cardInfo.englishName : 'card';
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'card' : cleaned.toLowerCase();
  }

  /// Captures the given [keys] as PNG and exports a single image (one key) to disk.
  Future<void> _downloadPng(List<GlobalKey> keys, String suffix) async {
    setState(() => _isSaving = true);
    final Uint8List? bytes = await _capturePngBytes(keys.first);
    setState(() => _isSaving = false);

    if (bytes == null) {
      _exportFailed();
      return;
    }
    final filename = '${_safeName()}_$suffix.png';
    await _deliverFile(bytes, filename);
  }

  /// Captures the given [keys] (one page each) and exports them as a PDF document.
  Future<void> _downloadPdf(List<GlobalKey> keys, String suffix) async {
    setState(() => _isSaving = true);

    Uint8List? pdfBytes;
    try {
      if (_selectedTemplate == CardTemplateType.bangladeshNid) {
        // Native, selectable/editable PDF — front + back on one page.
        pdfBytes = await NidPdfBuilder.build(
          _cardInfo,
          front: suffix != 'back',
          back: suffix != 'front',
        );
      } else {
        // Other templates: keep the rasterised image PDF.
        final pages = <Uint8List>[];
        for (final key in keys) {
          final bytes = await _capturePngBytes(key);
          if (bytes != null) pages.add(bytes);
        }
        if (pages.isNotEmpty) pdfBytes = await _buildPdf(pages);
      }
    } catch (e) {
      debugPrint('PDF build error: $e');
    }
    setState(() => _isSaving = false);

    if (pdfBytes == null) {
      _exportFailed();
      return;
    }
    final filename = '${_safeName()}_$suffix.pdf';
    await _deliverFile(pdfBytes, filename);
  }

  /// Builds a PDF with each PNG in [pageImages] centered on its own A4 page.
  Future<Uint8List> _buildPdf(List<Uint8List> pageImages) async {
    final doc = pw.Document();
    for (final imgBytes in pageImages) {
      final image = pw.MemoryImage(imgBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Saves [bytes] to the device's Downloads folder (mobile/desktop, via
  /// MediaStore on Android 10+) or triggers a browser download (web).
  Future<void> _deliverFile(Uint8List bytes, String filename) async {
    final SaveResult result = await FileExport.saveToDownloads(bytes, filename);
    if (!mounted) return;

    if (result.isWeb) {
      _showSavedDialog(
        title: 'DOWNLOADED',
        body: '$filename was downloaded by your browser. Check your Downloads.',
        bytes: bytes,
        filename: filename,
        canOpenDownloads: false,
      );
    } else if (result.ok) {
      _showSavedDialog(
        title: 'SAVED TO DOWNLOADS',
        body: '$filename was saved to your device\'s Downloads folder.',
        bytes: bytes,
        filename: filename,
        canOpenDownloads: result.canOpenDownloads,
      );
    } else {
      _showSavedDialog(
        title: 'FILE READY',
        body: 'Could not write directly to Downloads on this device. '
            'Tap "Save / Share" to store $filename in Downloads, Files or Drive.',
        bytes: bytes,
        filename: filename,
        canOpenDownloads: false,
      );
    }
  }

  void _showSavedDialog({
    required String title,
    required String body,
    required Uint8List bytes,
    required String filename,
    required bool canOpenDownloads,
  }) {
    final String mime = filename.endsWith('.pdf') ? 'application/pdf' : 'image/png';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.secondary),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Text(
            body,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: AppTheme.secondary)),
            ),
            if (canOpenDownloads)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  FileExport.openDownloads();
                },
                child: const Text('Open Downloads', style: TextStyle(color: AppTheme.secondary)),
              ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Share.shareXFiles(
                  [XFile.fromData(bytes, name: filename, mimeType: mime)],
                );
              },
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text('Save / Share'),
            ),
          ],
        );
      },
    );
  }

  void _exportFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export failed. Make sure the preview is visible.')),
    );
  }

  Future<void> _executeShare(GlobalKey key) async {
    setState(() => _isSaving = true);
    final Uint8List? bytes = await _capturePngBytes(key);
    setState(() => _isSaving = false);

    if (bytes != null && mounted) {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: '${_safeName()}.png', mimeType: 'image/png')],
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
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Template Editor'),
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
          child: ResponsiveCenter(
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
      ),
    );

    if (!widget.returnInfoOnPop) return scaffold;
    return PopScope<CardInfo>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _cardInfo);
      },
      child: scaffold,
    );
  }

  Widget _buildRepaintBoundaryPreview() {
    final isNid = _selectedTemplate == CardTemplateType.bangladeshNid;

    // Scale the fixed-size card design to the available width so it looks right
    // on every screen: it scales DOWN to avoid overflow on narrow phones and
    // UP (capped) to fill the space on web / big screens. The actual exports
    // read the inner RepaintBoundaries via toImage(), which ignores this
    // ancestor scale, so downloaded/shared files stay at full native resolution.
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = constraints.maxWidth.clamp(0.0, 480.0);
        return Center(
          child: SizedBox(
            width: targetWidth,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
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
            ),
          ),
        );
      },
    );
  }

  /// A tappable tile in EDIT DETAILS that previews the current image [bytes]
  /// (photo or signature). Tapping the tile picks from the gallery; the paste
  /// icon pastes from the clipboard (Batch-scanner flow: direct read, or arm +
  /// Ctrl/⌘+V on web). [light] uses a white backdrop + contain fit, suited to
  /// dark-on-transparent signatures; otherwise the image covers the tile.
  Widget _buildImageEditTile({
    required String label,
    required Uint8List? bytes,
    required IconData icon,
    required _ImageSlot slot,
    required VoidCallback onTap,
    bool light = false,
  }) {
    final hasImage = bytes != null;
    final armed = _armedSlot == slot;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.darkBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: armed ? AppTheme.secondary : AppTheme.borderCol,
              width: armed ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  _tileMiniButton(
                    Icons.content_paste,
                    'Paste image from clipboard',
                    () => _pasteImage(slot),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 54,
                  width: double.infinity,
                  alignment: Alignment.center,
                  color: light ? Colors.white : AppTheme.surfaceBg,
                  child: hasImage
                      ? Image.memory(bytes, fit: light ? BoxFit.contain : BoxFit.cover)
                      : Icon(icon, color: AppTheme.textSecondary, size: 22),
                ),
              ),
              if (armed)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Press Ctrl/⌘+V to paste here',
                    style: TextStyle(
                      color: AppTheme.secondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasImage ? Icons.swap_horiz : Icons.add_photo_alternate,
                    size: 14,
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasImage ? 'Change' : 'Add',
                    style: const TextStyle(
                      color: AppTheme.secondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          const Text(
            'EDIT DETAILS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          // Photo (avatar) + holder signature — tap a tile to pick a new image.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImageEditTile(
                label: 'PHOTO',
                bytes: _cardInfo.avatarBytes,
                icon: Icons.person,
                slot: _ImageSlot.photo,
                onTap: _pickNewAvatar,
              ),
              const SizedBox(width: 10),
              _buildImageEditTile(
                label: 'SIGNATURE',
                bytes: _cardInfo.signatureBytes,
                icon: Icons.draw,
                slot: _ImageSlot.signature,
                onTap: _pickNewSignature,
                light: true,
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
              onPressed: _isSaving ? null : _downloadCard,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download, size: 18),
              label: const Text('DOWNLOAD'),
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
