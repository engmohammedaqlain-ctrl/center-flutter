import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

/// طباعة كشف العلامات — مصفوفة طلاب × تقييمات عند الإمكان، وإلا قائمة.
Future<void> printEvaluations(
  BuildContext context, {
  required AppStore store,
  required List<Evaluation> evaluations,
  String groupName = '',
}) {
  return runBusyOp(context, () async {
    final year = store.viewedAcademicYear?.label ?? academicYear();
    final logo = PdfKit.decodeImage(store.institutionLogo);
    final extracted = isoDate(DateTime.now());

    // أعمدة التقييم: عنوان فريد مع أعلى maxScore ظاهر
    final columnKeys = <String>[];
    final columnMax = <String, double>{};
    for (final e in evaluations) {
      final key = e.title.trim().isEmpty ? e.typeLabel : e.title.trim();
      if (!columnKeys.contains(key)) columnKeys.add(key);
      final prev = columnMax[key] ?? 0;
      if (e.maxScore > prev) columnMax[key] = e.maxScore;
    }

    // ترتيب الطلاب كما يظهرون أول مرة في القائمة
    final studentIds = <String>[];
    for (final e in evaluations) {
      if (!studentIds.contains(e.studentId)) studentIds.add(e.studentId);
    }

    final scoreMap = <String, Map<String, String>>{};
    for (final e in evaluations) {
      final key = e.title.trim().isEmpty ? e.typeLabel : e.title.trim();
      scoreMap.putIfAbsent(e.studentId, () => {})[key] = trimNum(e.score);
    }

    // مجموع الفصل إن وُجدت درجات رقمية
    final useMatrix = columnKeys.isNotEmpty && studentIds.isNotEmpty;

    late final Uint8List? bytes;
    if (useMatrix) {
      final headers = <dynamic>[
        'م',
        'الطالب',
        for (final k in columnKeys)
          PdfKit.gradeEvalHeader(
            title: k,
            outOf: 'من ${trimNum(columnMax[k] ?? 100)}',
          ),
      ];
      final flex = <int>[1, 4, ...List.filled(columnKeys.length, 2)];
      final rows = [
        for (var i = 0; i < studentIds.length; i++)
          [
            '${i + 1}',
            store.studentById(studentIds[i])?.fullName ?? 'طالب محذوف',
            for (final k in columnKeys) scoreMap[studentIds[i]]?[k] ?? '-',
          ],
      ];

      final subjectName = evaluations
          .map((e) => store.subjects.where((s) => s.id == e.subjectId).firstOrNull?.name ?? '')
          .where((x) => x.isNotEmpty)
          .toSet()
          .join(' · ');
      final teacherName = evaluations
          .map((e) => store.teacherById(e.teacherId)?.name ?? '')
          .where((x) => x.isNotEmpty)
          .toSet()
          .join(' · ');

      bytes = await PdfKit.buildSafe(
        title: 'كشف العلامات',
        institutionName: store.institutionName,
        logoBase64: store.institutionLogo,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfKit.docHeader(
              institution: store.institutionName,
              title: 'كشف العلامات',
              academicYearLabel: year,
              dateLabel: 'التاريخ: $extracted',
              logo: logo,
            ),
            PdfKit.metaRow([
              if (subjectName.isNotEmpty) 'المادة: $subjectName',
              if (groupName.trim().isNotEmpty) 'الصف: ${groupName.trim()}',
              if (teacherName.isNotEmpty) 'المعلم: $teacherName',
              '${studentIds.length} طلاب',
            ]),
          ],
        ),
        body: (_) => [
          PdfKit.table(headers: headers, rows: rows, flex: flex),
        ],
        endMatter: [
          PdfKit.signatureRow(const ['المعلم', 'المشرف', 'الإدارة']),
        ],
      );
    } else {
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
            e.notes.isEmpty ? '-' : e.notes,
          ],
      ];
      bytes = await PdfKit.buildSafe(
        title: 'كشف العلامات',
        institutionName: store.institutionName,
        logoBase64: store.institutionLogo,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfKit.docHeader(
              institution: store.institutionName,
              title: 'كشف العلامات',
              academicYearLabel: year,
              dateLabel: 'التاريخ: $extracted',
              logo: logo,
            ),
          ],
        ),
        body: (_) => [
          PdfKit.table(
            headers: const ['الطالب', 'المادة والمرحلة', 'عنوان التقييم', 'النوع', 'الدرجة', 'النسبة', 'التاريخ', 'ملاحظات'],
            rows: rows,
            flex: const [5, 4, 4, 3, 2, 2, 3, 4],
          ),
        ],
        endMatter: [
          PdfKit.signatureRow(const ['المعلم', 'المشرف', 'الإدارة']),
        ],
      );
    }

    if (!context.mounted) return;
    if (bytes == null) {
      showAppSnack(context, 'تعذّر تجهيز كشف العلامات', error: true);
      return;
    }
    final suffix = groupName.trim().isEmpty ? '' : ' ${groupName.trim()}';
    try {
      await PdfKit.preview(bytes, PdfKit.fileName('كشف العلامات$suffix'));
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر تنزيل كشف العلامات', error: true);
    }
  }, message: 'جارٍ تجهيز كشف العلامات...');
}
