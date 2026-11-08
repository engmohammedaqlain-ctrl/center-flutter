/// أرصدة الحسابات (نقداً، بنك، محافظ) عبر السنين — المقابل لـ `yearClosing.ts`.
///
/// كل حركة نقدية تقع في سنة واحدة بتاريخ حدوثها: السنة من بدايتها إلى بداية
/// التالية، وأول سنة تأخذ ما قبلها. رصيد آخر السنة = الافتتاحي + ما دخل − ما خرج.
/// الإقفال يثبّت رصيد آخر السنة، فيصير افتتاحي السنة التالية؛ وسنة لم تُقفل
/// يُرحَّل محسوبها كما هو.
library;

import '../models/models.dart';

typedef Balances = Map<String, double>;

double _round2(num n) => (n * 100).round() / 100;

void _add(Balances b, String method, double amount) {
  b[method] = _round2((b[method] ?? 0) + amount);
}

/// إقفال سنة في `settings.year_closings` — `YearClosing`.
class YearClosing {
  const YearClosing({required this.balances, required this.computed, this.at = '', this.by = ''});

  /// المعتمد: المعدود فعلاً في كل حساب.
  final Balances balances;

  /// المحسوب لحظة الإقفال: إن تغيّرت حركة السنة بعده يُنبَّه المدير.
  final Balances computed;
  final String at;
  final String by;

  Map<String, dynamic> toMap() => {'balances': balances, 'computed': computed, 'at': at, 'by': by};

  static Balances _balances(Object? raw) => {
        if (raw is Map)
          for (final e in raw.entries) '${e.key}': (e.value is num ? (e.value as num).toDouble() : 0.0),
      };

  factory YearClosing.fromMap(Map<String, dynamic> m) => YearClosing(
        balances: _balances(m['balances']),
        computed: _balances(m['computed']),
        at: '${m['at'] ?? ''}',
        by: '${m['by'] ?? ''}',
      );

  /// `settings.year_closings` مقروءة؛ قيمة تالفة لا تُعطّل شيئاً.
  static Map<String, YearClosing> allFrom(Object? raw) => {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map) '${e.key}': YearClosing.fromMap(Map<String, dynamic>.from(e.value as Map)),
      };
}

/// السنين بترتيب بدايتها، ومدى كل سنة النقدي: [بدايتها، بداية التالية) — `yearSpans`.
List<({AcademicYear year, String from, String until})> yearSpans(Iterable<AcademicYear> years) {
  final sorted = [for (final y in years) if (y.startsOn.isNotEmpty) y]
    ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
  return [
    for (var i = 0; i < sorted.length; i++)
      (
        year: sorted[i],
        from: i == 0 ? '' : sorted[i].startsOn,
        until: i + 1 < sorted.length ? sorted[i + 1].startsOn : '9999-12-31',
      ),
  ];
}

String _day(String date) => date.length >= 10 ? date.substring(0, 10) : date;

/// ما دخل كل حساب ناقص ما خرج منه بين تاريخين — `walletFlows`.
Balances walletFlows({
  required Iterable<Payment> payments,
  required Iterable<Expense> expenses,
  required Iterable<TeacherPayout> payouts,
  required String from,
  required String until,
}) {
  bool inRange(String date) {
    final day = _day(date);
    return day.isNotEmpty && day.compareTo(from) >= 0 && day.compareTo(until) < 0;
  }

  final b = <String, double>{};
  for (final p in payments) {
    if (!p.cancelled && inRange(isoDate(p.date))) _add(b, p.method, p.amount);
  }
  for (final e in expenses) {
    if (e.cancelled || !inRange(e.expenseDate)) continue;
    _add(b, e.method, -e.amount);
    // التحويل يخرج من حسابه ويدخل المستلِم؛ التحويل القديم بلا مستلِم يخرج فقط
    if (e.isTransferIn) _add(b, e.toMethod, e.amount);
  }
  for (final p in payouts) {
    if (!p.cancelled && inRange(p.paymentDate)) _add(b, p.method, -p.amount);
  }
  return b;
}

Balances _sum(Balances a, Balances b) {
  final out = {...a};
  for (final e in b.entries) {
    out[e.key] = _round2((out[e.key] ?? 0) + e.value);
  }
  return out;
}

/// تطابق رصيدين حتى القرش، والحساب الغائب صفر — `same`.
bool sameBalances(Balances a, Balances b) {
  final keys = {...a.keys, ...b.keys};
  return keys.every((k) => ((a[k] ?? 0) - (b[k] ?? 0)).abs() < 0.01);
}

class YearBalances {
  const YearBalances({
    required this.opening,
    required this.flows,
    required this.computed,
    required this.closing,
    required this.closed,
    required this.stale,
  });

  /// افتتاحي السنة: إقفال السابقة أو محسوبها.
  final Balances opening;

  /// حركة السنة.
  final Balances flows;

  /// محسوب آخر السنة: الافتتاحي + الحركة.
  final Balances computed;

  /// المعتمد آخر السنة: المُقفل إن أُقفلت، وإلا المحسوب.
  final Balances closing;
  final YearClosing? closed;

  /// حركة السنة أو ما قبلها تغيّرت بعد إقفالها.
  final bool stale;
}

/// أرصدة كل سنة بالترتيب، كل سنة تبدأ بما أُقفلت عليه التي قبلها — `yearBalances`.
Map<String, YearBalances> yearBalances({
  required Iterable<AcademicYear> years,
  required Map<String, YearClosing> closings,
  required Iterable<Payment> payments,
  required Iterable<Expense> expenses,
  required Iterable<TeacherPayout> payouts,
}) {
  final out = <String, YearBalances>{};
  var carry = <String, double>{};
  for (final span in yearSpans(years)) {
    final flows = walletFlows(payments: payments, expenses: expenses, payouts: payouts, from: span.from, until: span.until);
    final computed = _sum(carry, flows);
    final closed = closings[span.year.id];
    final closing = closed?.balances ?? computed;
    out[span.year.id] = YearBalances(
      opening: carry,
      flows: flows,
      computed: computed,
      closing: closing,
      closed: closed,
      stale: closed != null && !sameBalances(closed.computed, computed),
    );
    carry = closing;
  }
  return out;
}

/// الأرصدة سطوراً للعرض، الأكبر أولاً، بلا حساب صفري — `balanceRows`.
List<({String method, double amount})> balanceRows(Balances b) => [
      for (final e in b.entries)
        if (e.value.abs() >= 0.01) (method: e.key, amount: e.value),
    ]..sort((x, y) => y.amount.compareTo(x.amount));

/// السنة المغلقة التي يقع فيها التاريخ لهذا النوع من الكتابة — `closedYearOf`.
///
/// **المال** (`money`): يُرفض بتاريخ سنة أُقفلت مالياً، حتى يُفتح الإقفال من الأرباح.
/// **المدرسة** (`school`، حضور وعلامات): يُرفض بتاريخ داخل سنة أُغلقت دراسياً حتى
/// نهايتها، وما بعد نهايتها مفتوح للإكمال والتصحيح.
AcademicYear? closedYearOf(
  String date,
  Iterable<AcademicYear> years,
  Map<String, YearClosing> closings, {
  String kind = 'money',
}) {
  final day = _day(date);
  if (day.isEmpty) return null;
  for (final s in yearSpans(years)) {
    if (day.compareTo(s.from) < 0 || day.compareTo(s.until) >= 0) continue;
    if (kind == 'money') return closings.containsKey(s.year.id) ? s.year : null;
    return s.year.status == 'closed' && (s.year.endsOn.isEmpty || day.compareTo(s.year.endsOn) <= 0) ? s.year : null;
  }
  return null;
}

/// نص الرفض — `closedYearMessage`.
String closedYearMessage(AcademicYear year, String what, {String kind = 'money'}) =>
    '${what.isEmpty ? '' : '$what — '}سنة ${year.label} مغلقة'
    '${kind == 'money' ? ' مالياً: افتح الإقفال من الأرباح للتصحيح' : ''}';
