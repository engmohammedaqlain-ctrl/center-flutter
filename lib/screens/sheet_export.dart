import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/doc_export.dart';
import '../data/printing.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

/// كشف جدولي واحد يُطبع PDF أو يُنزَّل Excel: كشف علامات اختبار، وكشف حضور الشهر.
///
/// العمود الثاني اسم الطالب. [landscape] لكشف الشهر العريض.
class SheetData {
  const SheetData({
    required this.title,
    required this.institution,
    required this.headers,
    required this.rows,
    this.logo = '',
    this.meta = const [],
    this.flex,
    this.landscape = false,
    this.signatures = const ['المعلم', 'الإدارة'],
    this.yearLabel = '',
  });

  final String title;
  final String institution;
  final String logo;
  final List<String> meta;
  final List<String> headers;
  final List<List<String>> rows;
  final List<int>? flex;
  final bool landscape;
  final List<String> signatures;
  final String yearLabel;
}

/// طباعة الكشف: ورقة الإجراءات (تنزيل، مشاركة) كبقية كشوف التطبيق.
Future<void> printSheet(BuildContext context, SheetData sheet) {
  return runBusyOp(context, () async {
    final logo = PdfKit.decodeImage(sheet.logo);
    final bytes = await PdfKit.buildSafe(
      title: sheet.title,
      institutionName: sheet.institution,
      logoBase64: sheet.logo,
      landscape: sheet.landscape,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          PdfKit.docHeader(
            institution: sheet.institution,
            title: sheet.title,
            academicYearLabel: sheet.yearLabel.isEmpty ? academicYear() : sheet.yearLabel,
            dateLabel: 'التاريخ: ${isoDate(DateTime.now())}',
            logo: logo,
          ),
          if (sheet.meta.isNotEmpty) PdfKit.metaRow(sheet.meta),
        ],
      ),
      body: (_) => [PdfKit.table(headers: sheet.headers, rows: sheet.rows, flex: sheet.flex)],
      endMatter: [if (sheet.signatures.isNotEmpty) PdfKit.signatureRow(sheet.signatures)],
    );
    if (!context.mounted) return;
    if (bytes == null) {
      showAppSnack(context, 'تعذّر تجهيز ${sheet.title}', error: true);
      return;
    }
    DocExport.showActions(context, bytes, PdfKit.fileName(sheet.title));
  }, message: 'جارٍ تجهيز الكشف...');
}

/// الكشف ملف CSV يفتحه Excel بالعربية: علامة BOM في أوله تجعله يُقرأ UTF-8.
Uint8List sheetCsvBytes(List<String> headers, List<List<String>> rows) {
  String cell(String v) => '"${v.replaceAll('"', '""')}"';
  final text = [headers, ...rows].map((r) => r.map(cell).join(',')).join('\r\n');
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
}

/// تنزيل الكشف Excel في مجلد التنزيلات.
Future<void> downloadSheetCsv(BuildContext context, SheetData sheet) {
  final name = '${sheet.title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').replaceAll(RegExp(r'\s+'), '_')}.csv';
  return DocExport.download(context, sheetCsvBytes(sheet.headers, sheet.rows), name, mime: 'text/csv');
}
