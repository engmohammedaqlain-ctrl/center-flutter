import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'attendance_print.dart';

/// كشف الحضور الأسبوعي — المقابل لـ `pages/Attendance.tsx`.
///
/// الأسبوع المدرسي كامل (السبت → الخميس) مع التنقّل بين الأسابيع، لا يوم واحد.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int weekOffset = 0;
  String? grade;
  String? ownerId;
  String saved = '';

  void _flash(String msg) {
    setState(() => saved = msg);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && saved == msg) setState(() => saved = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('attendance')) {
          return NoAccess(section: 'attendance', roleName: store.roleName);
        }

        final week = AppStore.schoolWeek(weekOffset);
        final school = store.isSchool;
        final canEdit = store.can('attendance.edit');

        // نظام المدرسة: المرحلة ثم الشعبة. نظام المركز: المجموعة مباشرة.
        final grades = school
            ? store.rooms.map((r) => r.gradeLevel).where((g) => g.trim().isNotEmpty).toSet().toList()
            : <String>[];
        final currentGrade = school
            ? (grade != null && grades.contains(grade) ? grade : (grades.isNotEmpty ? grades.first : null))
            : null;
        final owners = school
            ? store.rooms.where((r) => currentGrade == null || r.gradeLevel == currentGrade).toList()
            : store.groups.where((g) => g.isActive).toList();

        final ownerIds = school
            ? owners.cast<Classroom>().map((r) => r.id).toList()
            : owners.cast<Group>().map((g) => g.id).toList();
        final currentOwner =
            (ownerId != null && ownerIds.contains(ownerId)) ? ownerId! : (ownerIds.isNotEmpty ? ownerIds.first : '');

        final list = currentOwner.isEmpty
            ? <Student>[]
            : school
                ? store.studentsOf(store.rooms.firstWhere((r) => r.id == currentOwner))
                : store.studentsInGroup(currentOwner);

        final ownerName = currentOwner.isEmpty
            ? ''
            : school
                ? store.rooms.firstWhere((r) => r.id == currentOwner).name
                : store.groupById(currentOwner)?.name ?? '';

        final today = week.where((d) => d.isToday).firstOrNull ?? week.first;
        var present = 0, absent = 0, unmarked = 0;
        for (final s in list) {
          switch (store.attendanceInSession(currentOwner, s.id, today.dateStr)) {
            case 'present':
            case 'late':
              present++;
            case 'absent':
              absent++;
            default:
              unmarked++;
          }
        }

        return Column(
          children: [
            _controls(
              context,
              store: store,
              school: school,
              grades: grades,
              currentGrade: currentGrade,
              owners: owners,
              currentOwner: currentOwner,
              week: week,
            ),
            Expanded(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: EmptyState(message: 'لا يوجد طلاب مسجلون في هذا الصف/المجموعة'),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: [
                        _todayCard(
                          store: store,
                          today: today,
                          list: list,
                          owner: currentOwner,
                          present: present,
                          absent: absent,
                          unmarked: unmarked,
                          canEdit: canEdit,
                        ),
                        const SizedBox(height: 8),
                        _legend(),
                        const SizedBox(height: 8),
                        for (var i = 0; i < list.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _StudentWeekRow(
                              index: i + 1,
                              student: list[i],
                              week: week,
                              owner: currentOwner,
                              canEdit: canEdit,
                              onCycle: (dateStr) {
                                store.cycleAttendance(list[i].id, dateStr, ownerId: currentOwner);
                                _flash('تم الحفظ تلقائياً');
                              },
                              onPick: (dateStr) => _pickStatus(context, store, list[i], dateStr, currentOwner),
                            ),
                          ),
                        const SizedBox(height: 10),
                        GhostButton(
                          label: 'طباعة كشف الأسبوع',
                          icon: Icons.print_outlined,
                          onPressed: currentOwner.isEmpty
                              ? null
                              : () => printWeeklyAttendance(
                                    context,
                                    store: store,
                                    title: ownerName,
                                    week: week,
                                    students: list,
                                    ownerId: currentOwner,
                                  ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _controls(
    BuildContext context, {
    required AppStore store,
    required bool school,
    required List<String> grades,
    required String? currentGrade,
    required List<Object> owners,
    required String currentOwner,
    required List<SchoolDay> week,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: AppCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                if (school) ...[
                  Expanded(
                    child: AppDropdown<String>(
                      value: currentGrade,
                      items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => setState(() {
                        grade = v;
                        ownerId = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: AppDropdown<String>(
                    value: currentOwner.isEmpty ? null : currentOwner,
                    items: [
                      for (final o in owners)
                        if (o is Classroom)
                          DropdownMenuItem(value: o.id, child: Text(o.name))
                        else if (o is Group)
                          DropdownMenuItem(value: o.id, child: Text(o.name)),
                    ],
                    onChanged: (v) => setState(() => ownerId = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SquareIconButton(icon: Icons.chevron_right, onTap: () => setState(() => weekOffset--)),
                Expanded(
                  child: Center(
                    child: Text(
                      weekOffset == 0
                          ? 'الأسبوع الحالي (${week.first.shortDate} - ${week.last.shortDate})'
                          : 'أسبوع ${week.first.shortDate} - ${week.last.shortDate}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
                    ),
                  ),
                ),
                SquareIconButton(icon: Icons.chevron_left, onTap: () => setState(() => weekOffset++)),
                if (weekOffset != 0) ...[
                  const SizedBox(width: 6),
                  GhostButton(label: 'اليوم', onPressed: () => setState(() => weekOffset = 0)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayCard({
    required AppStore store,
    required SchoolDay today,
    required List<Student> list,
    required String owner,
    required int present,
    required int absent,
    required int unmarked,
    required bool canEdit,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رصد حضور اليوم: ${today.dayName} (${today.shortDate})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    text: 'إجمالي الصف: ${list.length} طالب  ',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    children: [
                      TextSpan(text: '• حاضر: $present  ', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                      TextSpan(text: '• غائب: $absent  ', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
                      TextSpan(text: '• غير مرصود: $unmarked', style: const TextStyle(color: AppColors.faint, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (saved.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(saved, style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          PrimaryButton(
            label: 'الكل حاضر',
            icon: Icons.done_all,
            color: AppColors.success,
            onPressed: list.isEmpty || !canEdit
                ? null
                : () {
                    store.markAllPresent(today.dateStr, list, ownerId: owner);
                    _flash('تم رصد جميع طلاب الصف كحاضرين بنجاح');
                  },
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          const Text('انقر للتبديل · اضغط مطولاً للمزيد', style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
          const Spacer(),
          for (final e in attendanceStatusNames.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 9, height: 9, color: _statusColor(e.key)),
                  const SizedBox(width: 3),
                  Text(e.value, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickStatus(BuildContext context, AppStore store, Student s, String dateStr, String owner) async {
    if (!store.can('attendance.edit')) return;
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                '${s.fullName} — ${formatDate(parseIsoDate(dateStr) ?? DateTime.now())}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
              ),
            ),
            for (final e in attendanceStatusNames.entries)
              ListTile(
                dense: true,
                leading: Container(width: 12, height: 12, color: _statusColor(e.key)),
                title: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.close, size: 16, color: AppColors.muted),
              title: const Text('إلغاء الرصد', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    store.setAttendance(s.id, dateStr, chosen.isEmpty ? null : chosen, ownerId: owner);
    _flash('تم الحفظ');
  }
}

Color _statusColor(String? status) => switch (status) {
      'present' => AppColors.success,
      'absent' => AppColors.danger,
      'late' => AppColors.amber,
      'excused' => AppColors.info,
      _ => AppColors.line,
    };

class _StudentWeekRow extends StatelessWidget {
  const _StudentWeekRow({
    required this.index,
    required this.student,
    required this.week,
    required this.owner,
    required this.canEdit,
    required this.onCycle,
    required this.onPick,
  });

  final int index;
  final Student student;
  final List<SchoolDay> week;
  final String owner;
  final bool canEdit;
  final ValueChanged<String> onCycle;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final statuses = [for (final d in week) store.attendanceInSession(owner, student.id, d.dateStr)];
    final weekAbsences = statuses.where((s) => s == 'absent').length;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('#$index', style: const TextStyle(color: AppColors.faint, fontSize: 10, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  student.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                ),
              ),
              if (weekAbsences > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: AppColors.dangerSoft,
                  child: Text(
                    'غياب الأسبوع: $weekAbsences',
                    style: const TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < week.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _Cell(
                      day: week[i],
                      status: statuses[i],
                      enabled: canEdit,
                      onTap: () => onCycle(week[i].dateStr),
                      onLongPress: () => onPick(week[i].dateStr),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.status,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final SchoolDay day;
  final String? status;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final marked = status != null;
    return InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: Column(
        children: [
          Text(
            day.dayName,
            style: TextStyle(
              fontSize: 9,
              fontWeight: day.isToday ? FontWeight.w900 : FontWeight.w600,
              color: day.isToday ? AppColors.amber : AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: marked ? color : Colors.white,
              border: Border.all(color: day.isToday ? AppColors.amber : (marked ? color : AppColors.line)),
            ),
            child: Text(
              switch (status) {
                'present' => '✓',
                'absent' => '✕',
                'late' => 'م',
                'excused' => 'ع',
                _ => '',
              },
              style: TextStyle(
                color: marked ? Colors.white : AppColors.faint,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
