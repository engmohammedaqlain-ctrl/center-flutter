import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';
import 'attendance_print.dart';

/// كشف الحضور — مطابق لعرض الهاتف في `Attendance.tsx`:
/// شريط أيام الأسبوع المدرسي، ثم إحصاء اليوم المختار، ثم صفوف الطلاب بزرّي
/// لمس كبيرين. الشبكة الأسبوعية الكاملة تبقى في كشف الطباعة.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int weekOffset = 0;
  String? grade;
  String? ownerId;

  /// اليوم المعروض في الشريط. يبدأ من اليوم الحالي.
  String selectedDate = isoDate(DateTime.now());

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

        // اليوم المختار داخل الأسبوع المعروض، وإلا اليوم الحالي أو أوله
        final day = week.firstWhere(
          (d) => d.dateStr == selectedDate,
          orElse: () => week.where((d) => d.isToday).firstOrNull ?? week.first,
        );

        var present = 0, absent = 0, unmarked = 0;
        for (final s in list) {
          switch (store.attendanceInSession(currentOwner, s.id, day.dateStr)) {
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
            _pickers(
              store,
              school: school,
              grades: grades,
              currentGrade: currentGrade,
              owners: owners,
              currentOwner: currentOwner,
            ),
            _dayStrip(week, day),
            Expanded(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: EmptyState(message: 'لا يوجد طلاب مسجلون في هذا الصف/المجموعة'),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      children: [
                        _dayStats(
                          store: store,
                          day: day,
                          list: list,
                          owner: currentOwner,
                          present: present,
                          absent: absent,
                          unmarked: unmarked,
                          canEdit: canEdit,
                        ),
                        const SizedBox(height: 10),
                        for (var i = 0; i < list.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _StudentRow(
                              index: i + 1,
                              student: list[i],
                              status: store.attendanceInSession(currentOwner, list[i].id, day.dateStr),
                              canEdit: canEdit,
                              onSet: (status) => store.setAttendance(
                                list[i].id,
                                day.dateStr,
                                status,
                                ownerId: currentOwner,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
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

  Widget _pickers(
    AppStore store, {
    required bool school,
    required List<String> grades,
    required String? currentGrade,
    required List<dynamic> owners,
    required String currentOwner,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          if (school) ...[
            Expanded(
              child: AppDropdown<String>(
                value: currentGrade,
                hint: 'المرحلة',
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
              hint: school ? 'الشعبة' : 'المجموعة',
              items: [
                for (final o in owners)
                  DropdownMenuItem(
                    value: school ? (o as Classroom).id : (o as Group).id,
                    child: Text(school ? (o as Classroom).name : (o as Group).name),
                  ),
              ],
              onChanged: (v) => setState(() => ownerId = v),
            ),
          ),
        ],
      ),
    );
  }

  /// شريط أيام الأسبوع المدرسي مع التنقّل بين الأسابيع.
  Widget _dayStrip(List<SchoolDay> week, SchoolDay selected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          _weekArrow(Icons.chevron_left, () => setState(() => weekOffset--)),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                for (final d in week)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _DayChip(
                        day: d,
                        selected: d.dateStr == selected.dateStr,
                        onTap: () => setState(() => selectedDate = d.dateStr),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _weekArrow(Icons.chevron_right, () => setState(() => weekOffset++)),
        ],
      ),
    );
  }

  Widget _weekArrow(IconData icon, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, size: 17, color: AppColors.heading),
      ),
    );
  }

  Widget _dayStats({
    required AppStore store,
    required SchoolDay day,
    required List<Student> list,
    required String owner,
    required int present,
    required int absent,
    required int unmarked,
    required bool canEdit,
  }) {
    final disabled = !canEdit || list.isEmpty;
    return AppCard(
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'رصد حضور: ${day.dayName} (${day.shortDate})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 9,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'إجمالي الصف: ${list.length} طالب',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                    _stat('حاضر', present, AppColors.success),
                    _stat('غائب', absent, AppColors.danger),
                    if (unmarked > 0) _stat('لم يُرصد', unmarked, AppColors.faint),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PressableScale(
            onTap: disabled ? null : () => store.markAllPresent(day.dateStr, list, ownerId: owner),
            child: Opacity(
              opacity: disabled ? 0.5 : 1,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.done_all, size: 15, color: Colors.white),
                    SizedBox(width: 5),
                    Text('الكل حاضر', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('• $label: ', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
        AnimatedCount(
          value,
          duration: const Duration(milliseconds: 400),
          style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.selected, required this.onTap});

  final SchoolDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg, fg, border;
    if (selected) {
      bg = AppColors.amber;
      fg = Colors.white;
      border = AppColors.amber;
    } else if (day.isToday) {
      bg = AppColors.amberSoft;
      fg = AppColors.amber;
      border = AppColors.amberBorder;
    } else {
      bg = Colors.white;
      fg = const Color(0xFF475569);
      border = AppColors.line;
    }

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day.dayName,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                color: fg,
                fontWeight: selected || day.isToday ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              day.shortDate,
              style: TextStyle(fontSize: 9, height: 1, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

/// صف الطالب: رقمه واسمه وهاتفه، وزرّا رصد كبيران للّمس.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.index,
    required this.student,
    required this.status,
    required this.canEdit,
    required this.onSet,
  });

  final int index;
  final Student student;
  final String? status;
  final bool canEdit;
  final ValueChanged<String?> onSet;

  @override
  Widget build(BuildContext context) {
    final present = status == 'present' || status == 'late';
    final absent = status == 'absent';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '#$index',
                      style: const TextStyle(color: AppColors.faint, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        student.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                      ),
                    ),
                  ],
                ),
                if (student.phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    student.phone,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _markButton(
            label: 'حاضر ✓',
            on: present,
            fg: AppColors.success,
            softBg: const Color(0xFFF0FDF4),
            softBorder: AppColors.successBorder,
            onTap: canEdit ? () => onSet(present ? null : 'present') : null,
          ),
          const SizedBox(width: 7),
          _markButton(
            label: 'غائب ✗',
            on: absent,
            fg: AppColors.danger,
            softBg: const Color(0xFFFEF2F2),
            softBorder: AppColors.dangerBorder,
            onTap: canEdit ? () => onSet(absent ? null : 'absent') : null,
          ),
        ],
      ),
    );
  }

  Widget _markButton({
    required String label,
    required bool on,
    required Color fg,
    required Color softBg,
    required Color softBorder,
    VoidCallback? onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? fg : softBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? fg : softBorder),
          boxShadow: on ? [BoxShadow(color: fg.withValues(alpha: 0.3), blurRadius: 7, offset: const Offset(0, 2))] : null,
        ),
        child: Text(
          label,
          style: TextStyle(color: on ? Colors.white : fg, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
