import 'package:center_mobile/data/teacher_salary.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `teacherSalary.test.ts`: صرفٌ حرّ لا مستحقات.
///
/// كان النظام يحسب راتباً مستحقاً ومتبقياً عن كل شهر ويلاحق المدير بها. لم يبقَ
/// إلا ما صُرف فعلاً، مفصولاً بنوعه.

TeacherPayout _payout(
  double amount, {
  String month = '',
  String date = '2026-10-05',
  String type = 'salary',
  String teacherId = 't1',
}) =>
    TeacherPayout(
      id: 'p-$amount-$month-$type',
      teacherId: teacherId,
      amount: amount,
      payoutType: type,
      paymentDate: date,
      periodStart: month.isEmpty ? '' : '$month-01',
    );

void main() {
  group('شهر السند', () {
    test('يُنسب لشهر الراتب لا ليوم صرفه', () {
      expect(salaryMonthOf(_payout(400, month: '2026-09', date: '2026-10-03')), '2026-09');
    });

    test('سندٌ بلا فترة يُنسب ليوم صرفه', () {
      expect(salaryMonthOf(_payout(400, date: '2026-09-28')), '2026-09');
    });

    test('آخر يوم في الشهر يُحسب بطول الشهر نفسه', () {
      expect(monthEnd('2026-09'), '2026-09-30');
      expect(monthEnd('2026-02'), '2026-02-28');
      expect(monthLabel('2026-09'), '09/2026');
    });
  });

  group('ما صُرف عن شهر', () {
    test('يُجمع بنوعه، والراتب هو الافتراضي', () {
      final paid = paidInMonth(
        [
          _payout(1000, month: '2026-09'),
          _payout(200, month: '2026-09', type: 'advance'),
          _payout(150, month: '2026-09', type: 'bonus'),
        ],
        't1',
        '2026-09',
      );

      expect(paid.salary, 1000);
      expect(paid.advance, 200);
      expect(paid.bonus, 150);
      expect(paid.total, 1350);
    });

    test('سند شهر آخر أو معلم آخر لا يُحتسب', () {
      final payouts = [
        _payout(1000, month: '2026-10'),
        _payout(500, month: '2026-09', teacherId: 't2'),
      ];

      expect(paidInMonth(payouts, 't1', '2026-09').total, 0);
      expect(paidInMonth(payouts, 't1', '2026-10').salary, 1000);
      expect(paidInMonth(payouts, 't2', '2026-09').salary, 500);
    });

    test('شهرٌ بلا صرف يعيد أصفاراً — لا مطالبة تُولَّد', () {
      expect(paidInMonth(const [], 't1', '2026-09').total, 0);
    });

    test('نوعٌ لا يعرفه النظام يُحسب راتباً', () {
      expect(paidInMonth([_payout(300, month: '2026-09', type: 'other')], 't1', '2026-09').salary, 300);
    });
  });

  test('أسماء أنواع السند كما تُعرض', () {
    expect(payoutTypeNames['salary'], 'راتب');
    expect(payoutTypeNames['advance'], 'سلفة');
    expect(payoutTypeNames['bonus'], 'مكافأة');
  });
}
