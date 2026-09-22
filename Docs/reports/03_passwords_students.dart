/// 03 - كشف كلمات مرور الطلاب - مقابل `ClassPortalCodesModal` mode=student.
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'preview_kit.dart';

Future<File> buildPasswordsStudentsPreview() {
  final students = [
    ('محمد النجار', '401234567', '219283'),
    ('حمزة الغول', '401234568', '296415'),
    ('سارة خضير', '401234569', '183746'),
    ('يوسف أحمد', '401234570', '552019'),
    ('ليان خالد', '401234571', '774301'),
    for (var i = 6; i <= 40; i++)
      ('طالب تجريبي $i', '40123${i.toString().padLeft(4, '0')}', '${100000 + i * 17}'),
  ];

  final rows = [
    for (var i = 0; i < students.length; i++)
      ['${i + 1}', students[i].$1, students[i].$2, students[i].$3],
  ];

  return writePreviewPdf(
    fileName: '03_passwords_students.pdf',
    format: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
    header: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        webDocHeader(
          institution: PreviewSample.institution,
          title: 'كشف كلمات مرور الطلاب',
          academicYear: PreviewSample.academicYear,
          dateLabel: PreviewSample.longDate,
        ),
        metaRow([
          'الصف / الشعبة: ${PreviewSample.roomName} - ${PreviewSample.gradeLevel}',
          'إجمالي الطلاب: ${students.length} طالب',
        ]),
      ],
    ),
    build: (ctx) => [
      repeatingTable(
        headers: const ['م', 'اسم الطالب', 'رقم الهوية', 'كلمة المرور'],
        rows: rows,
        flex: const [1, 5, 4, 3],
        ltrColumns: const {2, 3},
        accentColumns: const {3},
      ),
    ],
    endMatter: [
      signatureRow(const [
        'إدارة المدرسة',
        'مسؤول النظام',
        'الختم الرسمي',
      ]),
    ],
  );
}
