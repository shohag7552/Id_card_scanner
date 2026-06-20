import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/card_info.dart';
import '../widgets/card_template_widgets.dart' show CardTemplateWidget;

/// Builds a *native* (selectable / editable) PDF of a Bangladesh NID — front and
/// back on a SINGLE page — instead of rasterising the whole card to one image.
///
/// Hybrid strategy (see chat): English text, numbers, the photo/signatures and
/// the PDF417 barcode are placed as real PDF objects (selectable + editable).
/// Bangla lines are rendered to crisp images via Flutter (which shapes Nikosh
/// correctly) because the `pdf` package can't shape Bengali conjuncts/vowels —
/// so the Bangla *looks* right even though those specific lines aren't text.
class NidPdfBuilder {
  /// Builds the PDF. [front]/[back] choose which sides to include (both → one
  /// page with the front above the back).
  static Future<Uint8List> build(
    CardInfo info, {
    bool front = true,
    bool back = true,
  }) async {
    final seal = pw.MemoryImage(await _asset('assets/images/gov_seal.png'));
    final sapla = pw.MemoryImage(await _asset('assets/images/sapla_logo.png'));

    final cards = <pw.Widget>[];
    if (front) cards.add(_physical(await _front(info, seal, sapla)));
    if (back) cards.add(_physical(await _back(info, sapla)));

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) pw.SizedBox(height: 22),
                cards[i],
              ],
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> _asset(String path) async =>
      (await rootBundle.load(path)).buffer.asUint8List();

  /// Scales a design-sized card (logical units, CR80 aspect) to the EXACT
  /// physical CR80 size in PDF points (85.60 × 53.98 mm). Aspect ratios match,
  /// so this is a uniform scale — vector text/barcode and the high-DPI Bangla
  /// images stay crisp, and a printed card measures true-to-size.
  static pw.Widget _physical(pw.Widget designCard) {
    return pw.SizedBox(
      width: CardTemplateWidget.nidCardWidthMm * PdfPageFormat.mm,
      height: CardTemplateWidget.nidCardHeightMm * PdfPageFormat.mm,
      child: pw.FittedBox(fit: pw.BoxFit.fill, child: designCard),
    );
  }

  // Helvetica is the PDF standard sans (Arial-like) — selectable, no embedding.
  static final pw.Font _en = pw.Font.helvetica();
  static final pw.Font _enBold = pw.Font.helveticaBold();

  static pw.TextStyle _enStyle(double size, {PdfColor? color, bool bold = false}) =>
      pw.TextStyle(
        font: bold ? _enBold : _en,
        // Scaled so the FittedBox down-scale lands on the standard point size.
        fontSize: size * CardTemplateWidget.fontScale,
        color: color ?? PdfColors.black,
      );

  // ---- Bangla text → image (Nikosh shaped by Flutter) ----------------------

  /// Rendered Bangla text: PNG [bytes] plus the logical [w]×[h] to place it at.
  static Future<_BnImg> _bn(
    String text, {
    required double fontSize,
    ui.FontWeight weight = ui.FontWeight.normal,
    int color = 0xFF000000,
    int? bgColor,
    bool italic = false,
    double maxWidth = 1000,
    double pixelRatio = 4.0,
  }) async {
    // Match _enStyle: render at the scaled size so the card's FittedBox brings
    // it back to the standard point size, identical to the on-screen preview.
    fontSize = fontSize * CardTemplateWidget.fontScale;
    final style = ui.TextStyle(
      color: ui.Color(color),
      fontSize: fontSize,
      fontWeight: weight,
      fontStyle: italic ? ui.FontStyle.italic : ui.FontStyle.normal,
      fontFamily: 'Nikosh',
      fontFamilyFallback: const ['Arial'],
    );
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: 'Nikosh',
      fontSize: fontSize,
    ))
      ..pushStyle(style)
      ..addText(text);
    final para = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));

    final lineW = para.longestLine > 0 ? para.longestLine : para.maxIntrinsicWidth;
    final w = lineW.ceilToDouble().clamp(1.0, maxWidth);
    final h = para.height;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);
    if (bgColor != null) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..color = ui.Color(bgColor),
      );
    }
    canvas.drawParagraph(para, ui.Offset.zero);
    final img = await recorder
        .endRecording()
        .toImage((w * pixelRatio).ceil(), (h * pixelRatio).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return _BnImg(data!.buffer.asUint8List(), w, h);
  }

  static pw.Widget _bnImage(_BnImg b) =>
      pw.Image(pw.MemoryImage(b.bytes), width: b.w, height: b.h);

  /// One detail row: a fixed-width [label] column then the [value], left-aligned
  /// — mirrors the on-screen `_buildNidRow` so all values line up like the real
  /// NID instead of each label+value being its own free-floating block.
  static pw.Widget _row(pw.Widget label, pw.Widget value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 42, child: label),
          pw.Expanded(
            child: pw.Align(alignment: pw.Alignment.centerLeft, child: value),
          ),
        ],
      ),
    );
  }

  // ---- Front ----------------------------------------------------------------

  static Future<pw.Widget> _front(
    CardInfo info,
    pw.MemoryImage seal,
    pw.MemoryImage sapla,
  ) async {
    final green = PdfColor.fromInt(0xFF1E7D32);
    final red = PdfColor.fromInt(0xFFD32F2F);
    final border = PdfColor.fromInt(0xFF9AA4B2);

    final nameVal = info.banglaName.isNotEmpty
        ? info.banglaName
        : 'ছাবরিনা তাবাচ্ছুম সুরাইয়া';
    final fatherVal = info.banglaFatherName.isNotEmpty
        ? info.banglaFatherName
        : 'মোঃ মাহবুবুর রহমান';
    final motherVal = info.banglaMotherName.isNotEmpty
        ? info.banglaMotherName
        : 'খাতুনে জান্নাত শাহানাজ পারভীন';

    final hdr = await _bn('গণপ্রজাতন্ত্রী বাংলাদেশ সরকার',
        fontSize: 12, weight: ui.FontWeight.w500, color: 0xFF000000);
    final natId = await _bn(' / জাতীয় পরিচয় পত্র',
        fontSize: 8, weight: ui.FontWeight.w500);
    // Labels and values rendered SEPARATELY so the values line up in a column,
    // exactly like the on-screen card (the combined image broke the alignment).
    final lblName = await _bn('নাম:', fontSize: 11.0, weight: ui.FontWeight.w500);
    final lblFather = await _bn('পিতা:', fontSize: 9, weight: ui.FontWeight.w500);
    final lblMother = await _bn('মাতা:', fontSize: 9, weight: ui.FontWeight.w500);
    final valName = await _bn(nameVal,
        fontSize: 11.0, weight: ui.FontWeight.w600, color: 0xFF111827, maxWidth: 200);
    final valFather = await _bn(fatherVal,
        fontSize: 10, weight: ui.FontWeight.w500, color: 0xFF111827, maxWidth: 200);
    final valMother = await _bn(motherVal,
        fontSize: 10, weight: ui.FontWeight.w500, color: 0xFF111827, maxWidth: 200);

    // Photo
    final av = info.avatarBytes;
    final pw.Widget photo = pw.Container(
      width: 66,
      height: 80,
      color: PdfColor.fromInt(0xFFE5E7EB),
      child: av != null
          ? pw.Image(pw.MemoryImage(av), fit: pw.BoxFit.cover)
          : null,
    );

    // Holder signature
    pw.Widget sig;
    final sigBytes = info.signatureBytes;
    if (sigBytes != null) {
      sig = pw.Image(pw.MemoryImage(sigBytes),
          width: 60, height: 20, fit: pw.BoxFit.contain);
    } else {
      final sn = await _bn(
        nameVal.replaceAll('মো: ', '').replaceAll('মোছা: ', '').trim(),
        fontSize: 9,
        weight: ui.FontWeight.bold,
        italic: true,
        maxWidth: 66,
      );
      sig = _bnImage(sn);
    }

    final content = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(10, 8, 14, 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(seal, width: 35, height: 35),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    _bnImage(hdr),
                    pw.SizedBox(height: 1),
                    pw.Text("Government of the People's Republic of Bangladesh",
                        style: _enStyle(7, color: green, bold: false)),
                    pw.SizedBox(height: 1),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('National ID Card',
                            style: _enStyle(7, color: red, bold: false)),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: _bnImage(natId),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
            ],
          ),
        ),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 4),
        // Body
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(children: [photo, pw.SizedBox(height: 4), sig]),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _row(_bnImage(lblName), _bnImage(valName)),
                      pw.SizedBox(height: 3),
                      _row(
                        pw.Text('Name:', style: _enStyle(8.5)),
                        pw.Text(
                          info.englishName.isNotEmpty
                              ? info.englishName
                              : 'SUBRINA TABASSUM SURAIYA',
                          style: _enStyle(8.5, bold: false),
                        ),
                      ),
                      pw.SizedBox(height: 4.5),
                      _row(_bnImage(lblFather), _bnImage(valFather)),
                      pw.SizedBox(height: 2),
                      _row(_bnImage(lblMother), _bnImage(valMother)),
                      pw.SizedBox(height: 2),
                      pw.Row(children: [
                        pw.Text('Date of Birth: ', style: _enStyle(8)),
                        pw.Text(
                          info.dateOfBirth.isNotEmpty
                              ? info.dateOfBirth
                              : '20 Dec 2006',
                          style: _enStyle(8, color: red, bold: true),
                        ),
                      ]),
                      pw.SizedBox(height: 5),
                      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                        pw.Text('ID NO: ', style: _enStyle(8)),
                        pw.Text(
                          info.idNumber.isNotEmpty ? info.idNumber : '8279557295',
                          style: _enStyle(9, color: red, bold: true),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return _cardFrame(
      border: border,
      child: pw.Stack(
        fit: pw.StackFit.expand,
        children: [
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 50),
                child: pw.Opacity(
                  opacity: 0.3,
                  child: pw.Image(sapla, width: 125, height: 125),
                ),
              ),
            ),
          ),
          pw.Positioned.fill(child: content),
        ],
      ),
    );
  }

  // ---- Back -----------------------------------------------------------------

  static Future<pw.Widget> _back(CardInfo info, pw.MemoryImage sapla) async {
    final red = PdfColor.fromInt(0xFFD32F2F);
    final border = PdfColor.fromInt(0xFF9AA4B2);

    final addrVal = info.address.isNotEmpty
        ? info.address
        : 'বাসা/হোল্ডিং: ৪২৩, গ্রাম/রাস্তা: কীর্তিপাশা, ডাকঘর: কীর্তিপাশা - ৮৪০০, ঝালকাঠী সদর, ঝালকাঠী';
    final birthVal = info.birthPlace.isNotEmpty ? info.birthPlace : 'ঝালকাঠী';
    final issueVal = info.issueDate.isNotEmpty ? info.issueDate : '০৮/০৬/২০২৬';

    final prop = await _bn(
      'এই কার্ডটি গণপ্রজাতন্ত্রী বাংলাদেশ সরকারের সম্পত্তি। কার্ডটি ব্যবহারকারী ব্যতীত অন্য কোথাও পাওয়া গেলে নিকটস্থ পোস্ট অফিসে জমা দেবার জন্য অনুরোধ করা হলো।',
      fontSize: 7.0,
      weight: ui.FontWeight.bold,
      maxWidth: 322,
    );
    final addr = await _bn('ঠিকানা: $addrVal',
        fontSize: 7.5, weight: ui.FontWeight.bold, maxWidth: 322);
    final bloodBn = await _bn('রক্তের গ্রুপ', fontSize: 8, weight: ui.FontWeight.bold);
    final birth = await _bn('জন্মস্থান: $birthVal',
        fontSize: 8, weight: ui.FontWeight.bold, maxWidth: 130);
    final mudron = await _bn('মুদ্রণ: ০১',
        fontSize: 7.5, weight: ui.FontWeight.bold, color: 0xFFFFFFFF, bgColor: 0xFF000000);
    final sigCap = await _bn('প্রদানকারী কর্তৃপক্ষের স্বাক্ষর',
        fontSize: 8, weight: ui.FontWeight.bold);
    final issue = await _bn('প্রদানের তারিখ: $issueVal',
        fontSize: 8, weight: ui.FontWeight.bold, maxWidth: 160);

    final asb = info.authoritySignatureBytes;
    final pw.Widget authSig = asb != null
        ? pw.Image(pw.MemoryImage(asb), width: 60, height: 20, fit: pw.BoxFit.contain)
        : pw.SizedBox(width: 60, height: 20);

    final barcodeData =
        '<pin>${info.idNumber.isNotEmpty ? info.idNumber : '8279557295'}</pin>'
        '<name>${info.englishName.isNotEmpty ? info.englishName : 'SUBRINA TABASSUM SURAIYA'}</name>'
        '<DOB>${info.dateOfBirth.isNotEmpty ? info.dateOfBirth : '20 Dec 2006'}</DOB>';

    final content = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 2),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: _bnImage(prop),
        ),
        pw.Container(height: 1.2, color: PdfColors.black),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: pw.Align(alignment: pw.Alignment.topLeft, child: _bnImage(addr)),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              _bnImage(bloodBn),
              pw.Text('/Blood Group: ', style: _enStyle(8, bold: true)),
              pw.Text(info.bloodGroup.isNotEmpty ? info.bloodGroup : 'O+',
                  style: _enStyle(9, color: red, bold: true)),
              pw.SizedBox(width: 16),
              _bnImage(birth),
              pw.Spacer(),
              _bnImage(mudron),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 2),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(14, 0, 18, 0),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(children: [authSig, _bnImage(sigCap)]),
              pw.Spacer(),
              _bnImage(issue),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: pw.BarcodeWidget(
            // ~322×30 ≈ 10.7:1; build wide so it fills (see card widget note).
            barcode: pw.Barcode.pdf417(preferredRatio: 12),
            data: barcodeData,
            drawText: false,
            color: PdfColors.black,
            width: 322,
            height: 30,
          ),
        ),
      ],
    );

    return _cardFrame(border: border, child: content);
  }

  static pw.Widget _cardFrame({required PdfColor border, required pw.Widget child}) {
    return pw.Container(
      // Same size as the on-screen preview so the PDF matches exactly.
      width: CardTemplateWidget.nidCardWidth,
      height: CardTemplateWidget.nidCardHeight,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: border, width: 1),
      ),
      child: child,
    );
  }
}

class _BnImg {
  final Uint8List bytes;
  final double w;
  final double h;
  _BnImg(this.bytes, this.w, this.h);
}
