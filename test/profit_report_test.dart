import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/profit_report.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// تقرير الأرباح — مطابق لـ `profitReport.test.ts` في الويب.

Installment _inst(String id, String due, [double amount = 100]) =>
    Installment(id: id, studentId: 's1', title: id, amount: amount, dueDate: DateTime.parse(due));

var _seq = 0;
Payment _pay(
  double amount,
  String date, {
  String studentId = 's1',
  String? installmentId,
  double discount = 0,
  bool cancelled = false,
  String purpose = 'monthly_fee',
}) {
  _seq++;
  return Payment(
    id: 'p$_seq',
    receiptNumber: '$_seq',
    studentId: studentId,
    amount: amount,
    method: 'cash',
    date: DateTime.parse(date),
    purpose: purpose,
    installmentId: installmentId,
    discountAmount: discount,
    cancelled: cancelled,
    createdAt: '${date}T00:00:${_seq.toString().padLeft(2, '0')}',
  );
}

Expense _exp(double amount, String date, [String kind = 'expense']) {
  _seq++;
  return Expense(id: 'e$_seq', category: 'x', description: 'x', amount: amount, expenseDate: date, kind: kind);
}

TeacherPayout _payout(double amount, String periodStart, String paymentDate) {
  _seq++;
  return TeacherPayout(id: 't$_seq', teacherId: 'tch', amount: amount, paymentDate: paymentDate, periodStart: periodStart);
}

ProfitReport _report(
  ProfitBasis basis, {
  List<Payment> payments = const [],
  List<Installment> installments = const [],
  List<Expense> expenses = const [],
  List<TeacherPayout> payouts = const [],
}) =>
    computeProfitReport(
      payments: payments,
      installments: installments,
      expenses: expenses,
      payouts: payouts,
      range: (from: '2026-09-01', to: '2026-12-31'),
      basis: basis,
    );

ProfitRow _month(ProfitReport r, String m) => r.rows.firstWhere((x) => x.month == m);

void main() {
  group('allocatePaymentSlices', () {
    test('دفعة غير مربوطة تغطي قسطين تتقسم على الأقدم أولاً', () {
      final p = _pay(150, '2026-10-05');
      final slices = allocatePaymentSlices([p], [_inst('i10', '2026-10-01'), _inst('i9', '2026-09-01')]);
      expect(slices.map((s) => (s.installmentId, s.amount)), [('i9', 100.0), ('i10', 50.0)]);
    });

    test('دفعة مربوطة تروح لقسطها', () {
      final p = _pay(100, '2026-10-05', installmentId: 'i10');
      final slices = allocatePaymentSlices([p], [_inst('i9', '2026-09-01'), _inst('i10', '2026-10-01')]);
      expect(slices.map((s) => (s.installmentId, s.amount)), [('i10', 100.0)]);
    });

    test('الزائد عن الأقساط يبقى بلا قسط', () {
      final slices = allocatePaymentSlices([_pay(130, '2026-09-05')], [_inst('i9', '2026-09-01')]);
      expect(slices.firstWhere((s) => s.installmentId == null).amount, 30);
    });

    test('مطابق لـ allocatePaymentsToInstallments مع رد غير مربوط', () {
      final insts = [_inst('i9', '2026-09-01'), _inst('i10', '2026-10-01')];
      final payments = [_pay(200, '2026-09-05'), _pay(-70, '2026-10-05', purpose: 'refund')];
      final paid = allocatePaymentsToInstallments(insts, payments);
      expect(paid['i9'], 100);
      expect(paid['i10'], 30);
      final slices = allocatePaymentSlices(payments, insts);
      double sum(String id) => slices.where((s) => s.installmentId == id).fold(0.0, (a, s) => a + s.amount);
      expect(sum('i9'), 100);
      expect(sum('i10'), 30);
      expect(slices.fold<double>(0, (a, s) => a + s.amount), 130);
    });
  });

  group('computeProfitReport', () {
    test('قسط 9 مدفوع في 10: paid على 10، due على 9', () {
      final installments = [_inst('i9', '2026-09-01')];
      final payments = [_pay(100, '2026-10-10', installmentId: 'i9')];
      final paid = _report(ProfitBasis.paid, payments: payments, installments: installments);
      expect(_month(paid, '2026-10').income, 100);
      expect(_month(paid, '2026-09').income, 0);
      final due = _report(ProfitBasis.due, payments: payments, installments: installments);
      expect(_month(due, '2026-09').income, 100);
      expect(_month(due, '2026-10').income, 0);
    });

    test('due: دفعة غير مربوطة تتقسم على شهري القسطين، والدخل العام على يوم القبض', () {
      final r = _report(
        ProfitBasis.due,
        payments: [_pay(150, '2026-11-02'), _pay(80, '2026-11-02', studentId: '', purpose: 'other_income')],
        installments: [_inst('i9', '2026-09-01'), _inst('i10', '2026-10-01')],
      );
      expect(_month(r, '2026-09').income, 100);
      expect(_month(r, '2026-10').income, 50);
      expect(_month(r, '2026-11').income, 80);
    });

    test('الاسترجاع ينقص الربح، والملغى مستبعد', () {
      final r = _report(ProfitBasis.paid, payments: [
        _pay(100, '2026-09-05'),
        _pay(-40, '2026-10-05', purpose: 'refund'),
        _pay(500, '2026-09-06', cancelled: true),
      ]);
      expect(_month(r, '2026-10').refunds, -40);
      expect(r.total.net, 60);
    });

    test('الخصم يظهر ولا يمسّ الربح', () {
      final installments = [_inst('i9', '2026-09-01')];
      final payments = [_pay(80, '2026-09-05', discount: 20, installmentId: 'i9')];
      for (final basis in ProfitBasis.values) {
        final r = _report(basis, payments: payments, installments: installments);
        expect(r.total.discounts, 20);
        expect(r.total.income, 80);
        expect(r.total.net, 80);
      }
    });

    test('المسحوبات والتحويل لا يمسّان الربح، والمسحوبات تنقص الباقي', () {
      final r = _report(
        ProfitBasis.paid,
        payments: [_pay(1000, '2026-09-05')],
        expenses: [_exp(100, '2026-09-10'), _exp(200, '2026-09-11', 'draw'), _exp(300, '2026-09-12', 'transfer')],
        payouts: [_payout(150, '2026-09-01', '2026-10-03')],
      );
      final sep = _month(r, '2026-09');
      expect(sep.expenses, 100);
      expect(sep.salaries, 150);
      expect(sep.net, 750);
      expect(sep.draws, 200);
      expect(sep.remaining, 550);
      expect(_month(r, '2026-10').salaries, 0);
    });

    test('مجموع الأشهر = مجموع الفترة', () {
      final installments = [_inst('i9', '2026-09-01'), _inst('i10', '2026-10-01'), _inst('i11', '2026-11-01')];
      final payments = [
        _pay(150, '2026-09-20'),
        _pay(100, '2026-11-02', installmentId: 'i11', discount: 10),
        _pay(-30, '2026-12-01', purpose: 'refund'),
        _pay(50, '2026-10-02', studentId: ''),
      ];
      final expenses = [_exp(40, '2026-10-10'), _exp(25, '2026-12-01', 'draw')];
      final payouts = [_payout(60, '2026-11-01', '2026-11-30')];
      final keys = <double Function(ProfitRow)>[
        (x) => x.income,
        (x) => x.refunds,
        (x) => x.discounts,
        (x) => x.expenses,
        (x) => x.salaries,
        (x) => x.net,
        (x) => x.draws,
        (x) => x.remaining,
      ];
      for (final basis in ProfitBasis.values) {
        final r = _report(basis, payments: payments, installments: installments, expenses: expenses, payouts: payouts);
        for (final k in keys) {
          expect(r.rows.fold<double>(0, (s, row) => s + k(row)), closeTo(k(r.total), 1e-6));
        }
        expect(r.rows.map((x) => x.month), ['2026-09', '2026-10', '2026-11', '2026-12']);
      }
    });
  });

  test('نوع سند الصرف يُقرأ ويُكتب، والغائب مصروف', () {
    expect(Expense.fromCloud({'id': 'e', 'amount': 5, 'kind': 'draw'}).kind, 'draw');
    expect(expenseKindOf(Expense.fromCloud({'id': 'e', 'amount': 5})), 'expense');
    expect(expenseKindOf(Expense.fromCloud({'id': 'e', 'amount': 5, 'kind': 'odd'})), 'expense');
    expect(_exp(5, '2026-09-01', 'draw').toCloud()['kind'], 'draw');
  });
}
