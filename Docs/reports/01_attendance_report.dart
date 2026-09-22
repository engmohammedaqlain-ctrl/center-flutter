/// 01 — كشف الحضور والغياب (A4 عرضي) — مقابل `Attendance.tsx` طباعة.
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'preview_kit.dart';

Future<File> buildAttendancePreview() {
  const days = ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];

  // ✓ حاضر · ✕ غائب · م مأذون
  final students = <(String, List<String>, int, String)>[
    ('يامن البورنو', ['✓', '✓', '✓', '✕', '✓', '✓'], 1, '0598326654'),
    ('فارس الشوربجي', ['✓', '✓', '✓', '✓', '✓', '✓'], 0, '0599100001'),
    ('جهاد النعنع', ['✓', '✕', '✓', '✓', 'م', '✓'], 1, '0599100002'),
    ('غنى المدلل', ['✓', '✓', '✓', '✓', '✓', '✕'], 1, '0599100003'),
    for (var i = 5; i <= 40; i++)
      ('طالب تجريبي $i', ['✓', '✓', '✕', '✓', '✓', '✓'], 1, '05991${i.toString().padLeft(5, '0')}'),
  ];

  final headers = [
    '#',
    'اسم الطالب',
    ...days,
    'الغياب',
    'ولي الأمر',
    'ملاحظات',
  ];

  final rows = [
    for (var i = 0; i < students.length; i++)
      [
        '${i + 1}',
        students[i].$1,
        ...students[i].$2,
        '${students[i].$3}',
        students[i].$4,
        '',
      ],
  ];

  return writePreviewPdf(
    fileName: '01_attendance.pdf',
    format: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
    header: (ctx) => pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 1.2)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(PreviewSample.institution, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('سجل التفقد والدوام الأسبوعي الرسمي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('العام الدراسي: ${PreviewSample.academicYear}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 1.3)),
                      ),
                      child: pw.Text('كشف الحضور والغياب', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('الفترة: من السبت 19-9 إلى الخميس 24-9', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('المرحلة: رابع، شعبة ب', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text('إجمالي الطلاب: ${students.length} طالب', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('تاريخ الاستخراج: ${PreviewSample.longDate}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 5),
      ],
    ),
    build: (ctx) => [
      repeatingTable(
        headers: headers,
        rows: rows,
        flex: const [1, 5, 2, 2, 2, 2, 2, 2, 2, 3, 3],
        ltrColumns: const {9},
      ),
    ],
    endMatter: [
      signatureRow(const [
        'توقيع المعلم / مربي الصف',
        'توقيع المشرف الإداري',
        'مدير المدرسة / الختم الرسمي',
      ]),
    ],
  );
}
