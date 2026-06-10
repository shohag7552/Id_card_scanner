import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/batch_item.dart';
import '../models/card_info.dart';
import '../models/nid_input_pair.dart';
import '../services/file_export.dart';
import '../services/gemini_nid_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/card_template_widgets.dart';
import '../widgets/responsive_center.dart';

/// Which side(s) of a card to export for a single-item download.
enum _Side {
  front,
  back,
  both;

  /// Filename suffix for this side.
  String get suffix => switch (this) {
        _Side.front => 'front',
        _Side.back => 'back',
        _Side.both => 'both',
      };
}

/// Batch NID scanner: the user picks a list of FRONT images and a list of BACK
/// images (paired by order), then the page scans each pair with Gemini, renders
/// the Bangladesh NID card to PNG off-screen, and bundles every generated card
/// into a single ZIP download. Low-confidence scans are held back for a quick
/// review before they are included.
class BatchScanPage extends StatefulWidget {
  const BatchScanPage({super.key});

  @override
  State<BatchScanPage> createState() => _BatchScanPageState();
}

class _BatchScanPageState extends State<BatchScanPage> {
  final ImagePicker _picker = ImagePicker();

  /// Editable source pairs the user reviews and tweaks before scanning.
  final List<NidInputPair> _pairs = [];
  final List<BatchItem> _items = [];

  bool _processing = false;
  bool _cancelled = false;

  /// The single card currently mounted in the hidden render host. Only one card
  /// is ever rendered at a time, so memory stays flat regardless of batch size.
  BatchItem? _renderTarget;
  final GlobalKey _combinedKey = GlobalKey();
  final GlobalKey _frontKey = GlobalKey();
  final GlobalKey _backKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Warm the asset images the template paints (the gov seal + watermark) so
    // they're decoded before the first off-screen capture.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(const AssetImage('assets/images/gov_seal.png'), context);
      precacheImage(const AssetImage('assets/images/sapla_logo.png'), context);
    });
  }

  // ---------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------

  /// Bulk-pick all FRONT images. Each becomes a pair, preserving any back
  /// images already attached by index.
  Future<void> _pickFronts() async {
    final bytes = await _pickMulti();
    if (bytes == null) return;
    final existingBacks = _pairs.map((p) => p.back).toList();
    setState(() {
      _pairs
        ..clear()
        ..addAll(List.generate(
          bytes.length,
          (i) => NidInputPair(
            front: bytes[i],
            back: i < existingBacks.length ? existingBacks[i] : null,
          ),
        ));
    });
  }

  /// Bulk-pick all BACK images, assigned to existing pairs in order.
  Future<void> _pickBacks() async {
    if (_pairs.isEmpty) {
      _toast('Select the front images first.');
      return;
    }
    final bytes = await _pickMulti();
    if (bytes == null) return;
    setState(() {
      for (var i = 0; i < _pairs.length; i++) {
        if (i < bytes.length) _pairs[i].back = bytes[i];
      }
    });
    if (bytes.length > _pairs.length) {
      _toast('${bytes.length - _pairs.length} extra back image(s) ignored — '
          'no front to pair them with.');
    }
  }

  /// Replaces the front or back image of a single pair during review.
  Future<void> _changeImage(NidInputPair pair, {required bool isFront}) async {
    final bytes = await _pickSingle();
    if (bytes == null) return;
    setState(() {
      if (isFront) {
        pair.front = bytes;
      } else {
        pair.back = bytes;
      }
    });
  }

  /// Adds a brand-new pair from a single picked front image.
  Future<void> _addPair() async {
    final bytes = await _pickSingle();
    if (bytes == null) return;
    setState(() => _pairs.add(NidInputPair(front: bytes)));
  }

  void _removeBack(NidInputPair pair) => setState(() => pair.back = null);

  void _removePair(NidInputPair pair) => setState(() => _pairs.remove(pair));

  Future<List<Uint8List>?> _pickMulti() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(imageQuality: 90);
      if (picked.isEmpty) return null;
      final List<Uint8List> bytes = [];
      for (final x in picked) {
        bytes.add(await x.readAsBytes());
      }
      return bytes;
    } catch (e) {
      debugPrint('Batch pick error: $e');
      _toast('Error selecting images: $e');
      return null;
    }
  }

  Future<Uint8List?> _pickSingle() async {
    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      return picked == null ? null : await picked.readAsBytes();
    } catch (e) {
      debugPrint('Batch pick error: $e');
      _toast('Error selecting image: $e');
      return null;
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Processing
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    if (_pairs.isEmpty) return;

    _items
      ..clear()
      ..addAll(List.generate(
        _pairs.length,
        (i) => BatchItem(
          index: i,
          frontBytes: _pairs[i].front,
          backBytes: _pairs[i].back,
        ),
      ));

    setState(() {
      _processing = true;
      _cancelled = false;
    });

    for (final item in _items) {
      if (_cancelled) break;
      await _processOne(item);
    }

    if (mounted) setState(() => _processing = false);
    if (!_cancelled) await _autoDownloadIfReady();
  }

  /// Scans one item, then renders it unless it needs review.
  Future<void> _processOne(BatchItem item) async {
    if (mounted) setState(() => item.status = BatchStatus.scanning);

    final result = await GeminiNidService.scanNid(
      frontBytes: item.frontBytes,
      backBytes: item.backBytes,
    );
    item.info = result.info;
    item.error = result.error;

    // Hold back anything Gemini errored on or that's missing the anchor fields.
    if (result.hasError || item.isLowConfidence) {
      if (mounted) setState(() => item.status = BatchStatus.needsReview);
      return;
    }

    await _renderAndFinish(item);
  }

  /// Renders [item]'s card and marks it done/failed.
  Future<void> _renderAndFinish(BatchItem item) async {
    if (mounted) setState(() => item.status = BatchStatus.rendering);

    await _renderItem(item);

    if (mounted) {
      setState(() => item.status =
          item.isRendered ? BatchStatus.done : BatchStatus.failed);
    }
  }

  /// Mounts [item] in the hidden render host, waits for it to paint, and
  /// captures the combined image plus each side individually — so the user can
  /// later download any side, in any format, with no re-render.
  Future<void> _renderItem(BatchItem item) async {
    setState(() => _renderTarget = item);

    // Let the host build, then make sure its in-memory images are decoded
    // before we rasterize — otherwise the photo/signature paint blank.
    await WidgetsBinding.instance.endOfFrame;
    await _precacheItemImages(item);
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 120));

    item.frontPng = await _capturePng(_frontKey);
    item.backPng = await _capturePng(_backKey);
    item.combinedPng = await _capturePng(_combinedKey);

    if (mounted) setState(() => _renderTarget = null);
  }

  Future<void> _precacheItemImages(BatchItem item) async {
    if (!mounted) return;
    final futures = <Future<void>>[];
    void add(Uint8List? b) {
      if (b != null) futures.add(precacheImage(MemoryImage(b), context));
    }

    add(item.info.avatarBytes);
    add(item.info.signatureBytes);
    add(item.info.authoritySignatureBytes);
    if (futures.isNotEmpty) await Future.wait(futures);
  }

  Future<Uint8List?> _capturePng(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Batch capture error: $e');
      return null;
    }
  }

  void _cancel() {
    setState(() => _cancelled = true);
  }

  Future<void> _retryFailed() async {
    final failed = _items.where((i) => i.status == BatchStatus.failed).toList();
    if (failed.isEmpty) return;
    setState(() {
      _processing = true;
      _cancelled = false;
    });
    for (final item in failed) {
      if (_cancelled) break;
      await _processOne(item);
    }
    if (mounted) setState(() => _processing = false);
    if (!_cancelled) await _autoDownloadIfReady();
  }

  // ---------------------------------------------------------------------------
  // Review
  // ---------------------------------------------------------------------------

  Future<void> _reviewItem(BatchItem item) async {
    final edited = await showDialog<CardInfo>(
      context: context,
      builder: (context) => _ReviewDialog(item: item),
    );
    if (edited == null) return;

    item.info = edited;
    item.error = null;
    await _renderAndFinish(item);
    await _autoDownloadIfReady();
  }

  // ---------------------------------------------------------------------------
  // Delivery
  // ---------------------------------------------------------------------------

  /// Downloads automatically only when everything is resolved (nothing left to
  /// review and at least one card is ready).
  Future<void> _autoDownloadIfReady() async {
    final ready = _items.where((i) => i.status == BatchStatus.done).length;
    final pending =
        _items.where((i) => i.status == BatchStatus.needsReview).length;
    if (ready > 0 && pending == 0) {
      await _downloadZip(auto: true);
    }
  }

  Future<void> _downloadZip({bool auto = false}) async {
    final ready = _items
        .where((i) => i.status == BatchStatus.done && i.combinedPng != null)
        .toList();
    if (ready.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No finished cards to download yet.')),
        );
      }
      return;
    }

    final archive = Archive();
    for (final item in ready) {
      // One combined PNG per NID (front + back in a single image). Prefixed with
      // the 1-based index so two same-named people never collide.
      final base = '${(item.index + 1).toString().padLeft(2, '0')}_${item.safeBaseName}';
      archive.add(ArchiveFile.bytes('$base.png', item.combinedPng!));
    }

    final Uint8List zipBytes = ZipEncoder().encodeBytes(archive);
    final filename = 'nid_batch_${ready.length}_cards.zip';
    final SaveResult result = await FileExport.saveToDownloads(zipBytes, filename);
    if (!mounted) return;

    final where = result.isWeb
        ? 'downloaded by your browser'
        : (result.ok ? 'saved to your Downloads folder' : 'ready to share');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.secondary,
        content: Text(
          '${auto ? 'Done! ' : ''}$filename (${ready.length} cards) $where.',
          style: const TextStyle(color: Colors.black),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Per-item download (single NID): PNG / PDF, front / back / both.
  // ---------------------------------------------------------------------------

  void _showItemDownloadSheet(BatchItem item) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    'Download ${item.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  subtitle: const Text(
                    'Choose a format and side',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
                const Divider(color: AppTheme.borderCol),
                _sheetSectionLabel('PNG IMAGE'),
                _downloadTile(Icons.view_stream, 'Both sides (combined)',
                    () => _downloadItemPng(item, _Side.both)),
                _downloadTile(Icons.credit_card, 'Front side only',
                    () => _downloadItemPng(item, _Side.front)),
                _downloadTile(Icons.flip, 'Back side only',
                    () => _downloadItemPng(item, _Side.back)),
                const Divider(color: AppTheme.borderCol),
                _sheetSectionLabel('PDF DOCUMENT'),
                _downloadTile(Icons.picture_as_pdf, 'Both sides (2 pages)',
                    () => _downloadItemPdf(item, _Side.both)),
                _downloadTile(Icons.picture_as_pdf_outlined, 'Front side only',
                    () => _downloadItemPdf(item, _Side.front)),
                _downloadTile(Icons.picture_as_pdf_outlined, 'Back side only',
                    () => _downloadItemPdf(item, _Side.back)),
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

  /// The image bytes for a side; "both" uses the pre-rendered combined PNG.
  Uint8List? _pngForSide(BatchItem item, _Side side) {
    switch (side) {
      case _Side.front:
        return item.frontPng;
      case _Side.back:
        return item.backPng;
      case _Side.both:
        return item.combinedPng;
    }
  }

  Future<void> _downloadItemPng(BatchItem item, _Side side) async {
    final bytes = _pngForSide(item, side);
    if (bytes == null) {
      _toast('That image is not available.');
      return;
    }
    await _deliver(bytes, '${item.safeBaseName}_${side.suffix}.png');
  }

  Future<void> _downloadItemPdf(BatchItem item, _Side side) async {
    // For "both" the PDF gets one page per side (full-size each); single sides
    // are a one-page document.
    final List<Uint8List> pages;
    if (side == _Side.both) {
      pages = [
        if (item.frontPng != null) item.frontPng!,
        if (item.backPng != null) item.backPng!,
      ];
    } else {
      final b = _pngForSide(item, side);
      pages = b == null ? [] : [b];
    }
    if (pages.isEmpty) {
      _toast('Nothing to export.');
      return;
    }

    Uint8List? pdfBytes;
    try {
      pdfBytes = await _buildPdf(pages);
    } catch (e) {
      debugPrint('Batch PDF build error: $e');
    }
    if (pdfBytes == null) {
      _toast('Could not build the PDF.');
      return;
    }
    await _deliver(pdfBytes, '${item.safeBaseName}_${side.suffix}.pdf');
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
          build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return doc.save();
  }

  Future<void> _deliver(Uint8List bytes, String filename) async {
    final SaveResult result = await FileExport.saveToDownloads(bytes, filename);
    if (!mounted) return;
    final where = result.isWeb
        ? 'downloaded by your browser'
        : (result.ok ? 'saved to your Downloads folder' : 'ready to share');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.secondary,
        content: Text('$filename $where.', style: const TextStyle(color: Colors.black)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BATCH NID SCANNER')),
      body: Stack(
        children: [
          // Hidden render host: painted (so toImage works) but fully covered by
          // the opaque content layer above, so the user never sees it.
          if (_renderTarget != null)
            Positioned(left: 0, top: 0, child: _buildRenderHost(_renderTarget!)),

          Positioned.fill(
            child: Container(
              color: AppTheme.darkBg,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ResponsiveCenter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_items.isEmpty) ...[
                          _buildPickerCard(),
                          if (_pairs.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _buildPairReview(),
                            const SizedBox(height: 16),
                            _buildStartButton(),
                          ],
                        ] else ...[
                          _buildSummaryBar(),
                          const SizedBox(height: 16),
                          _buildItemList(),
                          const SizedBox(height: 20),
                          _buildActionBar(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The off-screen card, captured one item at a time. The outer boundary
  /// rasterizes front+back into the combined image; the inner boundaries
  /// capture each side on its own.
  Widget _buildRenderHost(BatchItem item) {
    return Material(
      type: MaterialType.transparency,
      child: RepaintBoundary(
        key: _combinedKey,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: _frontKey,
                child: CardTemplateWidget(
                  cardInfo: item.info,
                  templateType: CardTemplateType.bangladeshNid,
                  isBack: false,
                ),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                key: _backKey,
                child: CardTemplateWidget(
                  cardInfo: item.info,
                  templateType: CardTemplateType.bangladeshNid,
                  isBack: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerCard() {
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
              Icon(Icons.collections, color: AppTheme.secondary, size: 18),
              SizedBox(width: 8),
              Text(
                'UPLOAD NID IMAGES',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick all FRONT images, then all BACK images — they pair in the same '
            'order (1st front ↔ 1st back). You can review every pair and swap '
            'either image below before scanning. Back side is optional.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _pickerButton(
                  label: 'FRONT SIDES',
                  count: _pairs.length,
                  icon: Icons.badge,
                  onTap: _processing ? null : _pickFronts,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pickerButton(
                  label: 'BACK SIDES',
                  count: _pairs.where((p) => p.back != null).length,
                  icon: Icons.flip_to_back,
                  onTap: _processing ? null : _pickBacks,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pickerButton({
    required String label,
    required int count,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final hasItems = count > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.darkBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasItems ? AppTheme.secondary : AppTheme.borderCol,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: hasItems ? AppTheme.secondary : AppTheme.textSecondary, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hasItems ? '$count selected' : 'Tap to select',
              style: TextStyle(
                color: hasItems ? AppTheme.secondary : AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    final canStart = _pairs.isNotEmpty && !_processing;
    return Container(
      decoration: BoxDecoration(
        gradient: canStart ? AppTheme.primaryGradient : null,
        color: canStart ? null : AppTheme.surfaceBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ElevatedButton.icon(
        onPressed: canStart ? _start : null,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text('SCAN & GENERATE ${_pairs.length} NID${_pairs.length == 1 ? '' : 's'}'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pair review (pre-scan): inspect each front/back pair and swap images.
  // ---------------------------------------------------------------------------

  Widget _buildPairReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.fact_check, color: AppTheme.secondary, size: 16),
                const SizedBox(width: 8),
                Text(
                  'REVIEW ${_pairs.length} PAIR${_pairs.length == 1 ? '' : 'S'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _processing ? null : _addPair,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _pairs.length,
          separatorBuilder: (context, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _buildPairTile(_pairs[index], index),
        ),
      ],
    );
  }

  Widget _buildPairTile(NidInputPair pair, int index) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(38),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PAIR ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _processing ? null : () => _removePair(pair),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _imageSlot(
                  label: 'FRONT',
                  bytes: pair.front,
                  onChange: _processing ? null : () => _changeImage(pair, isFront: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _imageSlot(
                  label: 'BACK',
                  bytes: pair.back,
                  onChange: _processing ? null : () => _changeImage(pair, isFront: false),
                  onRemove: pair.back != null && !_processing ? () => _removeBack(pair) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageSlot({
    required String label,
    required Uint8List? bytes,
    required VoidCallback? onChange,
    VoidCallback? onRemove,
  }) {
    final hasImage = bytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1.6,
          child: hasImage
              ? GestureDetector(
                  onTap: () => _previewImage(bytes, label),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderCol),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(bytes, fit: BoxFit.cover),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Icon(Icons.zoom_in,
                              color: Colors.white.withAlpha(220), size: 16),
                        ),
                      ],
                    ),
                  ),
                )
              : InkWell(
                  onTap: onChange,
                  borderRadius: BorderRadius.circular(10),
                  child: DottedPlaceholder(label: 'Add $label side'),
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onChange,
                icon: Icon(hasImage ? Icons.swap_horiz : Icons.add_photo_alternate, size: 14),
                label: Text(hasImage ? 'Change' : 'Add', style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondary,
                  side: const BorderSide(color: AppTheme.borderCol),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, color: AppTheme.errorRed, size: 16),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _previewImage(Uint8List bytes, String label) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('$label side',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final total = _items.length;
    final done = _items.where((i) => i.status == BatchStatus.done).length;
    final review = _items.where((i) => i.status == BatchStatus.needsReview).length;
    final failed = _items.where((i) => i.status == BatchStatus.failed).length;
    final processed = _items
        .where((i) => i.status != BatchStatus.queued && i.status != BatchStatus.scanning)
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
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
              Text(
                _processing ? 'PROCESSING…' : 'BATCH RESULTS',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '$processed / $total',
                style: const TextStyle(
                  color: AppTheme.secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : processed / total,
              minHeight: 6,
              backgroundColor: AppTheme.darkBg,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.secondary),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('$done ready', AppTheme.secondary, Icons.check_circle),
              if (review > 0) _statChip('$review to review', AppTheme.accentGold, Icons.edit_note),
              if (failed > 0) _statChip('$failed failed', AppTheme.errorRed, Icons.error_outline),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(76)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (context, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildItemTile(_items[index]),
    );
  }

  Widget _buildItemTile(BatchItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderCol),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              item.frontBytes,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                _statusLine(item),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildItemTrailing(item),
        ],
      ),
    );
  }

  Widget _statusLine(BatchItem item) {
    late final String text;
    late final Color color;
    switch (item.status) {
      case BatchStatus.queued:
        text = 'Queued';
        color = AppTheme.textSecondary;
      case BatchStatus.scanning:
        text = 'Scanning with Gemini…';
        color = AppTheme.secondary;
      case BatchStatus.rendering:
        text = 'Generating card…';
        color = AppTheme.secondary;
      case BatchStatus.needsReview:
        text = item.error != null ? 'Needs review · scan issue' : 'Needs review · missing fields';
        color = AppTheme.accentGold;
      case BatchStatus.done:
        text = item.info.idNumber.isNotEmpty ? 'Ready · ID ${item.info.idNumber}' : 'Ready';
        color = AppTheme.secondary;
      case BatchStatus.failed:
        text = 'Failed to render';
        color = AppTheme.errorRed;
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11),
    );
  }

  Widget _buildItemTrailing(BatchItem item) {
    switch (item.status) {
      case BatchStatus.scanning:
      case BatchStatus.rendering:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondary),
        );
      case BatchStatus.needsReview:
        return TextButton(
          onPressed: _processing ? null : () => _reviewItem(item),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accentGold,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero,
            backgroundColor: AppTheme.accentGold.withAlpha(25),
          ),
          child: const Text('Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        );
      case BatchStatus.done:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.secondary, size: 18),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _processing ? null : () => _showItemDownloadSheet(item),
              icon: const Icon(Icons.download_for_offline, color: AppTheme.secondary),
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              tooltip: 'Download this NID',
            ),
          ],
        );
      case BatchStatus.failed:
        return TextButton(
          onPressed: _processing ? null : () => _retrySingle(item),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.errorRed,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero,
          ),
          child: const Text('Retry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        );
      case BatchStatus.queued:
        return const Icon(Icons.schedule, color: AppTheme.textSecondary, size: 18);
    }
  }

  Future<void> _retrySingle(BatchItem item) async {
    setState(() => _processing = true);
    await _processOne(item);
    if (mounted) setState(() => _processing = false);
    await _autoDownloadIfReady();
  }

  Widget _buildActionBar() {
    final readyCount =
        _items.where((i) => i.status == BatchStatus.done).length;
    final failedCount =
        _items.where((i) => i.status == BatchStatus.failed).length;

    if (_processing) {
      return OutlinedButton.icon(
        onPressed: _cancelled ? null : _cancel,
        icon: const Icon(Icons.stop_circle, size: 18),
        label: Text(_cancelled ? 'Finishing current…' : 'Cancel'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.errorRed,
          side: const BorderSide(color: AppTheme.errorRed),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: readyCount > 0 ? AppTheme.primaryGradient : null,
            color: readyCount > 0 ? null : AppTheme.surfaceBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ElevatedButton.icon(
            onPressed: readyCount > 0 ? () => _downloadZip() : null,
            icon: const Icon(Icons.download, size: 18),
            label: Text('DOWNLOAD ZIP ($readyCount CARD${readyCount == 1 ? '' : 'S'})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (failedCount > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _retryFailed,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('Retry $failedCount failed'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.secondary,
              side: const BorderSide(color: AppTheme.secondary),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact editor shown for a single low-confidence item. Returns the corrected
/// [CardInfo] on save, or null if dismissed.
class _ReviewDialog extends StatefulWidget {
  final BatchItem item;
  const _ReviewDialog({required this.item});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late CardInfo _info;

  @override
  void initState() {
    super.initState();
    _info = widget.item.info;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.borderCol),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: AppTheme.accentGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Review NID ${widget.item.index + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.item.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  widget.item.error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.errorRed, fontSize: 11),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _field('English Name', _info.englishName, (v) => _info = _info.copyWith(englishName: v)),
                    _field('Bangla Name (নাম)', _info.banglaName, (v) => _info = _info.copyWith(banglaName: v)),
                    _field('ID Number', _info.idNumber, (v) => _info = _info.copyWith(idNumber: v)),
                    _field('Date of Birth', _info.dateOfBirth, (v) => _info = _info.copyWith(dateOfBirth: v)),
                    _field('Father (পিতা)', _info.banglaFatherName, (v) => _info = _info.copyWith(banglaFatherName: v)),
                    _field('Mother (মাতা)', _info.banglaMotherName, (v) => _info = _info.copyWith(banglaMotherName: v)),
                    _field('Address (ঠিকানা)', _info.address, (v) => _info = _info.copyWith(address: v), maxLines: 2),
                    _field('Blood Group', _info.bloodGroup, (v) => _info = _info.copyWith(bloodGroup: v)),
                    _field('Issue Date', _info.issueDate, (v) => _info = _info.copyWith(issueDate: v)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: AppTheme.borderCol),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, _info),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Save & Generate'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value, ValueChanged<String> onChanged, {int maxLines = 1}) {
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
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
}

/// Empty image-slot placeholder shown when a pair has no front/back image yet.
class DottedPlaceholder extends StatelessWidget {
  final String label;
  const DottedPlaceholder({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderCol, width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_photo_alternate_outlined,
              color: AppTheme.textSecondary, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
