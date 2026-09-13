import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

Group makeGroup(
  AppStore s, {
  String name = 'مجموعة',
  String? teacherId,
  String roomId = '',
  List<int> days = const [0, 2],
  String start = '16:00',
  String end = '18:00',
  int? max,
  double price = 100,
}) {
  return Group(
    id: s.newId(),
    name: name,
    subjectId: s.subjects.first.id,
    teacherId: teacherId ?? s.teachers.first.id,
    roomId: roomId,
    days: [...days],
    startTime: start,
    endTime: end,
    maxStudents: max,
    pricePerMonth: price,
  );
}

void main() {
  group('group validation', () {
    test('rejects a group with no name, subject, teacher or days', () {
      final s = seeded();
      expect(() => s.upsertGroup(makeGroup(s, name: '  ')), throwsA(isA<StoreException>()));
      expect(() => s.upsertGroup(makeGroup(s, days: const [])), throwsA(isA<StoreException>()));
      expect(
        () => s.upsertGroup(Group(id: s.newId(), name: 'x', subjectId: '', teacherId: 't', days: [0])),
        throwsA(isA<StoreException>()),
      );
    });

    test('accepts and stores a valid group', () {
      final s = seeded();
      final g = makeGroup(s, name: 'رياضيات توجيهي');
      s.upsertGroup(g);
      expect(s.groups.map((e) => e.name), contains('رياضيات توجيهي'));
      expect(s.groupById(g.id)?.daysLabel, 'الأحد، الثلاثاء');
      expect(g.timeLabel, '16:00 - 18:00');
    });
  });

  group('schedule conflicts', () {
    test('the same teacher cannot be in two overlapping groups', () {
      final s = seeded();
      s.upsertGroup(makeGroup(s, name: 'أ', days: const [0], start: '16:00', end: '18:00'));
      expect(
        () => s.upsertGroup(makeGroup(s, name: 'ب', days: const [0], start: '17:00', end: '19:00')),
        throwsA(predicate((e) => e is StoreException && e.message.contains('المدرّس'))),
      );
    });

    test('a shared room on the same slot conflicts too', () {
      final s = seeded();
      final room = s.rooms.first.id;
      s.upsertGroup(makeGroup(s, name: 'أ', roomId: room, days: const [1], start: '16:00', end: '18:00'));
      expect(
        () => s.upsertGroup(makeGroup(
          s,
          name: 'ب',
          teacherId: s.teachers[1].id,
          roomId: room,
          days: const [1],
          start: '17:30',
          end: '19:00',
        )),
        throwsA(predicate((e) => e is StoreException && e.message.contains('القاعة'))),
      );
    });

    test('touching but non-overlapping times are allowed', () {
      final s = seeded();
      final before = s.groups.length;
      s.upsertGroup(makeGroup(s, name: 'أ', days: const [0], start: '16:00', end: '18:00'));
      s.upsertGroup(makeGroup(s, name: 'ب', days: const [0], start: '18:00', end: '20:00'));
      expect(s.groups.length, before + 2);
    });

    test('different days never conflict', () {
      final s = seeded();
      final before = s.groups.length;
      s.upsertGroup(makeGroup(s, name: 'أ', days: const [0], start: '16:00', end: '18:00'));
      s.upsertGroup(makeGroup(s, name: 'ب', days: const [3], start: '16:00', end: '18:00'));
      expect(s.groups.length, before + 2);
    });

    test('an archived group does not block the slot', () {
      final s = seeded();
      final before = s.groups.length;
      final old = makeGroup(s, name: 'قديمة', days: const [0])..status = 'archived';
      s.upsertGroup(old);
      s.upsertGroup(makeGroup(s, name: 'جديدة', days: const [0]));
      expect(s.groups.length, before + 2);
    });

    test('editing a group does not conflict with itself', () {
      final s = seeded();
      final g = makeGroup(s, name: 'أ', days: const [0]);
      s.upsertGroup(g);
      g.name = 'أ معدّلة';
      s.upsertGroup(g);
      expect(s.groupById(g.id)?.name, 'أ معدّلة');
    });
  });

  group('enrollment', () {
    test('links a student at the group price and fixes it in place', () {
      final s = seeded();
      final g = makeGroup(s, price: 150);
      s.upsertGroup(g);
      final stu = s.students.first;
      final e = s.enrollStudent(studentId: stu.id, groupId: g.id);
      expect(e.appliedPrice, 150);

      // تغيير سعر المجموعة لاحقاً لا يحرّك السعر المثبَّت
      g.pricePerMonth = 400;
      s.upsertGroup(g);
      expect(s.enrollmentsOf(stu.id).firstWhere((x) => x.groupId == g.id).appliedPrice, 150);
    });

    test('a custom price and its reason are kept', () {
      final s = seeded();
      final g = makeGroup(s, price: 150);
      s.upsertGroup(g);
      final e = s.enrollStudent(
        studentId: s.students.first.id,
        groupId: g.id,
        customPrice: 90,
        discountReason: 'خصم إخوة',
      );
      expect(e.customPrice, 90);
      expect(e.appliedPrice, 90);
      expect(e.discountReason, 'خصم إخوة');
    });

    test('refuses a duplicate enrollment', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);
      final stu = s.students.first;
      s.enrollStudent(studentId: stu.id, groupId: g.id);
      expect(
        () => s.enrollStudent(studentId: stu.id, groupId: g.id),
        throwsA(predicate((e) => e is StoreException && e.message.contains('مسجَّل بالفعل'))),
      );
    });

    test('refuses to exceed the group capacity', () {
      final s = seeded();
      final g = makeGroup(s, max: 2);
      s.upsertGroup(g);
      s.enrollStudent(studentId: s.students[0].id, groupId: g.id);
      s.enrollStudent(studentId: s.students[1].id, groupId: g.id);
      expect(
        () => s.enrollStudent(studentId: s.students[2].id, groupId: g.id),
        throwsA(predicate((e) => e is StoreException && e.message.contains('اكتمل'))),
      );
    });

    test('a withdrawn enrollment frees the seat', () {
      final s = seeded();
      final g = makeGroup(s, max: 1);
      s.upsertGroup(g);
      final first = s.enrollStudent(studentId: s.students[0].id, groupId: g.id);
      s.updateEnrollmentStatus(first.id, 'withdrawn');
      expect(s.enrollmentCount(g.id), 0);
      s.enrollStudent(studentId: s.students[1].id, groupId: g.id);
      expect(s.enrollmentCount(g.id), 1);
    });

    test('studentsInGroup lists only active members', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);
      final a = s.enrollStudent(studentId: s.students[0].id, groupId: g.id);
      s.enrollStudent(studentId: s.students[1].id, groupId: g.id);
      expect(s.studentsInGroup(g.id).length, 2);
      s.updateEnrollmentStatus(a.id, 'paused');
      expect(s.studentsInGroup(g.id).length, 1);
    });
  });

  group('group deletion', () {
    test('a group with enrolments is archived, not deleted', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);
      s.enrollStudent(studentId: s.students.first.id, groupId: g.id);

      // الحذف الجذري يمحو قيوداً مالية وسجلات حضور معلّقة بالمجموعة
      expect(s.deleteGroup(g.id), isFalse);
      expect(s.groupById(g.id)?.status, 'archived');
    });

    test('a group that held sessions is archived with its sessions kept', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);
      s.sessionFor(g.id, isoDate(DateTime.now()), school: false);

      expect(s.deleteGroup(g.id), isFalse);
      expect(s.groupById(g.id)?.status, 'archived');
      expect(s.sessions.where((x) => x.groupId == g.id), isNotEmpty);
    });

    test('a group with no history at all is deleted', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);

      expect(s.deleteGroup(g.id), isTrue);
      expect(s.groupById(g.id), isNull);
    });

    test('an enrolment fee lands on the balance and leaves when removed', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);
      final stu = s.students.firstWhere((x) => s.paymentsOf(x.id).isEmpty);
      final before = stu.balance;

      final e = s.enrollStudent(studentId: stu.id, groupId: g.id);
      expect(stu.balance, closeTo(before - (e.appliedPrice ?? 0), 0.01), reason: 'رسوم المجموعة مديونية');

      s.deleteEnrollment(e.id);
      expect(stu.balance, closeTo(before, 0.01));
    });

    test('deleting a student clears their enrollments', () {
      final s = seeded();
      final g = makeGroup(s);
      s.upsertGroup(g);
      final stu = s.students.firstWhere((x) => s.paymentsOf(x.id).isEmpty);
      s.enrollStudent(studentId: stu.id, groupId: g.id);
      s.deleteStudent(stu.id);
      expect(s.enrollmentsOf(stu.id), isEmpty);
      expect(s.enrollmentCount(g.id), 0);
    });
  });

  group('sessions', () {
    test('are created once per owner and date, then reused', () {
      final s = seeded();
      final room = s.rooms.first.id;
      final date = isoDate(DateTime.now());
      final a = s.sessionFor(room, date);
      final b = s.sessionFor(room, date);
      expect(a.id, b.id);
      expect(s.sessions.where((x) => x.sessionDate == date && x.roomId == room).length, 1);
    });

    test('a centre session inherits the group time and teacher', () {
      final s = seeded();
      final g = makeGroup(s, start: '17:00', end: '19:00');
      s.upsertGroup(g);
      final session = s.sessionFor(g.id, isoDate(DateTime.now()), school: false);
      expect(session.startTime, '17:00');
      expect(session.endTime, '19:00');
      expect(session.teacherId, g.teacherId);
    });
  });
}
