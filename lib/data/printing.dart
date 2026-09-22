import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';

/// أساس الطباعة و PDF — المقابل لـ `window.print()` وأزرار «تنزيل PDF»
/// في ReceiptModal و ClassPrintRoster و SchedulePDFModal و Reports.
///
/// الخط عربي من أصول Thmanyah المضمّنة (مطابق للويب)، بلا اعتماد على الشبكة.
class PdfKit {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.Font? _latin;
  static pw.Font? _latinBold;
  static pw.Font? _symbols;

  /// خطوط المستندات: Noto Naskh Arabic (تقارير واضحة) + لاتيني للترقيم.
  ///
  /// خط الواجهة (Thmanyah) وNoto Sans Arabic يظهران مقطّعين في بعض العارضات؛
  /// Naskh أوضح للتقارير المطبوعة.
  static const _pdfRegular = 'assets/fonts/pdf/NotoNaskhArabic-Regular.ttf';
  static const _pdfBold = 'assets/fonts/pdf/NotoNaskhArabic-Bold.ttf';
  static const _pdfLatin = 'assets/fonts/pdf/NotoSans-Regular.ttf';
  static const _pdfLatinBold = 'assets/fonts/pdf/NotoSans-Bold.ttf';
  static const _pdfSymbols = 'assets/fonts/pdf/NotoSansSymbols2-Regular.ttf';

  static Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) return;
    try {
      final regularData = await rootBundle.load(_pdfRegular);
      final boldData = await rootBundle.load(_pdfBold);
      _regular = pw.Font.ttf(regularData);
      _bold = pw.Font.ttf(boldData);
      try {
        _latin = pw.Font.ttf(await rootBundle.load(_pdfLatin));
        _latinBold = pw.Font.ttf(await rootBundle.load(_pdfLatinBold));
        _symbols = pw.Font.ttf(await rootBundle.load(_pdfSymbols));
      } catch (_) {
        _latin = null;
        _latinBold = null;
        _symbols = null;
      }
    } catch (_) {
      // بلا أصول: خط النظام أفضل من الفشل — لكنه لا يطبع العربية
      _regular = pw.Font.helvetica();
      _bold = pw.Font.helveticaBold();
    }
  }

  static Future<pw.ThemeData> theme() async {
    await _ensureFonts();
    final fallback = <pw.Font>[
      if (_latin != null) _latin!,
      if (_latinBold != null) _latinBold!,
      if (_symbols != null) _symbols!,
    ];
    return pw.ThemeData.withFont(
      base: _regular!,
      bold: _bold!,
      fontFallback: fallback.isEmpty ? null : fallback,
    );
  }

  /// مستند عربي جاهز بترويسة المنشأة.
  static Future<Uint8List> build({
    required String title,
    required String institutionName,
    String? logoBase64,
    String? subtitle,
    required List<pw.Widget> Function(pw.Context) body,
    PdfPageFormat format = PdfPageFormat.a4,
    bool landscape = false,
    pw.Widget Function(pw.Context)? header,
    List<pw.Widget>? endMatter,
    pw.EdgeInsets margin = const pw.EdgeInsets.fromLTRB(16, 12, 16, 10),
  }) async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final doc = pw.Document(theme: await theme());
    final logo = _decodeLogo(logoBase64);

    doc.addPage(
      pw.MultiPage(
        pageFormat: landscape ? format.landscape : format,
        margin: margin,
        textDirection: pw.TextDirection.rtl,
        header: header ?? (ctx) => _header(title, institutionName, subtitle, logo),
        build: (ctx) => [
          ...body(ctx),
          if (endMatter != null) ...endMatter,
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    return doc.save();
  }

  static Future<Uint8List?> buildSafe({
    required String title,
    required String institutionName,
    String? logoBase64,
    String? subtitle,
    required List<pw.Widget> Function(pw.Context) body,
    PdfPageFormat format = PdfPageFormat.a4,
    bool landscape = false,
    pw.Widget Function(pw.Context)? header,
    List<pw.Widget>? endMatter,
    pw.EdgeInsets margin = const pw.EdgeInsets.fromLTRB(16, 12, 16, 10),
  }) async {
    try {
      return await build(
        title: title,
        institutionName: institutionName,
        logoBase64: logoBase64,
        subtitle: subtitle,
        body: body,
        format: format,
        landscape: landscape,
        header: header,
        endMatter: endMatter,
        margin: margin,
      );
    } catch (_) {
      return null;
    }
  }

  /// صورة من `data:` للطباعة — الشعار والختم كلاهما يمرّ بها.
  static pw.MemoryImage? decodeImage(String? base64Src) => _decodeLogo(base64Src);

  static pw.MemoryImage? _decodeLogo(String? base64Src) {
    if (base64Src == null || base64Src.isEmpty) return null;
    try {
      final comma = base64Src.indexOf(',');
      final raw = comma >= 0 ? base64Src.substring(comma + 1) : base64Src;
      return pw.MemoryImage(base64Decode(raw));
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _header(String title, String institution, String? subtitle, pw.MemoryImage? logo) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.SizedBox(width: 42, height: 42, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(institution, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(title, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                if (subtitle != null && subtitle.isNotEmpty)
                  pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                // العام الدراسي يتبع التاريخ، فلا يُكتب عاماً ثابتاً يُقادم
                pw.Text(
                  'العام الدراسي ${academicYear()}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          pw.Text(
            _todayLabel(),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static String _todayLabel() {
    final n = DateTime.now();
    return '${n.day}/${n.month}/${n.year}';
  }

  /// جدول بحدود ورأس يتكرر — أعمدة يمين→يسار كالتقارير المعتمدة.
  ///
  /// [headers]: `String` أو `pw.Widget`.
  /// [ltrColumns]: فهارس أعمدة بيانات رقمية فقط (لا تُطبَّق على رؤوس عربية).
  /// [accentColumns]: أعمدة بيانات بلون برتقالي (كلمات مرور).
  static pw.Widget table({
    required List<dynamic> headers,
    required List<List<String>> rows,
    List<int>? flex,
    Set<int>? ltrColumns,
    Set<int>? accentColumns,
    PdfColor headerBg = const PdfColor.fromInt(0xFFE8EEF2),
    PdfColor accent = const PdfColor.fromInt(0xFFD97706),
  }) {
    final n = headers.length;
    final visualHeaders = headers.reversed.toList();
    final visualRows = [for (final r in rows) r.reversed.toList()];
    final visualFlex = flex?.reversed.toList();
    int rtlIx(int i) => n - 1 - i;
    final visualLtr = {for (final i in (ltrColumns ?? const <int>{})) rtlIx(i)};
    final visualAccent = {for (final i in (accentColumns ?? const <int>{})) rtlIx(i)};

    final widths = <int, pw.TableColumnWidth>{};
    if (visualFlex != null) {
      for (var i = 0; i < visualFlex.length; i++) {
        widths[i] = pw.FlexColumnWidth(visualFlex[i].toDouble());
      }
    }

    pw.Widget cell(dynamic content, {required int col, bool head = false}) {
      final forceLtr = !head && visualLtr.contains(col);
      final isAccent = !head && visualAccent.contains(col);
      final style = pw.TextStyle(
        fontSize: head ? 8.5 : 9,
        fontWeight: head || isAccent ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: isAccent ? accent : PdfColors.black,
      );
      final pw.Widget child;
      if (content is pw.Widget) {
        child = content;
      } else {
        final text = '${content ?? ' '}';
        child = pw.Directionality(
          textDirection: forceLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
          child: pw.Text(text.isEmpty ? ' ' : text, style: style, textAlign: pw.TextAlign.center),
        );
      }
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: head ? 4 : 3.5),
        child: child,
      );
    }

    return pw.Table(
      tableWidth: pw.TableWidth.max,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.45),
      columnWidths: widths.isEmpty ? null : widths,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            for (var c = 0; c < visualHeaders.length; c++)
              cell(visualHeaders[c], col: c, head: true),
          ],
        ),
        for (final r in visualRows)
          pw.TableRow(
            children: [
              for (var c = 0; c < r.length; c++) cell(r[c], col: c),
            ],
          ),
      ],
    );
  }

  /// ترويسة وثيقة: يمين منشأة · وسط عنوان · يسار تاريخ.
  static pw.Widget docHeader({
    required String institution,
    required String title,
    required String academicYearLabel,
    required String dateLabel,
    pw.MemoryImage? logo,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 1.6, color: PdfColors.black)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null) ...[
                  pw.SizedBox(width: 36, height: 36, child: pw.Image(logo)),
                  pw.SizedBox(height: 4),
                ],
                pw.Text(institution, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('العام الدراسي: $academicYearLabel', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          ),
          pw.Expanded(
            child: pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700), textAlign: pw.TextAlign.end),
          ),
        ],
      ),
    );
  }

  static pw.Widget metaRow(List<String> parts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final p in parts)
            pw.Text(p, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
        ],
      ),
    );
  }

  static pw.Widget signatureRow(List<String> labels) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final label in labels)
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    width: 140,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: PdfColors.black, style: pw.BorderStyle.dotted)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// رأس عمود تقييم: اسم + الدرجة القصوى.
  static pw.Widget gradeEvalHeader({required String title, required String outOf}) {
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center, maxLines: 2),
        pw.SizedBox(height: 2),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFE2E8F0),
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Text(outOf, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800), textAlign: pw.TextAlign.center),
        ),
      ],
    );
  }

  /// اسم الملف الناتج بلا فراغات، وبلاحقة `.pdf`.
  static String fileName(String raw) {
    final base = raw.trim().replaceAll(RegExp(r'\s+'), '_');
    if (base.toLowerCase().endsWith('.pdf')) return base;
    return '$base.pdf';
  }

  /// حفظ الكشف/السند: حوار اختيار مكان إن أمكن، وإلا ورقة مشاركة النظام.
  static Future<void> preview(Uint8List bytes, String name) => saveOrShare(bytes, name);

  /// حفظ أو مشاركة الملف مباشرةً.
  static Future<void> share(Uint8List bytes, String name) => saveOrShare(bytes, name);

  /// يختار المستخدم مكان الحفظ (سطح المكتب / SAF)، أو يشارك عبر النظام على الجوال.
  static Future<void> saveOrShare(
    Uint8List bytes,
    String name, {
    String mimeType = 'application/pdf',
  }) async {
    final file = fileName(name);

    // سطح المكتب وويب سطح المكتب: حوار «حفظ باسم»
    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!mobile) {
      try {
        final location = await getSaveLocation(
          suggestedName: file,
          acceptedTypeGroups: [
            XTypeGroup(
              label: mimeType.contains('pdf') ? 'PDF' : 'ملف',
              extensions: [file.contains('.') ? file.split('.').last : 'pdf'],
            ),
          ],
        );
        if (location != null) {
          await XFile.fromData(bytes, mimeType: mimeType, name: file).saveTo(location.path);
          return;
        }
      } catch (_) {
        // نكمل بالمشاركة / الطباعة
      }
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: file);
      return;
    }

    // الجوال: ورقة مشاركة النظام = اختيار الملفات / Drive / واتساب…
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}$file';
      await File(path).writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: mimeType, name: file)],
          subject: file,
        ),
      );
      return;
    } catch (_) {
      // احتياط: واجهة printing القديمة
      await Printing.sharePdf(bytes: bytes, filename: file);
    }
  }

  /// تُستخدم عند الحاجة لتحميل صورة من الأصول.
  static Future<Uint8List?> asset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}

/// يلف نصاً LTR داخل مستند RTL — للهواتف وأرقام الهوية وأرقام السندات.
pw.Widget ltr(String text, {pw.TextStyle? style}) => pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Text(text, style: style ?? const pw.TextStyle(fontSize: 8.5)),
    );

/// تحويل المبلغ إلى كلمات عربية — مطابق لـ `tafqeet` في ReceiptModal (بلا أغورات).
String amountInArabicWords(num value) {
  final whole = value.abs().floor();
  if (whole == 0) return 'صفر شيكل';
  final words = _numberToArabic(whole);
  return 'فقط $words شيكلاً لا غير';
}

const _ones = [
  '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة',
  'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر',
  'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = [
  '',
  'مائة',
  'مئتان',
  'ثلاثمائة',
  'أربعمائة',
  'خمسمائة',
  'ستمائة',
  'سبعمائة',
  'ثمانمائة',
  'تسعمائة',
];

String _numberToArabic(int n) {
  if (n == 0) return 'صفر';
  if (n < 0) return 'سالب ${_numberToArabic(-n)}';

  final parts = <String>[];

  void chunk(int value, String singular, String dual, String plural, {String accusative = ''}) {
    if (value == 0) return;
    if (value == 1) {
      parts.add(singular);
    } else if (value == 2) {
      parts.add(dual);
    } else if (value <= 10) {
      parts.add('${_below100(value)} $plural');
    } else {
      parts.add('${_below1000(value)} ${accusative.isEmpty ? singular : accusative}');
    }
  }

  final millions = n ~/ 1000000;
  final thousands = (n % 1000000) ~/ 1000;
  final rest = n % 1000;

  chunk(millions, 'مليون', 'مليونان', 'ملايين');
  chunk(thousands, 'ألف', 'ألفان', 'آلاف', accusative: 'ألفاً');
  if (rest > 0) parts.add(_below1000(rest));

  return parts.join(' و');
}

String _below100(int n) {
  if (n < 20) return _ones[n];
  final t = n ~/ 10;
  final o = n % 10;
  if (o == 0) return _tens[t];
  return '${_ones[o]} و${_tens[t]}';
}

String _below1000(int n) {
  if (n < 100) return _below100(n);
  final h = n ~/ 100;
  final rest = n % 100;
  if (rest == 0) return _hundreds[h];
  return '${_hundreds[h]} و${_below100(rest)}';
}
