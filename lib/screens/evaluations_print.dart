import 'package:flutter/material.dart';

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
  final rows = [
    for (final e in evaluations)
      [
        store.studentById(e.studentId)?.fullName ?? 'طالب محذوف',
        [
          store.groups.where((g) => g.id == e.groupId).firstOrNull?.name ?? '',
          store.subjects.where((s) => s.id == e.subjectId).firstOrNull?.name ?? '',
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
    title: 'كشف درجات وتقييمات الطلاب',
    institutionName: store.institutionName,
    logoBase64: store.institutionLogo,
    landscape: true,
    body: (ctx) => [
      PdfKit.table(
        headers: ['الطالب', 'الشعبة والمادة', 'عنوان التقييم', 'النوع', 'الدرجة', 'النسبة', 'التاريخ', 'ملاحظات'],
        rows: rows,
        flex: [5, 4, 4, 3, 2, 2, 3, 4],
      ),
    ],
  );

  if (!context.mounted) return;
  final suffix = groupName.trim().isEmpty ? '' : ' ${groupName.trim()}';
  await PdfKit.preview(bytes, PdfKit.fileName('كشف الدرجات والتقييمات$suffix'));
}
