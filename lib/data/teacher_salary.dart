import '../models/models.dart';

/// راتب المعلم الشهري وسجل تغييراته — المقابل لـ `features/finance/teacherSalary.ts`.
///
/// الراتب يتغيّر خلال السنة، وراتب شهر مضى يجب أن يبقى كما كان وقته: بلا سجل،
/// كانت زيادةٌ اليوم تظهر ديناً على أشهر صُرفت وأُغلقت.

/// بداية مفتوحة: راتب سُجّل قبل وجود السجل يسري على كل ما قبل أول تغيير.
const openSalaryStart = '0000-01';

String monthLabel(String month) =>
    month.length < 7 ? month : '${month.substring(5, 7)}/${month.substring(0, 4)}';

String monthKeyOf(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// شهر الراتب الذي يُنسب له الصرف، لا يوم صرفه: راتب أيلول المصروف في تشرين لأيلول.
String salaryMonthOf(TeacherPayout p) {
  final raw = p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate;
  return raw.length < 7 ? raw : raw.substring(0, 7);
}

/// الراتب النافذ في شهر: آخر تغيير بدأ فيه أو قبله، ولا راتب قبل أول تسجيل.
double salaryForMonth(Teacher teacher, String month) {
  final history = teacher.salaryHistory;
  if (history.isEmpty) return teacher.rate;
  final sorted = [...history]..sort((a, b) => a.from.compareTo(b.from));
  var amount = 0.0;
  for (final change in sorted) {
    if (change.from.compareTo(month) <= 0) amount = change.amount;
  }
  return amount;
}

/// تسجيل راتب يسري من شهر؛ تغيير في الشهر نفسه يستبدل قيمته.
List<SalaryChange> applySalaryChange(Teacher? teacher, String from, double amount) {
  final current = teacher == null ? 0.0 : salaryForMonth(teacher, from);
  final history = <SalaryChange>[
    if (teacher != null && teacher.salaryHistory.isNotEmpty)
      ...teacher.salaryHistory
    else if (teacher != null && teacher.rate > 0)
      SalaryChange(from: openSalaryStart, amount: teacher.rate),
  ];
  if (current == amount) return history;
  return [
    ...history.where((h) => h.from != from),
    SalaryChange(from: from, amount: amount),
  ]..sort((a, b) => a.from.compareTo(b.from));
}

String describeSalaryChange(SalaryChange change) =>
    change.from == openSalaryStart ? 'سابقاً ${money(change.amount)}' : '${monthLabel(change.from)}: ${money(change.amount)}';

/// راتب الشهر وما صُرف منه عن الشهر نفسه.
({double rate, double paid, double remaining}) teacherSalaryDue(
  Teacher teacher,
  Iterable<TeacherPayout> payouts,
  String month,
) {
  final rate = salaryForMonth(teacher, month);
  var paid = 0.0;
  for (final p in payouts) {
    if (p.teacherId == teacher.id && salaryMonthOf(p) == month) paid += p.amount;
  }
  final remaining = rate - paid;
  return (rate: rate, paid: paid, remaining: remaining < 0 ? 0 : remaining);
}
