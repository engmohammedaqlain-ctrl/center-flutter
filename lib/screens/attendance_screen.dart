import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String? grade;
  String? roomId;
  String saved = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final grades = store.rooms.map((r) => r.gradeLevel).toSet().toList();
        final currentGrade = grade ?? (grades.isNotEmpty ? grades.first : null);
        final rooms = store.rooms.where((r) => r.gradeLevel == currentGrade).toList();
        final currentRoomId =
            (roomId != null && rooms.any((r) => r.id == roomId)) ? roomId : (rooms.isNotEmpty ? rooms.first.id : null);
        final room = store.rooms.where((r) => r.id == currentRoomId).firstOrNull;
        final list = room == null ? <Student>[] : store.studentsOf(room);
        final today = isoDate(DateTime.now());
        final now = DateTime.now();
        final dayName = const ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'][now.weekday % 7];
        var present = 0;
        var absent = 0;
        for (final s in list) {
          final st = store.attendanceOf(s.id, today);
          if (st == 'present') present++;
          if (st == 'absent') absent++;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      value: currentGrade,
                      items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => setState(() {
                        grade = v;
                        roomId = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppDropdown<String>(
                      value: currentRoomId,
                      items: rooms.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
                      onChanged: (v) => setState(() => roomId = v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رصد حضور اليوم: $dayName (${now.day}/${now.month})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                        ),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            text: 'إجمالي الصف: ${list.length} طالب  ',
                            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                            children: [
                              TextSpan(text: '• حاضر: $present  ', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                              TextSpan(text: '• غائب: $absent', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
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
                    onPressed: list.isEmpty
                        ? null
                        : () {
                            store.markAllPresent(today, list);
                            setState(() => saved = 'تم رصد جميع طلاب الصف كحاضرين بنجاح');
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const EmptyState(message: 'لا يوجد طلاب مسجلون في هذا الصف/المجموعة')
            else
              for (var i = 0; i < list.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _Row(
                    index: i + 1,
                    student: list[i],
                    status: store.attendanceOf(list[i].id, today),
                    onPresent: () {
                      final cur = store.attendanceOf(list[i].id, today);
                      store.setAttendance(list[i].id, today, cur == 'present' ? null : 'present');
                      setState(() => saved = 'تم الحفظ');
                    },
                    onAbsent: () {
                      final cur = store.attendanceOf(list[i].id, today);
                      store.setAttendance(list[i].id, today, cur == 'absent' ? null : 'absent');
                      setState(() => saved = 'تم الحفظ');
                    },
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.index,
    required this.student,
    required this.status,
    required this.onPresent,
    required this.onAbsent,
  });

  final int index;
  final Student student;
  final String? status;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;

  @override
  Widget build(BuildContext context) {
    final present = status == 'present';
    final absent = status == 'absent';
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Text('#$index', style: const TextStyle(color: AppColors.faint, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                Text(student.phone, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
          _btn('حاضر', present, AppColors.success, const Color(0xFFF0FDF4), AppColors.successBorder, onPresent),
          const SizedBox(width: 6),
          _btn('غائب', absent, AppColors.danger, AppColors.dangerSoft, AppColors.dangerBorder, onAbsent),
        ],
      ),
    );
  }

  Widget _btn(String label, bool on, Color fg, Color soft, Color border, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? fg : soft,
          border: Border.all(color: on ? fg : border),
        ),
        child: Text(label, style: TextStyle(color: on ? Colors.white : fg, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );
  }
}
