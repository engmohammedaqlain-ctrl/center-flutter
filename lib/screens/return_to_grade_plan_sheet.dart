import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// نطاق اعتماد أقساط المرحلة — مطابق لـ `PlanReturnScope` في الويب.
enum PlanReturnScope {
  all,
  future,
  fromItem,
}

extension PlanReturnScopeX on PlanReturnScope {
  String get wire {
    switch (this) {
      case PlanReturnScope.all:
        return 'all';
      case PlanReturnScope.future:
        return 'future';
      case PlanReturnScope.fromItem:
        return 'from_item';
    }
  }
}

/// ورقة إرجاع / نقل لخطة المرحلة — مطابق لـ `ReturnToGradePlanModal.tsx`.
///
/// - [ReturnToGradePlanMode.returnPlan]: من مخصصة لخطة مرحلتهم.
/// - [ReturnToGradePlanMode.transfer]: نقل صف — إسقاط غير المدفوع القديم + اعتماد الخطة الجديدة.
Future<bool> showReturnToGradePlanSheet({
  required BuildContext context,
  required List<String> studentIds,
  List<String> studentGrades = const [],
  ReturnToGradePlanMode mode = ReturnToGradePlanMode.returnPlan,
  String? fixedGradeName,
  Future<void> Function()? onPrepare,
}) async {
  if (studentIds.isEmpty) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog)),
    ),
    builder: (_) => _ReturnToGradePlanSheet(
      studentIds: studentIds,
      studentGrades: studentGrades,
      mode: mode,
      fixedGradeName: fixedGradeName,
      onPrepare: onPrepare,
    ),
  );
  return result == true;
}

enum ReturnToGradePlanMode { returnPlan, transfer }

class _ReturnToGradePlanSheet extends StatefulWidget {
  const _ReturnToGradePlanSheet({
    required this.studentIds,
    required this.studentGrades,
    required this.mode,
    this.fixedGradeName,
    this.onPrepare,
  });

  final List<String> studentIds;
  final List<String> studentGrades;
  final ReturnToGradePlanMode mode;
  final String? fixedGradeName;
  final Future<void> Function()? onPrepare;

  @override
  State<_ReturnToGradePlanSheet> createState() => _ReturnToGradePlanSheetState();
}

class _ReturnToGradePlanSheetState extends State<_ReturnToGradePlanSheet> {
  late PlanReturnScope scope = PlanReturnScope.future;
  late String gradeName;
  String fromPlanItemId = '';
  var busy = false;

  bool get isTransfer => widget.mode == ReturnToGradePlanMode.transfer;

  List<String> get uniqueGrades {
    if (isTransfer) {
      final fixed = widget.fixedGradeName?.trim() ?? '';
      if (fixed.isNotEmpty) return [fixed];
    }
    final seen = <String>{};
    final list = <String>[];
    for (final g in widget.studentGrades) {
      final t = g.trim();
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      list.add(t);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    gradeName = (widget.fixedGradeName?.trim().isNotEmpty == true)
        ? widget.fixedGradeName!.trim()
        : (uniqueGrades.isNotEmpty ? uniqueGrades.first : '');
    _syncFromItem();
  }

  List<PlanItem> _planItems(AppStore store) {
    final fee = store.gradePlans()[gradeName.trim().toLowerCase()] ?? store.feeFor(gradeName);
    final items = [...store.planItemsOf(fee)]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return items;
  }

  void _syncFromItem() {
    final store = AppStore.instance;
    final items = _planItems(store);
    if (items.any((i) => i.id == fromPlanItemId)) return;
    fromPlanItemId = items.isEmpty ? '' : items.first.id;
  }

  String get _scopeLabel {
    switch (scope) {
      case PlanReturnScope.all:
        return 'كل أقساط المرحلة';
      case PlanReturnScope.future:
        return 'الأقساط المستقبلية فقط';
      case PlanReturnScope.fromItem:
        return 'من القسط المختار فما بعده';
    }
  }

  Future<void> _apply() async {
    final store = StoreScope.of(context);
    final targetGrade = (isTransfer ? (widget.fixedGradeName ?? gradeName) : gradeName).trim();

    if (isTransfer && targetGrade.isEmpty) {
      showAppSnack(context, 'حدّد المرحلة الجديدة', error: true);
      return;
    }
    if (scope == PlanReturnScope.fromItem) {
      if (targetGrade.isEmpty) {
        showAppSnack(context, 'حدّد المرحلة', error: true);
        return;
      }
      if (fromPlanItemId.isEmpty) {
        showAppSnack(context, 'حدّد القسط الذي يبدأ منه الاحتساب', error: true);
        return;
      }
    }

    setState(() => busy = true);
    try {
      final preview = isTransfer
          ? store.transferStudentsToGrade(
              studentIds: widget.studentIds,
              newGradeName: targetGrade,
              planScope: scope.wire,
              fromPlanItemId: scope == PlanReturnScope.fromItem ? fromPlanItemId : null,
            )
          : store.returnCustomStudentsToGradePlan(
              studentIds: widget.studentIds,
              gradeName: scope == PlanReturnScope.fromItem ? targetGrade : null,
              planScope: scope.wire,
              fromPlanItemId: scope == PlanReturnScope.fromItem ? fromPlanItemId : null,
            );

      if (preview.students == 0) {
        if (mounted) {
          showAppSnack(context, 'لا طلاب قابلين للتحويل بهذه الخيارات', error: true);
        }
        return;
      }

      final message = isTransfer
          ? 'نقل ${preview.students} طالب إلى «$targetGrade» ($_scopeLabel)؟\n'
              'يُزال غير المدفوع من الصف السابق ويُضاف ${preview.added} من الخطة الجديدة (حذف ${preview.removed}).\n'
              'المدفوع يبقى في السجل.'
          : 'إرجاع ${preview.students} طالب لخطة المرحلة ($_scopeLabel)؟\n'
              'إزالة ${preview.removed} من المخصصة / إضافة ${preview.added} من المرحلة.\n'
              'المدفوع من المخصصة يبقى.';

      if (!mounted) return;
      final confirmed = await confirmSheet(
        context,
        title: isTransfer ? 'نقل للمرحلة' : 'إرجاع لخطة المرحلة',
        message: message,
        confirmLabel: 'تنفيذ',
        confirmColor: AppColors.danger,
      );
      if (!confirmed || !mounted) return;

      final prepare = widget.onPrepare;
      if (prepare != null) await prepare();

      final done = isTransfer
          ? store.transferStudentsToGrade(
              studentIds: widget.studentIds,
              newGradeName: targetGrade,
              planScope: scope.wire,
              fromPlanItemId: scope == PlanReturnScope.fromItem ? fromPlanItemId : null,
              apply: true,
            )
          : store.returnCustomStudentsToGradePlan(
              studentIds: widget.studentIds,
              gradeName: scope == PlanReturnScope.fromItem ? targetGrade : null,
              planScope: scope.wire,
              fromPlanItemId: scope == PlanReturnScope.fromItem ? fromPlanItemId : null,
              apply: true,
            );

      if (!mounted) return;
      showAppSnack(
        context,
        'تم: ${done.students} طالب — أُزيل ${done.removed} وأُضيف ${done.added}',
      );
      Navigator.pop(context, true);
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذر التحويل', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final items = _planItems(store);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isTransfer
                        ? 'خطة المرحلة الجديدة (${widget.studentIds.length})'
                        : 'إرجاع لخطة المرحلة (${widget.studentIds.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              isTransfer
                  ? 'المدفوع من الصف السابق يبقى. غير المدفوع يُشال. اختر كيف تُحتسب أقساط «${widget.fixedGradeName ?? gradeName}»:'
                  : 'غير المدفوع من الخطة المخصصة يُزال. المدفوع يبقى. اختر كيف تُحتسب أقساط المرحلة:',
              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 10),
            _ScopeOption(
              active: scope == PlanReturnScope.all,
              title: 'احتساب كل أقساط المرحلة',
              subtitle: 'بما فيها ما فات تاريخه — يصير مستحقاً فوراً',
              onTap: () => setState(() => scope = PlanReturnScope.all),
            ),
            const SizedBox(height: 6),
            _ScopeOption(
              active: scope == PlanReturnScope.future,
              title: 'الأقساط المستقبلية فقط',
              subtitle: 'من تاريخ اليوم فصاعداً',
              onTap: () => setState(() => scope = PlanReturnScope.future),
            ),
            const SizedBox(height: 6),
            _ScopeOption(
              active: scope == PlanReturnScope.fromItem,
              title: 'البدء من قسط معيّن',
              subtitle: 'أول قسط مطلوب فما بعده',
              onTap: () => setState(() {
                scope = PlanReturnScope.fromItem;
                _syncFromItem();
              }),
            ),
            if (scope == PlanReturnScope.fromItem) ...[
              const SizedBox(height: 12),
              if (!isTransfer) ...[
                const Text('المرحلة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: uniqueGrades.contains(gradeName)
                      ? gradeName
                      : (uniqueGrades.isEmpty ? null : uniqueGrades.first),
                  items: [
                    for (final g in uniqueGrades)
                      DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      gradeName = v;
                      _syncFromItem();
                    });
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                isTransfer
                    ? 'أول قسط مطلوب — ${widget.fixedGradeName ?? gradeName}'
                    : 'أول قسط مطلوب',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'لا خطة أقساط لهذه المرحلة — عرّفها من الإعدادات أولاً',
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: items.any((i) => i.id == fromPlanItemId) ? fromPlanItemId : items.first.id,
                  items: [
                    for (final item in items)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${item.title} — ${_dueLabel(item.dueDate)} — ${money(item.amount)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => fromPlanItemId = v);
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  isExpanded: true,
                ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : _apply,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.heading),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('معاينة وتطبيق', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => Navigator.pop(context, false),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dueLabel(String due) {
    final d = parseIsoDate(due);
    return d == null ? due : formatDate(d);
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.active,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool active;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.heading : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppColors.heading : AppColors.lineStrong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: active ? Colors.white : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: active ? Colors.white.withValues(alpha: 0.8) : AppColors.faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
