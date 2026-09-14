import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

final _sixDigits = RegExp(r'^\d{6}$');

Future<AppStore> school() async {
  final s = AppStore.forTesting();
  await s.bootstrap(FakeDisk());
  injectDemoData(s);
  await s.login('amal', 'amal2026');
  return s;
}

Student draft(AppStore s, {String nationalId = '123456789'}) => Student(
      id: s.newId(),
      fullName: 'طالب جديد للبوابة',
      gradeLevel: 'عاشر',
      section: 'عاشر (أ)',
      phone: '0599111222',
      parentName: 'ولي الأمر',
      parentPhone: '0598111222',
      balance: 0,
      nationalId: nationalId,
    );

void main() {
  test('the version matches Center 1.2.7', () {
    expect(appVersion, '1.2.7');
  });

  test('a portal code is six digits, as Center generates them', () async {
    final s = await school();
    for (var i = 0; i < 50; i++) {
      expect(_sixDigits.hasMatch(s.newPortalCode()), isTrue);
    }
  });

  test('registering a student issues a portal code', () async {
    final s = await school();
    final student = draft(s);
    expect(student.portalCode, isEmpty);

    s.upsertStudent(student, isNew: true);
    expect(_sixDigits.hasMatch(student.portalCode), isTrue);
  });

  test('an explicit code is kept rather than overwritten', () async {
    final s = await school();
    final student = draft(s)..portalCode = '654321';
    s.upsertStudent(student, isNew: true);
    expect(student.portalCode, '654321');
  });

  test('filling a class issues codes only to those without one', () async {
    final s = await school();
    final room = s.rooms.first;
    final list = s.studentsOf(room);
    expect(list.length, greaterThan(1));

    for (final student in list) {
      student.portalCode = '';
    }
    list.first.portalCode = '111111';

    final made = s.ensureStudentPortalCodes(list);
    expect(made, list.length - 1);
    expect(list.first.portalCode, '111111', reason: 'الرمز القائم لا يُستبدل');
    for (final student in list) {
      expect(_sixDigits.hasMatch(student.portalCode), isTrue);
    }
    // ولا شيء يُرفع مرتين بلا تغيير
    expect(s.ensureStudentPortalCodes(list), 0);
  });

  test('a teacher keeps an identity and a code for the teacher portal', () async {
    final s = await school();
    final teacher = s.teachers.first
      ..nationalId = '400400400'
      ..portalCode = '';

    final code = s.ensureTeacherPortalCode(teacher);
    expect(_sixDigits.hasMatch(code), isTrue);
    expect(s.ensureTeacherPortalCode(teacher), code, reason: 'لا يُعاد التوليد');

    final row = teacher.toCloud();
    expect(row['national_id'], '400400400');
    expect(row['portal_code'], code);
  });

  test('portal fields survive a round trip through the cloud shape', () async {
    final s = await school();
    final student = draft(s)..portalCode = '246810';
    final back = Student.fromCloud(student.toCloud());
    expect(back.portalCode, '246810');

    final teacher = Teacher(id: s.newId(), name: 'أ. تجريبي', phone: '0599000111', subject: 'الرياضيات')
      ..nationalId = '111222333'
      ..portalCode = '135790';
    final teacherBack = Teacher.fromCloud(teacher.toCloud());
    expect(teacherBack.nationalId, '111222333');
    expect(teacherBack.portalCode, '135790');
  });

  test('the new portal columns and tables are allowed through sync', () {
    expect(tableAllowedColumns['students'], contains('portal_code'));
    expect(tableAllowedColumns['teachers'], contains('portal_code'));
    expect(tableAllowedColumns['teachers'], contains('national_id'));
    expect(tableAllowedColumns.containsKey('class_announcements'), isTrue);
    expect(tableAllowedColumns.containsKey('student_evaluations'), isTrue);
    // الإعلانات الصفية أُزيلت من السحابة وحلّ محلها المودل: لا تُسحب
    expect(syncedTables, isNot(contains('class_announcements')));
    expect(syncedTables, contains('student_evaluations'));
  });

  test('a portal code reaches the cloud payload unstripped', () {
    final clean = sanitizePayload('students', {'id': 'x', 'portal_code': '135791'}, 't1');
    expect(clean['portal_code'], '135791');
  });

  test('an empty code is sent as null, not as an empty string', () async {
    final s = await school();
    final student = draft(s);
    expect(student.toCloud()['portal_code'], isNull);
  });
}
