import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// رسوم تحددها الإدارة خارج الرسم الشهري، تُقيَّد أقساطاً على طلاب مرحلة أو الجميع.

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
    expect(created, active);
    expect(s.installments.where((i) => i.title == 'الزي المدرسي').length, active);

    expect(s.applyFeeItem(_item(s)), 0, reason: 'المعرّف حتمي');
    await s.flush();
  });

  test('رسم مرحلة يُقيَّد على طلابها وحدهم', () async {
    final s = _seeded();
    final grade = s.students.first.gradeLevel;
    final expected = s.students.where((x) => x.status == 'active' && x.gradeLevel == grade).length;

    expect(s.applyFeeItem(_item(s, grade: grade)), expected);
    final charged = s.installments.where((i) => i.title == 'الزي المدرسي').map((i) => i.studentId);
    expect(charged.every((id) => s.studentById(id)!.gradeLevel == grade), isTrue);
    await s.flush();
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
    expect(s.db.settings[feeItemsKey], contains('الزي المدرسي'));
    await s.flush();
  });

  test('الرسم الإضافي لا يُعدّ خطة أقساط فيوقف المستحق الشهري', () async {
    final s = _seeded();
    s.students.removeWhere((x) => true);
    s.installments.clear();
    s.gradeFees.clear();
    s.gradeFees.add(GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: 200, orderIndex: 0));
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
    await s.saveStudyMonths([9]);
    s.applyFeeItem(_item(s));

    final result = s.generateMonthlyDues(now: DateTime(2026, 9, 5));

    expect(result.created, 1, reason: 'الرسم الإضافي فوق الرسم الشهري لا بدلاً منه');
    expect(s.installments.any((i) => i.title.startsWith('رسوم 09')), isTrue);
    await s.flush();
  });
}
