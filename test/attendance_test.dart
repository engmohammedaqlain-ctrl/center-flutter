import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

Future<AppStore> school() async {
  final s = AppStore.forTesting();
  await s.bootstrap(FakeDisk());
  injectDemoData(s);
  await s.login('amal', 'amal2026');
  return s;
}

void main() {
  test('every attendance id is a uuid the cloud will accept', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final date = isoDate(DateTime.now());

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    final mark = s.attendanceRecord(student.id, date)!;
    expect(_uuid.hasMatch(mark.id), isTrue, reason: 'المعرّف ${mark.id} ليس uuid');

    // والرصد الجماعي كذلك
    s.markAllPresent(date, s.studentsOf(room), ownerId: room.id);
    for (final a in s.attendance) {
      expect(_uuid.hasMatch(a.id), isTrue, reason: 'المعرّف ${a.id} ليس uuid');
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
    final date = isoDate(DateTime.now());
    final student = s.studentsOf(a).first;

    final other = s.sessionFor(b.id, date, school: true);
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

  test('old text ids are rewritten as uuids and their stuck queue entries dropped', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final date = isoDate(DateTime.now());

    // سجل من إصدار سابق: معرّف نصي ترفضه السحابة، وعملية عالقة تشير إليه
    const staleId = 'att-abc-2026-09-09';
    s.attendance.add(
      AttendanceMark(id: staleId, studentId: student.id, date: date, status: 'present'),
    );
    queuePendingSync(
      s.pendingSyncs,
      tableName: 'attendance',
      recordId: staleId,
      action: 'INSERT',
      payload: {'id': staleId},
    );

    // الترحيل يجري مرة عند الدخول؛ نُعيده هنا على سجل قديم مُقحَم بعده
    await s.db.setSetting(attendanceIdMigrationKey, null);
    final moved = await s.migrateAttendanceIds();
    expect(moved, 1);
    expect(s.attendance.any((a) => a.id == staleId), isFalse);
    expect(s.pendingSyncs.any((p) => p.recordId == staleId), isFalse);

    final fresh = s.attendanceRecord(student.id, date)!;
    expect(_uuid.hasMatch(fresh.id), isTrue);
    expect(fresh.status, 'present', reason: 'الحالة تُنقل كما هي');
    expect(s.pendingSyncs.any((p) => p.recordId == fresh.id), isTrue);

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
    final session = s.sessionFor(room.id, isoDate(DateTime.now()), school: true);
    expect(session.groupId, room.id);
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

  test('switching days keeps each day independent', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final week = AppStore.schoolWeek(0);

    s.setAttendance(student.id, week[0].dateStr, 'present', ownerId: room.id);
    s.setAttendance(student.id, week[1].dateStr, 'absent', ownerId: room.id);

    expect(s.attendanceInSession(room.id, student.id, week[0].dateStr), 'present');
    expect(s.attendanceInSession(room.id, student.id, week[1].dateStr), 'absent');
    expect(s.attendanceInSession(room.id, student.id, week[2].dateStr), isNull);
  });
}
