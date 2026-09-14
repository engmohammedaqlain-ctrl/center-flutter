import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _store() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.rooms.clear();
  s.students.clear();
  return s;
}

Classroom _room(AppStore s, String name, {String grade = 'عاشر'}) {
  final room = Classroom(id: s.newId(), name: name, gradeLevel: grade, capacity: 25, teacherId: '');
  s.rooms.add(room);
  return room;
}

Student _student(AppStore s, {required String section, String grade = 'عاشر', String status = 'active'}) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب $section',
    gradeLevel: grade,
    section: section,
    phone: '0599000000',
    parentName: 'ولي',
    parentPhone: '0598000000',
    balance: 0,
    nationalId: '',
    status: status,
  );
  s.students.add(student);
  return student;
}

void main() {
  group('طلاب الشعبة', () {
    test('الطالب بلا شعبة لا يُحسب على كل شعب مرحلته', () {
      final s = _store();
      final a = _room(s, 'شعبة (أ)');
      final b = _room(s, 'شعبة (ب)');
      _student(s, section: '');

      expect(s.studentsOf(a), isEmpty, reason: 'مكانه غير معروف بين شعبتين');
      expect(s.studentsOf(b), isEmpty);
    });

    test('الطالب بلا شعبة يُحسب حين تكون لمرحلته شعبة واحدة', () {
      final s = _store();
      final only = _room(s, 'شعبة (أ)');
      final student = _student(s, section: '');

      expect(s.studentsOf(only).map((e) => e.id), [student.id], reason: 'مكانه معروف: لا شعبة غيرها');

      // فتح شعبة ثانية يُسقط النسبة المفترضة
      _room(s, 'شعبة (ب)');
      expect(s.studentsOf(only), isEmpty);
    });

    test('الإسناد الصريح يثبّت الشعبة في ملف الطالب', () {
      final s = _store();
      final a = _room(s, 'شعبة (أ)');
      _room(s, 'شعبة (ب)');
      final student = _student(s, section: '');

      expect(s.sectionCandidates(a).map((e) => e.id), contains(student.id));
      expect(s.assignSection([student.id], a.name), 1);
      expect(s.studentsOf(a).map((e) => e.id), [student.id]);
      expect(s.assignSection([student.id], a.name), 0, reason: 'موجود فيها أصلاً');
    });

    test('الإسناد ينقل الطالب من شعبته السابقة', () {
      final s = _store();
      final a = _room(s, 'شعبة (أ)');
      final b = _room(s, 'شعبة (ب)');
      final student = _student(s, section: 'شعبة (أ)');
      expect(s.studentsOf(a), hasLength(1));

      s.assignSection([student.id], b.name);

      expect(s.studentsOf(a), isEmpty, reason: 'الطالب في شعبة واحدة');
      expect(s.studentsOf(b).map((e) => e.id), [student.id]);
      expect(
        s.pendingSyncs.any((p) => p.tableName == 'students' && p.recordId == student.id),
        isTrue,
        reason: 'النقل يصل بقية الأجهزة',
      );
    });

    test('الطالب لا يظهر إلا في شعبته', () {
      final s = _store();
      final a = _room(s, 'شعبة (أ)');
      final b = _room(s, 'شعبة (ب)');
      final inA = _student(s, section: 'أ');

      expect(s.studentsOf(a).map((e) => e.id), [inA.id]);
      expect(s.studentsOf(b), isEmpty);
    });

    test('المؤرشف خريجٌ لا يُحسب على شعبته', () {
      final s = _store();
      final room = _room(s, 'شعبة (أ)');
      _student(s, section: 'أ', status: 'archived');

      expect(s.studentsOf(room), isEmpty);
    });

    test('صفوف المزامنة تحمل حالتها، وبها وحدها يعرف السحب المحذوف من السحابة', () {
      final s = _store();
      final room = _room(s, 'شعبة (أ)');

      // سجل محلي لم يُرفع بعد: لا يُلمس عند توفيق الحذف
      s.upsertRoom(room);
      expect(s.allOf('rooms').single['sync_status'], 'pending');
      expect(s.recordOf('rooms', room.id)!['sync_status'], 'pending');

      // بعد رفعه يصير مطابقاً للسحابة: غيابه منها لاحقاً يعني أنه حُذف فيها
      s.markSynced('rooms', room.id);
      expect(s.allOf('rooms').single['sync_status'], 'synced');
    });

    test('اختلاف المرحلة يمنع المطابقة ولو تشابهت أسماء الشعب', () {
      final s = _store();
      final tenth = _room(s, 'شعبة (أ)');
      _room(s, 'شعبة (أ)', grade: 'حادي عشر علمي');
      _student(s, section: 'أ', grade: 'حادي عشر علمي');

      expect(s.studentsOf(tenth), isEmpty, reason: 'طالب مرحلة أخرى');
    });
  });
}
