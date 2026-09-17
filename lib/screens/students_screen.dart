import 'package:flutter/material.dart';

import '../data/balance.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
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

  /// فارغ = إخفاء المؤرشفين (افتراضي الويب)؛ قيمة حالة = فلتر بها.
  String statusFilter = '';

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
        if (!store.canOpenSection('students')) {
          return NoAccess(section: 'students', roleName: store.roleName);
        }
        final q = search.text.trim().toLowerCase();
        final yearStudents = store.studentsInViewedYear;
        final dueMap = overdueByStudent(store.installmentsInViewedYear);
        final list =
            yearStudents.where((s) {
                // المؤرشف مخفي افتراضياً — مطابق لـ Students.tsx
                if (statusFilter.isEmpty) {
                  if (s.status == 'archived') return false;
                } else if (s.status != statusFilter) {
                  return false;
                }
                if (grade.isNotEmpty && s.gradeLevel.trim() != grade)
                  return false;
                if (q.isEmpty) return true;
                return s.fullName.toLowerCase().contains(q) ||
                    s.phone.contains(q) ||
                    s.parentName.toLowerCase().contains(q) ||
                    s.parentPhone.contains(q) ||
                    s.nationalId.contains(q);
              }).toList()
              // الأحدث تسجيلاً أولاً — مطابق لفرز Students.tsx
              ..sort(
                (a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''),
              );

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
                      MaterialPageRoute(
                        builder: (_) => const StudentFormScreen(),
                      ),
                    );
                  },
                )
              : null,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
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
                              if (list.length != yearStudents.length)
                                TextSpan(
                                  text: '/${yearStudents.length}',
                                  style: const TextStyle(
                                    color: AppColors.faint,
                                  ),
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
                      options: {
                        '': 'كل المراحل',
                        for (final g in store.gradeOptions) g: g,
                      },
                      onSelected: (v) => setState(() => grade = v),
                    ),
                    const SizedBox(width: 6),
                    FilterButton(
                      value: statusFilter,
                      options: const {
                        '': 'غير المؤرشفين',
                        'active': 'نشط',
                        'pending': 'معلق',
                        'withdrawn': 'منسحب',
                        'archived': 'مؤرشف',
                      },
                      onSelected: (v) => setState(() => statusFilter = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: EmptyState(
                          message: 'لا توجد بيانات طلاب مطابقة للبحث',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          thumbActionClearance,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final student = list[i];
                          final hasPlan = store.installmentsInViewedYear.any(
                            (inst) => inst.studentId == student.id,
                          );
                          final due = dueMap[student.id] ?? 0;
                          // من له خطة: المستحق الحالّ؛ بلا خطة: الرصيد — StudentTable.tsx
                          final shown = hasPlan ? -due : student.balance;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StudentCard(
                              student: student,
                              shownBalance: shown,
                              onConfirmPending:
                                  store.can('students') &&
                                      student.status == 'pending'
                                  ? () {
                                      try {
                                        final result = store
                                            .confirmPendingStudent(student.id);
                                        showAppSnack(
                                          context,
                                          result.planBuilt
                                              ? 'تم تأكيد تسجيل الطالب وبناء خطة أقساطه'
                                              : 'تم تأكيد تسجيل الطالب',
                                        );
                                      } on StoreException catch (e) {
                                        showAppSnack(
                                          context,
                                          e.message,
                                          error: true,
                                        );
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

/// بطاقة الطالب — بعناصر `StudentMobileCard.tsx` في صفّ واحد.
class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.shownBalance,
    this.onConfirmPending,
  });
  final Student student;
  final double shownBalance;
  final VoidCallback? onConfirmPending;

  @override
  Widget build(BuildContext context) {
    final phone = student.phone.trim().isNotEmpty
        ? student.phone.trim()
        : student.parentPhone.trim();
    final grade = student.gradeLevel.trim().isEmpty
        ? 'غير محدد'
        : student.gradeLevel.trim();
    final meta = student.section.trim().isEmpty
        ? grade
        : '$grade  ·  شعبة ${student.section.trim()}';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(6, 11, 12, 11),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StudentDetailScreen(studentId: student.id),
          ),
        );
      },
      child: Row(
        children: [
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
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                  ),
                ),
                if (student.parentName.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'ولي الأمر: ${student.parentName.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.faint,
                      fontSize: 11,
                    ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'تأكيد',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (StoreScope.of(context).can('finance'))
                _BalanceText(balance: shownBalance),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContactIconButton(
                      tooltip: 'اتصال هاتفي',
                      onTap: () => launchTel(phone),
                      child: const Icon(
                        Icons.phone_outlined,
                        size: 18,
                        color: AppColors.muted,
                      ),
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
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
        ],
      ),
    );
  }
}

/// الرصيد نصاً هادئاً بلونه — بلا شارة ولا خلفية تنافس الاسم.
class _BalanceText extends StatelessWidget {
  const _BalanceText({required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context) {
    final (text, color) = balance < 0
        ? ('عليه ${money(balance)}', AppColors.danger)
        : ('مسدد', AppColors.success);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
