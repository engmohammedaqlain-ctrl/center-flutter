import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'admin_tokens.dart' show AdminNoon;
import 'admin_ui.dart';
import 'animated_count.dart';

/// عناصر كشف الحضور المرئية — تستعملها شاشة الإدارة وبوابة المعلم معاً، فيرى
/// الاثنان الكشف نفسه: شريط الأيام، وملخّص اليوم، وصفّ الطالب بمفتاح رصده.

/// ألوان حالات الرصد — دلالية ثابتة لا تتبع هوية المنشأة.
const attendancePresentColor = Color(0xFF2E7D57);
const attendanceAbsentColor = Color(0xFFA5484A);
const attendanceExcusedColor = Color(0xFF475569);
const attendanceUnmarkedColor = Color(0xFFD5DAE2);

/// خانات رصد الطالب.
const studentMarkOptions = [
  ('present', 'حاضر', attendancePresentColor),
  ('absent', 'غائب', attendanceAbsentColor),
  ('excused', 'مأذون', attendanceExcusedColor),
];

/// خانات دوام الموظف: التأخر بلون المأذون في كشف الطلاب.
const staffMarkOptions = [
  ('present', 'حاضر', attendancePresentColor),
  ('absent', 'غائب', attendanceAbsentColor),
  ('late', 'متأخر', attendanceExcusedColor),
];

/// يوم في الشريط: بلا إطار إلا المختار — اسمه ورقمه ونقطة اكتمال رصده.
class AttendanceDayChip extends StatelessWidget {
  const AttendanceDayChip({
    super.key,required this.day, required this.selected, required this.progress, required this.onTap});

  final SchoolDay day;
  final bool selected;

  /// نسبة المرصودين في هذا اليوم، من 0 إلى 1.
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nameColor = selected ? Colors.white.withValues(alpha: 0.85) : (day.isToday ? AppColors.amberDark : AppColors.faint);
    final numColor = selected ? Colors.white : (day.isToday ? AppColors.amberDark : AppColors.heading);

    final Color? dot = progress >= 1
        ? (selected ? Colors.white : attendancePresentColor)
        : progress > 0
            ? (selected ? Colors.white.withValues(alpha: 0.7) : attendanceExcusedColor)
            : null;

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 58,
        decoration: BoxDecoration(
          color: selected ? AppColors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(Corner.field),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day.dayName,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: AppText.family,
                fontSize: 9.5,
                height: 1.1,
                color: nameColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${day.date.day}',
              style: TextStyle(
                fontFamily: AppText.family,
                fontSize: 16,
                height: 1,
                color: numColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot ?? Colors.transparent, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

/// ملخّص اليوم: شريط مضغوط بأربع خانات (حاضر، غائب، مأذون، لم يُرصد) وشريط تقدّم الرصد تحتها.
/// التاريخ لا يتكرر هنا: شريط الأيام فوقه يبيّنه.
class AttendanceDaySummary extends StatelessWidget {
  const AttendanceDaySummary({
    super.key,
    required this.day,
    required this.total,
    required this.present,
    required this.absent,
    required this.excused,
    required this.unmarked,
  });

  final SchoolDay day;
  final int total, present, absent, excused, unmarked;

  @override
  Widget build(BuildContext context) {
    final marked = total - unmarked;
    final ratio = total == 0 ? 0.0 : (marked / total).clamp(0.0, 1.0);
    final done = total > 0 && unmarked == 0;

    Widget cell(String label, int value, Color color) => Expanded(
          child: Column(
            children: [
              Text('$value', style: TextStyle(fontFamily: AppText.family, fontSize: 20, fontWeight: FontWeight.w700, color: color, height: 1.1)),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontFamily: AppText.family, fontSize: 11.5, color: AdminNoon.muted)),
            ],
          ),
        );
    final divider = Container(width: 1, height: 30, color: AdminNoon.line);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: noonPanel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            child: Row(
              children: [
                cell('حاضر', present, AdminNoon.green700),
                divider,
                cell('غائب', absent, AdminNoon.red600),
                divider,
                cell('مأذون', excused, AdminNoon.warn),
                divider,
                cell(done ? 'اكتمل' : 'لم يُرصد', done ? marked : unmarked, done ? AdminNoon.green700 : AdminNoon.muted),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 3,
            backgroundColor: AdminNoon.line,
            valueColor: AlwaysStoppedAnimation(done ? AdminNoon.green700 : AdminNoon.ink),
          ),
        ],
      ),
    );
  }
}

/// صف الطالب: رقمه بلون حالته، واسمه وهاتفه، ومفتاح رصد مقسّم — حاضر وغائب ومأذون.
class AttendanceStudentRow extends StatefulWidget {
  const AttendanceStudentRow({
    super.key,
    required this.index,
    required this.student,
    required this.status,
    required this.canEdit,
    required this.last,
    required this.onSet,
    this.note = '',
  });

  final int index;
  final Student student;
  final String? status;
  final bool canEdit;
  final bool last;
  final ValueChanged<String?> onSet;

  /// سطر تحت الاسم: غياب الشهر في بوابة المعلم.
  final String note;

  @override
  State<AttendanceStudentRow> createState() => AttendanceStudentRowState();
}

class AttendanceStudentRowState extends State<AttendanceStudentRow> {
  /// الحالة المعروضة. تُضبط فور اللمس ثم يلحق بها المخزن، فلا ينتظر المستخدم
  /// دورة إخطار وإعادة بناء ليرى أن ضغطته وصلت.
  String? _shown;
  bool _optimistic = false;

  String? get _status => _optimistic ? _shown : widget.status;

  @override
  void didUpdateWidget(covariant AttendanceStudentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // وصلت حالة المخزن: نتخلّى عن الحالة المتفائلة
    if (oldWidget.status != widget.status) _optimistic = false;
  }

  void _tap(String? next) {
    setState(() {
      _shown = next;
      _optimistic = true;
    });
    widget.onSet(next);
  }

  static Color? _colorOf(String? status) => switch (status) {
        'present' => attendancePresentColor,
        'absent' => attendanceAbsentColor,
        'excused' => attendanceExcusedColor,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final status = _status;
    final tint = _colorOf(status);

    final seat = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.12) ?? AppColors.sunken,
        borderRadius: BorderRadius.circular(Corner.field),
        border: Border.all(color: tint?.withValues(alpha: 0.35) ?? AppColors.line),
      ),
      child: Text(
        '${widget.index}'.padLeft(2, '0'),
        style: TextStyle(
          fontFamily: AppText.family,
          color: tint ?? AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          student.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.heading,
          ),
        ),
        if (student.phone.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            student.phone,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: AppColors.faint, fontSize: 11),
          ),
        ],
        if (widget.note.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            widget.note,
            style: const TextStyle(color: attendanceAbsentColor, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );

    Widget toggle({required bool expand}) => AttendanceMarkToggle(
          status: status,
          expand: expand,
          onSet: widget.canEdit ? (s) => _tap(s == status ? null : s) : null,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: widget.last ? null : const Border(bottom: BorderSide(color: AppColors.hover)),
      ),
      child: Row(
        children: [
          seat,
          const SizedBox(width: 10),
          Expanded(child: info),
          const SizedBox(width: 8),
          toggle(expand: false),
        ],
      ),
    );
  }
}

/// مفتاح رصد مقسّم بثلاث خانات متلاصقة؛ الخانة المختارة تمتلئ بلون حالتها.
/// للطلاب حاضر وغائب ومأذون، ولدوام الموظفين حاضر وغائب ومتأخر ([staffMarkOptions]).
class AttendanceMarkToggle extends StatelessWidget {
  const AttendanceMarkToggle({super.key, required this.status, required this.expand, required this.onSet, this.options = studentMarkOptions});

  final String? status;
  final bool expand;
  final ValueChanged<String>? onSet;
  final List<(String, String, Color)> options;

  List<(String, String, Color)> get _options => options;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(Corner.field + 2),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final (value, label, color) in _options)
            if (expand)
              Expanded(child: _segment(value, label, color))
            else
              SizedBox(width: 48, child: _segment(value, label, color)),
        ],
      ),
    );
  }

  Widget _segment(String value, String label, Color color) {
    final on = status == value;
    return PressableScale(
      onTap: onSet == null ? null : () => onSet!(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(Corner.field - 1),
          boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 5, offset: const Offset(0, 2))] : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AppText.family,
              color: on ? Colors.white : color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
