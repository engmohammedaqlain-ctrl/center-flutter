/// الراتب المقترح لشهر — المقابل لـ `features/finance/payrollCalc.ts`.
///
/// رقم يُعرض ويُعدَّل قبل الصرف، لا مطالبة. ثابت، أو بالحصة، أو نسبة من رسوم شعبه، أو ثابت
/// وحصص؛ ثم البدلات وبنود الشهر، وخصم الغياب والإجازة غير المدفوعة والتأخير، ومقتطع السلفة.
/// القواعد في إعدادات المدرسة (`settings.payroll`)، والافتراضي يطابق الحساب السابق.
library;

import 'dart:math' as math;

import '../models/models.dart';
import 'academic_matching.dart';
import 'balance.dart';
import 'profit_report.dart';
import 'staff.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double _r2(double n) => (n * 100).roundToDouble() / 100;

/// قواعد الحساب — `PayrollSettings`.
class PayrollSettings {
  const PayrollSettings({
    this.weekend = const [5],
    this.dayBasis = '26',
    this.absenceDeduct = true,
    this.latePerDay = 0,
    this.sessionsSource = 'load',
    this.percentBasis = 'paid',
    this.percentSplit = 'periods',
    this.rounding = 1,
  });

  /// أيام العطلة بترقيم JavaScript (الأحد 0 … السبت 6)
  final List<int> weekend;

  /// `26` أو `30` أو `work_days`
  final String dayBasis;
  final bool absenceDeduct;
  final int latePerDay;

  /// `load` أو `monthly` أو `daily`
  final String sessionsSource;

  /// `paid` أو `due`
  final String percentBasis;

  /// `periods` أو `full`
  final String percentSplit;
  final int rounding;

  factory PayrollSettings.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final w = m['weekend'];
    final weekend = w is List ? {for (final d in w) int.tryParse('$d')}.whereType<int>().where((d) => d >= 0 && d <= 6).toList() : <int>[5];
    final basis = '${m['day_basis'] ?? ''}';
    final rounding = int.tryParse('${m['rounding'] ?? ''}') ?? 1;
    return PayrollSettings(
      weekend: weekend.length < 7 ? weekend : const [5],
      dayBasis: basis == '30' || basis == 'work_days' ? basis : '26',
      absenceDeduct: m['absence_deduct'] != false,
      latePerDay: math.max(0, int.tryParse('${m['late_per_day'] ?? ''}') ?? 0),
      sessionsSource: m['sessions_source'] == 'monthly' || m['sessions_source'] == 'daily' ? '${m['sessions_source']}' : 'load',
      percentBasis: m['percent_basis'] == 'due' ? 'due' : 'paid',
      percentSplit: m['percent_split'] == 'full' ? 'full' : 'periods',
      rounding: rounding == 5 || rounding == 10 ? rounding : 1,
    );
  }
}

/// شروط الأجر السارية في شهر — `PayTerms`.
/// شروط الأجر بخاناتها الثلاث (ثابت، أجر حصة، نسبة): أي خليط جائز، والفارغ صفر لا يُحسب.
class PayTerms {
  const PayTerms({
    required this.contractType,
    required this.fixed,
    required this.sessionRate,
    required this.percent,
    required this.weeklyPeriods,
    required this.allowances,
  });

  /// مشتق من الخانات: `fixed` أو `sessions` أو `percent` أو `mixed`، وفارغ بلا أجر
  final String contractType;
  final double fixed;
  final double sessionRate;
  final double percent;
  final double weeklyPeriods;
  final List<({String name, double amount})> allowances;

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
  const PercentRoom({required this.label, required this.fees, required this.share, required this.amount});
  final String label;
  final double fees;
  final double? share;
  final double amount;
}

/// نصيب معلم «النسبة» من رسوم كل شعبة يدرّسها في الشهر — `percentRooms`.
List<PercentRoom> percentRooms({
  required Set<String> teacherIds,
  required List<Group> groups,
  required List<Classroom> rooms,
  required List<Student> students,
  required List<Installment> installments,
  required List<Payment> payments,
  required String month,
  required double percent,
  required PayrollSettings settings,
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
  final out = <PercentRoom>[];
  mineByRoom.forEach((roomId, mine) {
    final room = rooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null) return;
    final all = active.where((g) => g.roomIds.contains(roomId)).toList();
    final teacherPeriods = mine.fold<double>(0, (n, g) => n + (g.weeklyPeriods ?? 0));
    final totalPeriods = all.fold<double>(0, (n, g) => n + (g.weeklyPeriods ?? 0));
    final double? share = settings.percentSplit == 'full'
        ? 1.0
        : all.any((g) => (g.weeklyPeriods ?? 0) <= 0) || totalPeriods <= 0
            ? null
            : teacherPeriods / totalPeriods;
    var fees = 0.0;
    for (final s in students) {
      if (s.status == 'archived' || !studentBelongsToRoom(s, room)) continue;
      final own = (instOf[s.id] ?? const <Installment>[]).where((i) => isTuitionInstallmentId(i.id)).toList();
      if (settings.percentBasis == 'due') {
        for (final i in own) {
          if (isoDate(i.dueDate).startsWith(month)) fees += chargeableAmount(i);
        }
      } else {
        final list = payOf[s.id] ?? const <Payment>[];
        final byId = {for (final p in list) p.id: p};
        final tuition = {for (final i in own) i.id};
        for (final slice in allocatePaymentSlices(list, instOf[s.id] ?? const <Installment>[])) {
          if (slice.isDiscount || slice.installmentId == null || !tuition.contains(slice.installmentId)) continue;
          final p = byId[slice.paymentId];
          if (p != null && isoDate(p.date).startsWith(month)) fees += slice.amount;
        }
      }
    }
    fees = _r2(fees);
    out.add(PercentRoom(
      label: [room.gradeLevel, room.name].where((x) => x.trim().isNotEmpty).join(' - '),
      fees: fees,
      share: share,
      amount: share == null ? 0 : _r2(fees * share * percent / 100),
    ));
  });
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}

String payoutMonthOf(TeacherPayout p) => (p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate).padRight(7).substring(0, 7);

/// رصيد سلف الموظف قبل حساب الشهر — `advanceBalance`.
double advanceBalance(List<TeacherPayout> payouts, List<PayrollEntryRow> entries, String month) {
  final ids = {for (final p in payouts) p.id};
  final paid = entries.where((e) => e.month != month && e.payoutId.isNotEmpty && ids.contains(e.payoutId)).toList();
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

class PayrollCalc {
  PayrollCalc({
    required this.terms,
    required this.workDays,
    required this.absent,
    required this.late,
    required this.sessions,
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
  final double gross;
  final double net;
  final double payable;
  final double advance;
  final List<({String label, double amount})> lines;
  final List<String> warnings;

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

  final dayBasis = settings.dayBasis == 'work_days' ? math.max(1, days.length).toDouble() : double.parse(settings.dayBasis);
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
    if (rooms.any((r) => r.share == null)) warnings.add('حصص مادة ناقصة في شعبة');
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

  final byDay = hasSessions && from == 'load';
  final dayValue = _r2((hasFixed ? fixedRate / dayBasis : 0) + (byDay ? perDay * sessionRate : 0));
  var room = fixed + (byDay ? sessionsPay : 0);
  double deduct(String label, int n) {
    if (n == 0 || dayValue == 0 || room <= 0) return 0;
    final v = _r2(math.min(room, n * dayValue));
    room -= v;
    lines.add((label: label, amount: -v));
    return v;
  }

  final absentDays = settings.absenceDeduct ? absent : 0;
  final lateDays = settings.latePerDay > 0 ? late ~/ settings.latePerDay : 0;
  var deductions = deduct('غياب $absentDays يوم', absentDays) + deduct('إجازة بلا راتب $unpaidLeave يوم', unpaidLeave) + deduct('تأخير $late ($lateDays يوم)', lateDays);
  deductions = _r2(deductions + manual);

  final gross = _r2(fixed + sessionsPay + percentPay + allowances + additions);
  final before = math.max(0.0, gross - deductions);
  final wanted = entry?.advanceRecovered ?? math.max(0.0, advanceBalance);
  final advance = _r2(math.min(before, math.max(0.0, wanted)));
  if (advance > 0) lines.add((label: 'سلفة', amount: -advance));

  final net = math.max(0.0, ((before - advance) / settings.rounding).roundToDouble() * settings.rounding);
  final payable = entry?.netOverride != null ? math.max(0.0, entry!.netOverride!) : net;
  return PayrollCalc(
    terms: terms,
    workDays: days.length,
    absent: absent,
    late: late,
    sessions: sessions,
    gross: gross,
    net: net,
    payable: payable,
    advance: advance,
    lines: lines,
    warnings: warnings,
  );
}
