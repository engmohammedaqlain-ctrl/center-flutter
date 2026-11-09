import 'package:center_mobile/data/dashboard_stats.dart';
import 'package:center_mobile/data/followup.dart';
import 'package:center_mobile/data/school_calendar.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'performance_test.dart' show hugeSchool;
import 'persistence_test.dart' show FakeDisk;

/// قرص يعدّ الصفوف المكتوبة بدل ترميزها: كلفة الكتابة تُقاس بعدد الصفوف لا بسرعة FakeDisk.
class _CountingDisk extends FakeDisk {
  int rows = 0;

  @override
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows) async => this.rows += rows.length;

  @override
  Future<void> saveRecords(String table, List<Map<String, dynamic>> rows) async => this.rows += rows.length;
}

int _ms(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  return sw.elapsedMilliseconds;
}

// ignore: avoid_print
void _report(String line) => print('BENCH $line');

/// مدرسة بحجم مدرسة المستر: ~1200 طالب و50 ألف رصد و12 ألف قسط، وجلسات سنة لعدة شعب.
/// يطبع الأرقام ولا يفشل إلا إن انكسر شيء — للمقارنة قبل وبعد.
void main() {
  test('BENCH مدرسة كبيرة: الرئيسية والكتابة والعلامات', () async {
    final disk = _CountingDisk();
    final s = await hugeSchool(disk);
    final today = DateTime.now();
    for (var r = 0; r < 12; r++) {
      for (var d = 0; d < 170; d++) {
        s.sessions.add(ClassSession(
          id: 'bench-ses-$r-$d',
          groupId: '',
          roomId: 'bench-room-$r',
          sessionDate: isoDate(today.subtract(Duration(days: d))),
        ));
      }
    }
    await s.flush();
    _report('السجلات: طلاب ${s.students.length} حضور ${s.attendance.length} جلسات ${s.sessions.length} أقساط ${s.installments.length}');

    DashboardStats stats() => buildDashboard(
          today: isoDate(today),
          students: s.students,
          rooms: s.roomsInViewedYear,
          sessions: s.sessions,
          attendance: s.attendance,
          installments: s.installments,
          payments: s.payments,
          calendar: s.settings.calendar,
          days: 30,
          chronicPercent: s.settings.followup.chronicPercent,
        );
    _report('buildDashboard (الشهر): ${_ms(stats)}ms');
    _report('buildDashboard مرة ثانية: ${_ms(stats)}ms');
    _report('loadAbsenceAlerts: ${_ms(() => loadAbsenceAlerts(s))}ms');
    _report('evaluations ×2: ${_ms(() {
      s.evaluations;
      s.evaluations;
    })}ms');

    // لمسة حضور واحدة ثم الحفظ: كم صفاً يُكتب على القرص؟
    // لمسة تحمية أولاً: ما بقي من أعمال الدخول (إعادة حساب الأرصدة) يُكتب معها لا مع المقيسة
    final huge = s.students.where((x) => x.id.startsWith('huge-')).toList();
    s.setAttendance(huge[1].id, isoDate(today), 'absent', ownerId: s.rooms.first.id);
    await s.flush();
    disk.rows = 0;
    final student = huge.first;
    final sw = Stopwatch()..start();
    s.setAttendance(student.id, isoDate(today), 'absent', ownerId: s.rooms.first.id);
    await s.flush();
    sw.stop();
    _report('لمسة حضور + حفظ: ${sw.elapsedMilliseconds}ms، صفوف مكتوبة ${disk.rows}');

    // ختم سيرفر لسجل واحد بعد رفعه
    disk.rows = 0;
    s.serverStamps.putIfAbsent('attendance', () => {});
    for (final a in s.attendance.take(50000)) {
      s.serverStamps['attendance']![a.id] = '2026-01-01T00:00:00Z';
    }
    await s.flush();
    disk.rows = 0;
    final sw2 = Stopwatch()..start();
    s.rememberServerStamps('attendance', {s.attendance.first.id: '2026-01-02T00:00:00Z'});
    await s.flush();
    sw2.stop();
    _report('ختم سجل واحد + حفظ: ${sw2.elapsedMilliseconds}ms، صفوف مكتوبة ${disk.rows}');

    expect(s.students, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
