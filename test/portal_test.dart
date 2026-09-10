import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('دخول البوابة', () {
    test('رقم الهوية أو الرمز الفارغ يُرفض بلا نداء للسحابة', () async {
      const service = PortalService();
      expect((await service.login('', '123456')).error, contains('يرجى إدخال'));
      expect((await service.login('123456789', '')).error, contains('يرجى إدخال'));
      expect((await service.login('   ', '  ')).error, contains('يرجى إدخال'));
    });

    test('نتيجة بلا حسابات ليست ناجحة', () {
      const result = PortalLoginResult(users: []);
      expect(result.ok, isFalse);
    });

    test('النتيجة ناجحة حين تحمل حساباً بلا خطأ', () {
      const result = PortalLoginResult(users: [
        PortalUser(
          id: 's1',
          name: 'طالب',
          nationalId: '123456789',
          portalCode: '654321',
          role: 'student',
          tenantId: 't1',
        ),
      ]);
      expect(result.ok, isTrue);
      expect(result.users.single.isTeacher, isFalse);
    });
  });

  group('حساب البوابة', () {
    test('الدور يميّز المعلم عن الطالب', () {
      const teacher = PortalUser(
        id: 't1',
        name: 'أ. محمود',
        nationalId: '111111111',
        portalCode: '222222',
        role: 'teacher',
        tenantId: 'x',
      );
      expect(teacher.isTeacher, isTrue);
    });

    test('الحساب يمرّ عبر JSON بلا فقدان', () {
      const original = PortalUser(
        id: 's1',
        name: 'محمد أحمد',
        nationalId: '400400400',
        portalCode: '135790',
        role: 'student',
        tenantId: 'tenant-1',
        gradeLevel: 'عاشر',
        section: 'عاشر (أ)',
        tenantName: 'مدرسة الأمل',
      );
      final back = PortalUser.fromJson(original.toJson());
      expect(back.id, original.id);
      expect(back.name, original.name);
      expect(back.nationalId, original.nationalId);
      expect(back.portalCode, original.portalCode);
      expect(back.gradeLevel, original.gradeLevel);
      expect(back.tenantName, original.tenantName);
      expect(back.isTeacher, isFalse);
    });
  });

  group('إحصاء الحضور', () {
    test('الالتزام يحتسب الحاضر والمتأخر', () {
      const a = PortalAttendance(total: 10, present: 7, absent: 2, late: 1);
      expect(a.rate, 80);
    });

    test('بلا رصد يُعتبر الالتزام كاملاً', () {
      expect(const PortalAttendance().rate, 100);
    });
  });

  group('الإعلانات والتقييمات', () {
    test('الإعلان يمرّ عبر شكل السحابة', () {
      const a = ClassAnnouncement(
        id: 'a1',
        groupId: 'g1',
        title: 'اختبار الأسبوع',
        content: 'يوم الأحد',
        teacherId: 't1',
      );
      final back = ClassAnnouncement.fromCloud(a.toCloud());
      expect(back.title, 'اختبار الأسبوع');
      expect(back.content, 'يوم الأحد');
      expect(back.groupId, 'g1');
      expect(back.teacherId, 't1');
    });

    test('الحقول الفارغة تُرسل null لا نصاً فارغاً', () {
      const a = ClassAnnouncement(id: 'a1', groupId: 'g1', title: 'عنوان', content: '');
      final row = a.toCloud();
      expect(row['teacher_id'], isNull);
      expect(row['image_url'], isNull);
    });

    test('التقييم يمرّ عبر شكل السحابة', () {
      const e = StudentEvaluation(
        id: 'e1',
        studentId: 's1',
        teacherId: 't1',
        subjectId: 'sub1',
        score: 88.5,
        notes: 'ممتاز',
      );
      final back = StudentEvaluation.fromCloud(e.toCloud());
      expect(back.score, 88.5);
      expect(back.notes, 'ممتاز');
      expect(back.subjectId, 'sub1');
    });
  });

  group('هوية البوابة', () {
    test('الافتراضي اسم النظام وألوانه', () {
      const b = PortalBranding();
      expect(b.name, appName);
      expect(b.colors.actionButton, InstitutionColors.defaults.actionButton);
    });

    test('ألوان المنشأة تُقرأ كما حفظها سطح المكتب', () {
      final colors = InstitutionColors.fromMap(const {
        'sidebarBg': '#4A0E17',
        'activeItem': '#DC2626',
        'primaryButton': '#4A0E17',
        'actionButton': '#B91C1C',
        'appBg': '#FFF9F9',
      });
      expect(colors.sidebarBg, '#4A0E17');
      expect(colors.actionButton, '#B91C1C');
    });
  });

  group('مالية الطالب', () {
    test('المتبقي مستقل عن مجموع الأقساط', () {
      const f = PortalFinance(totalDue: 800, totalPaid: 500, remaining: 300);
      expect(f.totalDue - f.totalPaid, f.remaining);
    });
  });
}
