/// أجر الموظف وأرقام صف الرواتب — المقابل لـ `payTerms.ts` و`payCell.ts` و`payrollBase.ts`
/// و`payrollRows.ts`. دوال صافية: يستعملها كشف الرواتب ونموذج المعلم.
library;

import '../models/models.dart';
import 'payroll_calc.dart';

double _num(Object? v) {
  final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  return n < 0 || n.isNaN ? 0 : n;
}

/// خانات الأجر كما يكتبها المستخدم: الفارغ صفر — `PayInput`.
class PayInput {
  const PayInput({
    required this.fixed,
    required this.sessionRate,
    required this.percent,
    required this.percentBasis,
    required this.absenceDeduct,
    required this.allowances,
    required this.perLesson,
  });

  final double fixed;
  final double sessionRate;
  final double percent;
  final String percentBasis;
  final bool absenceDeduct;
  final List<({String name, double amount})> allowances;
  final bool perLesson;

  PayInput copyWith({double? fixed, double? sessionRate, double? percent, bool? perLesson}) => PayInput(
        fixed: fixed ?? this.fixed,
        sessionRate: sessionRate ?? this.sessionRate,
        percent: percent ?? this.percent,
        percentBasis: percentBasis,
        absenceDeduct: absenceDeduct,
        allowances: allowances,
        perLesson: perLesson ?? this.perLesson,
      );
}

/// شروط المعلم الحالية — `termsOf`.
PayTerms currentTerms(Teacher t) =>
    PayTerms.of(contractType: t.contractType, paymentRate: t.rate, weeklyPeriods: t.weeklyPeriods, payProfile: t.payProfile);

/// خانات الأجر الحالية للمعلم: منها يبدأ أي نموذج تعديل — `payInputOf`.
PayInput payInputOf(Teacher t) {
  final c = currentTerms(t);
  return PayInput(
    fixed: c.fixed,
    sessionRate: c.sessionRate,
    percent: c.percent,
    percentBasis: c.percentBasis,
    absenceDeduct: c.absenceDeduct,
    allowances: c.allowances,
    perLesson: c.perLesson,
  );
}

String _termsKey(PayTerms t) => [
      t.contractType,
      t.fixed,
      t.sessionRate,
      t.percent,
      t.percentBasis,
      t.absenceDeduct,
      t.weeklyPeriods,
      t.perLesson,
      for (final a in t.allowances) '${a.name}:${a.amount}',
    ].join('|');

/// ما يُكتب عند تعديل أجر معلم — `payUpdate`: الشروط المخزّنة، مع حفظ القديمة لما قبل الشهر
/// فلا يُعاد حساب شهر سابق بالأجر الجديد. قسط السلفة يبقى. `salary_history` غائب إن لم تتغير.
Map<String, dynamic> payUpdate(Teacher prev, PayInput input, String month, {double? weeklyPeriods}) {
  final fixed = _num(input.fixed);
  final rate = _num(input.sessionRate);
  final percent = _num(input.percent) > 100 ? 100.0 : _num(input.percent);
  final parts = [if (fixed > 0) 'fixed', if (rate > 0) 'sessions', if (percent > 0) 'percent'];
  final kind = parts.length > 1 ? 'mixed' : parts.firstOrNull ?? '';
  final sessionsOnly = kind == 'sessions';
  final prevProfile = prev.payProfile is Map ? prev.payProfile as Map : const {};
  final allowances = [
    for (final a in input.allowances)
      if (a.name.trim().isNotEmpty && a.amount > 0) {'name': a.name.trim(), 'amount': a.amount},
  ];
  final profile = <String, dynamic>{
    if (!sessionsOnly && rate > 0) 'session_rate': rate,
    if (percent > 0) 'percent': percent,
    if (allowances.isNotEmpty) 'allowances': allowances,
    if (percent > 0 && input.percentBasis == 'due') 'percent_basis': 'due',
    if (!input.absenceDeduct) 'absence_deduct': false,
    if (_num(prevProfile['advance_installment']) > 0) 'advance_installment': prevProfile['advance_installment'],
    if (input.perLesson) 'per_lesson': true,
  };
  final payProfile = profile.isEmpty ? null : profile;
  final paymentRate = sessionsOnly ? rate : fixed;
  final weekly = (weeklyPeriods ?? prev.weeklyPeriods);
  final weeklyValue = weekly != null && weekly > 0 ? weekly : null;

  final before = currentTerms(prev);
  final after = PayTerms.of(contractType: kind, paymentRate: paymentRate, weeklyPeriods: weeklyValue, payProfile: payProfile);
  Map<String, dynamic> record(String from, String? type, double r, double? w, Object? p) => {
        'from': from,
        'contract_type': type == null || type.isEmpty ? null : type,
        'payment_rate': r,
        'weekly_periods': w,
        'pay_profile': p,
      };
  List<Map<String, dynamic>>? history;
  if (_termsKey(before) != _termsKey(after)) {
    final kept = [
      for (final h in prev.salaryHistory)
        if (h['from'] is String && h.containsKey('payment_rate') && (h['from'] as String).compareTo(month) < 0) h,
    ];
    if (kept.isEmpty) kept.add(record('0000-00', prev.contractType, prev.rate, prev.weeklyPeriods, prev.payProfile));
    history = [...kept, record(month, kind, paymentRate, weeklyValue, payProfile)];
  }
  return {
    'contract_type': kind.isEmpty ? null : kind,
    'payment_rate': paymentRate,
    'pay_profile': payProfile,
    if (weeklyPeriods != null) 'weekly_periods': weeklyValue,
    if (history != null) 'salary_history': history,
  };
}

/// هل يُخصم غياب هذا الموظف: ثابت أو حصص نصاب، ما لم يُطفأ — `absenceApplies`.
bool absenceApplies(PayTerms t, String sessionsFrom, bool schoolDeducts, bool perLessonOn) =>
    !isPerLesson(t, perLessonOn) &&
    schoolDeducts &&
    t.absenceDeduct &&
    (t.fixed > 0 || (t.sessionRate > 0 && sessionsFrom == 'load'));

/// ما كتبه المستخدم رقماً: الفارغ `null`، وغير الرقم صفر. الأرقام العربية مقبولة — `numOrNull`.
double? numOrNull(String text) {
  final clean = text
      .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 1632}')
      .replaceAll('٫', '.')
      .replaceAll(RegExp(r'[٬,\s]'), '');
  if (clean.isEmpty) return null;
  return double.tryParse(clean) ?? 0;
}

/// الأشهر المعروضة: الحالي و11 قبله، الأحدث أولاً — `payrollMonths`.
List<String> payrollMonths(String today, {int count = 12}) {
  final y = int.parse(today.substring(0, 4));
  final m = int.parse(today.substring(5, 7));
  return [
    for (var i = 0; i < count; i++)
      () {
        final d = DateTime(y, m - i, 1);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      }(),
  ];
}

/// أرقام صف الكشف الأربعة: الراتب − خصم + إضافة = الصافي — `RowAmounts`.
class RowAmounts {
  const RowAmounts({required this.salary, required this.cut, required this.extra, required this.net});

  final int salary;
  final int cut;
  final int extra;
  final int net;
}

/// من أعمدة الحساب والصافي الظاهر — `rowAmounts`: ما قصّر عنه الصافي يُقصّ من الخصم، وما زاد
/// (صافٍ مُعدَّل للأعلى) يدخل الراتب، فتصح المعادلة في كل صف.
RowAmounts rowAmounts(PayrollColumns cols, double net) {
  final extra = cols.extra.round();
  final n = net < 0 ? 0 : net.round();
  final gross = cols.due.round() + extra;
  if (n > gross) return RowAmounts(salary: n - extra, cut: 0, extra: extra, net: n);
  return RowAmounts(salary: cols.due.round(), cut: gross - n, extra: extra, net: n);
}

/// الخصم مقسوماً لأعمدة الجدول: غياب (ودوام)، سلفة، وخصم آخر — `splitCut`.
({int absence, int advance, int other}) splitCut(int cut, double absence, double advance) {
  final abs = absence < 0 ? 0 : absence.round();
  final a = abs < cut ? abs : cut;
  final adv0 = advance < 0 ? 0 : advance.round();
  final adv = adv0 < cut - a ? adv0 : cut - a;
  return (absence: a, advance: adv, other: cut - a - adv);
}
