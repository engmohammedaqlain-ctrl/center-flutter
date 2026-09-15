import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// رسوم تحددها الإدارة خارج أقساط الخطة، تُقيَّد على مرحلة أو الجميع أو طلاب بعينهم.

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

FeeItem _item(AppStore s, {String grade = '', double amount = 60, String? due}) => FeeItem(
      id: 'fee-uniform',
      name: 'الزي المدرسي',
      amount: amount,
      dueDate: due ?? isoDate(DateTime.now()),
      gradeLevel: grade,
    );

void main() {
  test('التقييد يشمل النشطين وحدهم، ولا يتكرر مهما أُعيد', () async {
    final s = _seeded();
    final active = s.students.where((x) => x.status == 'active').length;
    expect(active, greaterThan(0));

    final created = s.applyFeeItem(_item(s));
    expect(created.added, active);
    expect(s.installments.where((i) => i.title == 'الزي المدرسي').length, active);

    expect(s.applyFeeItem(_item(s)).added, 0, reason: 'المعرّف حتمي');
    await s.flush();
  });

  test('رسم مرحلة يُقيَّد على طلابها وحدهم', () async {
    final s = _seeded();
    final grade = s.students.first.gradeLevel;
    final expected = s.students.where((x) => x.status == 'active' && x.gradeLevel == grade).length;

    expect(s.applyFeeItem(_item(s, grade: grade)).added, expected);
    final charged = s.installments.where((i) => i.title == 'الزي المدرسي').map((i) => i.studentId);
    expect(charged.every((id) => s.studentById(id)!.gradeLevel == grade), isTrue);
    await s.flush();
  });

  group('طلاب بعينهم', () {
    test('يُقيَّد على المختارين وحدهم', () async {
      final s = _seeded();
      final active = s.students.where((x) => x.status == 'active').toList();
      final two = active.take(2).map((x) => x.id).toList();

      final result = s.applyFeeItem(_item(s).copyWith(studentIds: two));

      expect(result.added, 2);
      expect(s.installments.where((i) => i.title == 'الزي المدرسي').map((i) => i.studentId).toSet(), two.toSet());
      await s.flush();
    });

    test('من خرج من القائمة يُرفع عنه، ومن دخلها يُضاف', () async {
      final s = _seeded();
      final active = s.students.where((x) => x.status == 'active').toList();
      final a = active[0].id;
      final b = active[1].id;
      final c = active[2].id;

      expect(s.applyFeeItem(_item(s).copyWith(studentIds: [a, b])).added, 2);

      // b خرج و c دخل: لا يُطالَب من رُفع عنه ولا يُترك من أُضيف
      final result = s.applyFeeItem(_item(s).copyWith(studentIds: [a, c]));
      expect(result, (added: 1, removed: 1));

      final charged = s.installments.where((i) => i.title == 'الزي المدرسي').map((i) => i.studentId).toSet();
      expect(charged, {a, c});
      await s.flush();
    });

    test('من دفع منه شيئاً لا يُرفع عنه: السجل المالي لا يُمحى', () async {
      final s = _seeded();
      final student = s.students.firstWhere((x) => x.status == 'active');
      s.applyFeeItem(_item(s).copyWith(studentIds: [student.id]));
      s.addPayment(
        studentId: student.id,
        amount: 60,
        method: 'cash',
        date: DateTime(2026, 9, 21),
        installmentId: AppStore.feeInstallmentId('fee-uniform', student.id),
      );

      final result = s.applyFeeItem(_item(s).copyWith(studentIds: const []));

      expect(result.removed, 0);
      expect(s.installments.any((i) => i.title == 'الزي المدرسي'), isTrue);
      await s.flush();
    });

    test('قائمة فارغة لا تُقيَّد على أحد', () async {
      final s = _seeded();
      expect(s.applyFeeItem(_item(s).copyWith(studentIds: const [])), (added: 0, removed: 0));
      expect(s.installments.any((i) => i.title == 'الزي المدرسي'), isFalse);
      await s.flush();
    });
  });

  test('الرسم يدخل في مستحق الطالب', () async {
    final s = _seeded();
    final student = s.students.firstWhere((x) => x.status == 'active');
    final before = s.outstandingDue(student.id);

    // تاريخ استحقاق حلّ: القادم لا يُطالَب به
    s.applyFeeItem(_item(s, amount: 60, due: '2026-09-01'));

    expect(s.outstandingDue(student.id), closeTo(before + 60, 0.01));
    await s.flush();
  });

  test('الحذف يزيله، إلا عمّن له سند مربوط به', () async {
    final s = _seeded();
    final student = s.students.firstWhere((x) => x.status == 'active');
    s.applyFeeItem(_item(s));
    final instId = AppStore.feeInstallmentId('fee-uniform', student.id);
    s.addPayment(
      studentId: student.id,
      amount: 60,
      method: 'cash',
      date: DateTime(2026, 9, 21),
      installmentId: instId,
    );

    final kept = s.removeFeeItem('fee-uniform');

    expect(kept, 1, reason: 'صاحب السند وحده');
    expect(s.installments.any((i) => i.id == instId), isTrue);
    expect(s.installments.where((i) => i.title == 'الزي المدرسي').length, 1);
    await s.flush();
  });

  test('القائمة تُحفظ وتُرفع مع إعدادات المنشأة', () async {
    final s = _seeded();
    await s.saveFeeItems([_item(s)]);

    expect(s.feeItems.single.name, 'الزي المدرسي');
    // عمود `settings` لا كائن الألوان: قواعد العمل تصل بقية الأجهزة من مكانها
    expect(s.db.settings[institutionSettingsKey], contains('الزي المدرسي'));
    await s.flush();
  });

  test('الرسم الإضافي يُقيَّد فوق أقساط الخطة لا بدلاً منها', () async {
    final s = _seeded();
    s.students.removeWhere((x) => true);
    s.installments.clear();
    s.gradeFees.clear();
    s.gradeFees.add(GradeFee(
      id: 'g1',
      gradeName: 'عاشر',
      monthlyFee: 200,
      orderIndex: 0,
      term1Start: '2026-09-05',
      planItems: const [PlanItem(id: 'p1', title: 'القسط 1', amount: 200, dueDate: '2026-09-05')],
    ));
    s.students.add(Student(
      id: 'stu',
      fullName: 'طالب الرسوم',
      gradeLevel: 'عاشر',
      section: '',
      phone: '0599000000',
      parentName: 'ولي',
      parentPhone: '0598000000',
      nationalId: '401092577',
      balance: 0,
      status: 'active',
    ));
    s.applyGradePlan('عاشر');
    s.applyFeeItem(_item(s));

    final own = s.installments.where((i) => i.studentId == 'stu').toList();
    expect(own.length, 2, reason: 'قسط الخطة والرسم الإضافي معاً');
    expect(own.map((i) => i.amount).reduce((a, b) => a + b), 260);
    await s.flush();
  });
}
