import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
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

/// يجعل سجلات جدول تبدو كما لو وصلت من السحابة للتوّ.
void pretendSynced(AppStore s, String table, List<Map<String, dynamic>> rows) {
  s.putRows(table, [
    for (final r in rows) {...r, 'sync_status': 'synced'},
  ]);
  s.pendingSyncs.clear();
}

void main() {
  test('changing a mark then changing it back leaves nothing to push', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const date = '2026-05-04';

    // رصد أُنشئ ورُفع، ثم صار معروفاً للسحابة
    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    final mark = s.markFor(room.id, student.id, date)!;
    final session = s.sessionFor(room.id, date);
    pretendSynced(s, 'sessions', [session.toCloud()]);
    pretendSynced(s, 'attendance', [mark.toCloud()]);
    expect(s.pendingPush, 0);

    // حاضر ← غائب: تعديل حقيقي ينتظر الرفع
    s.setAttendance(student.id, date, 'absent', ownerId: room.id);
    expect(s.pendingPush, 1);
    expect(s.attendanceInSession(room.id, student.id, date), 'absent');

    // ورجوعه حاضراً يُعيد الحال إلى ما في السحابة، فلا شيء يُرفع
    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    expect(s.attendanceInSession(room.id, student.id, date), 'present');
    expect(
      s.pendingPush,
      0,
      reason: 'العدّاد يشير إلى تعديل لم يبقَ له أثر',
    );
  });

  test('a real change still queues', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const date = '2026-05-05';

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    final mark = s.markFor(room.id, student.id, date)!;
    pretendSynced(s, 'sessions', [s.sessionFor(room.id, date).toCloud()]);
    pretendSynced(s, 'attendance', [mark.toCloud()]);

    s.setAttendance(student.id, date, 'absent', ownerId: room.id);
    expect(s.pendingPush, 1);
  });

  test('the same holds for any record, not just attendance', () async {
    final s = await school();
    final teacher = s.teachers.first;
    pretendSynced(s, 'teachers', [teacher.toCloud()]);
    expect(s.pendingPush, 0);

    final original = teacher.name;
    s.upsertTeacher(teacher..name = 'اسم مؤقت');
    expect(s.pendingPush, 1);

    s.upsertTeacher(teacher..name = original);
    expect(s.pendingPush, 0, reason: 'الاسم عاد كما كان');
  });

  test('a record never pushed keeps its insert even after an edit and undo', () async {
    final s = await school();
    final student = Student(
      id: s.newId(),
      fullName: 'طالب لم يُرفع بعد',
      gradeLevel: 'عاشر',
      section: 'عاشر (أ)',
      phone: '0599777888',
      parentName: 'ولي',
      parentPhone: '0598777888',
      balance: 0,
      nationalId: '777888999',
    );
    s.pendingSyncs.clear();
    s.upsertStudent(student, isNew: true);
    expect(s.pendingSyncs.where((p) => p.recordId == student.id), hasLength(1));

    final before = student.fullName;
    s.upsertStudent(student..fullName = 'اسم آخر');
    s.upsertStudent(student..fullName = before);

    expect(
      s.pendingSyncs.where((p) => p.recordId == student.id),
      hasLength(1),
      reason: 'السجل لم يصل السحابة قط، فإنشاؤه ما زال مطلوباً',
    );
  });

  test('clearing a synced mark still queues its delete', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    const date = '2026-05-06';

    s.setAttendance(student.id, date, 'present', ownerId: room.id);
    final mark = s.markFor(room.id, student.id, date)!;
    pretendSynced(s, 'sessions', [s.sessionFor(room.id, date).toCloud()]);
    pretendSynced(s, 'attendance', [mark.toCloud()]);

    s.setAttendance(student.id, date, null, ownerId: room.id);
    expect(
      s.pendingSyncs.any((p) => p.recordId == mark.id && p.action == 'DELETE'),
      isTrue,
    );
  });
}
