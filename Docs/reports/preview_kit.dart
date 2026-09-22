/// أساس مشترك لكشوفات المعاينة — مطابق تقريبًا لما سيُنقل إلى `lib/data/printing.dart`.
///
/// قواعد الويب المهمة:
/// - رأس الجدول يتكرر مع كل صفحة جديدة
/// - هوامش ثابتة
/// - ترويسة الوثيقة في أعلى كل صفحة
/// - الأعمدة من اليمين لليسار (عربي)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// بيانات تجريبية مستوحاة من لقطات الويب (الأمل تجربة ديمو).
abstract final class PreviewSample {
  static const institution = 'الأمل تجربة ديمو';
  static const academicYear = '2026 / 2027';
  static const longDate = 'الثلاثاء، 22 سبتمبر 2026';
  static const shortDate = '22/09/2026';
  static const roomName = 'شعبة أ';
  static const gradeLevel = 'عاشر';
  static const teacher = 'أ. محمود الزهار';
}

/// خطوط PDF للتقارير: Noto Naskh Arabic + لاتيني + رموز (✓ ✕).
Future<pw.ThemeData> previewTheme() async {
  final regular = await _font('assets/fonts/pdf/NotoNaskhArabic-Regular.ttf');
  final bold = await _font('assets/fonts/pdf/NotoNaskhArabic-Bold.ttf');
  final latin = await _font('assets/fonts/pdf/NotoSans-Regular.ttf');
  final latinBold = await _font('assets/fonts/pdf/NotoSans-Bold.ttf');
  final symbols = await _font('assets/fonts/pdf/NotoSansSymbols2-Regular.ttf');
  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    fontFallback: [latin, latinBold, symbols],
  );
}

Future<pw.Font> _font(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('خط PDF مفقود: $path — شغّل من جذر المشروع.');
  }
  return pw.Font.ttf(ByteData.sublistView(await file.readAsBytes()));
}

int _rtlIndex(int index, int length) => length - 1 - index;

Set<int>? _rtlSet(Set<int>? src, int length) {
  if (src == null || src.isEmpty) return src;
  return {for (final i in src) _rtlIndex(i, length)};
}

/// ترويسة ويب كلاسيكية: يمين مدرسة+عام · وسط عنوان · يسار تاريخ.
pw.Widget webDocHeader({
  required String institution,
  required String title,
  required String academicYear,
  required String dateLabel,
  String? logoNote,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(width: 1.6, color: PdfColors.black)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // مع textDirection.rtl: أول ابن يظهر يميناً
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(institution, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('العام الدراسي: $academicYear', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              if (logoNote != null) pw.Text(logoNote, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700), textAlign: pw.TextAlign.end),
        ),
      ],
    ),
  );
}

/// صف معلومات تحت الترويسة (صف/مربي/عدد…).
pw.Widget metaRow(List<String> parts) {
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

/// جدول يتكرر رأسه في كل صفحة.
///
/// الأعمدة تُمرَّر بمنطق القراءة العربي يمين→يسار، ثم تُعكس داخلياً لأن
/// `Table` في حزمة pdf يرتّب الأعمدة دائماً من اليسار لليمين.
///
/// [headers] عناصر `String` أو `pw.Widget` (لرموز رأس مخصّصة مثل تقييمات العلامات).
pw.Widget repeatingTable({
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
  final visualLtr = _rtlSet(ltrColumns, n) ?? const <int>{};
  final visualAccent = _rtlSet(accentColumns, n) ?? const <int>{};

  final widths = <int, pw.TableColumnWidth>{};
  if (visualFlex != null) {
    for (var i = 0; i < visualFlex.length; i++) {
      widths[i] = pw.FlexColumnWidth(visualFlex[i].toDouble());
    }
  }

  pw.Widget cell(
    dynamic content, {
    required int col,
    bool head = false,
  }) {
    final forceLtr = !head && visualLtr.contains(col);
    final isAccent = !head && visualAccent.contains(col);
    final style = pw.TextStyle(
      fontSize: head ? 8.5 : 9,
      fontWeight: head || isAccent ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: isAccent ? accent : PdfColors.black,
      lineSpacing: 1.05,
    );

    final pw.Widget child;
    if (content is pw.Widget) {
      child = content;
    } else {
      final text = content?.toString() ?? ' ';
      child = pw.Directionality(
        textDirection: forceLtr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        child: pw.Text(
          text.isEmpty ? ' ' : text,
          style: style,
          textAlign: pw.TextAlign.center,
        ),
      );
    }

    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: head ? 4 : 3.5),
      child: child,
    );
  }

  final tableRows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: headerBg),
      children: [
        for (var c = 0; c < visualHeaders.length; c++)
          cell(visualHeaders[c], col: c, head: true),
      ],
    ),
    for (var r = 0; r < visualRows.length; r++)
      pw.TableRow(
        children: [
          for (var c = 0; c < visualRows[r].length; c++)
            cell(visualRows[r][c], col: c),
        ],
      ),
  ];

  return pw.Table(
    tableWidth: pw.TableWidth.max,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.45),
    columnWidths: widths.isEmpty ? null : widths,
    children: tableRows,
  );
}

/// رأس عمود تقييم: اسم · تاريخ · الدرجة القصوى — كل سطر منفصل بوضوح.
pw.Widget gradeEvalHeader({
  required String title,
  String? date,
  required String outOf,
}) {
  return pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.center,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
        maxLines: 2,
      ),
      if (date != null && date.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          date,
          style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
          textAlign: pw.TextAlign.center,
        ),
      ],
      pw.SizedBox(height: 1),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFE2E8F0),
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Text(
          outOf,
          style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ],
  );
}

pw.Widget signatureRow(List<String> labels) {
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

/// يبني PDF ويحفظه تحت Docs/out.
///
/// التوقيعات ([endMatter]) تُلحق مباشرة بعد المحتوى — بدون footer يحجز
/// هامش سفلي فارغ في كل صفحة (كان `pagesCount` أثناء البناء يساوي رقم الصفحة
/// فيُحسب ذيل التوقيعات على كل الصفحات).
Future<File> writePreviewPdf({
  required String fileName,
  required PdfPageFormat format,
  required List<pw.Widget> Function(pw.Context) build,
  pw.Widget Function(pw.Context)? header,
  List<pw.Widget>? endMatter,
  pw.EdgeInsets margin = const pw.EdgeInsets.fromLTRB(16, 12, 16, 10),
}) async {
  final doc = pw.Document(theme: await previewTheme());
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: margin,
      textDirection: pw.TextDirection.rtl,
      header: header,
      build: (ctx) => [
        ...build(ctx),
        if (endMatter != null) ...endMatter,
      ],
    ),
  );
  final outDir = Directory('Docs/out');
  if (!await outDir.exists()) await outDir.create(recursive: true);
  final file = File('${outDir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(await doc.save());
  return file;
}
