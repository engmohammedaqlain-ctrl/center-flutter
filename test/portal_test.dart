import 'dart:convert';

import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/payment_methods.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Installment _inst(String id, double amount, DateTime due, {double paid = 0, String status = 'unpaid'}) => Installment(
      id: id,
      studentId: 's1',
      title: 'القسط $id',
      amount: amount,
      dueDate: due,
      paidAmount: paid,
      status: status,
    );

Payment _pay(String id, double amount, {bool cancelled = false, DateTime? date}) => Payment(
      id: id,
      receiptNumber: '2026/$id',
      studentId: 's1',
      amount: amount,
      method: 'cash',
      date: date ?? DateTime(2026, 9, 1),
      cancelled: cancelled,
    );

Student _student({String section = 'شعبة (1)', String grade = 'عاشر', String status = 'active'}) => Student(
      id: 'st',
      fullName: 'طالب',
      gradeLevel: grade,
      section: section,
      phone: '0599000000',
      parentName: 'ولي',
      parentPhone: '0598000000',
      balance: 0,
      status: status,
    );

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
      expect(back.gradeLevel, original.gradeLevel);
      expect(back.tenantName, original.tenantName);
      expect(back.isTeacher, isFalse);
    });
  });

  group('إحصاء الحضور', () {
    test('الالتزام يحتسب الحاضر وحده', () {
      const a = PortalAttendance(total: 10, present: 7, absent: 2, excused: 1);
      expect(a.rate, 70);
    });

    test('بلا رصد يُعتبر الالتزام كاملاً', () {
      expect(const PortalAttendance().rate, 100);
    });
  });

  group('المعرّفات الحتمية للحضور', () {
    test('مطابقة لـ AttendanceService في النسخة المكتبية', () {
      final session = PortalService.sessionIdFor('g1', '2026-09-12');
      expect(session, 'ses_g1_2026-09-12');
      expect(PortalService.attendanceIdFor(session, 'st7'), 'att_ses_g1_2026-09-12_st7');
    });
  });

  group('مالية الطالب — مطابقة لـ getStudentPortalData', () {
    final today = DateTime(2026, 9, 12);

    test('الإجمالي مجموع الأقساط، والمسدَّد يستبعد الملغى', () {
      final f = PortalFinance.compute(
        studentBalance: 0,
        installments: [
          _inst('1', 230, DateTime(2026, 8, 23)),
          _inst('2', 230, DateTime(2026, 9, 22)),
          _inst('3', 230, DateTime(2026, 10, 22)),
          _inst('4', 230, DateTime(2026, 11, 21)),
        ],
        payments: [_pay('a', 230), _pay('b', 200), _pay('c', 47), _pay('x', 999, cancelled: true)],
        today: today,
      );
      expect(f.totalDue, 920);
      expect(f.totalPaid, 477);
      expect(f.remainingBalance, 443);
      expect(f.payments.any((p) => p.cancelled), isFalse);
    });

    test('المستحق حالياً هو دين الطالب المسجَّل حين يكون عليه دين', () {
      final f = PortalFinance.compute(
        studentBalance: -443,
        installments: [_inst('1', 920, DateTime(2026, 12, 1))],
        payments: [_pay('a', 477)],
        today: today,
      );
      expect(f.currentDue, 443);
    });

    test('بلا دين مسجَّل: ما حلّ موعده ناقص المسدَّد، والقادم لا يُطلب', () {
      final f = PortalFinance.compute(
        studentBalance: 0,
        installments: [
          _inst('1', 230, DateTime(2026, 8, 23)),
          _inst('2', 230, DateTime(2026, 9, 12)),
          _inst('3', 230, DateTime(2026, 10, 22)),
        ],
        payments: [_pay('a', 300)],
        today: today,
      );
      expect(f.currentDue, 160, reason: 'قسطا 23/8 و12/9 (460) ناقص 300');
      expect(f.installments[1].isDueNow, isTrue, reason: 'يوم الاستحقاق نفسه مطلوب');
      expect(f.installments[2].isDueNow, isFalse);
    });

    test('المستحق حالياً لا يتجاوز المتبقي ولا ينزل تحت الصفر', () {
      final f = PortalFinance.compute(
        studentBalance: 0,
        installments: [_inst('1', 200, DateTime(2026, 8, 1))],
        payments: [_pay('a', 500)],
        today: today,
      );
      expect(f.currentDue, 0);
      expect(f.remainingBalance, 0);
    });

    test('الأقساط مرتّبة بالاستحقاق وحالتها المجهولة «غير مسددة»', () {
      final f = PortalFinance.compute(
        studentBalance: 0,
        installments: [
          _inst('late', 100, DateTime(2026, 11, 1), status: 'pending'),
          _inst('early', 100, DateTime(2026, 8, 1), status: 'paid'),
        ],
        payments: const [],
        today: today,
      );
      expect(f.installments.map((i) => i.id), ['early', 'late']);
      expect(f.installments.last.status, 'unpaid');
      expect(f.installments.first.status, 'paid');
    });
  });

  group('طلاب الشعبة بديلاً عن التسجيلات', () {
    test('الشعبة والمرحلة متطابقتان', () {
      expect(PortalService.studentInRoom(_student(), roomName: 'شعبة (1)', roomGrade: 'عاشر'), isTrue);
    });

    test('مرحلة مختلفة لا تُحتسب', () {
      expect(PortalService.studentInRoom(_student(grade: 'حادي عشر'), roomName: 'شعبة (1)', roomGrade: 'عاشر'), isFalse);
    });

    test('الطالب غير النشط لا يظهر للمعلم', () {
      expect(
        PortalService.studentInRoom(_student(status: 'withdrawn'), roomName: 'شعبة (1)', roomGrade: 'عاشر'),
        isFalse,
      );
    });

    test('شعبة أخرى لا تُحتسب', () {
      expect(PortalService.studentInRoom(_student(section: 'شعبة (2)'), roomName: 'شعبة (1)', roomGrade: 'عاشر'), isFalse);
    });
  });

  group('اسم الشعبة المنظّف — cleanGroupName', () {
    test('أعمق قوسين يحملان حرف الشعبة', () {
      expect(cleanGroupName('فصل عاشر (عاشر (أ))', 'عاشر'), 'شعبة (أ)');
    });

    test('تكرار المرحلة يُزال', () {
      expect(cleanGroupName('ثاني عشر علمي (12 علمي)', 'ثاني عشر علمي'), 'شعبة 1');
    });

    test('«فصل» في البداية تُحذف', () {
      expect(cleanGroupName('فصل الرياضيات'), 'الرياضيات');
    });

    test('الاسم الفارغ «شعبة»', () {
      expect(cleanGroupName(''), 'شعبة');
      expect(cleanGroupName(null), 'شعبة');
    });
  });

  group('المودل', () {
    test('المادة تمرّ عبر شكل السحابة', () {
      const item = CourseItem(
        id: 'i1',
        tenantId: 't1',
        sectionId: 's1',
        groupId: 'g1',
        title: 'ورقة عمل',
        type: 'assignment',
        description: 'ص 12',
        dueDate: '2026-09-20',
      );
      final back = CourseItem.fromCloud(item.toCloud());
      expect(back.title, 'ورقة عمل');
      expect(back.type, 'assignment');
      expect(back.dueDate, '2026-09-20');
      expect(back.typeLabel, 'واجب منزلي');
      expect(item.toCloud()['content_url'], isNull, reason: 'الحقل الفارغ يُرسل null');
    });

    test('موعد التسليم المنتهي، وشارة «جديد» خلال 48 ساعة', () {
      final now = DateTime(2026, 9, 12, 10);
      const due = CourseItem(id: 'i', sectionId: 's', groupId: 'g', title: 't', type: 'assignment', dueDate: '2026-09-11');
      expect(due.isOverdue(now), isTrue);
      const today = CourseItem(id: 'i', sectionId: 's', groupId: 'g', title: 't', type: 'assignment', dueDate: '2026-09-12');
      expect(today.isOverdue(now), isFalse, reason: 'يوم التسليم نفسه ليس منتهياً');

      final fresh = CourseItem(id: 'i', sectionId: 's', groupId: 'g', title: 't', type: 'note', createdAt: DateTime(2026, 9, 11, 12).toIso8601String());
      final old = CourseItem(id: 'i', sectionId: 's', groupId: 'g', title: 't', type: 'note', createdAt: DateTime(2026, 9, 9).toIso8601String());
      expect(fresh.isNew(now), isTrue);
      expect(old.isNew(now), isFalse);
    });

    test('القسم يمرّ عبر شكل السحابة، والمخفي يبقى مخفياً', () {
      const sec = CourseSection(id: 'c1', tenantId: 't', groupId: 'g', term: 'term_2', title: 'الوحدة الأولى', isVisible: false);
      final back = CourseSection.fromCloud(sec.toCloud());
      expect(back.isVisible, isFalse);
      expect(back.termLabel, 'الفصل الثاني');
      expect(CourseSection.fromCloud(const {'id': 'x', 'term': 'general'}).termLabel, 'أخرى');
    });

    test('مسار الملف في الحاوية يُستخرج من رابطه العام فقط', () {
      expect(
        PortalService.materialPath('https://x.supabase.co/storage/v1/object/public/course_materials/t1/170_ab.pdf'),
        't1/170_ab.pdf',
      );
      expect(PortalService.materialPath('https://youtube.com/watch?v=1'), isNull);
    });

    test('ملف الحاوية يُفتح برابط موقّت، والرابط الخارجي كما هو', () async {
      const service = PortalService();
      expect(await service.materialOpenUrl('https://youtube.com/watch?v=1'), 'https://youtube.com/watch?v=1');
      expect(await service.materialOpenUrl('  '), isNull);

      Uri? asked;
      Object? body;
      final signed = await http.runWithClient(
        () => service.materialOpenUrl(
            'https://x.supabase.co/storage/v1/object/public/course_materials/t1/170_ab.pdf'),
        () => MockClient((request) async {
          asked = request.url;
          body = jsonDecode(request.body);
          return http.Response(
            jsonEncode({'signedURL': '/object/sign/course_materials/t1/170_ab.pdf?token=abc'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      expect(asked?.path, endsWith('/storage/v1/object/sign/course_materials/t1/170_ab.pdf'));
      expect((body as Map)['expiresIn'], 3600, reason: 'ساعة واحدة كما في MoodleService');
      expect(signed, endsWith('/storage/v1/object/sign/course_materials/t1/170_ab.pdf?token=abc'));
    });

    test('تعذّر التوقيع لا يُعيد رابطاً غير موقّع', () async {
      const service = PortalService();
      final result = await http.runWithClient(
        () => service.materialOpenUrl(
            'https://x.supabase.co/storage/v1/object/public/course_materials/t1/170_ab.pdf'),
        () => MockClient((request) async => http.Response('{"error":"denied"}', 403)),
      );
      expect(result, isNull, reason: 'الحاوية خاصة: الرابط العام لا يفتح');
    });

    test('الأنواع المسموحة PDF والصور وحدها', () {
      expect(PortalService.materialMime('ملخص.PDF'), 'application/pdf');
      expect(PortalService.materialMime('صورة.jpeg'), 'image/jpeg');
      expect(PortalService.materialMime('عرض.pptx'), isNull);
    });

    test('الملف الكبير يُرفض قبل أي رفع', () async {
      const service = PortalService();
      await expectLater(
        service.uploadMaterial(bytes: List.filled(PortalService.maxMaterialBytes + 1, 0), fileName: 'a.pdf', tenantId: 't'),
        throwsA(isA<PortalException>().having((e) => e.message, 'message', contains('10 ميجابايت'))),
      );
    });
  });

  group('التقييمات', () {
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

    test('أسماء المادة والمعلم للعرض لا تُرفع', () {
      const e = StudentEvaluation(id: 'e1', studentId: 's1');
      final named = e.withNames(subjectName: 'الكيمياء', teacherName: 'أ. محمود');
      expect(named.subjectName, 'الكيمياء');
      expect(named.toCloud().containsKey('subject_name'), isFalse);
    });
  });

  group('هوية البوابة', () {
    test('الافتراضي اسم النظام وألوانه ووسائل الدفع الأساسية', () {
      const b = PortalBranding();
      expect(b.name, appName);
      expect(b.colors.actionButton, InstitutionColors.defaults.actionButton);
      expect(b.methodLabel('palpay'), 'محفظة بال بي');
    });

    test('مسمّى الوسيلة يتبع ضبط المنشأة', () {
      const b = PortalBranding(paymentMethods: [PaymentMethodItem(id: 'cash', name: 'كاش', type: 'cash')]);
      expect(b.methodLabel('cash'), 'كاش');
      expect(b.methodLabel('bop'), 'بنك فلسطين', reason: 'وسيلة محذوفة تُقرأ باسمها المعروف');
      expect(b.methodLabel(''), '-');
    });
  });
}
