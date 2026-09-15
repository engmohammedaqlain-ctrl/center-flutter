import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `installmentPlans.test.ts` — المتوقع لباقي السنة.
///
/// رقم للإدارة: الأقساط التي لم يحن موعدها وحدها، ناقصاً ما دُفع مقدماً. كان
/// يُحتسب برسم شهري مضروب بأشهر الدوام، وهي تفترض أن كل المراحل تدرس نفس الأشهر.

AppStore _school() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.students.removeWhere((x) => true);
  s.installments.clear();
  s.gradeFees.clear();
  s.gradeFees.add(GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: 100, orderIndex: 0));
  return s;
}

Student _student(AppStore s, {String id = 'stu', String status = 'active', double balance = 0}) {
  final student = Student(
    id: id,
    fullName: 'طالب $id',
    gradeLevel: 'عاشر',
    section: '',
    phone: '059900000$id'.substring(0, 10),
    parentName: 'ولي',
    parentPhone: '0598000000',
    nationalId: '40109250${id.length}',
    balance: balance,
    status: status,
  );
  s.students.add(student);
  return student;
}

/// قسطان: أحدهما حلّ موعده والآخر لم يحن.
void _twoInstallments(AppStore s, Student student, {double amount = 100}) {
  s.installments.addAll([
    Installment(
      id: 'plan_a_${student.id}',
      studentId: student.id,
      title: 'القسط 1',
      amount: amount,
      dueDate: DateTime(2026, 9, 1),
    ),
    Installment(
      id: 'plan_b_${student.id}',
      studentId: student.id,
      title: 'القسط 2',
      amount: amount,
      dueDate: DateTime(2026, 10, 1),
    ),
  ]);
}

void main() {
  test('القسط الذي لم يحن موعده يُحتسب، والذي حلّ لا — فهو في المستحق', () async {
    final s = _school();
    final student = _student(s);
    _twoInstallments(s, student);

    expect(s.projectRemainingYear(today: DateTime(2026, 9, 15)), 100, reason: 'القادم وحده');
    await s.flush();
  });

  test('الرصيد المدفوع مقدماً يُخصم، والمنسحب لا يُحتسب', () async {
    final s = _school();
    final student = _student(s, balance: 40);
    _twoInstallments(s, student);
    final out = _student(s, id: 'out', status: 'withdrawn');
    _twoInstallments(s, out);

    expect(s.projectRemainingYear(today: DateTime(2026, 9, 15)), 60);
    await s.flush();
  });

  test('من لا أقساط له لا يُحتسب عليه شيء', () async {
    final s = _school();
    _student(s);

    expect(s.projectRemainingYear(today: DateTime(2026, 9, 15)), 0,
        reason: 'لا رسم شهري مفترض فوق ما قُيّد فعلاً');
    await s.flush();
  });
}
