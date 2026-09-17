import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/installment_adjustments.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _store() {
  final store = AppStore.forTesting();
  injectDemoData(store);
  return store;
}

Student _student(AppStore store) {
  final student = Student(
    id: store.newId(),
    fullName: 'طالب التعديلات',
    gradeLevel: 'عاشر',
    section: 'أ',
    phone: '0599000000',
    parentName: 'ولي الأمر',
    parentPhone: '0598000000',
    balance: 0,
    nationalId: '123456789',
  );
  store.students.add(student);
  return student;
}

void main() {
  test('خصم مبلغ يحفظ الخصم منفصلاً ويعيد تسعير المطلوب', () {
    final store = _store();
    final student = _student(store);
    final installment = Installment(
      id: planInstallmentId('one', student.id),
      studentId: student.id,
      title: 'القسط الأول',
      amount: 100,
      dueDate: DateTime.now().add(const Duration(days: 20)),
    );
    store.installments.add(installment);

    InstallmentAdjustments(store).setDiscount(
      installment,
      const InstallmentDiscountInput.amount(25, 'أخوة'),
    );

    expect(installment.amount, 75);
    expect(installment.discountAmount, 25);
    expect(installment.discountReason, 'أخوة');
    expect(installment.isExempt, isFalse);
  });

  test('الإعفاء الكامل يصفّر المطالبة ويحافظ على القيمة الأصلية', () {
    final store = _store();
    final student = _student(store);
    final installment = Installment(
      id: planInstallmentId('one', student.id),
      studentId: student.id,
      title: 'القسط الأول',
      amount: 100,
      dueDate: DateTime.now(),
    );
    store.installments.add(installment);

    InstallmentAdjustments(
      store,
    ).setDiscount(installment, const InstallmentDiscountInput.exempt('منحة'));

    expect(installment.amount, 100);
    expect(installment.chargeable, 0);
    expect(installment.exemptReason, 'منحة');
  });

  test('الرسم الخاص يحمل extra_ ويمكن حذفه', () {
    final store = _store();
    final student = _student(store);
    final adjustments = InstallmentAdjustments(store);

    final extra = adjustments.addExtraCharge(
      studentId: student.id,
      title: 'كتاب',
      amount: 35,
      dueDate: DateTime.now(),
    );

    expect(isExtraChargeId(extra.id), isTrue);
    expect(InstallmentAdjustments.canRemove(extra), isTrue);
    adjustments.remove(extra);
    expect(store.installments.any((i) => i.id == extra.id), isFalse);
  });

  test('خصم الطالب يعاين بالقيمة الجديدة ثم يعيد تسعير أقساط الخطة', () {
    final store = _store();
    final student = _student(store);
    final fee = store.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
    fee.planItems = [
      PlanItem(
        id: 'discount_one',
        title: 'القسط الأول',
        amount: 100,
        dueDate: isoDate(DateTime.now().add(const Duration(days: 30))),
      ),
    ];
    store.syncGradePlan('عاشر', apply: true);
    final adjustments = InstallmentAdjustments(store);

    final preview = adjustments.setStudentDiscount(
      student.id,
      const PlanDiscount.percent(10, reason: 'أخوة'),
    );
    expect(preview.reprice.difference, -10);
    expect(student.planDiscountValue, 0, reason: 'المعاينة لا تكتب');

    adjustments.setStudentDiscount(
      student.id,
      const PlanDiscount.percent(10, reason: 'أخوة'),
      apply: true,
    );
    final row = store.installments.firstWhere(
      (i) => i.id == planInstallmentId('discount_one', student.id),
    );
    expect(row.amount, 90);
    expect(student.planDiscountValue, 10);
  });

  test('الحذف مقصور على الرسم الخاص والخطة المخصصة', () {
    final student = _student(_store());
    final stage = Installment(
      id: planInstallmentId('one', student.id),
      studentId: student.id,
      title: 'مرحلة',
      amount: 100,
      dueDate: DateTime.now(),
    );
    final custom = Installment(
      id: customInstallmentId('one', student.id),
      studentId: student.id,
      title: 'مخصص',
      amount: 100,
      dueDate: DateTime.now(),
    );
    expect(InstallmentAdjustments.canRemove(stage), isFalse);
    expect(InstallmentAdjustments.canRemove(custom), isTrue);
  });
}
