import 'package:center_mobile/data/attendance_days.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dailyAttendance: آخر كتابة تفوز ولو كانت مادة لا شعبة', () {
    final sessions = [
      ClassSession(id: 'room', groupId: '', sessionDate: '2026-09-11'),
      ClassSession(id: 'm3', groupId: 'math', sessionDate: '2026-09-11'),
      ClassSession(id: 'm1', groupId: 'math', sessionDate: '2026-09-10'),
      ClassSession(id: 'm2', groupId: 'sci', sessionDate: '2026-09-10'),
    ];
    final days = dailyAttendance(
      [
        AttendanceMark(
          studentId: 's',
          date: '2026-09-10',
          status: 'absent',
          sessionId: 'm1',
          updatedAt: '2026-09-10T08:00:00Z',
        ),
        AttendanceMark(
          studentId: 's',
          date: '2026-09-10',
          status: 'present',
          sessionId: 'm2',
          updatedAt: '2026-09-10T09:00:00Z',
        ),
        AttendanceMark(
          studentId: 's',
          date: '2026-09-11',
          status: 'present',
          sessionId: 'room',
          updatedAt: '2026-09-11T08:00:00Z',
        ),
        AttendanceMark(
          studentId: 's',
          date: '2026-09-11',
          status: 'absent',
          sessionId: 'm3',
          updatedAt: '2026-09-11T10:00:00Z',
        ),
      ],
      sessions,
    );
    expect(days.length, 2);
    expect(days[0], (date: '2026-09-11', status: 'absent'));
    expect(days[1], (date: '2026-09-10', status: 'present'));
  });

  test('dailyAttendance: عند تعادل الوقت تُفضَّل جلسة الشعبة', () {
    final sessions = [
      ClassSession(id: 'room', groupId: '', sessionDate: '2026-09-12'),
      ClassSession(id: 'subj', groupId: 'math', sessionDate: '2026-09-12'),
    ];
    final days = dailyAttendance(
      [
        AttendanceMark(
          studentId: 's',
          date: '2026-09-12',
          status: 'absent',
          sessionId: 'subj',
          updatedAt: '2026-09-12T08:00:00Z',
        ),
        AttendanceMark(
          studentId: 's',
          date: '2026-09-12',
          status: 'present',
          sessionId: 'room',
          updatedAt: '2026-09-12T08:00:00Z',
        ),
      ],
      sessions,
    );
    expect(days.single, (date: '2026-09-12', status: 'present'));
  });
}
