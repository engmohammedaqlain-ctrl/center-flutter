import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

int _save(AppStore s, Classroom room, Map<String, String> assignments) => s.saveSectionSubjectAssignments(
      roomId: room.id,
      gradeLevel: room.gradeLevel,
      roomName: room.name,
      assignments: assignments,
    );

void main() {
  group('مواد الشعبة ومعلموها', () {
    test('الإسناد يُنشئ موديلاً لكل مادة باسم «المادة - المعلم»', () {
      final s = _seeded();
      final room = s.rooms.first;
      final subject = s.subjects.first;
      final teacher = s.teachers.first;

      expect(_save(s, room, {subject.id: teacher.id}), 1);

      final group = s.sectionSubjectGroups(room.id).single;
      expect(group.name, '${subject.name} - ${teacher.name}');
      expect(group.teacherId, teacher.id);
      expect(group.allRoomIds, [room.id]);
      expect(group.days, isEmpty, reason: 'وعاء لا حصة لها موعد');
      expect(group.pricePerMonth, 0);
      expect(group.isSchoolGroup, isTrue);
    });

    test('طلاب الشعبة يُربطون بشعبتهم بلا رسوم فلا يتغيّر رصيدهم', () {
      final s = _seeded();
      final room = s.rooms.first;
      final roster = s.studentsOf(room);
      expect(roster, isNotEmpty);
      final before = {for (final st in roster) st.id: st.balance};

      _save(s, room, {s.subjects.first.id: s.teachers.first.id});

      final group = s.sectionSubjectGroups(room.id).single;
      expect(s.studentsInGroup(group.id).length, roster.length);
      expect(s.enrollmentsInGroup(group.id).every((e) => e.roomId == room.id), isTrue, reason: 'التسجيل مختوم بشعبته');
      for (final st in roster) {
        expect(s.computeStudentBalance(st.id), closeTo(before[st.id]!, 0.01), reason: 'الربط للعرض لا للمحاسبة');
      }
    });

    test('إعادة الحفظ بلا تغيير لا تكرّر التسجيل ولا الموديل', () {
      final s = _seeded();
      final room = s.rooms.first;
      final assignments = {s.subjects.first.id: s.teachers.first.id};

      _save(s, room, assignments);
      final groupId = s.sectionSubjectGroups(room.id).single.id;
      final enrolled = s.enrollmentsInGroup(groupId).length;

      _save(s, room, assignments);

      expect(s.sectionSubjectGroups(room.id).single.id, groupId);
      expect(s.enrollmentsInGroup(groupId).length, enrolled);
    });

    test('تغيير المعلم ينقل الشعبة إلى موديل المعلم الجديد', () {
      final s = _seeded();
      final room = s.rooms.first;
      final subject = s.subjects.first;

      _save(s, room, {subject.id: s.teachers[0].id});
      final oldId = s.sectionSubjectGroups(room.id).single.id;
      final roster = s.studentsInGroup(oldId).length;

      _save(s, room, {subject.id: s.teachers[1].id});

      final current = s.sectionSubjectGroups(room.id).single;
      expect(current.id, isNot(oldId));
      expect(current.teacherId, s.teachers[1].id);
      expect(s.studentsInGroup(current.id).length, roster);
      expect(s.groupById(oldId)?.status, 'archived', reason: 'لا شعبة بقيت عليه');
      expect(s.enrollmentsInGroup(oldId), isEmpty, reason: 'تسجيلاته أُنهيت لا حُذفت');
      expect(s.enrollments.where((e) => e.groupId == oldId), isNotEmpty);
    });

    test('إزالة المادة من قائمة الشعبة تؤرشف موديلها ولا تحذفه', () {
      final s = _seeded();
      final room = s.rooms.first;
      final subject = s.subjects.first;

      _save(s, room, {subject.id: s.teachers.first.id});
      final groupId = s.sectionSubjectGroups(room.id).single.id;

      _save(s, room, {});

      expect(s.sectionSubjectGroups(room.id), isEmpty);
      expect(s.groupById(groupId)?.status, 'archived', reason: 'لها حضور وتقييمات');
    });

    test('عدد معلمي الصف يجمع المربي ومعلمي المواد بلا تكرار', () {
      final s = _seeded();
      final room = s.rooms.firstWhere((r) => r.teacherId.isNotEmpty);
      expect(s.sectionTeacherIds(room).length, 1, reason: 'المربي وحده قبل الإسناد');

      _save(s, room, {
        s.subjects[0].id: room.teacherId,
        s.subjects[1].id: s.teachers.firstWhere((t) => t.id != room.teacherId).id,
      });

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

    test('الوقت الفارغ القادم من السحابة لا يوقف السحب، وشعب الموديل تُقرأ', () {
      final g = Group.fromCloud({
        'id': 'g1',
        'name': 'رياضيات - أحمد',
        'subject_id': 's1',
        'teacher_id': 't1',
        'room_id': 'r1',
        'room_ids': ['r1', 'r2'],
        'start_time': '',
        'end_time': '',
        'days': [],
      });
      expect(g.startTime, '');
      expect(g.timeLabel, 'غير محدد');
      expect(g.isSectionSubject, isTrue);
      expect(g.includesRoom('r2'), isTrue);

      final legacy = Group.fromCloud({'id': 'g2', 'name': 'قديم', 'room_id': 'r9', 'days': []});
      expect(legacy.allRoomIds, ['r9'], reason: 'سجل قديم بلا room_ids يبقى على شعبته');
    });
  });
}
