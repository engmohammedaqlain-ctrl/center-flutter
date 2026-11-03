/// الراتب المقترح لشهر — المقابل لـ `features/finance/payrollCalc.ts`.
///
/// رقم يُعرض ويُعدَّل قبل الصرف، لا مطالبة. ثابت، أو بالحصة، أو نسبة من نصيب مواده في رسوم
/// شعبه، أو خليط منها؛ ثم البدلات وبنود الشهر، وخصم الغياب والإجازة غير المدفوعة والتأخير،
/// ومقتطع السلفة. القواعد في إعدادات المدرسة (`settings.payroll`).
library;

import 'dart:math' as math;

import '../models/models.dart';
import 'academic_matching.dart';
import 'balance.dart';
import 'profit_report.dart';
import 'staff.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double _r2(double n) => (n * 100).roundToDouble() / 100;

/// ما يُخصم عن كل تأخير من أجر اليوم — `LATE_FRACTIONS`.
const lateFractions = [0.0, 0.2, 0.25, 1 / 3, 0.5];

/// قواعد الحساب — `PayrollSettings`.
class PayrollSettings {
  const PayrollSettings({
    this.weekend = const [5],
    this.absenceDeduct = true,
    this.lateFraction = 0,
    this.sessionsSource = 'load',
    this.paidLeaveDays = 0,
  });

  /// أيام العطلة بترقيم JavaScript (الأحد 0 … السبت 6)
  final List<int> weekend;

  /// الغياب بلا إجازة ينقص الراتب؛ الإجازة غير المدفوعة تنقصه دائماً
  final bool absenceDeduct;

  /// ما يُخصم عن كل تأخير من أجر اليوم (0.25 = ربع يوم)؛ 0 = بلا خصم
  final double lateFraction;

  /// `load` أو `monthly` أو `daily`
  final String sessionsSource;

  /// رصيد الإجازات المدفوعة في السنة؛ 0 = بلا رصيد
  final int paidLeaveDays;

  /// `normalizePayrollSettings`؛ العطلة الأسبوعية من `settings.weekend` وإلا القديمة في `payroll`.
  factory PayrollSettings.fromMap(Object? raw, {Object? weekend}) {
    final m = raw is Map ? raw : const {};
    final w = weekend ?? m['weekend'];
    final days = w is List ? ({for (final d in w) int.tryParse('$d')}.whereType<int>().where((d) => d >= 0 && d <= 6).toList()..sort()) : <int>[5];
    final fraction = _num(m['late_fraction']);
    final leave = _num(m['paid_leave_days']).floor();
    return PayrollSettings(
      weekend: days.length < 7 ? days : const [5],
      absenceDeduct: m['absence_deduct'] != false,
      lateFraction: lateFractions.where((f) => (f - fraction).abs() < 0.001).firstOrNull ?? 0,
      sessionsSource: m['sessions_source'] == 'monthly' || m['sessions_source'] == 'daily' ? '${m['sessions_source']}' : 'load',
      paidLeaveDays: leave.clamp(0, 60),
    );
  }
}

/// شروط الأجر بخاناتها الثلاث (ثابت، أجر حصة، نسبة): أي خليط جائز، والفارغ صفر لا يُحسب — `PayTerms`.
class PayTerms {
  const PayTerms({
    required this.contractType,
    required this.fixed,
    required this.sessionRate,
    required this.percent,
    required this.weeklyPeriods,
    required this.allowances,
    this.percentBasis = 'paid',
    this.absenceDeduct = true,
    this.advanceInstallment = 0,
  });

  /// مشتق من الخانات: `fixed` أو `sessions` أو `percent` أو `mixed`، وفارغ بلا أجر
  final String contractType;
  final double fixed;
  final double sessionRate;
  final double percent;
  final double weeklyPeriods;
  final List<({String name, double amount})> allowances;

  /// النسبة من المقبوض (`paid`) أو من المستحق (`due`)
  final String percentBasis;

  /// غيابه يُخصم؛ يطفئه المدير لموظف بعينه
  final bool absenceDeduct;

  /// قسط السلفة الشهري؛ 0 = الرصيد كله
  final double advanceInstallment;

  factory PayTerms.of({String? contractType, Object? paymentRate, Object? weeklyPeriods, Object? payProfile}) {
    final p = payProfile is Map ? payProfile : const {};
    final a = p['allowances'];
    // «بالحصة» و«نسبة» القديمان: payment_rate أجر حصة أو لا شيء، لا راتب ثابت — `termsOf`
    final type = (contractType ?? '').isEmpty ? 'fixed' : contractType!;
    final rate = math.max(0.0, _num(paymentRate));
    final fixed = type == 'sessions' || type == 'percent' ? 0.0 : rate;
    final session = type == 'sessions' ? rate : math.max(0.0, _num(p['session_rate']));
    final percent = _num(p['percent']).clamp(0, 100).toDouble();
    final parts = [if (fixed > 0) 'fixed', if (session > 0) 'sessions', if (percent > 0) 'percent'];
    return PayTerms(
      contractType: parts.length > 1 ? 'mixed' : parts.firstOrNull ?? '',
      fixed: fixed,
      sessionRate: session,
      percent: percent,
      weeklyPeriods: math.max(0.0, _num(weeklyPeriods)),
      allowances: [
        if (a is List)
          for (final x in a)
            if (x is Map && '${x['name'] ?? ''}'.trim().isNotEmpty && _num(x['amount']) > 0) (name: '${x['name']}', amount: _num(x['amount'])),
      ],
      percentBasis: p['percent_basis'] == 'due' ? 'due' : 'paid',
      absenceDeduct: p['absence_deduct'] != false,
      advanceInstallment: math.max(0.0, _num(p['advance_installment'])),
    );
  }
}

/// آخر سجل أجر بدأ قبل الشهر، وإلا الشروط الحالية — `termsFor`.
PayTerms termsFor(Teacher t, String month) {
  final history = [
    for (final h in t.salaryHistory)
      if (h['from'] is String && h.containsKey('payment_rate')) h,
  ];
  final applied = history.where((h) => (h['from'] as String).compareTo(month) <= 0).toList()
    ..sort((a, b) => (b['from'] as String).compareTo(a['from'] as String));
  final later = history.any((h) => (h['from'] as String).compareTo(month) > 0);
  if (applied.isNotEmpty && later) {
    final h = applied.first;
    return PayTerms.of(contractType: h['contract_type']?.toString(), paymentRate: h['payment_rate'], weeklyPeriods: h['weekly_periods'], payProfile: h['pay_profile']);
  }
  return PayTerms.of(contractType: t.contractType, paymentRate: t.rate, weeklyPeriods: t.weeklyPeriods, payProfile: t.payProfile);
}

/// أيام دوام الشهر: بلا العطلة الأسبوعية ولا العطل (`calendar` بنوع `holiday`).
List<String> payrollWorkDays(String month, List<int> weekend, List<Map<String, dynamic>> calendar) {
  final y = int.parse(month.substring(0, 4));
  final m = int.parse(month.substring(5, 7));
  final last = DateTime(y, m + 1, 0).day;
  final out = <String>[];
  for (var d = 1; d <= last; d++) {
    final date = '$month-${d.toString().padLeft(2, '0')}';
    final jsDay = DateTime(y, m, d).weekday % 7; // Dart: الاثنين 1 … الأحد 7
    final holiday = calendar.any((e) => e['kind'] == 'holiday' && '${e['from']}'.compareTo(date) <= 0 && date.compareTo('${e['to'] ?? e['from']}') <= 0);
    if (weekend.contains(jsDay) || holiday) continue;
    out.add(date);
  }
  return out;
}

/// أقساط الدراسة وحدها: لا الرسوم الإضافية ولا الخاصة بطالب ولا رسم الحجز.
bool isTuitionInstallmentId(String id) => !id.startsWith('extra_') && !id.startsWith('fee_') && !id.startsWith('plan_seat_');

class PercentRoom {
  const PercentRoom({
    required this.label,
    required this.fees,
    required this.teacherPeriods,
    required this.totalPeriods,
    required this.share,
    required this.missing,
    required this.amount,
  });

  final String label;

  /// رسوم الشعبة في الشهر بأساس المعلم
  final double fees;
  final double teacherPeriods;
  final double totalPeriods;

  /// نصيب مواده من رسوم الشعبة (0..1): حصصها ÷ حصص كل مواد الشعبة، أو عددها ÷ عدد المواد إن نقصت حصص
  final double share;

  /// مواد الشعبة بلا حصص، بأسمائها: النصيب حينها بعدد المواد
  final List<String> missing;
  final double amount;
}

/// نصيب معلم «النسبة» من رسوم كل شعبة يدرّسها في الشهر — `percentRooms`.
///
/// النسبة من حصة مواده من الرسوم لا من الرسوم كلها: حصة المادة = حصصها الأسبوعية ÷ حصص كل
/// مواد الشعبة (أياً كان أجر معلميها). إن نقصت حصص مادة: بالتساوي بين موادها. معلم الصف
/// الذي يدرّس كل موادها يأخذ رسومها كاملة. «من المقبوض»: كل دفعة في شهر قسطها، أو في شهر
/// قبضها إن قُبضت متأخرة، فمن دفع السنة مقدماً لا تُعطى نسبتها كلها في شهر واحد.
List<PercentRoom> percentRooms({
  required Set<String> teacherIds,
  required List<Group> groups,
  required List<Classroom> rooms,
  required List<Student> students,
  required List<Installment> installments,
  required List<Payment> payments,
  required String month,
  required double percent,
  String basis = 'paid',
  Map<String, String> subjectNames = const {},
}) {
  final active = groups.where((g) => g.status != 'archived').toList();
  final mineByRoom = <String, List<Group>>{};
  for (final g in active) {
    if (!teacherIds.contains(g.teacherId)) continue;
    for (final r in g.roomIds) {
      (mineByRoom[r] ??= []).add(g);
    }
  }
  final instOf = <String, List<Installment>>{};
  for (final i in installments) {
    (instOf[i.studentId] ??= []).add(i);
  }
  final payOf = <String, List<Payment>>{};
  for (final p in payments) {
    if (p.studentId.isNotEmpty) (payOf[p.studentId] ??= []).add(p);
  }
  String subjectOf(Group g) => g.subjectId.isNotEmpty ? g.subjectId : g.id;
  final out = <PercentRoom>[];
  mineByRoom.forEach((roomId, mine) {
    final room = rooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null) return;
    // كل مواد الشعبة بمعلميها كلهم: حصة مواده منها
    final all = active.where((g) => g.roomIds.contains(roomId)).toList();
    final teacherPeriods = mine.fold<double>(0, (n, g) => n + (g.weeklyPeriods ?? 0));
    final totalPeriods = all.fold<double>(0, (n, g) => n + (g.weeklyPeriods ?? 0));
    final unknown = all.where((g) => !((g.weeklyPeriods ?? 0) > 0)).toList();
    final share = unknown.isEmpty && totalPeriods > 0
        ? teacherPeriods / totalPeriods
        : {for (final g in mine) subjectOf(g)}.length / math.max(1, {for (final g in all) subjectOf(g)}.length);
    final missing = {for (final g in unknown) subjectNames[g.subjectId] ?? 'مادة'}.toList();

    var fees = 0.0;
    for (final s in students) {
      if (s.status == 'archived' || !studentBelongsToRoom(s, room)) continue;
      final own = (instOf[s.id] ?? const <Installment>[]).where((i) => isTuitionInstallmentId(i.id)).toList();
      if (basis == 'due') {
        for (final i in own) {
          if (isoDate(i.dueDate).startsWith(month)) fees += chargeableAmount(i);
        }
      } else {
        final list = payOf[s.id] ?? const <Payment>[];
        final byId = {for (final p in list) p.id: p};
        final dueMonth = {for (final i in own) i.id: isoDate(i.dueDate).substring(0, 7)};
        for (final slice in allocatePaymentSlices(list, instOf[s.id] ?? const <Installment>[])) {
          if (slice.isDiscount || slice.installmentId == null || !dueMonth.containsKey(slice.installmentId)) continue;
          final p = byId[slice.paymentId];
          final paidMonth = p == null ? '' : isoDate(p.date).substring(0, 7);
          final due = dueMonth[slice.installmentId]!.isEmpty ? paidMonth : dueMonth[slice.installmentId]!;
          if ((paidMonth.compareTo(due) > 0 ? paidMonth : due) == month) fees += slice.amount;
        }
      }
    }
    // ردّ يزيد على مقبوض الشهر لا يجعل الرسوم سالبة فيُنقص الأجر
    fees = math.max(0.0, _r2(fees));
    out.add(PercentRoom(
      label: [room.gradeLevel, room.name].where((x) => x.trim().isNotEmpty).join(' - '),
      fees: fees,
      teacherPeriods: teacherPeriods,
      totalPeriods: totalPeriods,
      share: share,
      missing: missing,
      amount: _r2(fees * share * percent / 100),
    ));
  });
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}

String payoutMonthOf(TeacherPayout p) => (p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate).padRight(7).substring(0, 7);

/// الشهر مُسوّى: بسنده، أو بلا سند حين أكلت السلفة الراتب كله (المصروف صفر).
bool _settled(PayrollEntryRow e, Set<String> payoutIds) =>
    e.payoutId.isNotEmpty ? payoutIds.contains(e.payoutId) : e.hasSnapshot && (e.paid ?? -1) == 0;

/// رصيد سلف الموظف قبل حساب الشهر — `advanceBalance`.
///
/// كل السلف حتى الشهر، ناقص ما اقتُطع في رواتب مصروفة لغيره (ومنها الشهر المسوّى بلا سند).
/// شهر صُرف راتبه قبل الحساب المفصّل (بلا سطر) تُعدّ سلفه مقتطعة فيه.
double advanceBalance(List<TeacherPayout> payouts, List<PayrollEntryRow> entries, String month) {
  final ids = {for (final p in payouts) p.id};
  final paid = entries.where((e) => e.month != month && _settled(e, ids)).toList();
  final settled = {for (final e in paid) e.month};
  var balance = 0.0;
  for (final p in payouts) {
    if (p.payoutType == 'advance' && payoutMonthOf(p).compareTo(month) <= 0) balance += p.amount;
  }
  for (final e in paid) {
    balance -= e.advanceRecovered ?? 0;
  }
  final legacy = {
    for (final p in payouts)
      if ((p.payoutType.isEmpty || p.payoutType == 'salary') && !settled.contains(payoutMonthOf(p)) && payoutMonthOf(p) != month) payoutMonthOf(p),
  };
  for (final p in payouts) {
    if (p.payoutType == 'advance' && legacy.contains(payoutMonthOf(p))) balance -= p.amount;
  }
  return math.max(0.0, _r2(balance));
}

/// صُرف راتب الشهر من قبل — `PayrollService.alreadyPaid`: بسطر مسوّى (بسنده أو بلا سند
/// حين أكلت السلفة الراتب)، أو بسند راتب لشهره. يمنع سنداً ثانياً (نقرتان، شاشة قديمة).
bool alreadyPaid(List<TeacherPayout> payouts, List<PayrollEntryRow> entries, String month) {
  final ids = {for (final p in payouts) p.id};
  if (entries.any((e) => e.month == month && _settled(e, ids))) return true;
  return payouts.any((p) => (p.payoutType.isEmpty || p.payoutType == 'salary') && payoutMonthOf(p) == month);
}

class PayrollCalc {
  PayrollCalc({
    required this.terms,
    required this.workDays,
    required this.absent,
    required this.late,
    required this.sessions,
    required this.dayValue,
    required this.gross,
    required this.net,
    required this.payable,
    required this.advance,
    required this.lines,
    required this.warnings,
  });

  final PayTerms terms;
  final int workDays;
  final int absent;
  final int late;
  final double? sessions;

  /// أجر اليوم: الراتب ÷ أيام دوام الشهر، وحصص يوم النصاب
  final double dayValue;
  final double gross;

  /// المقترح: المستحق والإضافات ناقص الغياب والخصومات والسلفة، بلا تقريب
  final double net;
  final double payable;
  final double advance;
  final List<({String label, double amount})> lines;
  final List<String> warnings;

  /// السلفة أكلت الراتب كله: يُسوّى الشهر بلا سند (لا نقد يخرج)، ويُقتطع من رصيدها.
  bool get settlesWithoutPayout => payable <= 0 && advance > 0;

  /// ما يُحفظ مع السند — `snapshotOf`.
  Map<String, dynamic> snapshot(double paid) => {
        'contract_type': [if (terms.fixed > 0) 'ثابت', if (terms.sessionRate > 0) 'حصص', if (terms.percent > 0) 'نسبة'].join(' + '),
        'lines': [for (final l in lines) {'label': l.label, 'amount': l.amount}],
        'gross': gross,
        'net': net,
        'paid': paid,
        'work_days': workDays,
        'absent': absent,
        'late': late,
        'sessions': sessions == null ? null : (sessions! * 10).roundToDouble() / 10,
      };
}

String _count(double n) {
  final v = (n * 10).roundToDouble() / 10;
  return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
}

/// الحساب نفسه في `computePayroll`.
PayrollCalc computePayroll({
  required Teacher teacher,
  required String month,
  required PayrollSettings settings,
  required List<Map<String, dynamic>> calendar,
  required List<StaffDay> attendance,
  required List<LeaveRequest> leaves,
  PayrollEntryRow? entry,
  List<PercentRoom> percentRooms = const [],
  double advanceBalance = 0,
}) {
  final terms = termsFor(teacher, month);
  final hasFixed = terms.fixed > 0;
  final hasSessions = terms.sessionRate > 0;
  final hasPercent = terms.percent > 0;
  final sessionRate = terms.sessionRate;
  final fixedRate = terms.fixed;
  final weekDays = 7 - settings.weekend.length;
  final perDay = weekDays > 0 ? terms.weeklyPeriods / weekDays : 0.0;

  final days = payrollWorkDays(month, settings.weekend, calendar);
  final cs = teacher.contractStart;
  final start = cs.length >= 7 && cs.substring(0, 7) == month ? cs : '';
  final notYet = cs.length >= 7 && cs.substring(0, 7).compareTo(month) > 0;
  final employed = notYet ? <String>[] : [for (final d in days) if (start.isEmpty || d.compareTo(start) >= 0) d];
  final warnings = <String>[];
  final lines = <({String label, double amount})>[];

  final dayOf = {for (final a in attendance) if (a.teacherId == teacher.id) a.date: a};
  var absent = 0, late = 0, unpaidLeave = 0, unmarked = 0;
  var daily = 0.0;
  for (final date in employed) {
    final leave = approvedLeaveOn(leaves, teacher.id, date);
    if (leave != null) {
      if (leave.paid != true) unpaidLeave++;
      continue;
    }
    final day = dayOf[date];
    if (day?.status == 'absent') absent++;
    if (day?.status == 'late') late++;
    if (day != null && day.status != 'absent') {
      if (day.periods == null) {
        unmarked++;
      } else {
        daily += day.periods!;
      }
    }
  }

  // يوم الغياب = أجر يوم من أيام دوام الشهر الفعلية
  final dayBasis = math.max(1, days.length).toDouble();
  final fixed = hasFixed && days.isNotEmpty ? _r2(fixedRate * employed.length / days.length) : 0.0;
  if (hasFixed) {
    lines.add((label: employed.length < days.length ? 'الراتب الثابت (${employed.length} من ${days.length} يوماً)' : 'الراتب الثابت', amount: fixed));
  }

  double? sessions;
  var from = '';
  if (hasSessions) {
    if (entry?.sessions != null) {
      sessions = entry!.sessions;
      from = 'entry';
    } else if (settings.sessionsSource == 'daily') {
      sessions = daily;
      from = 'daily';
      if (unmarked > 0) warnings.add('أيام بلا عدد حصص: $unmarked');
    } else if (settings.sessionsSource == 'monthly') {
      sessions = math.max(0.0, perDay * (employed.length - absent - unpaidLeave));
      from = 'monthly';
      warnings.add('عدد الحصص تقديري');
    } else {
      sessions = perDay * employed.length;
      from = 'load';
    }
    if (terms.weeklyPeriods <= 0 && (from == 'load' || from == 'monthly')) warnings.add('النصاب غير محدد');
  }
  final sessionsPay = sessions == null ? 0.0 : _r2(sessions * sessionRate);
  if (hasSessions) lines.add((label: 'الحصص: ${_count(sessions ?? 0)} × ${_count(sessionRate)}', amount: sessionsPay));

  final rooms = hasPercent ? percentRooms : const <PercentRoom>[];
  final percentPay = _r2(rooms.fold<double>(0, (n, r) => n + r.amount));
  if (hasPercent) {
    lines.add((label: 'نسبة ${_count(terms.percent)}% من الرسوم', amount: percentPay));
    for (final r in rooms) {
      if (r.missing.isNotEmpty) warnings.add('${r.label}: حصص ${r.missing.join('، ')} غير مسجّلة، فالنصيب بعدد المواد');
    }
    if (rooms.isEmpty) warnings.add('لا شعب مسندة');
  }

  final allowances = _r2(terms.allowances.fold<double>(0, (n, a) => n + a.amount));
  for (final a in terms.allowances) {
    lines.add((label: a.name, amount: a.amount));
  }

  var additions = 0.0, manual = 0.0;
  for (final a in entry?.adjustments ?? const <({String label, double amount})>[]) {
    final v = _r2(a.amount);
    if (v == 0) continue;
    lines.add((label: a.label.isEmpty ? (v > 0 ? 'إضافة' : 'خصم') : a.label, amount: v));
    if (v > 0) {
      additions += v;
    } else {
      manual -= v;
    }
  }

  // الخصم: الثابت وحصص النصاب وحدهما، فالحصص المكتوبة أو المرصودة عُدّت بعد الغياب
  final byDay = hasSessions && from == 'load';
  final dayValue = _r2((hasFixed ? fixedRate / dayBasis : 0) + (byDay ? perDay * sessionRate : 0));
  var room = fixed + (byDay ? sessionsPay : 0);
  double deduct(String label, double n) {
    if (n == 0 || dayValue == 0 || room <= 0) return 0;
    final v = _r2(math.min(room, n * dayValue));
    room -= v;
    lines.add((label: label, amount: -v));
    return v;
  }

  // الغياب كما في الدوام إلا إن عدّله المدير، ولا يُخصم لمن لا يُخصم غيابه أو إن أُطفئ في المدرسة
  final absentCounted = entry?.absentDays != null ? math.max(0.0, entry!.absentDays!).round() : absent;
  final absentDays = settings.absenceDeduct && terms.absenceDeduct ? absentCounted : 0;
  final lateDays = (late * settings.lateFraction * 100).roundToDouble() / 100;
  var attendanceCut = deduct('غياب $absentDays يوم', absentDays.toDouble()) +
      deduct('إجازة بلا راتب $unpaidLeave يوم', unpaidLeave.toDouble()) +
      deduct('تأخير $late', lateDays);
  attendanceCut = _r2(attendanceCut);
  final deductions = _r2(attendanceCut + manual);

  final gross = _r2(fixed + sessionsPay + percentPay + allowances + additions);
  final balance = math.max(0.0, advanceBalance);
  final before = math.max(0.0, gross - deductions);
  // المقترح: قسط السلفة الشهري إن حُدد، وإلا الرصيد كله
  final suggested = terms.advanceInstallment > 0 ? math.min(balance, terms.advanceInstallment) : balance;
  final advance = _r2(math.min(before, math.max(0.0, entry?.advanceRecovered ?? suggested)));
  if (advance > 0) lines.add((label: 'سلفة', amount: -advance));

  // الصافي كما هو بلا تقريب: ما يُصرف يُكتب ويُعدَّل في مكانه
  final net = math.max(0.0, _r2(before - advance));
  final payable = entry?.netOverride != null ? math.max(0.0, entry!.netOverride!) : net;
  return PayrollCalc(
    terms: terms,
    workDays: days.length,
    absent: absentCounted,
    late: late,
    sessions: sessions,
    dayValue: dayValue,
    gross: gross,
    net: net,
    payable: payable,
    advance: advance,
    lines: lines,
    warnings: warnings,
  );
}
