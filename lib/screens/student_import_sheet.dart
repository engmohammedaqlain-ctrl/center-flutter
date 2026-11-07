import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/discount_policy.dart';
import '../data/doc_export.dart';
import '../data/fee_plan.dart';
import '../data/store.dart';
import '../data/student_import.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// استيراد الطلاب بثلاث خطوات — `StudentImportModal`: الملف، ثم الفحص (لا يُكتب شيء)، ثم النتيجة.
Future<void> showStudentImportSheet(BuildContext context, AppStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _StudentImportSheet(store: store),
  );
}

class _StudentImportSheet extends StatefulWidget {
  const _StudentImportSheet({required this.store});

  final AppStore store;

  @override
  State<_StudentImportSheet> createState() => _StudentImportSheetState();
}

class _StudentImportSheetState extends State<_StudentImportSheet> {
  int step = 1;
  bool busy = false;
  List<List<String>> sheet = const [];
  ImportCheck? check;
  List<String> created = const [];
  List<({int line, String message})> failed = const [];

  AppStore get store => widget.store;

  Future<void> _template() => DocExport.download(
        context,
        writeXlsx([
          [for (final c in importColumns) c.header],
          [for (final c in importColumns) c.example],
        ]),
        'نموذج-استيراد-الطلاب.xlsx',
        mime: _xlsxMime,
      );

  Future<void> _pick() async {
    const type = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null) return;
    setState(() => busy = true);
    try {
      final rows = readXlsx(await file.readAsBytes());
      final sections = <String, List<String>>{};
      for (final r in store.roomsInViewedYear) {
        sections.putIfAbsent(r.gradeLevel.trim(), () => []).add(r.name);
      }
      final result = checkImport(
        rows,
        grades: [for (final f in store.gradeFeesInViewedYear) f.gradeName],
        sections: sections,
        existingIds: {
          for (final s in store.students)
            if (s.nationalId.trim().isNotEmpty) s.nationalId.trim(),
        },
      );
      if (!mounted) return;
      setState(() {
        sheet = rows;
        check = result;
        step = 2;
      });
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر قراءة الملف: احفظه بصيغة xlsx'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// الأسطر الخاطئة كما هي وبجانبها خطؤها: يصلحها المدير ويرفعها من جديد.
  Future<void> _downloadIssues() {
    final byLine = <int, List<String>>{};
    for (final i in check!.issues) {
      byLine.putIfAbsent(i.line, () => []).add('${i.column}: ${i.message}');
    }
    final header = [for (final h in sheet.first) h.trim()];
    final rows = <List<String>>[
      [for (final c in importColumns) c.header, 'الخطأ'],
      for (final e in byLine.entries)
        [
          for (final c in importColumns)
            () {
              final i = header.indexOf(c.header);
              final row = sheet[e.key - 1];
              return i >= 0 && i < row.length ? row[i] : '';
            }(),
          e.value.join(' · '),
        ],
    ];
    return DocExport.download(context, writeXlsx(rows), 'أخطاء-الاستيراد.xlsx', mime: _xlsxMime);
  }

  Future<void> _run() async {
    final rows = check?.rows ?? const <ImportRow>[];
    if (rows.isEmpty) return;
    setState(() => busy = true);
    final ok = <String>[];
    final bad = <({int line, String message})>[];
    final discounts = store.settings.discounts;
    for (final r in rows) {
      try {
        // خصم الإخوة كما في نموذج التسجيل: إخوته المسجلون قبله، ومنهم من سبقه في الملف
        final siblings = r.parentNationalId.isEmpty
            ? 0
            : store.students
                .where((s) =>
                    s.parentNationalId.trim() == r.parentNationalId && (s.status == 'active' || s.status == 'pending'))
                .length;
        final discount = suggestDiscount(discounts, siblingsBefore: siblings, average: 0);
        final id = store.newId();
        final hasDiscount = discount != null && discount.percent > 0;
        store.upsertStudent(
          Student(
            id: id,
            firstName: r.firstName,
            lastName: r.lastName,
            fullName: r.fullName,
            nationalId: r.nationalId,
            gradeLevel: r.gradeLevel,
            section: r.section,
            phone: r.phone,
            phonePrefix: r.phonePrefix,
            gender: r.gender,
            birthDate: r.birthDate,
            parentName: r.parentName,
            parentNationalId: r.parentNationalId,
            parentPhone: r.parentPhone,
            parentPhonePrefix: r.parentPhonePrefix,
            status: 'active',
            balance: 0,
            enrolledAt: DateTime.now(),
          ),
          isNew: true,
          allowDuplicatePhone: true,
          discount: hasDiscount ? PlanDiscount.percent(discount.percent, reason: discount.reason) : null,
        );
        ok.add(id);
        if (r.openingBalance > 0) {
          store.addExtraCharge(studentId: id, title: 'رصيد سابق', amount: r.openingBalance, dueDate: DateTime.now());
        }
      } catch (e) {
        bad.add((line: r.line, message: userMessage(e, 'تعذّر الحفظ')));
      }
    }
    if (!mounted) return;
    setState(() {
      created = ok;
      failed = bad;
      busy = false;
      step = 3;
    });
  }

  Future<void> _undo() async {
    final ok = await confirmSheet(
      context,
      title: 'تراجع عن الاستيراد',
      message: 'حذف الطلاب المستوردين الآن (${created.length})؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      for (final id in created) {
        store.deleteStudent(id);
      }
      if (!mounted) return;
      showAppSnack(context, 'حُذف المستورد');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحذف'), error: true);
    }
  }

  Widget _stat(String label, int value, {Color? color}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color ?? AppColors.heading)),
              Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = check;
    return NoonSheetFrame(
      title: 'استيراد الطلاب',
      footer: switch (step) {
        1 => [NoonButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))],
        2 => [
            NoonButton(label: 'ملف آخر', onPressed: () => setState(() => step = 1)),
            if (c != null && c.issues.isNotEmpty) NoonButton(label: 'الأخطاء', onPressed: _downloadIssues),
            NoonButton(
              label: 'استيراد السليم (${c?.rows.length ?? 0})',
              tone: NoonTone.sun,
              busy: busy,
              onPressed: busy || (c?.rows.isEmpty ?? true) ? null : _run,
            ),
          ],
        _ => [
            if (created.isNotEmpty) NoonButton(label: 'تراجع عن الاستيراد', onPressed: _undo),
            NoonButton(label: 'تم', tone: NoonTone.sun, onPressed: () => Navigator.pop(context)),
          ],
      },
      children: [
        if (step == 1) ...[
          GhostButton(label: 'تنزيل النموذج', icon: Icons.table_chart_outlined, onPressed: _template),
          PrimaryButton(
            label: busy ? 'جارِ القراءة...' : 'اختيار ملف xlsx',
            icon: Icons.upload_file_outlined,
            expand: true,
            height: 72,
            busy: busy,
            onPressed: busy ? null : _pick,
          ),
        ],
        if (step == 2 && c != null)
          if (c.missingColumns.isNotEmpty)
            Text(
              'أعمدة ناقصة: ${c.missingColumns.join('، ')}. استعمل النموذج.',
              style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w700),
            )
          else ...[
            Row(
              children: [
                _stat('سطر', c.total),
                _stat('سليم', c.rows.length, color: AppColors.success),
                _stat('فيه خطأ', {for (final i in c.issues) i.line}.length, color: c.issues.isEmpty ? null : AppColors.danger),
              ],
            ),
            if (c.issues.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final i in c.issues.take(200))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                          children: [
                            TextSpan(text: 'سطر ${i.line} · ${i.column}${i.value.isEmpty ? '' : ' (${i.value})'}: '),
                            TextSpan(
                              text: i.message,
                              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        if (step == 3) ...[
          Text(
            'أُضيف ${created.length} طالب',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.heading),
          ),
          for (final f in failed)
            Text('سطر ${f.line}: ${f.message}', style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
        ],
      ],
    );
  }
}
