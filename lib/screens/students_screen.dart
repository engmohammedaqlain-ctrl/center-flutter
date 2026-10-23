import 'package:flutter/material.dart';

import '../data/arabic_search.dart';
import '../data/balance.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
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
                return matchStudentSearch(
                  fullName: s.fullName,
                  query: search.text,
                  phone: s.phone,
                  parentPhone: s.parentPhone,
                  nationalId: s.nationalId,
                  parentName: s.parentName,
                  parentNationalId: s.parentNationalId,
                );
              }).toList();

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

        // حالات طلاب العام وحدها في ورقة التصفية — مطابق لـ presentStatuses في Students.tsx
        final presentStatuses = {for (final s in yearStudents) s.status};
        final hidden = list.length - page.length;
        final filtersActive = grade.isNotEmpty || statusFilter.isNotEmpty || section.isNotEmpty || customPlanOnly;

        return ThumbActionLayer(
          action: store.can('students')
              ? ThumbAction(
                  label: 'طالب جديد',
                  icon: Icons.person_add_alt_1,
                  color: AdminNoon.action,
                  foreground: AdminNoon.onAction,
                  noon: true,
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
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // البحث وعدد الطلاب، وزر التصفية وزر التحديد
                    Row(
                      children: [
                        Expanded(
                          child: NoonSearchField(
                            controller: search,
                            hint: 'بحث بالاسم أو الهاتف أو الهوية',
                            onChanged: (_) => setState(() => visibleCount = kListPageSize),
                            count: list.length == countDenom ? '$countDenom' : '${list.length}/$countDenom',
                          ),
                        ),
                        const SizedBox(width: 6),
                        NoonButton(
                          icon: Icons.tune_rounded,
                          tooltip: 'تصفية',
                          size: 44,
                          tone: filtersActive ? NoonTone.ink : NoonTone.line,
                          onPressed: () => _openFiltersSheet(
                            context,
                            gradeOptions: gradeFilterOptions,
                            presentStatuses: presentStatuses,
                          ),
                        ),
                        if (canSelect) ...[
                          const SizedBox(width: 6),
                          NoonButton(
                            icon: selectionMode ? Icons.close_rounded : Icons.checklist_rtl_rounded,
                            tooltip: selectionMode ? 'إنهاء التحديد' : 'تحديد',
                            size: 44,
                            tone: selectionMode ? NoonTone.ink : NoonTone.line,
                            onPressed: () => setState(() {
                              selectionMode = !selectionMode;
                              if (!selectionMode) selectedIds.clear();
                            }),
                          ),
                        ],
                      ],
                    ),
                    // الفلاتر المفعّلة تحت البحث، كل واحد يُلغى بلمسه
                    if (!selectionMode && filtersActive) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 28,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (grade.isNotEmpty)
                                NoonActiveChip(
                                  label: grade,
                                  onClear: () => _setGrade(''),
                                ),
                              if (section.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                NoonActiveChip(
                                  label: section.startsWith('شعبة')
                                      ? section
                                      : 'شعبة ${section.replaceAll(RegExp(r'[()]'), '').trim()}',
                                  onClear: () => setState(() => section = ''),
                                ),
                              ],
                              if (statusFilter.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                NoonActiveChip(
                                  label: studentStatusLabel(statusFilter),
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
                                const SizedBox(width: 6),
                                NoonActiveChip(
                                  label: 'خطة مخصصة',
                                  onClear: () => _setCustomPlanOnly(false),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    // بانتظار التأكيد: بطاقة تفتح تأكيدهم كلهم
                    if (pendingCount > 0 && !pendingMode && !selectionMode) ...[
                      const SizedBox(height: 8),
                      _PendingNotice(
                        count: pendingCount,
                        onConfirm: store.can('students') ? () => _confirmAllPending(store) : null,
                      ),
                    ],
                    // شريط التحديد
                    if (selectionMode && canSelect) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: noonPanel(),
                        child: Row(
                          children: [
                            NoonButton(
                              label: selectedIds.length == list.length ? 'إلغاء التحديد' : 'تحديد الكل',
                              tone: NoonTone.ghost,
                              small: true,
                              onPressed: () => setState(() {
                                if (selectedIds.length == list.length) {
                                  selectedIds.clear();
                                } else {
                                  selectedIds
                                    ..clear()
                                    ..addAll(list.map((s) => s.id));
                                }
                              }),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pendingMode ? '${selectedIds.length} بانتظار التأكيد' : '${selectedIds.length} محدّد',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted),
                              ),
                            ),
                            if (pendingMode)
                              NoonButton(
                                label: selectedIds.isEmpty ? 'تأكيد' : 'تأكيد (${selectedIds.length})',
                                tone: NoonTone.ink,
                                small: true,
                                onPressed: selectedIds.isEmpty ? null : () => _confirmSelected(store, list),
                              )
                            else if (customPlanOnly && store.can('finance.discount'))
                              NoonButton(
                                label: 'إرجاع لخطة المرحلة',
                                tone: NoonTone.ink,
                                small: true,
                                onPressed: selectedIds.isEmpty ? null : () => _returnSelected(store, list),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: NoonEmpty('لا توجد بيانات طلاب مطابقة للبحث'),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, thumbActionClearance),
                        itemCount: page.length + (hidden > 0 ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= page.length) {
                            return NoonButton(
                              label: 'عرض المزيد ($hidden)',
                              tone: NoonTone.ghost,
                              expand: true,
                              onPressed: () => setState(() => visibleCount += kListPageSize),
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
    required Set<String> presentStatuses,
  }) async {
    var draftGrade = grade;
    var draftSection = section;
    var draftStatus = statusFilter;
    var draftCustom = customPlanOnly;
    final yearStudents = StoreScope.of(context).studentsInViewedYear;
    await showNoonSheet<void>(
      context,
      title: 'تصفية القائمة',
      body: (ctx, setSheet) {
        final sections = <String>{};
        if (draftGrade.isNotEmpty) {
          for (final s in yearStudents) {
            if (s.gradeLevel.trim() != draftGrade) continue;
            final sec = s.section.trim();
            if (sec.isNotEmpty) sections.add(sec);
          }
        }
        Widget group(String label, List<Widget> chips) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NoonSheetLabel(label),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
              ],
            );
        return [
          group('المرحلة', [
            for (final e in gradeOptions.entries)
              NoonSheetChip(
                label: e.value,
                selected: draftGrade == e.key,
                onTap: () => setSheet(() {
                  draftGrade = e.key;
                  draftSection = '';
                }),
              ),
          ]),
          if (sections.isNotEmpty)
            group('الشعبة', [
              NoonSheetChip(
                label: 'كل الشعب',
                selected: draftSection.isEmpty,
                onTap: () => setSheet(() => draftSection = ''),
              ),
              for (final s in sections.toList()..sort())
                NoonSheetChip(
                  label: s.replaceAll(RegExp(r'[()]'), '').trim(),
                  selected: draftSection == s,
                  onTap: () => setSheet(() => draftSection = s),
                ),
            ]),
          group('الحالة', [
            NoonSheetChip(
              label: 'كل الحالات',
              selected: draftStatus.isEmpty,
              onTap: () => setSheet(() => draftStatus = ''),
            ),
            for (final st in studentStatusLabels.keys)
              if (presentStatuses.contains(st) || st == draftStatus)
                NoonSheetChip(
                  label: studentStatusLabel(st),
                  selected: draftStatus == st,
                  onTap: () => setSheet(() => draftStatus = st),
                ),
          ]),
          InkWell(
            onTap: () => setSheet(() => draftCustom = !draftCustom),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('خطة مخصصة فقط', style: NoonText.style(14, weight: FontWeight.w700)),
                  ),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: draftCustom,
                      activeColor: AdminNoon.ink,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setSheet(() => draftCustom = v ?? false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];
      },
      footer: (ctx, _) => [
        Expanded(
          child: NoonButton(
            label: 'تطبيق التصفية',
            tone: NoonTone.ink,
            expand: true,
            onPressed: () {
              setState(() {
                grade = draftGrade;
                section = draftSection;
                statusFilter = draftStatus;
                customPlanOnly = draftCustom;
                visibleCount = kListPageSize;
                if (draftStatus != 'pending' && !draftCustom) {
                  selectionMode = false;
                  selectedIds.clear();
                }
              });
              Navigator.pop(ctx);
            },
          ),
        ),
      ],
    );
  }
}

/// بانتظار التأكيد — لوح بعدد بوسم الشمس وزر «تأكيد / تأكيد الكل».
class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.count, this.onConfirm});

  final int count;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: noonPanel(),
      child: Row(
        children: [
          NoonBadge('$count', tone: NoonBadgeTone.sun),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'بانتظار تأكيد التسجيل',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NoonText.style(13.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'بعد التأكيد تُبنى أقساط السنة الجديدة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NoonText.style(11.5, color: AdminNoon.muted),
                ),
              ],
            ),
          ),
          if (onConfirm != null) ...[
            const SizedBox(width: 10),
            NoonButton(
              label: count == 1 ? 'تأكيد' : 'تأكيد الكل',
              tone: NoonTone.ink,
              small: true,
              onPressed: onConfirm,
            ),
          ],
        ],
      ),
    );
  }
}

/// بطاقة طالب كالويب على الجوال: الاسم، وسطر «المرحلة · الشعبة · الحالة · خطة مخصصة»،
/// وفي طرفها المستحق أو زر التأكيد أو مربع التحديد.
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
    final pending = student.status == 'pending';
    final showFinance = StoreScope.of(context).can('finance') && !pending;
    final grade = student.gradeLevel.trim().isEmpty ? 'غير محدد' : student.gradeLevel.trim();
    final raw = student.section.trim();
    final status = student.status == 'inactive' ? 'withdrawn' : student.status;
    final showStatus = status != 'active' && status != 'completed' && studentStatusLabels.containsKey(status);

    Widget trailing;
    if (selectionMode) {
      trailing = Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AdminNoon.ink : null,
          borderRadius: BorderRadius.circular(AdminNoon.rTag),
          border: Border.all(color: selected ? AdminNoon.ink : AdminNoon.muted, width: 2),
        ),
        child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
      );
    } else if (onConfirmPending != null) {
      trailing = NoonButton(label: 'تأكيد', tone: NoonTone.ink, small: true, onPressed: onConfirmPending);
    } else if (showFinance) {
      trailing = _FinanceChip(shownBalance: shownBalance, scheduled: scheduled, hasPlan: hasPlan);
    } else {
      trailing = AppChevron(size: 20, color: AdminNoon.faint);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NoonTapPanel(
        selected: selected,
        onTap: () {
          if (selectionMode && onToggleSelect != null) {
            onToggleSelect!();
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: student.id)),
          );
        },
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
                    style: NoonText.style(15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: grade),
                        if (raw.isNotEmpty) TextSpan(text: ' · ${raw.startsWith('شعبة') ? raw : 'شعبة $raw'}'),
                        if (showStatus)
                          TextSpan(
                            text: ' · ${studentStatusLabel(status)}',
                            style: TextStyle(color: Color(studentStatusColors[status]!)),
                          ),
                        if (student.usesCustomPlan) const TextSpan(text: ' · خطة مخصصة'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NoonText.style(12, color: AdminNoon.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// المستحق في طرف البطاقة — `MobileFinance`: المبلغ بوسم، و«قادم» تحته خافتاً.
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
    if (shownBalance.abs() <= cent) {
      return NoonBadge(
        hasPlan ? (scheduled > 0 ? 'مسدد حتى الآن' : 'مسدد') : 'خالص',
        tone: NoonBadgeTone.green,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        NoonBadge(
          money(shownBalance.abs()),
          tone: shownBalance < 0 ? NoonBadgeTone.red : NoonBadgeTone.neutral,
          height: 24,
          fontSize: 12,
        ),
        if (scheduled > 0) ...[
          const SizedBox(height: 4),
          Text(
            'قادم ${money(scheduled)}',
            style: NoonText.style(10.5, weight: FontWeight.w600, color: AdminNoon.muted),
          ),
        ],
      ],
    );
  }
}
