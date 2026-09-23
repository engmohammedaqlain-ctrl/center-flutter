import 'package:flutter/material.dart';

import '../data/balance.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import '../widgets/list_paging.dart';
import '../widgets/table_gate.dart';
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
  int visibleCount = kListPageSize;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _setGrade(String v) {
    setState(() {
      grade = v;
      section = '';
      visibleCount = kListPageSize;
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

  /// ضغطة واحدة من البانر: تأكيد كل المنتظرين بلا دخول وضع التحديد.
  Future<void> _confirmAllPending(AppStore store) async {
    final pending = store.studentsInViewedYear
        .where((s) => s.status == 'pending')
        .toList();
    if (pending.isEmpty) return;
    final ids = pending.map((s) => s.id).toList();
    final ok = await confirmSheet(
      context,
      title: 'تأكيد التسجيل',
      message: ids.length == 1
          ? 'تأكيد تسجيل ${pending.first.fullName} وبناء أقساط السنة الجديدة؟'
          : 'تأكيد تسجيل ${ids.length} طلاب وبناء أقساط سنتهم الجديدة؟',
      confirmLabel: ids.length == 1 ? 'تأكيد' : 'تأكيد الكل',
      confirmColor: AppColors.heading,
    );
    if (!ok || !mounted) return;
    try {
      final result = store.confirmPendingStudents(ids);
      setState(() {
        selectedIds.clear();
        selectionMode = false;
        if (statusFilter == 'pending') statusFilter = '';
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

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return TableGate(
      tables: const ['students', 'student_years', 'installments'],
      message: 'جارٍ تحميل الطلاب...',
      child: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('students')) {
          return NoAccess(section: 'students', roleName: store.roleName);
        }
        final q = search.text.trim().toLowerCase();
        final yearStudents = store.studentsInViewedYear;
        final buckets = store.installmentBuckets;
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

        final page = listPage(list, visibleCount);
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SearchField(
                            controller: search,
                            hint: 'بحث بالاسم أو الهاتف أو الهوية…',
                            onChanged: (_) => setState(() => visibleCount = kListPageSize),
                            trailing: Text(
                              list.length == countDenom
                                  ? '$countDenom'
                                  : '${list.length}/$countDenom',
                              style: TextStyle(
                                fontFamily: AppText.family,
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _FilterIconButton(
                          active: grade.isNotEmpty ||
                              statusFilter.isNotEmpty ||
                              section.isNotEmpty ||
                              customPlanOnly,
                          onTap: () => _openFiltersSheet(
                            context,
                            gradeOptions: gradeFilterOptions,
                          ),
                        ),
                        if (canSelect) ...[
                          const SizedBox(width: 6),
                          _FilterIconButton(
                            icon: selectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded,
                            active: selectionMode,
                            tooltip: selectionMode ? 'إنهاء التحديد' : 'تحديد',
                            onTap: () => setState(() {
                              selectionMode = !selectionMode;
                              if (!selectionMode) selectedIds.clear();
                            }),
                          ),
                        ],
                      ],
                    ),
                    // الفلاتر المفعّلة في سطر تحت البحث: كثرتها لا تضيّق حقل البحث
                    if (!selectionMode &&
                        (grade.isNotEmpty ||
                            statusFilter.isNotEmpty ||
                            section.isNotEmpty ||
                            customPlanOnly)) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (grade.isNotEmpty)
                                _ActiveFilterChip(
                                  label: grade,
                                  onClear: () => _setGrade(''),
                                ),
                              if (section.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                _ActiveFilterChip(
                                  label: section.startsWith('شعبة') ? section : 'شعبة $section',
                                  onClear: () => setState(() => section = ''),
                                ),
                              ],
                              if (statusFilter.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                _ActiveFilterChip(
                                  label: switch (statusFilter) {
                                    'active' => 'نشط',
                                    'pending' => 'بانتظار التأكيد',
                                    'withdrawn' => 'منسحب',
                                    'archived' => 'مؤرشف',
                                    'completed' => 'أنهى السنة',
                                    _ => statusFilter,
                                  },
                                  onClear: () => setState(() {
                                    statusFilter = '';
                                    if (!customPlanOnly) {
                                      selectionMode = false;
                                      selectedIds.clear();
                                    }
                                  }),
                                ),
                              ],
                              if (customPlanOnly) ...[
                                const SizedBox(width: 4),
                                _ActiveFilterChip(
                                  label: 'خطة مخصصة',
                                  onClear: () => _setCustomPlanOnly(false),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              if (pendingCount > 0 && !pendingMode && !selectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: _PendingNotice(
                    count: pendingCount,
                    onConfirm: store.can('students')
                        ? () => _confirmAllPending(store)
                        : null,
                  ),
                ),
              if (selectionMode && canSelect)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
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
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          selectedIds.length == list.length ? 'إلغاء التحديد' : 'تحديد الكل',
                          style: TextStyle(
                            fontFamily: AppText.family,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: AppColors.heading,
                          ),
                        ),
                      ),
                      Text(
                        pendingMode
                            ? '${selectedIds.length} بانتظار التأكيد'
                            : '${selectedIds.length} محدّد',
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: AppColors.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (pendingMode)
                        PrimaryButton(
                          label: selectedIds.isEmpty ? 'تأكيد' : 'تأكيد (${selectedIds.length})',
                          height: 40,
                          onPressed: selectedIds.isEmpty ? null : () => _confirmSelected(store, list),
                        )
                      else if (customPlanOnly && store.can('finance.discount'))
                        PrimaryButton(
                          label: 'إرجاع لخطة المرحلة',
                          height: 40,
                          onPressed: selectedIds.isEmpty ? null : () => _returnSelected(store, list),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: EmptyState(message: 'لا توجد بيانات طلاب مطابقة للبحث'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, thumbActionClearance),
                        itemCount: page.length + (page.length < list.length ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= page.length) {
                            return LoadMoreButton(
                              shown: page.length,
                              total: list.length,
                              onMore: () => setState(() => visibleCount += kListPageSize),
                            );
                          }
                          final student = page[i];
                          final hasPlan = store.installments.any((inst) => inst.studentId == student.id);
                          final due = buckets.due[student.id] ?? 0;
                          final scheduled = buckets.scheduled[student.id] ?? 0;
                          final shownBalance = hasPlan ? -due : student.balance;
                          final selected = selectedIds.contains(student.id);
                          return _StudentCard(
                            student: student,
                            shownBalance: shownBalance,
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
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  Future<void> _openFiltersSheet(
    BuildContext context, {
    required Map<String, String> gradeOptions,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
      ),
      builder: (ctx) {
        var draftGrade = grade;
        var draftSection = section;
        var draftStatus = statusFilter;
        var draftCustom = customPlanOnly;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final sections = <String>{};
            if (draftGrade.isNotEmpty) {
              for (final s in StoreScope.of(context).studentsInViewedYear) {
                if (s.gradeLevel.trim() != draftGrade) continue;
                final sec = s.section.trim();
                if (sec.isNotEmpty) sections.add(sec);
              }
            }
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.paddingOf(ctx).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.lineStrong,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('تصفية القائمة', style: AppText.title),
                    const SizedBox(height: 18),
                    Text('المرحلة', style: AppText.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in gradeOptions.entries)
                          SheetChoiceChip(
                            label: e.value,
                            selected: draftGrade == e.key,
                            onTap: () => setSheet(() {
                              draftGrade = e.key;
                              draftSection = '';
                            }),
                          ),
                      ],
                    ),
                    if (sections.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('الشعبة', style: AppText.label),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SheetChoiceChip(
                            label: 'كل الشعب',
                            selected: draftSection.isEmpty,
                            onTap: () => setSheet(() => draftSection = ''),
                          ),
                          for (final s in sections.toList()..sort())
                            SheetChoiceChip(
                              label: s.replaceAll(RegExp(r'[()]'), ''),
                              selected: draftSection == s,
                              onTap: () => setSheet(() => draftSection = s),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('الحالة', style: AppText.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in const {
                          '': 'كل الحالات',
                          'active': 'نشط',
                          'pending': 'بانتظار التأكيد',
                          'withdrawn': 'منسحب',
                          'archived': 'مؤرشف',
                          'completed': 'أنهى السنة',
                        }.entries)
                          SheetChoiceChip(
                            label: e.value,
                            selected: draftStatus == e.key,
                            onTap: () => setSheet(() => draftStatus = e.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('خطة مخصصة فقط', style: AppText.cardTitle.copyWith(fontSize: 14)),
                      value: draftCustom,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => setSheet(() => draftCustom = v),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      expand: true,
                      label: 'تطبيق التصفية',
                      height: 48,
                      onPressed: () {
                        setState(() {
                          grade = draftGrade;
                          section = draftSection;
                          statusFilter = draftStatus;
                          customPlanOnly = draftCustom;
                          if (draftStatus != 'pending' && !draftCustom) {
                            selectionMode = false;
                            selectedIds.clear();
                          }
                        });
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.onTap,
    this.active = false,
    this.icon = Icons.tune_rounded,
    this.tooltip,
  });

  final VoidCallback onTap;
  final bool active;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = PressableScale(
      onTap: onTap,
      child: Container(
        width: controlHeight,
        height: controlHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.amberSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(Corner.field),
          border: Border.all(color: active ? AppColors.amberBorder : AppColors.line),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? AppColors.amberDark : AppColors.muted,
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onClear,
        borderRadius: BorderRadius.circular(Corner.chip),
        child: Container(
          height: 28,
          padding: const EdgeInsetsDirectional.only(start: 8, end: 6),
          decoration: BoxDecoration(
            color: AppColors.amberSoft,
            borderRadius: BorderRadius.circular(Corner.chip),
            border: Border.all(color: AppColors.amberBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppText.family,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.amberDark,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.close_rounded, size: 14, color: AppColors.amberDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.count, this.onConfirm});

  final int count;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final cta = count == 1 ? 'تأكيد' : 'تأكيد الكل';
    return Material(
      color: AppColors.amberSoft,
      borderRadius: BorderRadius.circular(Corner.field),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(Corner.box),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: AppText.family,
                  color: AppColors.amberDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'بانتظار تأكيد التسجيل',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'بعد التأكيد تُبنى أقساط السنة الجديدة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (onConfirm != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: PrimaryButton(
                  label: cta,
                  height: 36,
                  onPressed: onConfirm,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة طالب بريميوم: أفاتار + اسم/مرحلة + شارة مالية مرتبة.
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

  String get _metaLine {
    final grade = student.gradeLevel.trim().isEmpty ? 'غير محدد' : student.gradeLevel.trim();
    final raw = student.section.trim();
    if (raw.isEmpty) return grade;
    final section = raw.startsWith('شعبة') ? raw : 'شعبة $raw';
    return '$grade · $section';
  }

  @override
  Widget build(BuildContext context) {
    final pending = student.status == 'pending';
    final showFinance = StoreScope.of(context).can('finance') && !pending;
    final shape = BorderRadius.circular(Corner.card);

    Widget trailing;
    if (selectionMode) {
      trailing = Checkbox(
        value: selected,
        activeColor: AppColors.amber,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (_) => onToggleSelect?.call(),
      );
    } else if (onConfirmPending != null) {
      trailing = _QuietAction(label: 'تأكيد', onTap: onConfirmPending!);
    } else if (showFinance) {
      trailing = _FinanceChip(
        shownBalance: shownBalance,
        scheduled: scheduled,
        hasPlan: hasPlan,
      );
    } else if (!student.isActiveStudent) {
      trailing = StudentStatusChip(status: student.status, compact: true);
    } else if (student.usesCustomPlan) {
      trailing = StatusChip.amber('مخصصة');
    } else {
      trailing = const AppChevron(size: 20);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
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
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: shape,
              border: Border.all(
                color: selected ? AppColors.accent.withValues(alpha: 0.35) : AppColors.line,
              ),
              boxShadow: cardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.cardTitle.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _metaLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            color: AppColors.muted,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر صف مضغوط بنفس لغة PrimaryButton — لا إطار أبيض خفيف يُشبه «مراجعة».
class _QuietAction extends StatelessWidget {
  const _QuietAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.heading,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corner.box),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

/// شارة مالية مرتبة — مبلغ بارز، والمجدول تحته بخط ثانوي.
class _FinanceChip extends StatelessWidget {
  const _FinanceChip({
    required this.shownBalance,
    required this.scheduled,
    required this.hasPlan,
  });

  final double shownBalance;
  final double scheduled;
  final bool hasPlan;

  @override
  Widget build(BuildContext context) {
    final clear = shownBalance.abs() <= cent;
    if (clear) {
      return StatusChip.success(hasPlan ? 'مسدد' : 'خالص');
    }

    final due = shownBalance < 0;
    final amount = money(shownBalance.abs());
    final fg = due ? const Color(0xFFAE2A19) : AppColors.heading;
    final bg = due ? AppColors.dangerSoft : AppColors.hover;
    final border = due ? AppColors.dangerBorder : AppColors.lineStrong;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Corner.chip),
            border: Border.all(color: border),
          ),
          child: Text(
            amount,
            style: TextStyle(
              fontFamily: AppText.family,
              color: fg,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
        if (scheduled > 0) ...[
          const SizedBox(height: 4),
          Text(
            'مجدول ${money(scheduled)}',
            style: TextStyle(
              fontFamily: AppText.family,
              color: AppColors.faint,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
