import 'dart:convert';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/card_info.dart';
import '../widgets/card_template_widgets.dart';

/// Builds a self-contained HTML page of the Bangladesh NID whose Bangla is REAL
/// Unicode text in the embedded **Nikosh** font (the official BD NID font). When
/// this page is printed to PDF by a browser (Chrome/Safari), the browser shapes
/// the Bengali with HarfBuzz/CoreText and embeds a font subset + ToUnicode map —
/// so the Bangla opens as EDITABLE text in Illustrator/Photoshop, like English.
///
/// The layout mirrors the on-screen card: design px [CardTemplateWidget
/// .nidCardWidth] (350) with every font size multiplied by [CardTemplateWidget
/// .fontScale] (≈1.4424), then the whole box is scaled to the true CR80 size.
class NidEditableHtml {
  static const String _green = '#1E7D32';
  static const String _red = '#D32F2F';

  static double get _cardW => CardTemplateWidget.nidCardWidth; // 350 design px
  static double get _cardH => CardTemplateWidget.nidCardHeight; // ≈220.71
  // 350 design px == 92.6mm at 96dpi; scale down to the real 85.6mm CR80 width.
  static double get _mmScale =>
      CardTemplateWidget.nidCardWidthMm / (_cardW / 96 * 25.4); // ≈0.9244

  /// Full HTML document. [front]/[back] choose which sides to include.
  static Future<String> build(
    CardInfo info, {
    bool front = true,
    bool back = true,
  }) async {
    final seal = await _assetUri('assets/images/gov_seal.png');
    final sapla = await _assetUri('assets/images/sapla_logo.png');
    final authSig = await _assetUri('assets/images/authority_signature.png');
    final nikosh = await _fontUri('assets/fonts/Nikosh.ttf');
    final avatar = _bytesUri(info.avatarBytes);
    final signature = _bytesUri(info.signatureBytes);

    final cards = <String>[];
    if (front) cards.add(_front(info, seal, sapla, avatar, signature));
    if (back) cards.add(_back(info, authSig));
    return _doc(cards, nikosh);
  }

  // --- helpers ---------------------------------------------------------------

  static Future<String> _assetUri(String path) async {
    final bytes = (await rootBundle.load(path)).buffer.asUint8List();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }

  /// The bundled Nikosh TTF as a data: URI, embedded via @font-face so the
  /// exported HTML is fully self-contained and offline (no Google Fonts).
  static Future<String> _fontUri(String path) async {
    final bytes = (await rootBundle.load(path)).buffer.asUint8List();
    return 'data:font/ttf;base64,${base64Encode(bytes)}';
  }

  static String? _bytesUri(dynamic bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    final isJpeg = bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    return 'data:${isJpeg ? 'image/jpeg' : 'image/png'};base64,${base64Encode(bytes)}';
  }

  /// Font size in px = design size × fontScale (matches the app's textScaler).
  static String _fs(double n) =>
      (n * CardTemplateWidget.fontScale).toStringAsFixed(2);

  static String _esc(String? s) => (s ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _barcodeSvg(CardInfo info) {
    final id = info.idNumber.isNotEmpty ? info.idNumber : '8279557295';
    final name =
        info.englishName.isNotEmpty ? info.englishName : 'SUBRINA TABASSUM SURAIYA';
    final dob = info.dateOfBirth.isNotEmpty ? info.dateOfBirth : '20 Dec 2006';
    // Same data + geometry as the on-screen card's PDF417.
    final data = '<pin>$id</pin><name>$name</name><DOB>$dob</DOB>';
    // Taller than the on-screen card (user asked for more barcode height here).
    return Barcode.pdf417(preferredRatio: 9)
        .toSvg(data, width: 322, height: 42, drawText: false);
  }

  // --- front -----------------------------------------------------------------

  static String _front(
    CardInfo info,
    String seal,
    String sapla,
    String? avatar,
    String? signature,
  ) {
    final photo = avatar != null
        ? '<img src="$avatar" style="width:66px;height:80px;object-fit:cover" />'
        : '<div style="width:66px;height:80px;background:#E5E7EB"></div>';

    final sign = signature != null
        ? '<img src="$signature" style="height:20px;width:60px;object-fit:contain" />'
        : '<div class="bn" style="font-size:${_fs(9)}px;font-style:italic;font-weight:bold">'
            '${_esc((info.banglaName.isNotEmpty ? info.banglaName : 'তাবাচ্ছুম').replaceAll('মো: ', '').replaceAll('মোছা: ', '').trim())}</div>';

    String row(String lbl, String val, bool lblBn, bool bn, double size,
        {bool bold = true}) {
      return '<div class="row">'
          '<span class="lbl ${lblBn ? 'bn' : 'en'}">${_esc(lbl)}</span>'
          '<span class="${bn ? 'bn' : 'en'}" style="font-size:${_fs(size)}px;'
          '${bold ? 'font-weight:800;' : ''}color:#111827">${_esc(val)}</span></div>';
    }

    return '''
  <div class="card">
    <img class="watermark" src="$sapla" />
    <div class="pad">
      <div class="header">
        <img class="seal" src="$seal" />
        <div class="head-center">
          <div class="bn" style="font-size:${_fs(12)}px;font-weight:600">গণপ্রজাতন্ত্রী বাংলাদেশ সরকার</div>
          <div class="en" style="font-size:${_fs(7)}px;font-weight:600;color:$_green">Government of the People's Republic of Bangladesh</div>
          <div class="nidline">
            <span class="en" style="font-size:${_fs(7)}px;font-weight:bold;color:$_red">National ID Card</span>
            <span class="bn" style="font-size:${_fs(8)}px;font-weight:bold;color:#1a1a1a"> / জাতীয় পরিচয় পত্র</span>
          </div>
        </div>
        <div style="width:20px"></div>
      </div>
      <div class="hr"></div>
      <div class="body">
        <div class="left">
          $photo
          <div style="height:4px"></div>
          $sign
        </div>
        <div class="right">
          ${row('নাম:', info.banglaName.isNotEmpty ? info.banglaName : 'ছাবরিনা তাবাচ্ছুম সুরাইয়া', true, true, 11)}
          ${row('Name:', info.englishName.isNotEmpty ? info.englishName : 'SUBRINA TABASSUM SURAIYA', false, false, 8.5, bold: false)}
          ${row('পিতা:', info.banglaFatherName.isNotEmpty ? info.banglaFatherName : 'মোঃ মাহবুবুর রহমান', true, true, 8.5)}
          ${row('মাতা:', info.banglaMotherName.isNotEmpty ? info.banglaMotherName : 'খাতুনে জান্নাত শাহানাজ পারভীন', true, true, 8.5)}
          <div class="row">
            <span class="en" style="font-size:${_fs(8)}px;font-weight:600">Date of Birth:&nbsp;</span>
            <span class="en" style="font-size:${_fs(8)}px;font-weight:bold;color:$_red">${_esc(info.dateOfBirth.isNotEmpty ? info.dateOfBirth : '20 Dec 2006')}</span>
          </div>
          <div class="row">
            <span class="en" style="font-size:${_fs(8)}px;font-weight:600">ID NO:&nbsp;</span>
            <span class="en" style="font-size:${_fs(9.5)}px;font-weight:bold;letter-spacing:.6px;color:$_red">${_esc(info.idNumber.isNotEmpty ? info.idNumber : '8279557295')}</span>
          </div>
        </div>
      </div>
    </div>
  </div>''';
  }

  // --- back ------------------------------------------------------------------

  static String _back(CardInfo info, String authSig) {
    return '''
  <div class="card">
    <div class="pad">
      <div class="prop bn" style="font-size:${_fs(6.5)}px;line-height:1.3">এই কার্ডটি গণপ্রজাতন্ত্রী বাংলাদেশ সরকারের সম্পত্তি। কার্ডটি ব্যবহারকারী ব্যতীত অন্য কোথাও পাওয়া গেলে নিকটস্থ পোস্ট অফিসে জমা দেবার জন্য অনুরোধ করা হলো।</div>
      <div class="hr thick"></div>
      <div class="addr">
        <span class="bn" style="font-size:${_fs(8)}px">ঠিকানা:&nbsp;</span>
        <span class="bn" style="font-size:${_fs(8)}px;line-height:1.35">${_esc(info.address.isNotEmpty ? info.address : 'বাসা/হোল্ডিং: ৪২৩, গ্রাম/রাস্তা: কীর্তিপাশা, ডাকঘর: কীর্তিপাশা - ৮৪০০, ঝালকাঠী সদর, ঝালকাঠী')}</span>
      </div>
      <div class="spacer"></div>
      <div class="bgrow">
        <span class="bn" style="font-size:${_fs(8)}px">রক্তের গ্রুপ</span><span class="en" style="font-size:${_fs(8)}px">/Blood Group:&nbsp;</span>
        <span class="en" style="font-size:${_fs(9)}px;color:$_red">${_esc(info.bloodGroup)}</span>
        <span style="width:14px"></span>
        <span class="bn" style="font-size:${_fs(8)}px">জন্মস্থান:&nbsp;${_esc(info.birthPlace.isNotEmpty ? info.birthPlace : 'ঝালকাঠী')}</span>
        <span class="flex"></span>
        <span class="bn mudron" style="font-size:${_fs(7)}px">মুদ্রণ: ০১</span>
      </div>
      <div class="hr thin"></div>
      <div class="sigrow">
        <div class="sigcol">
          <img src="$authSig" style="height:20px;width:60px;object-fit:contain" />
          <div class="bn" style="font-size:${_fs(8)}px">প্রদানকারী কর্তৃপক্ষের স্বাক্ষর</div>
        </div>
        <span class="flex"></span>
        <div class="bn" style="font-size:${_fs(8)}px">প্রদানের তারিখ: ${CardTemplateWidget.issueDateBangla()}</div>
      </div>
      <div class="barcode">${_barcodeSvg(info)}</div>
    </div>
  </div>''';
  }

  // --- document shell --------------------------------------------------------

  static String _doc(List<String> cards, String nikoshUri) {
    final pages =
        cards.map((c) => '<div class="page">$c</div>').join('\n');
    return '''<!doctype html>
<html><head><meta charset="utf-8" />
<title>NID (editable)</title>
<style>
  @font-face { font-family: 'Nikosh'; font-weight: normal;
    src: url($nikoshUri) format('truetype'); }
  @page { size: 85.6mm 53.98mm; margin: 0; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { background: #fff; }
  .en { font-family: Arial, Helvetica, sans-serif; color: #000; }
  .bn { font-family: 'Nikosh', serif; color: #000; }
  .page { width: 85.6mm; height: 53.98mm; overflow: hidden; page-break-after: always; }
  .page:last-child { page-break-after: auto; }
  .card { width: ${_cardW.toStringAsFixed(0)}px; height: ${_cardH.toStringAsFixed(2)}px;
    transform: scale(${_mmScale.toStringAsFixed(5)}); transform-origin: top left;
    position: relative; background: #fff; color: #000; }
  .watermark { position: absolute; left: 50%; top: 85px; width: 125px; height: 125px;
    object-fit: contain; opacity: .3; transform: translateX(-50%); }
  .pad { position: relative; display: flex; flex-direction: column; height: 100%; }
  .header { display: flex; align-items: center; padding: 8px 14px 2px 10px; }
  .seal { width: 35px; height: 35px; object-fit: contain; }
  .head-center { flex: 1; display: flex; flex-direction: column; align-items: center; text-align: center; margin-left: 6px; }
  .nidline { display: flex; align-items: center; }
  .hr { border-top: 1px solid #1a1a1a; margin: 3px 0; }
  .hr.thick { border-top-width: 1.2px; margin: 2px 0; }
  .hr.thin { border-top-width: 1px; margin: 3px 0; }
  .body { flex: 1; display: flex; align-items: flex-start; padding: 0 14px 10px; }
  .left { display: flex; flex-direction: column; align-items: center; }
  .right { flex: 1; margin-left: 10px; }
  .row { display: flex; align-items: baseline; padding: 1px 0; }
  .lbl { width: 42px; color: #1a1a1a; font-weight: 600; }
  .lbl.bn { font-size: ${_fs(9)}px; } .lbl.en { font-size: ${_fs(8.5)}px; }
  .prop { padding: 8px 14px; }
  .addr { display: flex; padding: 5px 14px 0; }
  .bgrow { display: flex; align-items: center; padding: 0 14px; }
  .spacer { flex: 1; }
  .flex { flex: 1; }
  .mudron { color: #fff; background: #000; padding: 0 2px; }
  .sigrow { display: flex; align-items: flex-end; padding: 2px 18px 0 14px; }
  .sigcol { display: flex; flex-direction: column; align-items: center; }
  .barcode { padding: 3px 14px 8px; }
  .barcode svg { width: 322px; height: 42px; }
</style></head>
<body>
  $pages
  <script>
    // Explicitly load the embedded Nikosh (both weights) BEFORE printing, so the
    // saved PDF embeds Nikosh instead of falling back to a system Bangla font.
    window.addEventListener('load', function () {
      var go = function () { setTimeout(function () { window.print(); }, 250); };
      if (document.fonts && document.fonts.load) {
        Promise.all([
          document.fonts.load("normal 16px Nikosh"),
          document.fonts.load("bold 16px Nikosh")
        ]).then(function () { return document.fonts.ready; }).then(go, go);
      } else { setTimeout(go, 700); }
    });
  </script>
</body></html>''';
  }
}
