import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

void main() {
  group('مواد الشعبة ومعلموها', () {
    test('الإسناد يُنشئ مجموعة لكل مادة باسم «المادة - الشعبة»', () {
      final s = _seeded();
      final room = s.rooms.first;
      final subject = s.subjects.first;
      final teacher = s.teachers.first;

      final count = s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: {subject.id: teacher.id},
      );

      expect(count, 1);
      final group = s.sectionSubjectGroups(room.id).single;
      expect(group.name, '${subject.name} - ${room.name}');
      expect(group.teacherId, teacher.id);
      expect(group.roomId, room.id);
      expect(group.days, isEmpty, reason: 'وعاء لا حصة لها موعد');
      expect(group.pricePerMonth, 0);
    });

    test('طلاب الشعبة يُربطون بلا رسوم فلا يتغيّر رصيدهم', () {
      final s = _seeded();
      final room = s.rooms.first;
      final roster = s.studentsOf(room);
      expect(roster, isNotEmpty);
      final before = {for (final st in roster) st.id: st.balance};

      s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: {s.subjects.first.id: s.teachers.first.id},
      );

      final group = s.sectionSubjectGroups(room.id).single;
      expect(s.studentsInGroup(group.id).length, roster.length);
      for (final st in roster) {
        expect(s.computeStudentBalance(st.id), closeTo(before[st.id]!, 0.01), reason: 'الربط للعرض لا للمحاسبة');
      }
    });

    test('إعادة الحفظ لا تكرّر التسجيل ولا المجموعة', () {
      final s = _seeded();
      final room = s.rooms.first;
      final assignments = {s.subjects.first.id: s.teachers.first.id};

      s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: assignments,
      );
      final groupId = s.sectionSubjectGroups(room.id).single.id;
      final enrolled = s.enrollmentsInGroup(groupId).length;

      s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: {...assignments, s.subjects.first.id: s.teachers[1].id},
      );

      expect(s.sectionSubjectGroups(room.id).single.id, groupId, reason: 'المجموعة نفسها تُحدَّث');
      expect(s.sectionSubjectGroups(room.id).single.teacherId, s.teachers[1].id);
      expect(s.enrollmentsInGroup(groupId).length, enrolled);
    });

    test('رفع الإسناد يؤرشف المجموعة ولا يحذفها', () {
      final s = _seeded();
      final room = s.rooms.first;
      final subject = s.subjects.first;

      s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: {subject.id: s.teachers.first.id},
      );
      final groupId = s.sectionSubjectGroups(room.id).single.id;

      s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: {subject.id: ''},
      );

      expect(s.sectionSubjectGroups(room.id), isEmpty);
      expect(s.groupById(groupId)?.status, 'archived', reason: 'لها حضور وتقييمات');
    });

    test('عدد معلمي الصف يجمع المربي ومعلمي المواد بلا تكرار', () {
      final s = _seeded();
      final room = s.rooms.firstWhere((r) => r.teacherId.isNotEmpty);
      expect(s.sectionTeacherIds(room).length, 1, reason: 'المربي وحده قبل الإسناد');

      s.saveSectionSubjectAssignments(
        roomId: room.id,
        gradeLevel: room.gradeLevel,
        roomName: room.name,
        assignments: {
          s.subjects[0].id: room.teacherId,
          s.subjects[1].id: s.teachers.firstWhere((t) => t.id != room.teacherId).id,
        },
      );

      expect(s.sectionTeacherIds(room).length, 2, reason: 'المربي لا يُعدّ مرتين');
    });

    test('مواد المرحلة: العام ينطبق على الجميع والمخصص على مرحلته', () {
      final s = _seeded();
      final general = SubjectItem(id: s.newId(), name: 'تربية وطنية', code: 'NAT');
      final tenth = SubjectItem(id: s.newId(), name: 'أحياء عاشر', code: 'BIO', gradeLevel: 'عاشر');
      s.subjects.addAll([general, tenth]);

      final forTenth = s.gradeApplicableSubjects('عاشر').map((x) => x.id).toList();
      expect(forTenth, contains(general.id));
      expect(forTenth, contains(tenth.id));

      final forTwelfth = s.gradeApplicableSubjects('ثاني عشر أدبي').map((x) => x.id).toList();
      expect(forTwelfth, contains(general.id));
      expect(forTwelfth, isNot(contains(tenth.id)));

      expect(s.gradeApplicableSubjects('').length, s.subjects.length, reason: 'بلا مرحلة: الكل');
    });

    test('الوقت الفارغ القادم من السحابة لا يوقف السحب', () {
      final g = Group.fromCloud({
        'id': 'g1',
        'name': 'رياضيات - عاشر (أ)',
        'subject_id': 's1',
        'teacher_id': 't1',
        'room_id': 'r1',
        'start_time': '',
        'end_time': '',
        'days': [],
      });
      expect(g.startTime, '');
      expect(g.timeLabel, 'غير محدد');
      expect(g.isSectionSubject, isTrue);
    });
  });
}
