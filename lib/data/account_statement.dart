/// كشف الحسابات الشهري — المقابل لـ `accountStatement.ts`: لكل حساب في كل شهر ما دخله وما خرج
/// منه ورصيد آخره. الداخل: القبض وما حُوِّل إليه. الخارج: سندات الصرف بأنواعها وأجور المعلمين
/// ورد المبالغ. الملغى لا يُعدّ، والرصيد نفس رصيد `yearBalances` لآخر السنة.
library;

import '../models/models.dart';
import 'method_owners.dart';
import 'payment_methods.dart';

double _round2(num n) => (n * 100).round() / 100;

class StatementMonth {
  const StatementMonth({required this.month, required this.inflow, required this.outflow, required this.balance});

  final String month;
  final double inflow;
  final double outflow;

  /// رصيد آخر الشهر.
  final double balance;
}

class AccountStatement {
  const AccountStatement({
    required this.method,
    required this.opening,
    required this.months,
    required this.totalIn,
    required this.totalOut,
    required this.closing,
  });

  final String method;
  final double opening;
  final List<StatementMonth> months;
  final double totalIn;
  final double totalOut;
  final double closing;

  bool get active => opening.abs() >= 0.01 || totalIn >= 0.01 || totalOut >= 0.01;
}

/// [opening] رصيد كل حساب أول الفترة؛ [from] بدايتها النقدية و[until] نهايتها (مستثناة)؛
/// حركة قبل أول [months] تدخل الافتتاحي، وبعد آخرها تدخل آخرها.
Map<String, AccountStatement> accountStatement({
  required Iterable<Payment> payments,
  required Iterable<Expense> expenses,
  required Iterable<TeacherPayout> payouts,
  required Map<String, double> opening,
  required String from,
  required String until,
  required List<String> months,
  Iterable<String> methods = const [],
}) {
  final first = months.isEmpty ? '' : months.first;
  final last = months.isEmpty ? '' : months.last;
  final carry = <String, double>{};
  final flows = <String, Map<String, List<double>>>{};
  final methodSet = <String>{...opening.keys, ...methods};

  void post(String method, String date, double amount) {
    final day = date.length >= 10 ? date.substring(0, 10) : date;
    if (day.isEmpty || day.compareTo(from) < 0 || day.compareTo(until) >= 0 || amount == 0) return;
    methodSet.add(method);
    final month = day.substring(0, 7);
    if (first.isNotEmpty && month.compareTo(first) < 0) {
      carry[method] = _round2((carry[method] ?? 0) + amount);
      return;
    }
    final at = last.isNotEmpty && month.compareTo(last) > 0 ? last : month;
    final c = flows.putIfAbsent(method, () => {}).putIfAbsent(at, () => [0, 0]);
    if (amount > 0) {
      c[0] += amount;
    } else {
      c[1] -= amount;
    }
  }

  for (final p in payments) {
    if (!p.cancelled) post(p.method, isoDate(p.date), p.amount);
  }
  for (final e in expenses) {
    if (e.cancelled) continue;
    post(e.method, e.expenseDate, -e.amount);
    if (e.isTransferIn) post(e.toMethod, e.expenseDate, e.amount);
  }
  for (final p in payouts) {
    if (!p.cancelled) post(p.method, p.paymentDate, -p.amount);
  }

  final out = <String, AccountStatement>{};
  for (final method in methodSet) {
    final start = _round2((opening[method] ?? 0) + (carry[method] ?? 0));
    var balance = start;
    var totalIn = 0.0;
    var totalOut = 0.0;
    final rows = <StatementMonth>[];
    for (final month in months) {
      final c = flows[method]?[month];
      final inn = _round2(c?[0] ?? 0);
      final outt = _round2(c?[1] ?? 0);
      balance = _round2(balance + inn - outt);
      totalIn += inn;
      totalOut += outt;
      rows.add(StatementMonth(month: month, inflow: inn, outflow: outt, balance: balance));
    }
    out[method] = AccountStatement(
      method: method,
      opening: start,
      months: rows,
      totalIn: _round2(totalIn),
      totalOut: _round2(totalOut),
      closing: balance,
    );
  }
  return out;
}

/// الحسابات مجمّعة بصاحبها، وغير المسجَّلين آخراً — `groupByOwner`.
List<({String owner, String label, List<PaymentMethodItem> accounts})> statementOwners(
  Iterable<PaymentMethodItem> methods,
) {
  final g = groupMethodsByOwner<PaymentMethodItem>(methods, (m) => m.owner);
  return [
    for (final x in g.groups) (owner: x.owner, label: x.owner, accounts: x.items),
    if (g.ungrouped.isNotEmpty) (owner: '', label: noOwner, accounts: g.ungrouped),
  ];
}

/// أشهر من YYYY-MM إلى YYYY-MM شاملة — `monthsBetween`.
List<String> statementMonthsBetween(String from, String to) {
  final out = <String>[];
  if (from.length < 7 || to.length < 7) return out;
  var y = int.parse(from.substring(0, 4));
  var m = int.parse(from.substring(5, 7));
  final ty = int.parse(to.substring(0, 4));
  final tm = int.parse(to.substring(5, 7));
  while ((y < ty || (y == ty && m <= tm)) && out.length < 36) {
    out.add('$y-${m.toString().padLeft(2, '0')}');
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}
