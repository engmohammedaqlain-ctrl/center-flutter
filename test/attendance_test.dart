import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

Future<AppStore> school() async {
  final s = AppStore.forTesting();
  await s.bootstrap(FakeDisk());
  injectDemoData(s);
  await s.login('amal', 'amal2026');
  return s;
}

void main() {
  test('admin and teacher produce the same deterministic attendance id', () async {
    final s = await school();
    final room = s.rooms.first;
    final list = s.studentsOf(room);
    // يوم بلا رصد تجريبي حتى يُنشأ الصف بالمعرّف الحتمي لا يُحدَّث صف قديم
    const date = '2026-06-15';
    s.attendance.removeWhere((a) => a.date == date);

    final session = s.sessionFor(room.id, date);
    final student = list.first;
    final expected = AppStore.attendanceIdFor(session.id, student.id);

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    expect(s.attendanceRecord(student.id, date)!.id, expected, reason: 'الإدارة تكتب المعرّف الحتمي');
    // بوابة المعلم تستخدم نفس الدالة — نفس الصف في السحابة
    expect(AppStore.attendanceIdFor(session.id, student.id), expected);

    s.markAllPresent(date, list, ownerId: room.id);
    for (final a in s.attendance.where((a) => a.sessionId == session.id)) {
      expect(a.id, AppStore.attendanceIdFor(session.id, a.studentId));
    }
  });

  test('marking then reading back returns the same status', () async {
    final s = await school();
    final room = s.rooms.first;
    final list = s.studentsOf(room);
    final date = isoDate(DateTime.now());

    for (final student in list) {
      s.setAttendance(student.id, date, 'present', ownerId: room.id);
    }
    for (final student in list) {
      expect(
        s.attendanceInSession(room.id, student.id, date),
        'present',
        reason: 'الرصد يجب أن يظهر فوراً لكل طالب',
      );
    }
  });

  test('a mark from another device is not hidden by its unknown session', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final date = isoDate(DateTime.now());

    // سجل وصل من السحابة يتبع جلسة أنشأها جهاز آخر ولا نسخة منها هنا
    s.attendance.add(
      AttendanceMark(
        id: s.newId(),
        studentId: student.id,
        date: date,
        status: 'absent',
        sessionId: 'session-from-another-device',
      ),
    );
    s.notifySync();

    expect(
      s.attendanceInSession(room.id, student.id, date),
      'absent',
      reason: 'جلسة مجهولة محلياً لا تُخفي رصداً موجوداً',
    );
  });

  test('a mark belonging to another class does not leak into this one', () async {
    final s = await school();
    final a = s.rooms[0];
    final b = s.rooms[1];
    // يوم لا تحمل البيانات التجريبية رصداً فيه، حتى يُختبر الفصل وحده
    const date = '2026-04-15';
    final student = s.studentsOf(a).first;

    final other = s.sessionFor(b.id, date);
    s.attendance.add(
      AttendanceMark(
        id: s.newId(),
        studentId: student.id,
        date: date,
        status: 'present',
        sessionId: other.id,
      ),
    );
    s.notifySync();

    expect(s.attendanceInSession(b.id, student.id, date), 'present');
    expect(s.attendanceInSession(a.id, student.id, date), isNull);
  });

  test('clearing a mark removes it and queues the delete', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final date = isoDate(DateTime.now());

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    final id = s.attendanceRecord(student.id, date)!.id;

    s.setAttendance(student.id, date, null, ownerId: room.id);
    expect(s.attendanceRecord(student.id, date), isNull);
    expect(
      s.pendingSyncs.any((p) => p.tableName == 'attendance' && p.recordId == id && p.action == 'DELETE'),
      isTrue,
    );
  });

  test('legacy room sessions with group_id are migrated to room_id shape', () async {
    // بلا تسجيل دخول: الترحيل يجري تلقائياً بعده، فيسبق ما يريده الاختبار
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);
    final room = s.rooms.first;
    const date = '2026-05-01';
    final wantedId = AppStore.roomSessionIdFor(room.id, date);

    // شكل قديم: معرّف الشعبة في group_id بدل room_id
    s.sessions.add(ClassSession(
      id: 'legacy-room-session',
      groupId: room.id,
      sessionDate: date,
      startTime: '08:00',
      endTime: '10:00',
      teacherId: '',
      roomId: room.id,
      status: 'scheduled',
    ));
    final student = s.studentsOf(room).first;
    s.attendance.add(AttendanceMark(
      id: 'att-legacy-1',
      studentId: student.id,
      date: date,
      status: 'present',
      sessionId: 'legacy-room-session',
    ));

    final moved = await s.migrateAttendanceIds();
    expect(moved, greaterThan(0));
    expect(s.sessions.any((x) => x.id == 'legacy-room-session'), isFalse);
    final migrated = s.sessions.firstWhere((x) => x.id == wantedId);
    expect(migrated.groupId, '');
    expect(migrated.roomId, room.id);

    final mark = s.attendance.firstWhere((a) => a.studentId == student.id && a.date == date);
    expect(mark.sessionId, wantedId);
    expect(mark.id, AppStore.attendanceIdFor(wantedId, student.id));
    expect(mark.status, 'present');

    // لا تُعاد مرة ثانية على نفس الجهاز
    expect(await s.migrateAttendanceIds(), 0);
  });

  test('attendance upserts resolve on the natural key the cloud enforces', () {
    // uq_attendance_session_student = UNIQUE (tenant_id, session_id, student_id)
    expect(tableConflictTarget['attendance'], 'tenant_id,session_id,student_id');
    expect(tableConflictTarget['students'], isNull, reason: 'البقية تتصالح على المعرّف');
  });

  test('a school session keeps the desktop shape so both write one row', () async {
    final s = await school();
    final room = s.rooms.first;
    final session = s.sessionFor(room.id, isoDate(DateTime.now()));
    expect(session.groupId, '');
    expect(session.roomId, room.id);
  });

  test('the marked day survives a restart', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    await first.login('amal', 'amal2026');

    final room = first.rooms.first;
    final student = first.studentsOf(room).first;
    final week = AppStore.schoolWeek(0);
    final day = week[1].dateStr;

    first.setAttendance(student.id, day, 'absent', ownerId: room.id);
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(
      second.attendanceRecord(student.id, day)?.status,
      'absent',
      reason: 'اليوم المرصود يُحفظ محلياً ولا يُشتق من وقت الإنشاء',
    );
  });

  test('a cloud mark takes its day from the session, not from created_at', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const day = '2026-03-04';

    // جلسة وصلت من السحابة ليوم غير يوم إنشاء السجل
    s.putRows('sessions', [
      {
        'id': 'cloud-session-1',
        'group_id': room.id,
        'room_id': room.id,
        'session_date': day,
        'start_time': '08:00',
        'end_time': '10:00',
        'status': 'scheduled',
      }
    ]);
    s.putRows('attendance', [
      {
        'id': 'cloud-att-1',
        'session_id': 'cloud-session-1',
        'student_id': student.id,
        'status': 'absent',
        'created_at': '2026-09-09T05:00:00Z',
      }
    ]);

    expect(s.attendanceRecord(student.id, day)?.status, 'absent');
    expect(s.attendanceInSession(room.id, student.id, day), 'absent');

    // ورصد نفس اليوم يُحدّث السجل القائم بدل إنشاء صف يصطدم بالقيد الفريد
    s.setAttendance(student.id, day, 'present', ownerId: room.id);
    expect(s.attendanceRecord(student.id, day)!.id, 'cloud-att-1');
    expect(s.attendance.where((a) => a.studentId == student.id && a.date == day), hasLength(1));
  });

  test('a tap lands on the same record the screen is reading', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const date = '2026-04-20';

    // سجلان لنفس الطالب واليوم: واحد يخص صفاً آخر. القارئ كان يأخذ الأخير
    // والكاتب الأول، فتبدو النقرة بلا أثر.
    final other = s.sessionFor(s.rooms[1].id, date);
    s.attendance.add(AttendanceMark(
      id: s.newId(),
      studentId: student.id,
      date: date,
      status: 'absent',
      sessionId: other.id,
    ));
    s.notifySync();

    expect(s.attendanceInSession(room.id, student.id, date), isNull);

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    expect(
      s.attendanceInSession(room.id, student.id, date),
      'present',
      reason: 'النقرة تظهر فوراً في الصف الذي رُصد منه',
    );
    // ولا تمسّ رصد الصف الآخر
    expect(s.attendanceInSession(s.rooms[1].id, student.id, date), 'absent');
  });

  test('mark-all-present reaches every student, even ones tied elsewhere', () async {
    final s = await school();
    final room = s.rooms.first;
    final list = s.studentsOf(room);
    const date = '2026-04-21';
    expect(list.length, greaterThan(1));

    // طالب سجله مرتبط بجلسة صف آخر، وآخر مرصود غائباً هنا
    final other = s.sessionFor(s.rooms[1].id, date);
    s.attendance.add(AttendanceMark(
      id: s.newId(),
      studentId: list.first.id,
      date: date,
      status: 'absent',
      sessionId: other.id,
    ));
    s.setAttendance(list.last.id, date, 'absent', ownerId: room.id);

    s.markAllPresent(date, list, ownerId: room.id);

    for (final student in list) {
      expect(
        s.attendanceInSession(room.id, student.id, date),
        'present',
        reason: 'لم يتخلّف ${student.fullName} عن «الكل حاضر»',
      );
    }
  });

  test('marking the same status twice does nothing', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const date = '2026-04-22';

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    final queued = s.pendingSyncs.length;

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    expect(s.pendingSyncs.length, queued, reason: 'لا كتابة ولا إخطار بلا تغيير');
  });

  test('duplicate marks for one session and student are collapsed', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const date = '2026-04-23';
    final session = s.sessionFor(room.id, date);

    for (final status in ['present', 'absent', 'present']) {
      s.attendance.add(AttendanceMark(
        id: s.newId(),
        studentId: student.id,
        date: date,
        status: status,
        sessionId: session.id,
        updatedAt: '2026-04-23T0${['1', '2', '3'][['present', 'absent', 'present'].indexOf(status)]}:00:00Z',
      ));
    }
    s.notifySync();

    final dropped = s.dedupeAttendance();
    expect(dropped, 2, reason: 'القيد الفريد يقبل صفاً واحداً لكل (جلسة، طالب)');
    expect(
      s.attendance.where((a) => a.sessionId == session.id && a.studentId == student.id),
      hasLength(1),
    );
  });

  test('switching days keeps each day independent', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final week = AppStore.schoolWeek(0);
    // الديمو يرصد أياماً قريبة، ومنها اليوم نفسه: تُمحى كي يُختبر الرصد وحده
    s.attendance.removeWhere((a) => a.studentId == student.id);

    s.setAttendance(student.id, week[0].dateStr, 'present', ownerId: room.id);
    s.setAttendance(student.id, week[1].dateStr, 'absent', ownerId: room.id);

    expect(s.attendanceInSession(room.id, student.id, week[0].dateStr), 'present');
    expect(s.attendanceInSession(room.id, student.id, week[1].dateStr), 'absent');
    expect(s.attendanceInSession(room.id, student.id, week[2].dateStr), isNull);
  });
}
