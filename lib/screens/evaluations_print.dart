import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';

/// طباعة كشف الدرجات — المقابل لزر «طباعة الكشف» في `pages/Evaluations.tsx`.
///
/// يطبع القائمة كما هي معروضة بعد التصفية، بأعمدة الجدول نفسها عدا «إجراء».
Future<void> printEvaluations(
  BuildContext context, {
  required AppStore store,
  required List<Evaluation> evaluations,

  /// الشعبة المصفّى عليها — تدخل اسم الملف كما في `groupSuffix` بالنسخة المكتبية.
  String groupName = '',
}) async {
  final year = store.viewedAcademicYear?.label ?? '';
  final extracted = isoDate(DateTime.now());
  final rows = [
    for (final e in evaluations)
      [
        store.studentById(e.studentId)?.fullName ?? 'طالب محذوف',
        [
          store.subjects.where((s) => s.id == e.subjectId).firstOrNull?.name ?? '',
          store.groups.where((g) => g.id == e.groupId).firstOrNull?.gradeLevel ?? '',
        ].where((x) => x.isNotEmpty).join(' · '),
        e.title,
        e.typeLabel,
        '${trimNum(e.score)} / ${trimNum(e.maxScore)}',
        '${e.percent}%',
        e.evaluationDate,
        e.notes.isEmpty ? '—' : e.notes,
      ],
  ];

  final bytes = await PdfKit.build(
    title: 'كشف العلامات',
    institutionName: store.institutionName,
    logoBase64: store.institutionLogo,
    subtitle: [
      if (year.isNotEmpty) 'العام الدراسي: $year',
      'تاريخ الاستخراج: $extracted',
    ].join('   ·   '),
    landscape: true,
    body: (ctx) => [
      PdfKit.table(
        headers: ['الطالب', 'المادة والمرحلة', 'عنوان التقييم', 'النوع', 'الدرجة', 'النسبة', 'التاريخ', 'ملاحظات'],
        rows: rows,
        flex: [5, 4, 4, 3, 2, 2, 3, 4],
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('المعلم: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('المشرف: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('الإدارة: ....................', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    ],
  );

  if (!context.mounted) return;
  final suffix = groupName.trim().isEmpty ? '' : ' ${groupName.trim()}';
  await PdfKit.preview(bytes, PdfKit.fileName('كشف العلامات$suffix'));
}
