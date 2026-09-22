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

  static Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) return;
    try {
      final regularData = await rootBundle.load('assets/fonts/ThmanyahSans-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/ThmanyahSans-Bold.ttf');
      _regular = pw.Font.ttf(regularData);
      _bold = pw.Font.ttf(boldData);
    } catch (_) {
      // بلا أصول: خط النظام أفضل من الفشل
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

  /// جدول بسيط بحدود — الشكل المستعمل في كل الكشوف المطبوعة.
  ///
  /// [ltrColumns]: فهارس أعمدة تُعرض LTR (هواتف، هوية، أرقام).
  static pw.Widget table({
    required List<String> headers,
    required List<List<String>> rows,
    List<int>? flex,
    Set<int>? ltrColumns,
  }) {
    pw.Widget cell(String text, {bool head = false, PdfColor? bg, bool forceLtr = false}) {
      final style = pw.TextStyle(fontSize: head ? 9 : 8.5, fontWeight: head ? pw.FontWeight.bold : null);
      final child = forceLtr ? ltr(text, style: style) : pw.Text(text, style: style);
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: pw.BoxDecoration(
          color: bg ?? (head ? PdfColors.grey200 : null),
          border: const pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: child,
      );
    }

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
        pw.TableRow(
          children: [
            for (var i = 0; i < headers.length; i++)
              cell(headers[i], head: true, forceLtr: ltrColumns?.contains(i) ?? false),
          ],
        ),
        for (final r in rows)
          pw.TableRow(
            children: [
              for (var i = 0; i < r.length; i++)
                cell(r[i], forceLtr: ltrColumns?.contains(i) ?? false),
            ],
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
