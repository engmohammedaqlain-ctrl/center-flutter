import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

/// خطة مرحلة: أقساط متساوية من بداية فصلها الأول.
void _plan(AppStore s, String grade, {double amount = 100, int count = 3, String from = '2026-09-05'}) {
  final fee = s.feeFor(grade)!;
  fee.term1Start = from;
  fee.planItems = generatePlanItems(
    count: count,
    amount: amount,
    firstDueDate: from,
    newId: s.newId,
  );
}

/// طالب نشط بلا أقساط ولا سندات — لوحة نظيفة لتطبيق الخطة.
Student _cleanStudent(AppStore s, {String grade = 'عاشر', bool seatPaid = false}) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب الأقساط',
    gradeLevel: grade,
    section: 'أ',
    phone: '0599000222',
    parentName: 'ولي الأمر',
    parentPhone: '0598000222',
    balance: 0,
    nationalId: '123123123',
    enrolledAt: DateTime(2026, 9, 1),
    seatReservationPaid: seatPaid,
  );
  s.students.add(student);
  return student;
}

Future<void> _pumpSettings(WidgetTester tester, AppStore s) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SettingsScreen())),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('خطة أقساط المرحلة', () {
    test('بلا خطة لا تُقيَّد أقساط على من يُسجَّل', () {
      final s = _seeded();
      final student = _cleanStudent(s);

      expect(s.planItemsOf(s.planForStudent(student)), isEmpty);
      expect(s.studentsMissingPlan, greaterThan(0));
      expect(s.applyGradePlan('عاشر').applied, 0);
      expect(s.installments.where((i) => i.studentId == student.id), isEmpty);
    });

    test('التطبيق يُقيَّد مرة واحدة ويترك من له أقساط', () {
      final s = _seeded();
      _plan(s, 'عاشر');
      final student = _cleanStudent(s);

      final first = s.applyGradePlan('عاشر');
      expect(first.applied, greaterThan(0));

      final own = s.installments.where((i) => i.studentId == student.id).toList();
      expect(own.length, 3);
      expect(own.every((i) => isPlanInstallmentId(i.id)), isTrue, reason: 'معرّف حتمي لا يتكرر بين الأجهزة');
      expect(own.map((i) => i.amount), everyElement(100));

      // تشغيل ثانٍ يتركه كما هو: تعديل الخطة لا يُعيد ضبط أقساط من سُجّل قبلها
      final again = s.applyGradePlan('عاشر');
      expect(again.applied, 0);
      expect(again.skipped, greaterThan(0));
      expect(s.installments.where((i) => i.studentId == student.id).length, 3);
    });

    test('تواريخ الأقساط تتبع تاريخ فصل المرحلة لا أول الشهر', () {
      final s = _seeded();
      _plan(s, 'عاشر', from: '2026-09-05');
      final student = _cleanStudent(s);
      s.applyGradePlan('عاشر');

      final dates = s.installments
          .where((i) => i.studentId == student.id)
          .map((i) => isoDate(i.dueDate))
          .toList()
        ..sort();
      expect(dates, ['2026-09-05', '2026-10-05', '2026-11-05']);
    });

    test('الطالب الجديد يأخذ نسخته من خطة مرحلته عند تسجيله', () {
      final s = _seeded();
      _plan(s, 'عاشر');

      final student = Student(
        id: s.newId(),
        fullName: 'طالب مسجَّل حديثاً',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599777666',
        parentName: 'ولي الأمر',
        parentPhone: '0598777666',
        balance: 0,
        nationalId: '321321321',
        enrolledAt: DateTime(2026, 9, 1),
      );
      s.upsertStudent(student, isNew: true);

      expect(s.installments.where((i) => i.studentId == student.id).length, 3);
    });

    test('الخصم يوزَّع على الأقساط وتبقى قيمتها قبله ظاهرة', () {
      final s = _seeded();
      _plan(s, 'عاشر');
      final student = _cleanStudent(s);

      final rows = buildStudentPlan(
        s.planItemsOf(s.planForStudent(student)),
        student.id,
        discount: const PlanDiscount.percent(10),
      );

      expect(rows.map((r) => r.amount), everyElement(90));
      expect(rows.map((r) => r.originalAmount), everyElement(100), reason: 'الخصم يبقى ظاهراً في كشف الطالب');
    });

    test('المؤرشف لا يُقيَّد عليه شيء', () {
      final s = _seeded();
      _plan(s, 'عاشر');
      final student = _cleanStudent(s);
      s.promoteStudents({'عاشر': null});

      s.applyGradePlan('عاشر');
      expect(s.installments.where((i) => i.studentId == student.id), isEmpty);
    });
  });

  group('رسم الحجز على الخطة', () {
    test('يُقتطع من الأقساط بترتيبها الزمني', () async {
      final s = _seeded();
      _plan(s, 'عاشر', amount: 30);
      await s.setSeatReservationFee(50, deduct: true);
      final student = _cleanStudent(s);

      s.applyGradePlan('عاشر');
      final own = s.installments.where((i) => i.studentId == student.id).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      expect(own.first.title, AppStore.seatInstallmentTitle);
      expect(own.first.amount, 50);
      // خمسون على قسطين: الأول كاملاً وعشرون من الثاني
      expect(own.skip(1).map((i) => i.amount), [0, 10, 30]);
      expect(own.fold<double>(0, (sum, i) => sum + i.amount), 90, reason: 'لا يدفع أكثر من مجموع الخطة');
    });

    test('المستقل يبقى مطالبة فوق الأقساط كاملة', () async {
      final s = _seeded();
      _plan(s, 'عاشر', amount: 30);
      await s.setSeatReservationFee(50, deduct: false);
      final student = _cleanStudent(s);

      s.applyGradePlan('عاشر');
      final own = s.installments.where((i) => i.studentId == student.id).toList();

      expect(own.firstWhere((i) => i.title == AppStore.seatInstallmentTitle).amount, 50);
      expect(own.where((i) => i.title != AppStore.seatInstallmentTitle).map((i) => i.amount), everyElement(30));
    });

    test('من دفعه لا يُقيَّد عليه قسطٌ به', () async {
      final s = _seeded();
      _plan(s, 'عاشر');
      await s.setSeatReservationFee(50);
      final student = _cleanStudent(s, seatPaid: true);

      s.applyGradePlan('عاشر');
      final own = s.installments.where((i) => i.studentId == student.id);

      expect(own.any((i) => i.title == AppStore.seatInstallmentTitle), isFalse);
      expect(own.map((i) => i.amount), everyElement(100), reason: 'دفعه يزيد رصيده لا يخصم من أقساطه');
    });
  });

  group('ترقية الطلاب', () {
    test('الصف ينتقل لتاليه، ومن لا صف بعده يُؤرشف، والشعبة تُمسح', () {
      final s = _seeded();
      final tenth = _cleanStudent(s);
      final last = _cleanStudent(s, grade: 'ثاني عشر علمي');

      final res = s.promoteStudents({'عاشر': 'حادي عشر علمي', 'ثاني عشر علمي': null});

      expect(res.promoted, greaterThan(0));
      expect(res.archived, greaterThan(0));
      expect(tenth.gradeLevel, 'حادي عشر علمي');
      expect(tenth.status, 'pending', reason: 'بانتظار التأكيد فلا تُستحق عليه رسوم');
      expect(tenth.section, '');
      expect(last.status, 'archived');
      expect(s.pendingSyncs.any((p) => p.tableName == 'students' && p.recordId == tenth.id), isTrue);
    });
  });

  group('شاشة المراحل والرسوم', () {
    testWidgets('تعرض رسم الحجز وطريقته وزر الترقية', (tester) async {
      final s = _seeded();
      await s.login('amal', 'amal2026');
      await _pumpSettings(tester, s);
      // الشاشة تفتح على «المعلمون»: ننتقل إلى تبويب المراحل والرسوم
      await tester.tap(find.text('المراحل والرسوم'));
      await tester.pumpAndSettle();

      // أقسام التبويب مطوية: تُفتح بعناوينها
      await tester.tap(find.text('رسم حجز المقعد').first);
      await tester.pumpAndSettle();
      expect(find.text('يُدفع مرة واحدة ويُخصم من أول الأقساط'), findsOneWidget);
      await tester.tap(find.text('الترقية'));
      await tester.pumpAndSettle();
      expect(find.text('ترقية الطلاب'), findsOneWidget);

      await s.flush();
    });

    testWidgets('اعتماد رسم الحجز مستقلاً يُحفظ في الإعدادات المشتركة', (tester) async {
      final s = _seeded();
      await s.login('amal', 'amal2026');
      await _pumpSettings(tester, s);
      await tester.tap(find.text('المراحل والرسوم'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('رسم حجز المقعد').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '40');
      await tester.tap(find.text('رسم مستقل فوقها'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(s.seatReservationFee, 40);
      expect(s.deductsSeatFee, isFalse);

      await s.flush();
    });
  });
}
