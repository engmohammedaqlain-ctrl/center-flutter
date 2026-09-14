import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'attendance_period_sheet.dart';
import 'attendance_print.dart';

/// كشف الحضور — مطابق لعرض الهاتف في `Attendance.tsx`:
/// شريط أيام الأسبوع المدرسي، ثم إحصاء اليوم المختار، ثم صفوف الطلاب بزرّي
/// لمس كبيرين. الشبكة الأسبوعية الكاملة تبقى في كشف الطباعة.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.initialGrade, this.initialOwnerId});

  /// المرحلة والصف المختاران سلفاً — حين تُفتح الشاشة من صفحة صف بعينه.
  final String? initialGrade;
  final String? initialOwnerId;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

/// رصد حضور صف من صفحته: الشاشة نفسها والصف مختار، فلا يُعاد اختياره يدوياً.
Future<void> openClassAttendance(BuildContext context, {required Classroom room}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'رصد الحضور',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(height: 2),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        body: AttendanceScreen(initialGrade: room.gradeLevel, initialOwnerId: room.id),
      ),
    ),
  );
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int weekOffset = 0;
  String? grade;
  String? ownerId;

  @override
  void initState() {
    super.initState();
    grade = widget.initialGrade?.trim().isEmpty ?? true ? null : widget.initialGrade;
    ownerId = widget.initialOwnerId?.trim().isEmpty ?? true ? null : widget.initialOwnerId;
  }

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
        final canEdit = store.can('attendance.edit');

        // المرحلة ثم الشعبة
        final grades = store.rooms.map((r) => r.gradeLevel).where((g) => g.trim().isNotEmpty).toSet().toList();
        final currentGrade =
            grade != null && grades.contains(grade) ? grade : (grades.isNotEmpty ? grades.first : null);
        final owners = store.rooms.where((r) => currentGrade == null || r.gradeLevel == currentGrade).toList();

        final ownerIds = owners.map((r) => r.id).toList();
        final currentOwner =
            (ownerId != null && ownerIds.contains(ownerId)) ? ownerId! : (ownerIds.isNotEmpty ? ownerIds.first : '');
        final room = store.rooms.where((r) => r.id == currentOwner).firstOrNull;

        final list = room == null ? <Student>[] : store.attendanceRosterOf(room);
        final ownerName = room?.name ?? '';

        // اليوم المختار داخل الأسبوع المعروض، وإلا اليوم الحالي أو أوله
        final day = week.firstWhere(
          (d) => d.dateStr == selectedDate,
          orElse: () => week.where((d) => d.isToday).firstOrNull ?? week.first,
        );

        var present = 0, absent = 0, excused = 0, unmarked = 0;
        for (final s in list) {
          switch (store.attendanceInSession(currentOwner, s.id, day.dateStr)) {
            case 'present':
              present++;
            case 'absent':
              absent++;
            case 'excused':
              excused++;
            default:
              unmarked++;
          }
        }

        return ThumbActionLayer(
          action: canEdit
              ? ThumbAction(
                  label: 'الكل حاضر',
                  icon: Icons.done_all,
                  color: AppColors.success,
                  onPressed: list.isEmpty || currentOwner.isEmpty
                      ? null
                      : () => store.markAllPresent(day.dateStr, list, ownerId: currentOwner),
                )
              : null,
          child: Column(
            children: [
              _pickers(
                store,
                grades: grades,
                currentGrade: currentGrade,
                owners: owners,
                currentOwner: currentOwner,
                onCalendar: () => _openPeriod(
                  store,
                  ownerId: currentOwner,
                  ownerName: ownerName,
                  students: list,
                  day: day.date,
                ),
              ),
              _dayStrip(week, day),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: EmptyState(message: 'لا يوجد طلاب مسجلون في هذا الصف/المجموعة'),
                      )
                    // بناء كسول: صفّ واحد لكل ما يظهر على الشاشة فقط.
                    // بناء القائمة كاملةً كان يُنشئ مئات الصفوف عند كل تعديل،
                    // فيتأخر التبديل بين الأيام والصفوف تأخراً محسوساً.
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, thumbActionClearance),
                        itemCount: list.length + 2,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _dayStats(
                                list: list,
                                present: present,
                                absent: absent,
                                excused: excused,
                                unmarked: unmarked,
                              ),
                            );
                          }
                          if (i == list.length + 1) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: GhostButton(
                                label: 'تنزيل كشف الأسبوع',
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
                            );
                          }
                          final student = list[i - 1];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _StudentRow(
                              // مفتاح يشمل اليوم والحالة: الصف يُعاد بناؤه عند
                              // تغيّر رصده وحده، لا مع كل إخطار من المخزن
                              key: ValueKey('${student.id}|${day.dateStr}'),
                              index: i,
                              student: student,
                              status: store.attendanceInSession(currentOwner, student.id, day.dateStr),
                              canEdit: canEdit,
                              onSet: (status) => store.setAttendance(
                                student.id,
                                day.dateStr,
                                status,
                                ownerId: currentOwner,
                              ),
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

  /// أسبوع الشريط هو أسبوع اليوم المختار: الانتقال إلى تاريخ بعيد يحرّك الشريط
  /// معه بدل أن يبقى على أسبوع اليوم فلا يظهر ما اختير.
  static int _weekOffsetOf(DateTime target) {
    int saturdayOf(DateTime d) =>
        dateOnly(d).subtract(Duration(days: (d.weekday + 1) % 7)).millisecondsSinceEpoch ~/ 86400000;
    return ((saturdayOf(target) - saturdayOf(DateTime.now())) / 7).round();
  }

  Future<void> _openPeriod(
    AppStore store, {
    required String ownerId,
    required String ownerName,
    required List<Student> students,
    required DateTime day,
  }) async {
    final jumpTo = await showAttendancePeriodSheet(
      context,
      store: store,
      ownerId: ownerId,
      ownerName: ownerName,
      students: students,
      initialDate: day,
    );
    if (jumpTo == null || !mounted) return;
    setState(() {
      weekOffset = _weekOffsetOf(jumpTo);
      selectedDate = isoDate(jumpTo);
    });
  }

  Widget _pickers(
    AppStore store, {
    required List<String> grades,
    required String? currentGrade,
    required List<Classroom> owners,
    required String currentOwner,
    required VoidCallback onCalendar,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          ...[
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
              hint: 'الشعبة',
              items: [
                for (final o in owners) DropdownMenuItem(value: o.id, child: Text(o.name)),
              ],
              onChanged: (v) => setState(() => ownerId = v),
            ),
          ),
          const SizedBox(width: 8),
          // التقويم: حضور فترة كاملة، والانتقال إلى يوم خارج الأسبوع المعروض
          PressableScale(
            onTap: onCalendar,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: AppColors.line),
              ),
              child: Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.heading),
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
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, size: 17, color: AppColors.heading),
      ),
    );
  }

  Widget _dayStats({
    required List<Student> list,
    required int present,
    required int absent,
    required int excused,
    required int unmarked,
  }) {
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
                // اليوم واسمه ظاهران في شريط الأيام فوقه: تكرارهما هنا حشو
                Wrap(
                  spacing: 9,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'الطلاب: ${list.length}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                    ),
                    _stat('حاضر', present, AppColors.success),
                    _stat('غائب', absent, AppColors.danger),
                    _stat('مأذون', excused, const Color(0xFFD97706)),
                    if (unmarked > 0) _stat('غير مرصود', unmarked, AppColors.faint),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// نص واحد لا صفّ: الصفّ لا ينكسر، فكان يطفح بجوار زر «الكل حاضر» على
  /// الشاشات الضيقة. العدد يبقى متحرّكاً داخل النص.
  Widget _stat(String label, int value, Color color) {
    return Text.rich(
      TextSpan(
        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
        children: [
          TextSpan(text: '• $label: '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: AnimatedCount(
              value,
              duration: const Duration(milliseconds: 400),
              style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
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
          borderRadius: BorderRadius.circular(Corner.box),
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

/// صف الطالب: رقمه واسمه وهاتفه، وثلاثة أزرار رصد للّمس — حاضر وغائب ومأذون
/// كما في «أزرار الرصد اللمسية» في Attendance.tsx.
class _StudentRow extends StatefulWidget {
  const _StudentRow({
    super.key,
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
  State<_StudentRow> createState() => _StudentRowState();
}

class _StudentRowState extends State<_StudentRow> {
  /// الحالة المعروضة. تُضبط فور اللمس ثم يلحق بها المخزن، فلا ينتظر المستخدم
  /// دورة إخطار وإعادة بناء ليرى أن ضغطته وصلت.
  String? _shown;

  String? get _status => _shown ?? widget.status;

  @override
  void didUpdateWidget(covariant _StudentRow old) {
    super.didUpdateWidget(old);
    // وصلت حالة المخزن: نتخلّى عن الحالة المتفائلة
    if (old.status != widget.status) _shown = null;
  }

  void _tap(String? next) {
    setState(() => _shown = next);
    widget.onSet(next);
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final index = widget.index;
    final canEdit = widget.canEdit;
    final status = _status;
    final present = status == 'present';
    final absent = status == 'absent';
    final excused = status == 'excused';

    final info = Column(
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
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
    );

    final buttons = [
      _markButton(
        label: 'حاضر ✓',
        on: present,
        fg: AppColors.success,
        softBg: const Color(0xFFF0FDF4),
        softBorder: AppColors.successBorder,
        onTap: canEdit ? () => _tap(present ? null : 'present') : null,
      ),
      _markButton(
        label: 'غائب ✗',
        on: absent,
        fg: AppColors.danger,
        softBg: const Color(0xFFFEF2F2),
        softBorder: AppColors.dangerBorder,
        onTap: canEdit ? () => _tap(absent ? null : 'absent') : null,
      ),
      _markButton(
        label: 'مأذون',
        on: excused,
        fg: const Color(0xFFD97706),
        softBg: const Color(0xFFFFFBEB),
        softBorder: const Color(0xFFFDE68A),
        onTap: canEdit ? () => _tap(excused ? null : 'excused') : null,
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, box) {
          // ثلاثة أزرار بجوار الاسم لا تفي بها شاشة هاتف: عند 360 بكسل كان
          // الاسم يُسحق إلى 15 بكسل ويطفح رقم المقعد. دون 340 تنزل الأزرار
          // تحته بعرض كامل، فتبقى أهداف اللمس كبيرة ويُقرأ الاسم كاملاً.
          if (box.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                info,
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: buttons[i]),
                    ],
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 8),
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                buttons[i],
              ],
            ],
          );
        },
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? fg : softBg,
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: on ? fg : softBorder),
          boxShadow: on ? [BoxShadow(color: fg.withValues(alpha: 0.3), blurRadius: 7, offset: const Offset(0, 2))] : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(color: on ? Colors.white : fg, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
