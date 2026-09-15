import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `monthlyDues.test.ts` — DUE-5: المتوقع لباقي السنة.
///
/// رقم للإدارة: الأشهر القادمة والأقساط التي لم يحن موعدها، ناقصاً ما دُفع مقدماً.

AppStore _school({double monthlyFee = 100}) {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.students.removeWhere((x) => true);
  s.installments.clear();
  s.gradeFees.clear();
  s.gradeFees.add(GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: monthlyFee, orderIndex: 0));
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

void main() {
  test('أشهر الدراسة الباقية تُحسب من أيلول لا من كانون الثاني', () async {
    final s = _school();
    await s.saveStudyMonths([9, 10, 11, 12, 1, 2]);

    expect(s.remainingStudyMonths(9), 5);
    expect(s.remainingStudyMonths(12), 2, reason: 'كانون الثاني وشباط بعده');
    expect(s.remainingStudyMonths(2), 0);
    await s.flush();
  });

  test('المتوقع = الرسم الشهري × الأشهر الباقية', () async {
    final s = _school(monthlyFee: 100);
    await s.saveStudyMonths([9, 10, 11]);
    _student(s);

    expect(s.projectRemainingYear(today: DateTime(2026, 9, 15)), 200, reason: 'تشرين الأول والثاني');
    await s.flush();
  });

  test('الرصيد المدفوع مقدماً يُخصم، والمنسحب لا يُحتسب', () async {
    final s = _school(monthlyFee: 100);
    await s.saveStudyMonths([9, 10, 11]);
    _student(s, balance: 50);
    _student(s, id: 'out', status: 'withdrawn');

    expect(s.projectRemainingYear(today: DateTime(2026, 9, 15)), 150);
    await s.flush();
  });

  test('قسط لم يحن موعده يُضاف، والذي حلّ لا — فهو في المستحق', () async {
    final s = _school(monthlyFee: 0);
    await s.saveStudyMonths([9]);
    final student = _student(s);
    s.installments.addAll([
      Installment(
        id: 'due_${student.id}_2026-09',
        studentId: student.id,
        title: 'رسوم 09/2026',
        amount: 100,
        dueDate: DateTime(2026, 9, 1),
      ),
      Installment(
        id: 'due_${student.id}_2026-10',
        studentId: student.id,
        title: 'رسوم 10/2026',
        amount: 100,
        dueDate: DateTime(2026, 10, 1),
      ),
    ]);

    expect(s.projectRemainingYear(today: DateTime(2026, 9, 15)), 100, reason: 'القادم وحده');
    await s.flush();
  });
}
