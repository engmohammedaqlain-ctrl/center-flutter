import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

/// عملية معلّقة على سجل بعينه.
bool _queued(AppStore s, String table, String id, String action) =>
    s.pendingSyncs.any((p) => p.tableName == table && p.recordId == id && p.action == action);

void main() {
  group('ما حُذف في السحابة يُحذف على الجهاز', () {
    final synced = {'id': 'r1', 'sync_status': 'synced', 'updated_at': '2026-09-01T00:00:00.000Z'};

    test('السجل المتزامن الغائب عن السحابة يُحذف', () {
      expect(
        rowsDeletedInCloud(local: [synced], cloudIds: {}, pendingIds: {}, lastPullAt: null),
        ['r1'],
        reason: 'السحب الكامل يوفّق الحذف كالتزايدي',
      );
      expect(
        rowsDeletedInCloud(local: [synced], cloudIds: {}, pendingIds: {}, lastPullAt: '2026-09-13T00:00:00.000Z'),
        ['r1'],
      );
    });

    test('الموجود في السحابة يبقى', () {
      expect(rowsDeletedInCloud(local: [synced], cloudIds: {'r1'}, pendingIds: {}, lastPullAt: null), isEmpty);
    });

    test('ما لم يُرفع بعد لا يُحذف: شغل المستخدم لا نسخة من السحابة', () {
      final pending = {'id': 'r2', 'sync_status': 'pending', 'updated_at': null};
      expect(rowsDeletedInCloud(local: [pending], cloudIds: {}, pendingIds: {}, lastPullAt: null), isEmpty);
      expect(
        rowsDeletedInCloud(local: [synced], cloudIds: {}, pendingIds: {'r1'}, lastPullAt: null),
        isEmpty,
        reason: 'له عملية في الطابور',
      );
    });

    test('ما عُدّل بعد آخر ختم يُترك لجولة قادمة', () {
      final fresh = {'id': 'r3', 'sync_status': 'synced', 'updated_at': '2026-09-13T10:00:00.000Z'};
      expect(
        rowsDeletedInCloud(local: [fresh], cloudIds: {}, pendingIds: {}, lastPullAt: '2026-09-13T09:00:00.000Z'),
        isEmpty,
      );
    });
  });

  group('الحذف يفكّ ما يشير إليه قبل أن يُرفع', () {
    test('حذف المعلم يفكّه من مجموعاته ومن الشعب التي هو مربّيها', () {
      final s = _seeded();
      final teacher = s.teachers.first;
      final group = s.groups.firstWhere((g) => g.teacherId == teacher.id);
      final room = s.rooms.first..teacherId = teacher.id;

      s.deleteTeacher(teacher.id);

      expect(s.teachers.any((t) => t.id == teacher.id), isFalse);
      expect(group.teacherId, '', reason: 'القيد الأجنبي كان يرفض حذف المعلم');
      expect(room.teacherId, '');
      expect(_queued(s, 'groups', group.id, 'UPDATE'), isTrue);
      expect(_queued(s, 'rooms', room.id, 'UPDATE'), isTrue);
      expect(_queued(s, 'teachers', teacher.id, 'DELETE'), isTrue);
    });

    test('حذف المادة يفكّ مجموعاتها منها', () {
      final s = _seeded();
      final subject = s.subjects.first;
      final group = s.groups.firstWhere((g) => g.subjectId == subject.id);

      s.deleteSubject(subject.id);

      expect(s.subjects.any((x) => x.id == subject.id), isFalse);
      expect(group.subjectId, '');
      expect(_queued(s, 'groups', group.id, 'UPDATE'), isTrue);
      expect(_queued(s, 'subjects', subject.id, 'DELETE'), isTrue);
    });

    test('حذف الشعبة يفكّ طلابها ومجموعاتها منها', () {
      final s = _seeded();
      final room = s.rooms.first;
      final student = s.students.first
        ..section = room.name
        ..gradeLevel = room.gradeLevel;
      final group = Group(
        id: s.newId(),
        name: 'مادة الشعبة',
        subjectId: s.subjects.first.id,
        teacherId: s.teachers.first.id,
        roomId: room.id,
        gradeLevel: room.gradeLevel,
      );
      s.groups.add(group);

      s.deleteRoom(room.id);

      expect(s.rooms.any((r) => r.id == room.id), isFalse);
      expect(student.section, '', reason: 'لا تبقى شعبةٌ اسماً لصف محذوف');
      expect(group.roomId, '');
      expect(_queued(s, 'students', student.id, 'UPDATE'), isTrue);
      expect(_queued(s, 'groups', group.id, 'UPDATE'), isTrue);
      expect(_queued(s, 'rooms', room.id, 'DELETE'), isTrue);
    });

    test('حذف الطالب يحذف معه أقساطه وحضوره وتسجيلاته', () {
      final s = _seeded();
      final student = s.students.first;
      // مسدَّدٌ حتى اليوم: ما استُحق عليه حُصِّل، والقادم لم يحن بعد
      for (final inst in s.installments.where((i) => i.studentId == student.id)) {
        inst.dueDate = DateTime.now().add(const Duration(days: 30));
      }
      s.recalculateAllBalances();
      expect(s.isSettledToDate(student.id), isTrue);
      final instIds = s.installments.where((i) => i.studentId == student.id).map((i) => i.id).toList();

      s.deleteStudent(student.id);

      expect(s.students.any((x) => x.id == student.id), isFalse);
      expect(s.installments.any((i) => i.studentId == student.id), isFalse);
      expect(s.attendance.any((a) => a.studentId == student.id), isFalse);
      expect(s.enrollments.any((e) => e.studentId == student.id), isFalse);
      for (final id in instIds) {
        expect(_queued(s, 'installments', id, 'DELETE'), isTrue, reason: 'يُحذف من السحابة أيضاً');
      }
      expect(_queued(s, 'students', student.id, 'DELETE'), isTrue);
    });

    test('الطالب الذي عليه مستحقات حتى اليوم لا يُحذف', () {
      final s = _seeded();
      final student = s.students.first;
      s.installments.add(Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'قسط متأخر',
        amount: 200,
        dueDate: DateTime.now().subtract(const Duration(days: 10)),
      ));
      s.recalculateAllBalances();

      expect(() => s.deleteStudent(student.id), throwsA(isA<StoreException>()));
      expect(s.students.any((x) => x.id == student.id), isTrue);

      // القسط القادم وحده لا يمنع: لم يُستحق بعد
      s.installments.removeWhere((i) => i.studentId == student.id);
      s.installments.add(Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'قسط قادم',
        amount: 200,
        dueDate: DateTime.now().add(const Duration(days: 20)),
      ));
      s.recalculateAllBalances();
      s.deleteStudent(student.id);
      expect(s.students.any((x) => x.id == student.id), isFalse);
    });

    test('المجموعة ذات السجلات تُؤرشف ولا تُحذف', () {
      final s = _seeded();
      final group = s.groups.firstWhere((g) => s.enrollments.any((e) => e.groupId == g.id));

      expect(s.deleteGroup(group.id), isFalse);
      expect(group.status, 'archived');
      expect(_queued(s, 'groups', group.id, 'UPDATE'), isTrue);
    });
  });
}
