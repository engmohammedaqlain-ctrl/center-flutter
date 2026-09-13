import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// ترقية طلاب المدرسة لصف أعلى — المقابل لـ `StudentPromotion.tsx`.
///
/// ترتيب المراحل في الإعدادات هو ترتيب إضافتها لا ترتيبها الدراسي، فالانتقال
/// المقترح لكل صف يُعرض للمراجعة قبل التنفيذ ولا يُفترض.
Future<void> showStudentPromotionSheet(BuildContext context, AppStore store) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _PromotionSheet(store: store),
  );
}

/// «أرشفة» بدل صفٍّ تالٍ — مطابق لـ `ARCHIVE` في النسخة المكتبية.
const _archive = '__archive__';

class _PromotionSheet extends StatefulWidget {
  const _PromotionSheet({required this.store});

  final AppStore store;

  @override
  State<_PromotionSheet> createState() => _PromotionSheetState();
}

class _PromotionSheetState extends State<_PromotionSheet> {
  late final List<GradeFee> grades = widget.store.gradeFees;
  late final Map<String, int> counts = _countByGrade();
  late final Map<String, String> targets = _initialTargets();

  bool running = false;
  String? result;

  String _key(String? name) => (name ?? '').trim().toLowerCase();

  Map<String, int> _countByGrade() {
    final map = <String, int>{};
    for (final s in widget.store.students.where((s) => s.status == 'active')) {
      final key = _key(s.gradeLevel);
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  /// الصف التالي في ترتيب الإعدادات، وآخر صفٍّ يُؤرشف طلابه.
  Map<String, String> _initialTargets() => {
        for (var i = 0; i < grades.length; i++)
          grades[i].gradeName: i + 1 < grades.length ? grades[i + 1].gradeName : _archive,
      };

  /// من لا طلاب نشطين في صفه لا يُعرض: لا شيء لترقيته.
  List<GradeFee> get rows => grades.where((g) => (counts[_key(g.gradeName)] ?? 0) > 0).toList();

  int get unknownGradeCount {
    final known = grades.map((g) => _key(g.gradeName)).toSet();
    return widget.store.students
        .where((s) => s.status == 'active' && !known.contains(_key(s.gradeLevel)))
        .length;
  }

  Future<void> _run() async {
    final ok = await confirmSheet(
      context,
      title: 'ترقية الطلاب',
      message: 'سينتقل طلاب كل صف إلى ما اخترته له، ويصير الطالب «بانتظار التأكيد» وتُمسح شعبته. هل تتابع؟',
      confirmLabel: 'تنفيذ',
    );
    if (!ok || !mounted) return;

    setState(() => running = true);
    try {
      final plan = <String, String?>{
        for (final g in rows) g.gradeName: targets[g.gradeName] == _archive ? null : targets[g.gradeName],
      };
      final res = widget.store.promoteStudents(plan);
      if (!mounted) return;
      setState(() => result = 'رُقّي ${res.promoted}، أُرشف ${res.archived}');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ترقية الطلاب',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                  ),
                ),
                SquareIconButton(icon: Icons.close, onTap: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),

            if (result != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  result!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.success),
                ),
              )
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  'لا طلاب نشطون في المراحل المعرّفة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              )
            else ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final g in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      g.gradeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                                    ),
                                    Text(
                                      '${counts[_key(g.gradeName)]} طالب',
                                      style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_back, size: 14, color: AppColors.faint),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 5,
                                child: AppDropdown<String>(
                                  value: targets[g.gradeName] ?? _archive,
                                  items: [
                                    for (final o in grades)
                                      if (o.id != g.id)
                                        DropdownMenuItem(
                                          value: o.gradeName,
                                          child: Text(o.gradeName, overflow: TextOverflow.ellipsis),
                                        ),
                                    const DropdownMenuItem(value: _archive, child: Text('أرشفة')),
                                  ],
                                  onChanged: (v) => setState(() => targets[g.gradeName] = v ?? _archive),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'يصبح الطالب «بانتظار التأكيد» حتى تأكيده، وتُمسح شعبته. ديونه تبقى كما هي.',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              if (unknownGradeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'طلاب بصف غير معرّف لن يُرقَّوا: $unknownGradeCount',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.danger, fontWeight: FontWeight.w800),
                  ),
                ),
            ],

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context))),
                if (result == null && list.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: running ? 'جارِ التنفيذ...' : 'تنفيذ الترقية',
                      color: AppColors.navy,
                      busy: running,
                      onPressed: running ? null : _run,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
