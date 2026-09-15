import 'package:center_mobile/data/teacher_salary.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `teacherSalary.test.ts`.

Teacher _teacher({double rate = 0, List<SalaryChange>? history}) => Teacher(
      id: 't1',
      name: 'أ. محمود',
      phone: '0599000000',
      subject: 'رياضيات',
      rate: rate,
      salaryHistory: history,
    );

TeacherPayout _payout(double amount, {String month = '', String date = '2026-10-05'}) => TeacherPayout(
      id: 'p-$amount-$month',
      teacherId: 't1',
      amount: amount,
      paymentDate: date,
      periodStart: month.isEmpty ? '' : '$month-01',
    );

void main() {
  group('راتب الشهر', () {
    test('بلا سجل: الراتب المسجل يسري على كل الأشهر', () {
      expect(salaryForMonth(_teacher(rate: 500), '2026-09'), 500);
    });

    test('آخر تغيير بدأ في الشهر أو قبله هو النافذ', () {
      final t = _teacher(rate: 800, history: const [
        SalaryChange(from: '0000-01', amount: 500),
        SalaryChange(from: '2026-10', amount: 800),
      ]);

      expect(salaryForMonth(t, '2026-09'), 500, reason: 'شهر مضى يبقى براتبه');
      expect(salaryForMonth(t, '2026-10'), 800);
      expect(salaryForMonth(t, '2026-11'), 800);
    });

    test('لا راتب قبل أول تسجيل', () {
      final t = _teacher(rate: 600, history: const [SalaryChange(from: '2026-10', amount: 600)]);
      expect(salaryForMonth(t, '2026-09'), 0);
    });
  });

  group('تسجيل تغيير الراتب', () {
    test('المعلم الجديد يبدأ بسجل من شهره', () {
      final history = applySalaryChange(null, '2026-09', 500);
      expect(history.single.from, '2026-09');
      expect(history.single.amount, 500);
    });

    test('راتب قديم بلا سجل يُحفظ ببداية مفتوحة قبل التغيير', () {
      final history = applySalaryChange(_teacher(rate: 500), '2026-10', 800);
      expect(history.map((c) => c.from), [openSalaryStart, '2026-10']);
      expect(history.last.amount, 800);
    });

    test('تغيير في الشهر نفسه يستبدل قيمته، والقيمة ذاتها لا تُسجَّل', () {
      final t = _teacher(rate: 800, history: const [SalaryChange(from: '2026-10', amount: 800)]);
      expect(applySalaryChange(t, '2026-10', 900).single.amount, 900);
      expect(applySalaryChange(t, '2026-10', 800), hasLength(1), reason: 'لا تغيير');
    });
  });

  group('المستحق للمعلم عن شهر', () {
    test('ما صُرف عن الشهر نفسه يُخصم، ولو صُرف في شهر تالٍ', () {
      final t = _teacher(rate: 1000);
      final due = teacherSalaryDue(t, [_payout(400, month: '2026-09', date: '2026-10-03')], '2026-09');

      expect(due.rate, 1000);
      expect(due.paid, 400);
      expect(due.remaining, 600);
    });

    test('صرف بلا شهر يُنسب ليوم صرفه', () {
      final t = _teacher(rate: 1000);
      expect(teacherSalaryDue(t, [_payout(1000, date: '2026-09-28')], '2026-09').remaining, 0);
      expect(teacherSalaryDue(t, [_payout(1000, date: '2026-09-28')], '2026-10').remaining, 1000);
    });
  });
}
