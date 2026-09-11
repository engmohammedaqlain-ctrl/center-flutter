import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'evaluation_form_sheet.dart';
import 'evaluations_print.dart';

/// الدرجات والتقييمات الأكاديمية — المقابل لـ `pages/Evaluations.tsx`.
///
/// الميزة قابلة للتعطيل من إعدادات المطور؛ الشاشة تُغلق نفسها إن عُطّلت،
/// كما يفعل `useEffect` في النسخة المكتبية بالتوجيه إلى الطلاب.
class EvaluationsScreen extends StatefulWidget {
  const EvaluationsScreen({super.key});

  @override
  State<EvaluationsScreen> createState() => _EvaluationsScreenState();
}

class _EvaluationsScreenState extends State<EvaluationsScreen> {
  final search = TextEditingController();
  String groupId = 'all';
  String type = 'all';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.features.enableEvaluations || !store.can('attendance.view')) {
          return Scaffold(
            appBar: AppBar(title: const Text('الدرجات والتقييمات')),
            body: NoAccess(section: 'attendance', roleName: store.roleName),
          );
        }

        final q = search.text.trim().toLowerCase();
        final list = store.evaluations.where((e) {
          if (groupId != 'all' && e.groupId != groupId) return false;
          if (type != 'all' && e.type != type) return false;
          if (q.isEmpty) return true;
          final name = (store.studentById(e.studentId)?.fullName ?? '').toLowerCase();
          return name.contains(q) || e.title.toLowerCase().contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('الدرجات والتقييمات'),
            actions: [
              IconButton(
                tooltip: 'تنزيل الكشف',
                icon: const Icon(Icons.print_outlined),
                onPressed: list.isEmpty
                    ? null
                    : () => printEvaluations(context, store: store, evaluations: list),
              ),
            ],
          ),
          body: ThumbActionLayer(
            action: store.can('attendance.edit')
                ? ThumbAction(
                    label: 'رصد درجات جديدة',
                    icon: Icons.edit_note,
                    color: AppColors.navy,
                    onPressed: () => _record(context, store),
                  )
                : null,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: _stats(list),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SearchField(
                    controller: search,
                    hint: 'ابحث باسم الطالب أو عنوان التقييم...',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppDropdown<String>(
                          value: groupId,
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('كل الشعب')),
                            for (final g in store.groups)
                              DropdownMenuItem(value: g.id, child: Text(g.name)),
                          ],
                          onChanged: (v) => setState(() => groupId = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppDropdown<String>(
                          value: type,
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('كل الأنواع')),
                            for (final e in evaluationTypeNames.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (v) => setState(() => type = v ?? 'all'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: EmptyState(message: 'لا توجد تقييمات مرصودة مطابقة للبحث.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, thumbActionClearance),
                          itemCount: list.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _EvalCard(
                              evaluation: list[i],
                              studentName: store.studentById(list[i].studentId)?.fullName ?? 'طالب محذوف',
                              groupName: store.groups.where((g) => g.id == list[i].groupId).firstOrNull?.name ?? '',
                              onDelete: store.can('attendance.edit')
                                  ? () => _delete(context, store, list[i])
                                  : null,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// أربع إحصاءات سريعة — نفس حساب `stats` في Evaluations.tsx: النسبة تُحسب
  /// من كل تقييم على حدة ثم تُعدّل، لا من مجموع الدرجات على مجموع القصوى.
  Widget _stats(List<Evaluation> list) {
    var totalPercent = 0;
    var passCount = 0;
    var highest = 0;
    for (final e in list) {
      totalPercent += e.percent;
      if (e.passed) passCount++;
      if (e.percent > highest) highest = e.percent;
    }
    final average = list.isEmpty ? 0 : (totalPercent / list.length).round();
    final passRate = list.isEmpty ? 0 : ((passCount / list.length) * 100).round();

    return Row(
      children: [
        _stat('التقييمات', '${list.length}', AppColors.heading),
        const SizedBox(width: 6),
        _stat('المعدل العام', '$average%', AppColors.success),
        const SizedBox(width: 6),
        _stat('النجاح (≥50%)', '$passRate%', AppColors.info),
        const SizedBox(width: 6),
        _stat('الأعلى', '$highest%', AppColors.amber),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: Colors.white, border: Border.all(color: AppColors.line)),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _record(BuildContext context, AppStore store) async {
    final saved = await showEvaluationSheet(context, store);
    if (saved > 0 && context.mounted) {
      showAppSnack(context, 'تم رصد $saved درجة');
    }
  }

  Future<void> _delete(BuildContext context, AppStore store, Evaluation e) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف التقييم',
      message: 'هل أنت متأكد من حذف تقييم «${e.title}»؟',
      confirmLabel: 'حذف',
    );
    if (!ok) return;
    store.deleteEvaluation(e.id);
    if (context.mounted) showAppSnack(context, 'تم حذف التقييم');
  }
}

class _EvalCard extends StatelessWidget {
  const _EvalCard({
    required this.evaluation,
    required this.studentName,
    required this.groupName,
    this.onDelete,
  });

  final Evaluation evaluation;
  final String studentName;
  final String groupName;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final e = evaluation;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                    ),
                    if (groupName.isNotEmpty)
                      Text(groupName, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              StatusChip.muted(e.typeLabel),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                SquareIconButton(
                  icon: Icons.delete_outline,
                  color: AppColors.danger,
                  bg: AppColors.dangerSoft,
                  border: AppColors.dangerBorder,
                  onTap: onDelete!,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    Text(
                      e.evaluationDate,
                      style: const TextStyle(color: AppColors.faint, fontSize: 10.5, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${trimNum(e.score)} / ${trimNum(e.maxScore)}',
                    style: TextStyle(
                      color: _tierColor(e.percent),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '${e.percent}%',
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
          if (e.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.notes, style: const TextStyle(color: AppColors.faint, fontSize: 10.5, height: 1.5)),
          ],
        ],
      ),
    );
  }
}


/// لون النسبة بثلاث درجات — مطابق لشارة النسبة في جدول Evaluations.tsx:
/// 85% فأكثر ممتاز، 50% فأكثر مقبول، وما دونها راسب.
Color _tierColor(int percent) {
  if (percent >= 85) return AppColors.success;
  if (percent >= 50) return AppColors.amber;
  return AppColors.danger;
}
