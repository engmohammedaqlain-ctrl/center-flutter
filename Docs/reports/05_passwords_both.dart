/// 05 — كشف كلمات مرور البوابة (كلاهما) — مقابل mode=all.
///
/// أعمدة: م | اسم | هوية طالب | مرور طالب | هوية ولي | مرور ولي
/// (اسم واحد؛ دخول الطالب حقلان؛ دخول ولي الأمر حقلان).
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'preview_kit.dart';

Future<File> buildPasswordsBothPreview() {
  final students = [
    ('محمد النجار', '401234567', '219283', '-', '881122'),
    ('حمزة الغول', '401234568', '296415', '-', '773344'),
    ('سارة خضير', '401234569', '183746', '-', '665544'),
    ('يوسف أحمد', '401234570', '552019', '401998877', '112233'),
    ('ليان خالد', '401234571', '774301', '-', '998877'),
    for (var i = 6; i <= 36; i++)
      (
        'طالب تجريبي $i',
        '40123${i.toString().padLeft(4, '0')}',
        '${100000 + i * 17}',
        i.isEven ? '40998${i.toString().padLeft(4, '0')}' : '-',
        '${300000 + i * 11}',
      ),
  ];

  // رؤوس منطقية يمين→يسار — repeatingTable يعكسها للرسم
  final headers = [
    'م',
    'اسم الطالب',
    'هوية الطالب',
    'مرور الطالب',
    'هوية ولي الأمر',
    'مرور ولي الأمر',
  ];

  final rows = [
    for (var i = 0; i < students.length; i++)
      [
        '${i + 1}',
        students[i].$1,
        students[i].$2,
        students[i].$3,
        students[i].$4,
        students[i].$5,
      ],
  ];

  return writePreviewPdf(
    fileName: '05_passwords_both.pdf',
    format: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
    header: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        webDocHeader(
          institution: PreviewSample.institution,
          title: 'كشف كلمات مرور البوابة',
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
        headers: headers,
        rows: rows,
        flex: const [1, 4, 3, 3, 3, 3],
        ltrColumns: const {2, 3, 4, 5},
        accentColumns: const {3, 5},
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
