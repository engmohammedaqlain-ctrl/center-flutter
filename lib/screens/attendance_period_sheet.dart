import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/panels.dart';
import '../widgets/widgets.dart';

/// حضور فترة مختارة — ما لا يظهره شريط الأسبوع الواحد.
///
/// الشريط يجيب «من حضر اليوم»، وهذه الورقة تجيب «كم غاب فلان هذا الشهر»: مدى
/// تاريخي يُختار، وحصيلة كل طالب فيه مرتّبةً بالأكثر غياباً كي يظهر المتعثّر
/// أولاً بلا بحث. وتُرجع تاريخاً إن اختار المستخدم الانتقال إلى يوم بعينه،
/// فيتولّى الشريط عرضه للرصد.
Future<DateTime?> showAttendancePeriodSheet(
  BuildContext context, {
  required AppStore store,
  required String ownerId,
  required String ownerName,
  required List<Student> students,
  required DateTime initialDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (_) => _PeriodSheet(
      store: store,
      ownerId: ownerId,
      ownerName: ownerName,
      students: students,
      initialDate: initialDate,
    ),
  );
}

/// حصيلة طالب واحد في الفترة.
class _Tally {
  _Tally(this.student);
  final Student student;
  int present = 0;
  int absent = 0;
  int excused = 0;
  int unmarked = 0;

  int get marked => present + absent + excused;

  /// نسبة الحضور من الأيام المرصودة فقط: يوم لم يُرصد ليس غياباً.
  int get rate => marked == 0 ? 0 : (present * 100 / marked).round();
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({
    required this.store,
    required this.ownerId,
    required this.ownerName,
    required this.students,
    required this.initialDate,
  });

  final AppStore store;
  final String ownerId;
  final String ownerName;
  final List<Student> students;
  final DateTime initialDate;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late DateTime from;
  late DateTime to;

  @override
  void initState() {
    super.initState();
    // تنتهي الفترة باليوم الحالي لا باليوم المعروض في الشريط: يوم الجمعة —
    // أو أي تصفّح لأسبوع سابق — كان يُنهي الفترة قبل آخر رصد فتبدو فارغة.
    final today = dateOnly(DateTime.now());
    final anchor = dateOnly(widget.initialDate);
    to = anchor.isAfter(today) ? anchor : today;
    from = to.subtract(const Duration(days: 29));
  }

  /// الجمعة عطلة الأسبوع المدرسي، فلا تُحسب يوماً بلا رصد.
  static bool _schoolDay(DateTime d) => d.weekday != DateTime.friday;

  List<DateTime> get _days {
    final list = <DateTime>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      if (_schoolDay(d)) list.add(d);
    }
    return list;
  }

  List<_Tally> _tallies(List<DateTime> days) {
    final store = widget.store;
    final out = [for (final s in widget.students) _Tally(s)];
    for (final t in out) {
      for (final d in days) {
        switch (store.attendanceInSession(widget.ownerId, t.student.id, isoDate(d))) {
          case 'present':
            t.present++;
          case 'absent':
            t.absent++;
          case 'excused':
            t.excused++;
          default:
            t.unmarked++;
        }
      }
    }
    // الأكثر غياباً أولاً: هو سبب فتح هذه الورقة أصلاً
    out.sort((a, b) {
      final byAbsent = b.absent.compareTo(a.absent);
      if (byAbsent != 0) return byAbsent;
      final byExcused = b.excused.compareTo(a.excused);
      if (byExcused != 0) return byExcused;
      return a.student.fullName.compareTo(b.student.fullName);
    });
    return out;
  }

  Future<void> _pick({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: start ? 'بداية الفترة' : 'نهاية الفترة',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = dateOnly(picked);
      if (start) {
        from = d;
        // البداية بعد النهاية تعطي فترة فارغة، فتتبعها النهاية
        if (to.isBefore(from)) to = from;
      } else {
        to = d;
        if (from.isAfter(to)) from = to;
      }
    });
  }

  void _preset(int days) {
    setState(() {
      to = dateOnly(DateTime.now());
      from = to.subtract(Duration(days: days - 1));
    });
  }

  void _thisMonth() {
    final now = DateTime.now();
    setState(() {
      from = DateTime(now.year, now.month, 1);
      to = dateOnly(now);
    });
  }

  Future<void> _jumpToDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: to,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: 'اختر يوماً لعرضه',
      cancelText: 'إلغاء',
      confirmText: 'عرض',
    );
    if (picked == null || !mounted) return;
    Navigator.pop(context, dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final tallies = _tallies(days);
    final present = tallies.fold<int>(0, (a, t) => a + t.present);
    final absent = tallies.fold<int>(0, (a, t) => a + t.absent);
    final excused = tallies.fold<int>(0, (a, t) => a + t.excused);
    final marked = present + absent + excused;
    final rate = marked == 0 ? 0 : (present * 100 / marked).round();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'الحضور في فترة',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.heading),
                      ),
                      if (widget.ownerName.trim().isNotEmpty)
                        Text(
                          widget.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
                SquareIconButton(icon: Icons.close, onTap: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 10),

            // ── المدى ───────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _DateField(label: 'من', date: from, onTap: () => _pick(start: true))),
                const SizedBox(width: 8),
                Expanded(child: _DateField(label: 'إلى', date: to, onTap: () => _pick(start: false))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _presetChip('آخر ٧ أيام', () => _preset(7)),
                _presetChip('آخر ٣٠ يوماً', () => _preset(30)),
                _presetChip('هذا الشهر', _thisMonth),
              ],
            ),
            const SizedBox(height: 10),

            // ── الحصيلة ─────────────────────────────────────────────────────
            StatRow(
              children: [
                StatCard(label: 'حاضر', value: '$present', color: AppColors.success),
                StatCard(label: 'غائب', value: '$absent', color: AppColors.danger),
                StatCard(label: 'مأذون', value: '$excused', color: const Color(0xFFD97706)),
                StatCard(label: 'نسبة الحضور', value: '$rate٪', color: AppColors.navy),
              ],
            ),
            const SizedBox(height: 8),
            InfoStrip(
              child: Text(
                '${days.length} يوم دراسي في الفترة  ·  ${widget.students.length} طالب  ·  $marked رصد',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 10),

            // ── الطلاب ──────────────────────────────────────────────────────
            Flexible(
              child: tallies.isEmpty || days.isEmpty
                  ? const EmptyState(message: 'لا يوجد رصد في هذه الفترة')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: tallies.length,
                      itemBuilder: (context, i) => _TallyRow(tally: tallies[i], index: i + 1),
                    ),
            ),
            const SizedBox(height: 10),
            GhostButton(label: 'عرض يوم محدد للرصد', icon: Icons.event_available, onPressed: _jumpToDay),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.chip),
          color: AppColors.bg,
          border: Border.all(color: AppColors.line),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// حقل تاريخ بشكل الحقول لا بشكل الزر: يُقرأ كجزء من النموذج.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.box),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: tileDecoration(white: true),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.faint),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.faint, fontSize: 10)),
                  Text(
                    formatDate(date),
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.heading),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({required this.tally, required this.index});

  final _Tally tally;
  final int index;

  @override
  Widget build(BuildContext context) {
    final rateColor = switch (tally.rate) {
      >= 90 => AppColors.success,
      >= 75 => const Color(0xFFD97706),
      _ => AppColors.danger,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: tileDecoration(),
        child: Row(
          children: [
            Text('#$index', style: const TextStyle(color: AppColors.faint, fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tally.student.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'حاضر ${tally.present}  ·  غائب ${tally.absent}  ·  مأذون ${tally.excused}'
                    '${tally.unmarked > 0 ? '  ·  لم يُرصد ${tally.unmarked}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tally.marked == 0 ? '—' : '${tally.rate}٪',
              style: TextStyle(color: rateColor, fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
