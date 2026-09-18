import 'package:center_mobile/data/attendance_days.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dailyAttendance: كشف الشعبة يغلب مواد اليوم، والغياب يُحسب يوماً واحداً', () {
    final sessions = [
      ClassSession(id: 'm1', groupId: 'math', sessionDate: '2026-09-10'),
      ClassSession(id: 'm2', groupId: 'sci', sessionDate: '2026-09-10'),
      ClassSession(id: 'room', groupId: '', sessionDate: '2026-09-11'),
      ClassSession(id: 'm3', groupId: 'math', sessionDate: '2026-09-11'),
    ];
    final days = dailyAttendance(
      [
        AttendanceMark(studentId: 's', date: '2026-09-10', status: 'absent', sessionId: 'm1'),
        AttendanceMark(studentId: 's', date: '2026-09-10', status: 'absent', sessionId: 'm2'),
        AttendanceMark(studentId: 's', date: '2026-09-11', status: 'present', sessionId: 'room'),
        AttendanceMark(studentId: 's', date: '2026-09-11', status: 'absent', sessionId: 'm3'),
      ],
      sessions,
    );
    expect(days.length, 2);
    expect(days[0], (date: '2026-09-11', status: 'present'));
    expect(days[1], (date: '2026-09-10', status: 'absent'));
  });
}
