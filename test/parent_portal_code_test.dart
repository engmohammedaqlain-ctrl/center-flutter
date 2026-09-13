import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _sixDigits = RegExp(r'^\d{6}$');

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

void main() {
  group('كلمة مرور ولي الأمر', () {
    test('تمرّ عبر شكل السحابة بالعمود نفسه الذي يقرأه سطح المكتب', () {
      final student = _seeded().students.first..parentPortalCode = '246810';
      final row = student.toCloud();
      expect(row['parent_portal_code'], '246810');
      expect(Student.fromCloud(row).parentPortalCode, '246810');

      student.parentPortalCode = '';
      expect(student.toCloud()['parent_portal_code'], isNull, reason: 'الفارغ يُرسل null لا نصاً فارغاً');
    });

    test('التوليد يملأ الكلمتين ولا تتساويان', () {
      final s = _seeded();
      final list = s.students.take(5).toList();
      for (final st in list) {
        st
          ..portalCode = ''
          ..parentPortalCode = '';
      }

      expect(s.ensureStudentPortalCodes(list), list.length);
      for (final st in list) {
        expect(_sixDigits.hasMatch(st.portalCode), isTrue);
        expect(_sixDigits.hasMatch(st.parentPortalCode), isTrue);
        expect(st.parentPortalCode, isNot(st.portalCode), reason: 'السيرفر يرفض الدخول حين تتساويان');
      }
      expect(s.ensureStudentPortalCodes(list), 0, reason: 'لا يُعاد التوليد لمن اكتملت كلمتاه');
    });

    test('الكلمة القائمة لا تُستبدل، والناقصة وحدها تُولَّد', () {
      final s = _seeded();
      final st = s.students.first
        ..portalCode = '111111'
        ..parentPortalCode = '';

      expect(s.ensureStudentPortalCodes([st]), 1);
      expect(st.portalCode, '111111');
      expect(_sixDigits.hasMatch(st.parentPortalCode), isTrue);
      expect(st.parentPortalCode, isNot('111111'));
    });

    test('الرمز المختلف لا يساوي الرمز الآخر أبداً', () {
      final s = _seeded();
      for (var i = 0; i < 300; i++) {
        final other = s.newPortalCode();
        expect(s.newDistinctPortalCode(other), isNot(other));
      }
    });

    test('البيانات التجريبية تحمل الكلمتين مختلفتين لكل طالب، ومعها حساب ولي أمر', () {
      final s = AppStore.forTesting();
      final stats = injectDemoData(s);
      for (final st in s.students) {
        expect(_sixDigits.hasMatch(st.parentPortalCode), isTrue, reason: st.fullName);
        expect(st.parentPortalCode, isNot(st.portalCode));
      }
      expect(stats.parent.nationalId, stats.student.nationalId, reason: 'ولي الأمر يدخل برقم هوية ابنه');
      expect(stats.parent.portalCode, isNot(stats.student.portalCode));
    });
  });

  group('خيار الدخول كما تعيده دالة portal-login', () {
    test('ولي الأمر: معرّف ابنه واسمه، واسم ولي الأمر للترويسة', () {
      final user = PortalService.userFromChoice({
        'tenant_id': 't1',
        'tenant_name': 'مركز النون',
        'role': 'parent',
        'user': {
          'id': 'stu-1',
          'name': 'أبو علي',
          'student_name': 'علي أبو حسنين',
          'national_id': '401334845',
          'portal_code': '444444',
          'grade_level': 'عاشر',
          'section': 'أ',
        },
      });
      expect(user.isParent, isTrue);
      expect(user.isTeacher, isFalse);
      expect(user.roleLabel, 'ولي أمر');
      expect(user.id, 'stu-1', reason: 'بيانات البوابة تُجلب بمعرّف الطالب');
      expect(user.name, 'أبو علي');
      expect(user.studentName, 'علي أبو حسنين');
      expect(user.tenantId, 't1');
      expect(user.tenantName, 'مركز النون');
      expect(PortalUser.fromJson(user.toJson()).studentName, 'علي أبو حسنين');
    });

    test('المعلم والطالب يُقرآن كما كانا', () {
      final teacher = PortalService.userFromChoice({
        'tenant_id': 't1',
        'tenant_name': 'مركز النون',
        'role': 'teacher',
        'user': {'id': 'tch-1', 'name': 'أ. وفاء', 'subject_ids': ['a', 'b']},
      });
      expect(teacher.isTeacher, isTrue);
      expect(teacher.roleLabel, 'معلم');
      expect(teacher.subjectIds, ['a', 'b']);

      final student = PortalService.userFromChoice({
        'tenant_id': 't1',
        'role': 'student',
        'user': {'id': 'stu-1', 'name': 'علي'},
      });
      expect(student.roleLabel, 'طالب');
      expect(student.tenantName, 'منشأة غير محددة');
    });
  });
}
