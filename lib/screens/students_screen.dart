import 'package:flutter/material.dart';

import '../data/balance.dart';
import '../data/phone.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/due_status.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'return_to_grade_plan_sheet.dart';
import 'student_detail_screen.dart';
import 'student_form_screen.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final search = TextEditingController();
  String grade = '';
  String section = '';

  /// فارغ = إخفاء المؤرشفين (افتراضي الويب)؛ قيمة حالة = فلتر بها.
  String statusFilter = '';
  bool customPlanOnly = false;
  bool selectionMode = false;
  final selectedIds = <String>{};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _setGrade(String v) {
    setState(() {
      grade = v;
      section = '';
    });
  }

  void _setCustomPlanOnly(bool on) {
    setState(() {
      customPlanOnly = on;
      if (!on && statusFilter != 'pending') {
        selectionMode = false;
        selectedIds.clear();
      }
    });
  }

  Future<void> _confirmSelected(AppStore store, List<Student> pendingInList) async {
    final ids = selectedIds.where((id) => pendingInList.any((s) => s.id == id)).toList();
    if (ids.isEmpty) {
      showAppSnack(context, 'حدّد طلاباً بانتظار التأكيد', error: true);
      return;
    }
    final ok = await confirmSheet(
      context,
      title: 'تأكيد التسجيل',
      message: 'تأكيد ${ids.length} طالب وبناء أقساط سنتهم الجديدة؟',
      confirmLabel: 'تأكيد',
      confirmColor: AppColors.heading,
    );
    if (!ok || !mounted) return;
    try {
      final result = store.confirmPendingStudents(ids);
      setState(() {
        selectedIds.clear();
        selectionMode = false;
      });
      final parts = <String>[
        'تم تأكيد ${result.confirmed}',
        if (result.planBuilt > 0) 'بُنيت أقساط ${result.planBuilt}',
        if (result.customPlan > 0) '${result.customPlan} على خطة مخصصة',
        if (result.withoutPlan > 0) '${result.withoutPlan} بلا أقساط',
      ];
      showAppSnack(context, parts.join(' · '));
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _returnSelected(AppStore store, List<Student> list) async {
    final ids = selectedIds
        .where((id) => list.any((s) => s.id == id && s.usesCustomPlan))
        .toList();
    if (ids.isEmpty) {
      showAppSnack(context, 'حدّد طلاباً على خطة مخصصة', error: true);
      return;
    }
    final grades = [
      for (final id in ids) store.studentById(id)?.gradeLevel ?? '',
    ].where((g) => g.trim().isNotEmpty).toList();
    final done = await showReturnToGradePlanSheet(
      context: context,
      studentIds: ids,
      studentGrades: grades,
    );
    if (!done || !mounted) return;
    setState(() {
      selectedIds.clear();
      selectionMode = false;
    });
  }

  void _openPendingSelection(AppStore store) {
    final pending = store.studentsInViewedYear.where((s) => s.status == 'pending').map((s) => s.id).toSet();
    setState(() {
      statusFilter = 'pending';
      selectionMode = true;
      selectedIds
        ..clear()
        ..addAll(pending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('students')) {
          return NoAccess(section: 'students', roleName: store.roleName);
        }
        final q = search.text.trim().toLowerCase();
        final yearStudents = store.studentsInViewedYear;
        final buckets = installmentBucketsByStudent(store.installments);
        final pendingCount = yearStudents.where((s) => s.status == 'pending').length;
        final pendingMode = statusFilter == 'pending';

        // شعب المرحلة المختارة فقط — مطابق لـ Students.tsx
        final sectionOptions = <String>{};
        if (grade.isNotEmpty) {
          for (final s in yearStudents) {
            if (s.gradeLevel.trim() != grade) continue;
            final sec = s.section.trim();
            if (sec.isNotEmpty) sectionOptions.add(sec);
          }
        }

        final list =
            yearStudents.where((s) {
                if (statusFilter.isEmpty) {
                  if (s.status == 'archived') return false;
                } else if (s.status != statusFilter) {
                  return false;
                }
                if (grade.isNotEmpty && s.gradeLevel.trim() != grade) return false;
                if (section.isNotEmpty) {
                  final sec = s.section.trim().replaceAll(RegExp(r'[()]'), '');
                  final want = section.replaceAll(RegExp(r'[()]'), '');
                  if (sec != want) return false;
                }
                if (customPlanOnly && !s.usesCustomPlan) return false;
                if (q.isEmpty) return true;
                return s.fullName.toLowerCase().contains(q) ||
                    s.phone.contains(q) ||
                    s.parentName.toLowerCase().contains(q) ||
                    s.parentPhone.contains(q) ||
                    s.nationalId.contains(q);
              }).toList()
              ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

        final canSelect = (customPlanOnly || pendingMode) && list.isNotEmpty && store.can('students');
        // المقام يستثني المؤرشفين حين الفلتر فارغ (كل الحالات) — مطابق للويب
        final countDenom = statusFilter.isEmpty
            ? yearStudents.where((s) => s.status != 'archived').length
            : yearStudents.length;
        // مراحل الإعدادات + أي مرحلة لطلاب العام غير موجودة في القائمة (محذوفة/قديمة)
        final gradeFilterOptions = <String, String>{
          '': 'كل المراحل',
          for (final g in store.gradeOptions) g: g,
        };
        for (final s in yearStudents) {
          final g = s.gradeLevel.trim();
          if (g.isNotEmpty && !gradeFilterOptions.containsKey(g)) {
            gradeFilterOptions[g] = g;
          }
        }

        return ThumbActionLayer(
          action: store.can('students')
              ? ThumbAction(
                  label: 'طالب جديد',
                  icon: Icons.person_add_alt_1,
                  onPressed: () {
                    if (store.gradeOptions.isEmpty) {
                      showAppSnack(
                        context,
                        'لا توجد مراحل دراسية معرّفة. أضفها أولاً من الإعدادات ← المراحل والرسوم.',
                        error: true,
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StudentFormScreen()),
                    );
                  },
                )
              : null,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SearchField(
                            controller: search,
                            hint: 'بحث بالاسم أو الهاتف...',
                            onChanged: (_) => setState(() {}),
                            trailing: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${list.length}',
                                    style: TextStyle(
                                      color: AppColors.heading,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (list.length != countDenom)
                                    TextSpan(
                                      text: '/$countDenom',
                                      style: const TextStyle(color: AppColors.faint),
                                    ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterButton(
                          value: grade,
                          options: gradeFilterOptions,
                          onSelected: _setGrade,
                        ),
                        const SizedBox(width: 6),
                        FilterButton(
                          value: statusFilter,
                          options: const {
                            '': 'كل الحالات',
                            'active': 'نشط',
                            'pending': 'بانتظار التأكيد',
                            'withdrawn': 'منسحب',
                            'archived': 'مؤرشف',
                            'completed': 'أنهى السنة',
                          },
                          onSelected: (v) => setState(() {
                            statusFilter = v;
                            if (v != 'pending' && !customPlanOnly) {
                              selectionMode = false;
                              selectedIds.clear();
                            }
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (grade.isNotEmpty && sectionOptions.isNotEmpty) ...[
                          FilterButton(
                            value: section,
                            options: {
                              '': 'كل الشعب',
                              for (final s in sectionOptions.toList()..sort())
                                s: s.replaceAll(RegExp(r'[()]'), ''),
                            },
                            onSelected: (v) => setState(() => section = v),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _ToggleChip(
                          label: 'خطة مخصصة',
                          on: customPlanOnly,
                          onTap: () => _setCustomPlanOnly(!customPlanOnly),
                        ),
                        if (canSelect) ...[
                          const SizedBox(width: 6),
                          _ToggleChip(
                            label: selectionMode ? 'إنهاء التحديد' : 'تحديد',
                            on: selectionMode,
                            onTap: () => setState(() {
                              selectionMode = !selectionMode;
                              if (!selectionMode) selectedIds.clear();
                            }),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (pendingCount > 0 && !pendingMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: InfoStrip(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$pendingCount طالب بانتظار التأكيد بعد الترقية — لا أقساط لسنتهم الجديدة حتى تأكيدهم',
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (store.can('students'))
                          TextButton(
                            onPressed: () => _openPendingSelection(store),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.amber,
                              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                            child: const Text('تأكيد الطلاب'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (selectionMode && canSelect)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          if (selectedIds.length == list.length) {
                            selectedIds.clear();
                          } else {
                            selectedIds
                              ..clear()
                              ..addAll(list.map((s) => s.id));
                          }
                        }),
                        child: Text(
                          selectedIds.length == list.length
                              ? 'إلغاء تحديد الكل'
                              : 'تحديد الكل (${list.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
                        ),
                      ),
                      Text(
                        'محدّد: ${selectedIds.length}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                      const Spacer(),
                      if (pendingMode)
                        PrimaryButton(
                          label: 'تأكيد المحدّدين (${selectedIds.length})',
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => _confirmSelected(store, list),
                        )
                      else if (customPlanOnly && store.can('finance.discount'))
                        PrimaryButton(
                          label: 'إرجاع المحددين لخطة المرحلة',
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => _returnSelected(store, list),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: EmptyState(message: 'لا توجد بيانات طلاب مطابقة للبحث'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, thumbActionClearance),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final student = list[i];
                          final hasPlan = store.installments.any((inst) => inst.studentId == student.id);
                          final due = buckets.due[student.id] ?? 0;
                          final scheduled = buckets.scheduled[student.id] ?? 0;
                          final shown = hasPlan ? -due : student.balance;
                          final selected = selectedIds.contains(student.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StudentCard(
                              student: student,
                              shownBalance: shown,
                              scheduled: scheduled,
                              hasPlan: hasPlan,
                              selectionMode: selectionMode,
                              selected: selected,
                              onToggleSelect: selectionMode
                                  ? () => setState(() {
                                      if (selected) {
                                        selectedIds.remove(student.id);
                                      } else {
                                        selectedIds.add(student.id);
                                      }
                                    })
                                  : null,
                              onConfirmPending: store.can('students') &&
                                      student.status == 'pending' &&
                                      !selectionMode
                                  ? () {
                                      try {
                                        final usesCustom = student.usesCustomPlan;
                                        final result = store.confirmPendingStudent(student.id);
                                        showAppSnack(
                                          context,
                                          result.planBuilt
                                              ? 'تم تأكيد تسجيل الطالب وبناء خطة أقساطه'
                                              : usesCustom
                                                  ? 'تم تأكيد تسجيل الطالب'
                                                  : 'تم التأكيد — بلا أقساط',
                                        );
                                      } on StoreException catch (e) {
                                        showAppSnack(context, e.message, error: true);
                                      }
                                    }
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.amberSoft : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? AppColors.amber : AppColors.line),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: on ? AppColors.amberDark : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// بطاقة الطالب — بعناصر `StudentMobileCard.tsx` في صفّ واحد.
class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.shownBalance,
    this.scheduled = 0,
    this.hasPlan = false,
    this.onConfirmPending,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
  });
  final Student student;
  final double shownBalance;
  final double scheduled;
  final bool hasPlan;
  final VoidCallback? onConfirmPending;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final phone = student.phone.trim().isNotEmpty
        ? student.phone.trim()
        : student.parentPhone.trim();
    final grade = student.gradeLevel.trim().isEmpty ? 'غير محدد' : student.gradeLevel.trim();
    final meta = student.section.trim().isEmpty
        ? grade
        : '$grade  ·  شعبة ${student.section.trim()}';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(6, 11, 12, 11),
      onTap: () {
        if (selectionMode && onToggleSelect != null) {
          onToggleSelect!();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StudentDetailScreen(studentId: student.id),
          ),
        );
      },
      child: Row(
        children: [
          if (selectionMode) ...[
            Checkbox(
              value: selected,
              activeColor: AppColors.amber,
              onChanged: (_) => onToggleSelect?.call(),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        student.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle.copyWith(fontSize: 14),
                      ),
                    ),
                    if (!student.isActiveStudent) ...[
                      const SizedBox(width: 6),
                      StudentStatusChip(status: student.status, compact: true),
                    ],
                    if (student.usesCustomPlan) ...[
                      const SizedBox(width: 6),
                      StatusChip.amber('مخصصة'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
                if (student.parentName.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'ولي الأمر: ${student.parentName.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11),
                  ),
                ] else if (student.phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    formatPhoneDisplay(student.phone, student.phonePrefix),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11),
                  ),
                ],
                if (onConfirmPending != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: onConfirmPending,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.amber,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'تأكيد',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ),
                ],
                if (selectionMode)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StudentDetailScreen(studentId: student.id),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'فتح',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (StoreScope.of(context).can('finance'))
                DueStatus(
                  kind: shownBalance.abs() <= cent
                      ? DueStatusKind.clear
                      : shownBalance < 0
                          ? DueStatusKind.due
                          : DueStatusKind.credit,
                  amount: shownBalance.abs(),
                  scheduled: scheduled,
                  clearLabel: hasPlan ? 'لا مستحق' : 'خالص',
                  compact: true,
                ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContactIconButton(
                      tooltip: 'اتصال هاتفي',
                      onTap: () => launchTel(phone),
                      child: const Icon(Icons.phone_outlined, size: 18, color: AppColors.muted),
                    ),
                    ContactIconButton(
                      tooltip: 'مراسلة واتساب',
                      onTap: () => launchWa(phone),
                      child: const MessageCircleIcon(color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (!selectionMode) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
          ],
        ],
      ),
    );
  }
}
