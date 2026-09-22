/// 04 - كشف كلمات مرور أولياء الأمور - مقابل mode=parent.
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'preview_kit.dart';

Future<File> buildPasswordsParentsPreview() {
  final students = [
    ('محمد النجار', '-', '-', '219283'),
    ('حمزة الغول', '-', '-', '296415'),
    ('سارة خضير', '-', '-', '183746'),
    ('يوسف أحمد', 'خالد أحمد', '401998877', '552019'),
    ('ليان خالد', '-', '-', '774301'),
    for (var i = 6; i <= 40; i++)
      ('طالب تجريبي $i', i.isEven ? 'ولي أمر $i' : '-', i.isEven ? '40998${i.toString().padLeft(4, '0')}' : '-', '${200000 + i * 13}'),
  ];

  final rows = [
    for (var i = 0; i < students.length; i++)
      ['${i + 1}', students[i].$1, students[i].$2, students[i].$3, students[i].$4],
  ];

  return writePreviewPdf(
    fileName: '04_passwords_parents.pdf',
    format: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
    header: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        webDocHeader(
          institution: PreviewSample.institution,
          title: 'كشف كلمات مرور أولياء الأمور',
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
        headers: const ['م', 'اسم الطالب', 'ولي الأمر', 'رقم هوية ولي الأمر', 'كلمة المرور'],
        rows: rows,
        flex: const [1, 4, 3, 4, 3],
        ltrColumns: const {3, 4},
        accentColumns: const {4},
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
