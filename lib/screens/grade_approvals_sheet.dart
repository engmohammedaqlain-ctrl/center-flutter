import 'package:flutter/material.dart';
import '../data/grade_approval.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

// طلبات الاعتماد — المقابل لـ `GradeApprovalsButton` و`GradeApprovalsPanel` في الويب.

/// زر في شريط العلامات بعدد ما ينتظر الاعتماد، كزر «نشر»؛ لا يظهر بلا طلبات.
class GradeApprovalsButton extends StatelessWidget {
  const GradeApprovalsButton({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final pending = store.pendingApprovals;
    if (pending.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'طلبات الاعتماد (${pending.length})',
      onPressed: () => showGradeApprovals(context, store),
      icon: Badge(label: Text('${pending.length}'), child: const Icon(Icons.fact_check_outlined)),
    );
  }
}

/// سطر لكل اختبار رصده معلم (الأقدم أولاً)، و«اعتماد» للسطر أو للكل. النشر بعده من «نشر».
Future<void> showGradeApprovals(BuildContext context, AppStore store) {
  var busy = false;
  Future<void> approve(BuildContext ctx, StateSetter setSheet, List<String> keys) async {
    setSheet(() => busy = true);
    try {
      await store.approveTests(keys);
      if (ctx.mounted) showAppSnack(ctx, 'اعتُمد ${keys.length}');
    } on StoreException catch (e) {
      if (ctx.mounted) showAppSnack(ctx, e.message, error: true);
    } finally {
      if (ctx.mounted) setSheet(() => busy = false);
    }
    if (store.pendingApprovals.isEmpty && ctx.mounted) Navigator.pop(ctx);
  }

  String dm(String d) => d.length >= 10 ? '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}' : d;

  return showNoonSheet<void>(
    context,
    title: 'طلبات الاعتماد',
    body: (ctx, setSheet) {
      final pending = store.pendingApprovals;
      return [
        for (final t in pending)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(14, weight: FontWeight.w700)),
                      Text(
                        [
                          store.subjectById(t.subjectId)?.name ?? '',
                          store.groups.where((g) => g.id == t.groupId).firstOrNull?.gradeLevel ?? '',
                          store.teacherById(t.teacherId)?.name ?? '',
                          '${dm(t.date)} · ${t.count} طالب',
                        ].where((s) => s.trim().isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(12, color: AdminNoon.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: busy ? null : () => approve(ctx, setSheet, [t.key]), child: const Text('اعتماد')),
              ],
            ),
          ),
      ];
    },
    footer: (ctx, setSheet) => [
      FilledButton.icon(
        onPressed: busy ? null : () => approve(ctx, setSheet, [for (final t in store.pendingApprovals) t.key]),
        icon: const Icon(Icons.done_all_rounded),
        label: const Text('اعتماد الكل'),
      ),
    ],
  );
}

/// سبب تعديل علامة معتمدة (إجباري)، أو `null` إن أُلغي.
Future<String?> askApprovedEditReason(BuildContext context) {
  final ctl = TextEditingController();
  return showNoonSheet<String>(
    context,
    title: 'علامة معتمدة',
    body: (ctx, _) => [
      TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'سبب التعديل (يُكتب في السجل)'),
      ),
    ],
    footer: (ctx, _) => [
      FilledButton(
        onPressed: () {
          if (ctl.text.trim().isEmpty) return showAppSnack(ctx, 'اكتب السبب', error: true);
          Navigator.pop(ctx, ctl.text.trim());
        },
        child: const Text('متابعة'),
      ),
    ],
  );
}
