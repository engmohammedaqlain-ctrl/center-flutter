import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';

/// أساس الطباعة و PDF — المقابل لـ `window.print()` وأزرار «تنزيل PDF»
/// في ReceiptModal و ClassPrintRoster و SchedulePDFModal و Reports.
///
/// الخط عربي محمَّل من Google Fonts عبر حزمة printing، وإلا خرجت المستندات
/// بمربعات فارغة بدل النص.
class PdfKit {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) return;
    try {
      _regular = await PdfGoogleFonts.iBMPlexSansArabicRegular();
      _bold = await PdfGoogleFonts.iBMPlexSansArabicBold();
    } catch (_) {
      // بلا اتصال: خط النظام الافتراضي أفضل من الفشل
      _regular = pw.Font.helvetica();
      _bold = pw.Font.helveticaBold();
    }
  }

  static Future<pw.ThemeData> theme() async {
    await _ensureFonts();
    return pw.ThemeData.withFont(base: _regular!, bold: _bold!);
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
  }) async {
    final doc = pw.Document(theme: await theme());
    final logo = _decodeLogo(logoBase64);

    doc.addPage(
      pw.MultiPage(
        pageFormat: landscape ? format.landscape : format,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        header: (ctx) => _header(title, institutionName, subtitle, logo),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: body,
      ),
    );
    return doc.save();
  }

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

  /// جدول بسيط بحدود — الشكل المستعمل في كل الكشوف المطبوعة.
  static pw.Widget table({
    required List<String> headers,
    required List<List<String>> rows,
    List<int>? flex,
  }) {
    pw.Widget cell(String text, {bool head = false, PdfColor? bg}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: pw.BoxDecoration(
            color: bg ?? (head ? PdfColors.grey200 : null),
            border: const pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            ),
          ),
          child: pw.Text(
            text,
            style: pw.TextStyle(fontSize: head ? 9 : 8.5, fontWeight: head ? pw.FontWeight.bold : null),
          ),
        );

    final widths = <int, pw.TableColumnWidth>{};
    if (flex != null) {
      for (var i = 0; i < flex.length; i++) {
        widths[i] = pw.FlexColumnWidth(flex[i].toDouble());
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: widths.isEmpty ? null : widths,
      children: [
        pw.TableRow(children: headers.map((h) => cell(h, head: true)).toList()),
        for (final r in rows) pw.TableRow(children: r.map((c) => cell(c)).toList()),
      ],
    );
  }

  /// اسم الملف الناتج بلا فراغات — هو ما يظهر للمستخدم عند الحفظ أو المشاركة.
  /// مطابق لما تكتبه النسخة المكتبية في `document.title` قبل الطباعة، فيخرج
  /// «كشف_طلاب_شعبة_(1)» بدل اسم عام لا يدلّ على شيء.
  static String fileName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), '_');

  /// فتح معاينة الطباعة / المشاركة على الجهاز.
  static Future<void> preview(Uint8List bytes, String name) {
    return Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }

  /// حفظ أو مشاركة الملف مباشرةً.
  static Future<void> share(Uint8List bytes, String fileName) {
    return Printing.sharePdf(bytes: bytes, filename: fileName);
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

/// تحويل المبلغ إلى كلمات عربية — «وقدره كتابةً» في سند القبض.
String amountInArabicWords(num value) {
  final whole = value.abs().floor();
  final fraction = ((value.abs() - whole) * 100).round();
  final words = _numberToArabic(whole);
  if (fraction == 0) return '$words شيكل فقط لا غير';
  return '$words شيكل و${_numberToArabic(fraction)} أغورة فقط لا غير';
}

const _ones = [
  '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة',
  'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر',
  'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = ['', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة'];

String _numberToArabic(int n) {
  if (n == 0) return 'صفر';
  if (n < 0) return 'سالب ${_numberToArabic(-n)}';

  final parts = <String>[];

  void chunk(int value, String singular, String dual, String plural) {
    if (value == 0) return;
    if (value == 1) {
      parts.add(singular);
    } else if (value == 2) {
      parts.add(dual);
    } else if (value <= 10) {
      parts.add('${_below100(value)} $plural');
    } else {
      parts.add('${_below1000(value)} $singular');
    }
  }

  final millions = n ~/ 1000000;
  final thousands = (n % 1000000) ~/ 1000;
  final rest = n % 1000;

  chunk(millions, 'مليون', 'مليونان', 'ملايين');
  chunk(thousands, 'ألف', 'ألفان', 'آلاف');
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
