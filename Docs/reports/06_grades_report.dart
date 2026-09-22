/// 06 — كشف العلامات — مقابل `Evaluations.tsx` (إدارة + معلم).
library;

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'preview_kit.dart';

Future<File> buildGradesPreview() {
  // رأس كل تقييم: اسم + الدرجة القصوى (بدون تاريخ)
  final evalHeaders = <pw.Widget>[
    gradeEvalHeader(title: 'اختبار قصير 1', outOf: 'من 20'),
    gradeEvalHeader(title: 'امتحان الشهر الأول', outOf: 'من 100'),
    gradeEvalHeader(title: 'الواجبات والمشاركة', outOf: 'من 10'),
    gradeEvalHeader(title: 'تقييم السلوك', outOf: 'من 10'),
    gradeEvalHeader(title: 'امتحان نهاية الفصل', outOf: 'من 100'),
    gradeEvalHeader(title: 'مجموع الفصل', outOf: 'من 100'),
  ];

  final students = [
    for (var i = 1; i <= 32; i++)
      (
        'طالب تجريبي $i',
        '${12 + (i % 8)}',
        '${60 + (i % 35)}',
        '${6 + (i % 4)}',
        '${7 + (i % 3)}',
        '${55 + (i % 40)}',
        '${65 + (i % 30)}',
      ),
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
        students[i].$6,
        students[i].$7,
      ],
  ];

  return writePreviewPdf(
    fileName: '06_grades.pdf',
    format: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
    header: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        webDocHeader(
          institution: PreviewSample.institution,
          title: 'كشف العلامات',
          academicYear: PreviewSample.academicYear,
          dateLabel: 'التاريخ: ${PreviewSample.shortDate}',
        ),
        pw.SizedBox(height: 6),
        metaRow([
          'المادة: الرياضيات',
          'الصف: ثامن',
          'الفصل الأول',
          'المعلم: ${PreviewSample.teacher}',
          '${students.length} طلاب',
        ]),
      ],
    ),
    build: (ctx) => [
      repeatingTable(
        headers: ['م', 'الطالب', ...evalHeaders],
        rows: rows,
        flex: const [1, 4, 2, 3, 2, 2, 3, 2],
      ),
    ],
    endMatter: [
      signatureRow(const [
        'المعلم',
        'المشرف',
        'الإدارة',
      ]),
    ],
  );
}
