import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `sectionEnrollmentIntegrity.test.ts`.
///
/// الموديل الواحد يشترك فيه أكثر من شعبة، وكان فصل شعبة عنه يمسّ التسجيلات
/// بمطابقة اسم الشعبة نصياً، فتضيع تسجيلات شعبة أخرى اسمها قريب. وكانت المادة بلا
/// معلم تُسقَط عند الحفظ.

AppStore _empty() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.rooms.clear();
  s.students.clear();
  s.subjects.clear();
  s.teachers.clear();
  s.groups.clear();
  s.enrollments.clear();
  return s;
}

Classroom _room(AppStore s, String id, String name, String grade) {
  final room = Classroom(id: id, name: name, gradeLevel: grade, capacity: 30, teacherId: '');
  s.rooms.add(room);
  return room;
}

Student _student(AppStore s, String id, String section, String grade) {
  final student = Student(
    id: id,
    fullName: 'طالب $id',
    gradeLevel: grade,
    section: section,
    phone: '0599000000',
    parentName: 'ولي',
    parentPhone: '0598000000',
    balance: 0,
    nationalId: '',
    status: 'active',
  );
  s.students.add(student);
  return student;
}

void _subject(AppStore s, String id, String name, String grade) =>
    s.subjects.add(SubjectItem(id: id, name: name, code: id, gradeLevel: grade));

void _teacher(AppStore s, String id, String name) =>
    s.teachers.add(Teacher(id: id, name: name, phone: '0599111222', subject: ''));

int _save(AppStore s, Classroom room, Map<String, String> assignments) => s.saveSectionSubjectAssignments(
      roomId: room.id,
      gradeLevel: room.gradeLevel,
      roomName: room.name,
      assignments: assignments,
    );

StudentEnrollment? _enrollment(AppStore s, String studentId, String groupId) =>
    s.enrollments.where((e) => e.studentId == studentId && e.groupId == groupId).firstOrNull;

void main() {
  group('سلامة تسجيلات الشعب في الموديل المشترك', () {
    test('فصل شعبة عن موديل مشترك لا يمسّ طلاب شعبة اسمها يبدأ بنفس الحروف', () {
      final s = _empty();
      const grade = 'ثاني عشر علمي';
      final room1 = _room(s, 'room-1', 'شعبة علمي 1', grade);
      final room10 = _room(s, 'room-10', 'شعبة علمي 10', grade);
      _subject(s, 'sub-math', 'الرياضيات', grade);
      _teacher(s, 'tch-1', 'أحمد');
      _student(s, 'stu-1', 'شعبة علمي 1', grade);
      _student(s, 'stu-10', 'شعبة علمي 10', grade);

      _save(s, room1, {'sub-math': 'tch-1'});
      _save(s, room10, {'sub-math': 'tch-1'});

      final shared = s.sectionSubjectGroups('room-1').single;
      expect(s.sectionSubjectGroups('room-10').single.id, shared.id, reason: 'مادة ومعلم ومرحلة: موديل واحد');
      expect(s.enrollmentsInGroup(shared.id), hasLength(2));

      // إلغاء المادة عن الشعبة 10 وحدها
      _save(s, room10, {});

      expect(_enrollment(s, 'stu-1', shared.id)?.status, 'active');
      expect(_enrollment(s, 'stu-10', shared.id)?.status, 'withdrawn');
      expect(s.enrollments.where((e) => e.groupId == shared.id), hasLength(2), reason: 'يُنهى ولا يُحذف');
      expect(s.groupById(shared.id)?.status, 'active');
      expect(s.groupById(shared.id)?.roomIds, ['room-1']);
    });

    test('طالب بلا مرحلة لا يُسجَّل تلقائياً في شعبة', () {
      final s = _empty();
      const grade = 'عاشر';
      final room = _room(s, 'room-a', 'شعبة (أ)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _teacher(s, 'tch-1', 'سامي');
      _student(s, 'stu-in', 'شعبة (أ)', grade);
      _student(s, 'stu-no-grade', 'شعبة (أ)', '');

      _save(s, room, {'sub-sci': 'tch-1'});

      final group = s.sectionSubjectGroups('room-a').single;
      expect(s.enrollmentsInGroup(group.id).map((e) => e.studentId), ['stu-in']);
    });

    test('مادة بلا معلم تبقى محفوظة بانتظار الإسناد', () {
      final s = _empty();
      const grade = 'عاشر';
      final room = _room(s, 'room-a', 'شعبة (أ)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _subject(s, 'sub-art', 'الفنون', grade);
      _teacher(s, 'tch-1', 'سامي');

      _save(s, room, {'sub-sci': 'tch-1', 'sub-art': ''});

      final groups = s.sectionSubjectGroups('room-a');
      expect(groups, hasLength(2));
      expect(groups.firstWhere((g) => g.subjectId == 'sub-art').teacherId, '');
    });

    test('حذف مادة يؤرشف مجموعتها فلا تبقى صفاً خفياً في قائمة الشعبة', () {
      final s = _empty();
      const grade = 'عاشر';
      final room = _room(s, 'room-a', 'شعبة (أ)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _subject(s, 'sub-art', 'الفنون', grade);
      _teacher(s, 'tch-1', 'سامي');

      _save(s, room, {'sub-sci': 'tch-1', 'sub-art': 'tch-1'});
      expect(s.sectionSubjectGroups('room-a'), hasLength(2));

      s.deleteSubject('sub-art');

      final groups = s.sectionSubjectGroups('room-a');
      expect(groups.single.subjectId, 'sub-sci');
    });

    test('نقل الطالب بين شعبتين ينقل تسجيلاته معه', () {
      final s = _empty();
      const grade = 'عاشر';
      final roomA = _room(s, 'room-a', 'شعبة (أ)', grade);
      final roomB = _room(s, 'room-b', 'شعبة (ب)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _teacher(s, 'tch-1', 'سامي');
      _teacher(s, 'tch-2', 'ليث');
      _student(s, 'stu-1', 'شعبة (أ)', grade);

      _save(s, roomA, {'sub-sci': 'tch-1'});
      _save(s, roomB, {'sub-sci': 'tch-2'});
      final groupA = s.sectionSubjectGroups('room-a').single;
      final groupB = s.sectionSubjectGroups('room-b').single;
      expect(groupA.id, isNot(groupB.id));

      s.assignSection(['stu-1'], 'شعبة (ب)');

      expect(_enrollment(s, 'stu-1', groupA.id)?.status, 'withdrawn');
      expect(_enrollment(s, 'stu-1', groupB.id)?.status, 'active');
      expect(_enrollment(s, 'stu-1', groupB.id)?.roomId, 'room-b');
    });

    test('تعديل شعبة الطالب من ملفه ينقل تسجيلاته أيضاً', () {
      final s = _empty();
      const grade = 'عاشر';
      final roomA = _room(s, 'room-a', 'شعبة (أ)', grade);
      final roomB = _room(s, 'room-b', 'شعبة (ب)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _teacher(s, 'tch-1', 'سامي');
      final student = _student(s, 'stu-1', 'شعبة (أ)', grade);

      _save(s, roomA, {'sub-sci': 'tch-1'});
      _save(s, roomB, {'sub-sci': 'tch-1'});
      final shared = s.sectionSubjectGroups('room-a').single;
      expect(_enrollment(s, 'stu-1', shared.id)?.roomId, 'room-a');

      final moved = Student(
        id: student.id,
        fullName: 'طالب منقول بعد التعديل',
        gradeLevel: grade,
        section: 'شعبة (ب)',
        phone: '0599000001',
        parentName: 'ولي',
        parentPhone: '0598000000',
        balance: 0,
        nationalId: '401092580',
        status: 'active',
      );
      s.upsertStudent(moved);

      final enrollment = _enrollment(s, 'stu-1', shared.id);
      expect(enrollment?.status, 'active', reason: 'الموديل مشترك بين الشعبتين');
      expect(enrollment?.roomId, 'room-b', reason: 'التسجيل يتبع شعبته الجديدة');
    });

    test('التسجيل المجدول المدفوع لا يمسّه منطق الشعب', () {
      final s = _empty();
      const grade = 'عاشر';
      _room(s, 'room-a', 'شعبة (أ)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _teacher(s, 'tch-1', 'سامي');
      _student(s, 'stu-1', 'شعبة (أ)', grade);

      s.groups.add(Group(
        id: 'grp-paid',
        name: 'دورة تقوية',
        subjectId: 'sub-sci',
        teacherId: 'tch-1',
        roomId: 'room-a',
        roomIds: ['room-a'],
        gradeLevel: grade,
        pricePerMonth: 150,
        days: [1, 3],
        startTime: '16:00',
        endTime: '17:30',
      ));
      s.enrollments.add(StudentEnrollment(
        id: 'enr-paid',
        studentId: 'stu-1',
        groupId: 'grp-paid',
        roomId: 'room-a',
        customPrice: 150,
        appliedPrice: 150,
      ));

      s.assignSection(['stu-1'], 'شعبة (ب)');

      final paid = s.enrollments.firstWhere((e) => e.id == 'enr-paid');
      expect(paid.status, 'active');
      expect(paid.appliedPrice, 150);
    });

    test('حذف شعبة يفصلها عن موديلها ويُبقيه لبقية شعبه', () {
      final s = _empty();
      const grade = 'عاشر';
      final roomA = _room(s, 'room-a', 'شعبة (أ)', grade);
      final roomB = _room(s, 'room-b', 'شعبة (ب)', grade);
      _subject(s, 'sub-sci', 'العلوم', grade);
      _teacher(s, 'tch-1', 'سامي');

      _save(s, roomA, {'sub-sci': 'tch-1'});
      _save(s, roomB, {'sub-sci': 'tch-1'});
      final shared = s.sectionSubjectGroups('room-a').single;

      s.deleteRoom('room-a');

      expect(s.groupById(shared.id)?.allRoomIds, ['room-b']);
      expect(s.groupById(shared.id)?.roomId, 'room-b');
    });
  });

  group('ربط التسجيلات القائمة بشعبها', () {
    test('يُحسم ما يمكن حسمه ويُترك الملتبس، مرة واحدة', () async {
      final s = _empty();
      await s.bootstrap(NoPersistence());
      const grade = 'عاشر';
      _room(s, 'room-a', 'شعبة (أ)', grade);
      _room(s, 'room-b', 'شعبة (ب)', grade);
      _student(s, 'stu-a', 'شعبة (أ)', grade);
      _student(s, 'stu-x', 'شعبة (س)', grade);

      s.groups.addAll([
        Group(id: 'g-one', name: 'مفرد', subjectId: '', teacherId: '', roomId: 'room-a', startTime: '', endTime: ''),
        Group(
          id: 'g-shared',
          name: 'مشترك',
          subjectId: '',
          teacherId: '',
          roomId: 'room-a',
          roomIds: ['room-a', 'room-b'],
          startTime: '',
          endTime: '',
        ),
      ]);
      s.enrollments.addAll([
        StudentEnrollment(id: 'e-one', studentId: 'stu-x', groupId: 'g-one'),
        StudentEnrollment(id: 'e-shared', studentId: 'stu-a', groupId: 'g-shared'),
        StudentEnrollment(id: 'e-unknown', studentId: 'stu-x', groupId: 'g-shared'),
      ]);

      expect(await s.migrateEnrollmentRooms(), 2);

      String roomOf(String id) => s.enrollments.firstWhere((e) => e.id == id).roomId;
      expect(roomOf('e-one'), 'room-a', reason: 'مجموعة بشعبة واحدة');
      expect(roomOf('e-shared'), 'room-a', reason: 'شعبة الطالب تحسم بين شعب الموديل');
      expect(roomOf('e-unknown'), '', reason: 'لا يقين: يُترك فارغاً');
      expect(s.pendingSyncs.where((p) => p.tableName == 'enrollments'), hasLength(2), reason: 'يُرفع كي لا يمحوه سحب');

      s.enrollments.firstWhere((e) => e.id == 'e-unknown').roomId = '';
      expect(await s.migrateEnrollmentRooms(), 0, reason: 'مرة واحدة');
    });
  });
}
