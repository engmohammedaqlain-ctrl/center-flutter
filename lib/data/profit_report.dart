/// تقرير الأرباح — المقابل لـ `features/finance/profitReport.ts`.
library;

import 'dart:math' as math;

import '../models/models.dart';
import 'balance.dart';
import 'teacher_salary.dart';

const _cent = 0.005;

/// جزء من سند ذهب لقسط بعينه، أو بقي بلا قسط (`installmentId: null`: زائد عن الأقساط،
/// أو مال تقابل مع سند خارج). مجموع شرائح السند = مبلغه + خصمه دائماً.
/// `isDiscount`: الجزء من خصم السند لا من نقده — النقد يُستهلك أولاً.
typedef PaymentSlice = ({String paymentId, String? installmentId, double amount, bool isDiscount});

/// ما بقي من سند موجب لم يُوزَّع: نقده ثم خصمه.
class _Chunk {
  _Chunk(this.paymentId, this.cash, this.discount);
  final String paymentId;
  double cash;
  double discount;
}

/// يأخذ من رأس الحصة: النقد أولاً ثم الخصم.
void _take(_Chunk chunk, double amount, String? installmentId, List<PaymentSlice> out) {
  final cash = math.min(amount, chunk.cash);
  if (cash > _cent) out.add((paymentId: chunk.paymentId, installmentId: installmentId, amount: cash, isDiscount: false));
  chunk.cash -= cash;
  final discount = math.min(amount - cash, chunk.discount);
  if (discount > _cent) {
    out.add((paymentId: chunk.paymentId, installmentId: installmentId, amount: discount, isDiscount: true));
  }
  chunk.discount -= discount;
}

/// توزيع سندات طالب واحد على أقساطه، شريحةً شريحة — `allocatePaymentSlices`.
///
/// القواعد نفسها التي يُحسب بها المسدَّد ([allocatePaymentsToInstallments]): السند
/// المربوط يسدّد قسطه أولاً، والباقي يُجمع ويذهب للأقدم استحقاقاً. السند الخارج (رد أو
/// عكس) يُفك من قسط السند الأصلي، وما زاد يقابل المال الحر، ثم يُفك من أحدث الأقساط
/// المسددة. الملغى لا شرائح له.
List<PaymentSlice> allocatePaymentSlices(Iterable<Payment> payments, Iterable<Installment> installments) {
  final ordered = [...installments]..sort(compareInstallments);
  final remaining = {for (final i in ordered) i.id: math.max(0.0, chargeableAmount(i))};
  final paid = {for (final i in ordered) i.id: 0.0};
  final slices = <PaymentSlice>[];

  final all = [...payments];
  final byId = {for (final p in all) p.id: p};
  final active = all.where((p) => !p.cancelled).toList()
    ..sort((a, b) {
      final byCreated = (a.createdAt ?? '').compareTo(b.createdAt ?? '');
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

  final positive = <_Chunk>[];
  final negative = <({String paymentId, double amount})>[];

  for (final p in active) {
    final cashAmount = p.amount;
    var credit = cashAmount + p.discountAmount;

    if (credit < 0) {
      final originId = p.reversesPaymentId;
      final origin = originId == null ? null : byId[originId];
      final back = p.installmentId ?? origin?.installmentId;
      if (back != null && paid.containsKey(back)) {
        final give = math.min(-credit, paid[back]!);
        paid[back] = paid[back]! - give;
        remaining[back] = remaining[back]! + give;
        credit += give;
        if (give > _cent) slices.add((paymentId: p.id, installmentId: back, amount: -give, isDiscount: false));
      }
      if (credit < -_cent) negative.add((paymentId: p.id, amount: credit));
      continue;
    }

    final cash = math.max(0.0, cashAmount);
    final chunk = _Chunk(p.id, cash, credit - cash);
    final target = p.installmentId;
    if (target != null && remaining.containsKey(target)) {
      final t = math.min(credit, remaining[target]!);
      remaining[target] = remaining[target]! - t;
      paid[target] = paid[target]! + t;
      _take(chunk, t, target, slices);
    }
    if (chunk.cash + chunk.discount > _cent) positive.add(chunk);
  }

  // المجمّع: المال الحر ناقص الخارج غير المربوط. صافيه وحده يُوزَّع، والمتقابل منه
  // يبقى بلا قسط في الطرفين
  final posTotal = positive.fold<double>(0, (s, c) => s + c.cash + c.discount);
  final negTotal = negative.fold<double>(0, (s, n) => s + n.amount);
  var pool = posTotal + negTotal;

  if (pool > _cent) {
    for (final inst in ordered) {
      if (pool <= _cent) break;
      var t = math.min(pool, remaining[inst.id]!);
      remaining[inst.id] = remaining[inst.id]! - t;
      paid[inst.id] = paid[inst.id]! + t;
      pool -= t;
      for (final chunk in positive) {
        if (t <= _cent) break;
        final part = math.min(t, chunk.cash + chunk.discount);
        if (part <= 0) continue;
        _take(chunk, part, inst.id, slices);
        t -= part;
      }
    }
  }
  // ما بقي من المال الحر: زائد عن الأقساط، أو تقابل مع الخارج
  for (final chunk in positive) {
    _take(chunk, chunk.cash + chunk.discount, null, slices);
  }

  // ما رُدّ أكثر من المال الحر يُفك من أحدث الأقساط المسددة
  final unwound = <({String installmentId, double amount})>[];
  for (final inst in ordered.reversed) {
    if (pool >= -_cent) break;
    final give = math.min(-pool, paid[inst.id]!);
    if (give <= 0) continue;
    paid[inst.id] = paid[inst.id]! - give;
    remaining[inst.id] = remaining[inst.id]! + give;
    pool += give;
    unwound.add((installmentId: inst.id, amount: give));
  }
  var u = 0;
  var uLeft = unwound.isEmpty ? 0.0 : unwound.first.amount;
  for (final n in negative) {
    var left = -n.amount;
    while (left > _cent && u < unwound.length) {
      final part = math.min(left, uLeft);
      slices.add((paymentId: n.paymentId, installmentId: unwound[u].installmentId, amount: -part, isDiscount: false));
      uLeft -= part;
      left -= part;
      if (uLeft <= _cent) {
        u++;
        uLeft = u < unwound.length ? unwound[u].amount : 0;
      }
    }
    if (left > _cent) slices.add((paymentId: n.paymentId, installmentId: null, amount: -left, isDiscount: false));
  }

  return slices;
}

/// `paid`: الدفعة في شهر قبضها. `due`: كل شريحة في شهر موعد قسطها.
enum ProfitBasis { paid, due }

class ProfitRow {
  ProfitRow(this.month);

  /// YYYY-MM، أو '' لصف المجموع.
  final String month;

  /// المقبوض نقداً.
  double income = 0;

  /// الرد والعكس (سالب).
  double refunds = 0;

  /// الخصومات: للمعلومة، لا تنقص الربح.
  double discounts = 0;
  double expenses = 0;
  double salaries = 0;

  /// income + refunds − expenses − salaries
  double net = 0;

  /// المسحوبات من الربح.
  double draws = 0;

  /// net − draws
  double remaining = 0;

  /// المقبوض صافياً بعد الرد والعكس — كما يُعرض في الجدول.
  double get received => income + refunds;
}

typedef ProfitReport = ({List<ProfitRow> rows, ProfitRow total});

/// أشهر المدى بالترتيب (YYYY-MM).
List<String> monthsInRange(String from, String to) {
  final out = <String>[];
  if (from.length < 7 || to.length < 7) return out;
  var y = int.tryParse(from.substring(0, 4)) ?? 0;
  var m = int.tryParse(from.substring(5, 7)) ?? 0;
  final end = to.substring(0, 7);
  if (y == 0 || m == 0) return out;
  for (;;) {
    final key = '$y-${m.toString().padLeft(2, '0')}';
    if (key.compareTo(end) > 0) break;
    out.add(key);
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  return out;
}

/// مدى تواريخ العام أو أحد فصليه — `academicRange`: الفصل بتواريخه إن ضُبطت، وإلا نصف العام.
({String from, String to}) academicRange(AcademicYear year, String term) {
  if (term == 'term_1') {
    if (year.term1Start.isNotEmpty && year.term1End.isNotEmpty) return (from: year.term1Start, to: year.term1End);
    final mid = _midpoint(year.startsOn, year.endsOn);
    return (from: year.startsOn, to: mid.compareTo(year.startsOn) > 0 ? _addDays(mid, -1) : year.endsOn);
  }
  if (term == 'term_2') {
    if (year.term2Start.isNotEmpty && year.term2End.isNotEmpty) return (from: year.term2Start, to: year.term2End);
    return (from: _midpoint(year.startsOn, year.endsOn), to: year.endsOn);
  }
  return (from: year.startsOn, to: year.endsOn);
}

String _addDays(String date, int days) {
  final d = DateTime.utc(int.parse(date.substring(0, 4)), int.parse(date.substring(5, 7)), int.parse(date.substring(8, 10)));
  return isoDate(d.add(Duration(days: days)));
}

String _midpoint(String start, String end) {
  final a = DateTime.tryParse(start);
  final b = DateTime.tryParse(end);
  if (a == null || b == null) return start;
  return isoDate(DateTime.fromMillisecondsSinceEpoch(a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) ~/ 2));
}

/// ربح المدى شهراً شهراً — `computeProfitReport`.
///
/// `due`: قسط 9 قُبض في 10 يُحسب لـ9؛ الدخل العام والزائد عن الأقساط يبقيان على يوم
/// القبض. الخصم يظهر وحده ولا ينقص الربح. سند الصرف: المصروف ينقص الربح، والمسحوبات
/// تنقص الباقي وحده، والتحويل لا يدخل. الراتب على شهره ([salaryMonthOf]).
ProfitReport computeProfitReport({
  required Iterable<Payment> payments,
  required Iterable<Installment> installments,
  required Iterable<Expense> expenses,
  required Iterable<TeacherPayout> payouts,
  required ({String from, String to}) range,
  required ProfitBasis basis,
}) {
  final rows = {for (final m in monthsInRange(range.from, range.to)) m: ProfitRow(m)};
  ProfitRow? at(String date) {
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    if (d.isEmpty || d.compareTo(range.from) < 0 || d.compareTo(range.to) > 0) return null;
    return rows[d.substring(0, 7)];
  }

  void addMoney(ProfitRow? row, double amount, bool isDiscount) {
    if (row == null || amount == 0) return;
    if (isDiscount) {
      row.discounts += amount;
    } else if (amount < 0) {
      row.refunds += amount;
    } else {
      row.income += amount;
    }
  }

  final active = payments.where((p) => !p.cancelled);

  if (basis == ProfitBasis.paid) {
    for (final p in active) {
      final row = at(isoDate(p.date));
      addMoney(row, p.amount, false);
      addMoney(row, p.discountAmount, true);
    }
  } else {
    final paymentsByStudent = <String, List<Payment>>{};
    for (final p in active) {
      if (p.studentId.isEmpty) {
        final row = at(isoDate(p.date));
        addMoney(row, p.amount, false);
        addMoney(row, p.discountAmount, true);
        continue;
      }
      paymentsByStudent.putIfAbsent(p.studentId, () => []).add(p);
    }
    final installmentsByStudent = <String, List<Installment>>{};
    for (final i in installments) {
      installmentsByStudent.putIfAbsent(i.studentId, () => []).add(i);
    }
    final installmentById = {for (final i in installments) i.id: i};
    for (final e in paymentsByStudent.entries) {
      final paymentById = {for (final p in e.value) p.id: p};
      for (final s in allocatePaymentSlices(e.value, installmentsByStudent[e.key] ?? const [])) {
        final inst = s.installmentId == null ? null : installmentById[s.installmentId];
        final paidOn = paymentById[s.paymentId];
        final date = inst != null ? isoDate(inst.dueDate) : (paidOn == null ? '' : isoDate(paidOn.date));
        addMoney(at(date), s.amount, s.isDiscount);
      }
    }
  }

  for (final e in expenses) {
    final row = at(e.expenseDate);
    if (row == null) continue;
    switch (expenseKindOf(e)) {
      case 'expense':
        row.expenses += e.amount;
      case 'draw':
        row.draws += e.amount;
    }
  }

  for (final p in payouts) {
    if (at(p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate) == null) continue;
    final row = rows[salaryMonthOf(p)];
    if (row != null) row.salaries += p.amount;
  }

  final total = ProfitRow('');
  final list = rows.values.toList();
  for (final r in list) {
    r.net = r.income + r.refunds - r.expenses - r.salaries;
    r.remaining = r.net - r.draws;
    total.income += r.income;
    total.refunds += r.refunds;
    total.discounts += r.discounts;
    total.expenses += r.expenses;
    total.salaries += r.salaries;
    total.draws += r.draws;
  }
  total.net = total.income + total.refunds - total.expenses - total.salaries;
  total.remaining = total.net - total.draws;
  return (rows: list, total: total);
}
