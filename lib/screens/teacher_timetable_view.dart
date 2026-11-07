import 'package:flutter/material.dart';

import '../data/portal.dart';
import '../data/timetable_model.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// «جدولي» في بوابة المعلم: الجدول المعتمد واحتياطه — `TeacherTimetable`.
class TeacherTimetableView extends StatelessWidget {
  const TeacherTimetableView({
    super.key,
    required this.entries,
    required this.covers,
    required this.classes,
    required this.settings,
    required this.weekend,
    required this.onRefresh,
  });

  final List<TimetableEntry> entries;
  final List<TimetableCover> covers;
  final List<TeacherClass> classes;
  final TimetableSettings settings;
  final List<int> weekend;
  final VoidCallback onRefresh;

  String _roomName(String id) {
    for (final c in classes) {
      for (final r in c.rooms) {
        if (r.id == id) return [r.gradeLevel, r.name].where((s) => s.isNotEmpty).join(' ');
      }
    }
    return '—';
  }

  String _subjectOf(String groupId) => classes.where((c) => c.group.id == groupId).firstOrNull?.subjectName ?? '';

  @override
  Widget build(BuildContext context) {
    final days = schoolDays(weekend);
    final today = jsDay(DateTime.now());
    final max = settings.periods.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (covers.isNotEmpty) ...[
          Text('احتياط (${covers.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
          const SizedBox(height: 6),
          for (final c in covers)
            Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${DateTime.tryParse(c.date) == null ? '' : dayNames[jsDay(DateTime.parse(c.date))]} ${c.date.length >= 10 ? c.date.substring(5) : c.date}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text('الحصة ${c.period}', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(width: 10),
                  Text(_roomName(c.roomId), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: Text('جدولي (${entries.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
            ),
            IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: onRefresh),
          ],
        ),
        if (entries.isEmpty)
          const EmptyState(message: 'لا جدول معتمد')
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(82),
                columnWidths: const {0: FixedColumnWidth(62)},
                border: TableBorder.all(color: AppColors.line),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: AppColors.sunken),
                    children: [
                      const SizedBox(height: 40),
                      for (var i = 0; i < max; i++)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            Text(settings.periods[i].start, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                          ],
                        ),
                    ],
                  ),
                  for (final d in days)
                    TableRow(
                      decoration: d == today ? const BoxDecoration(color: Color(0xFFE6F4F4)) : null,
                      children: [
                        Container(
                          height: 50,
                          alignment: Alignment.center,
                          child: Text(dayNames[d], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ),
                        for (var i = 0; i < max; i++)
                          i + 1 > settings.periodsOn(d)
                              ? Container(height: 50, color: AppColors.sunken)
                              : () {
                                  final e = entries.where((x) => x.day == d && x.period == i + 1).firstOrNull;
                                  return Container(
                                    height: 50,
                                    padding: const EdgeInsets.all(3),
                                    alignment: Alignment.center,
                                    child: e == null
                                        ? const SizedBox.shrink()
                                        : Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(_roomName(e.roomId), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                              Text(_subjectOf(e.groupId), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                                            ],
                                          ),
                                  );
                                }(),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
