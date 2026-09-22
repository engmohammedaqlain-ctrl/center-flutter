/// 02 — كشف بيانات وحضور طلاب الصف — مقابل `ClassPrintRoster.tsx`.
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'preview_kit.dart';

Future<File> buildClassRosterPreview() {
  final students = [
    ('محمد النجار', 'ذكر', '0599100000', '-'),
    ('حمزة الغول', 'ذكر', '0599108888', '-'),
    ('نور السوسي', 'أنثى', '0599106666', '-'),
    ('عمر الشوا', 'ذكر', '0599104444', '-'),
    ('سارة خضير', 'أنثى', '0599102222', '-'),
    for (var i = 6; i <= 32; i++)
      ('طالب تجريبي $i', i.isEven ? 'أنثى' : 'ذكر', '05991${i.toString().padLeft(5, '0')}', '-'),
  ];

  final rows = [
    for (var i = 0; i < students.length; i++)
      ['${i + 1}', students[i].$1, students[i].$2, students[i].$3, students[i].$4, ''],
  ];

  return writePreviewPdf(
    fileName: '02_class_roster.pdf',
    format: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
    header: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        webDocHeader(
          institution: PreviewSample.institution,
          title: 'كشف بيانات وحضور طلاب الصف',
          academicYear: PreviewSample.academicYear,
          dateLabel: PreviewSample.longDate,
        ),
        metaRow([
          'الصف / الشعبة: ${PreviewSample.roomName} - ${PreviewSample.gradeLevel}',
          'مربي الصف: ${PreviewSample.teacher}',
          'إجمالي الطلاب: ${students.length} طالب',
        ]),
      ],
    ),
    build: (ctx) => [
      repeatingTable(
        headers: const ['م', 'اسم الطالب الكامل', 'الجنس', 'الهاتف', 'ولي الأمر / الهاتف', 'ملاحظات / الحضور'],
        rows: rows,
        flex: const [1, 5, 2, 3, 4, 3],
        ltrColumns: const {3},
      ),
    ],
    endMatter: [
      signatureRow(const [
        'توقيع مربي الصف',
        'اعتماد الإدارة المدرسية',
      ]),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(PreviewSample.teacher, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ),
      ),
    ],
  );
}
