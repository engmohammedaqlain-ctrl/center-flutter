import 'package:flutter_test/flutter_test.dart';
import 'package:center_mobile/data/payroll_calc.dart';
import 'package:center_mobile/data/staff.dart';
import 'package:center_mobile/models/models.dart';

// نفس قواعد features/finance/payrollCalc.ts في الويب: الحساب واحد في الطرفين.
// نوفمبر 2026: 26 يوم دوام بلا الجمعة، و22 بلا الجمعة والسبت.
const month = '2026-11';

Teacher teacher(String type, double rate, {double? weekly, Map<String, dynamic>? profile, String start = '', String id = 't'}) => Teacher(
      id: id,
      name: 'م',
      phone: '',
      subject: '',
      rate: rate,
      contractType: type,
      weeklyPeriods: weekly,
      payProfile: profile,
      contractStart: start,
    );

StaffDay day(String date, String status, [double? periods]) => StaffDay(teacherId: 't', date: date, status: status, periods: periods);

PayrollCalc calc(Teacher t, {List<StaffDay> days = const [], PayrollSettings settings = const PayrollSettings(), PayrollEntryRow? entry, double advance = 0}) =>
    computePayroll(teacher: t, month: month, settings: settings, calendar: const [], attendance: days, leaves: const [], entry: entry, advanceBalance: advance);

// ── شعبة السابع (أ) بموادها ─────────────────────────────────────────────────

final room = Classroom(id: 'r7a', name: 'أ', gradeLevel: 'السابع', teacherId: '');

Group group(String id, String teacher, String subject, double? periods) =>
    Group(id: id, name: id, subjectId: subject, teacherId: teacher, roomIds: ['r7a'], weeklyPeriods: periods);

Student student(String id) => Student(
      id: id,
      fullName: id,
      gradeLevel: 'السابع',
      section: 'أ',
      phone: '',
      parentName: '',
      parentPhone: '',
      balance: 0,
    );

Installment inst(String id, String student, double amount, String due) =>
    Installment(id: id, studentId: student, title: id, amount: amount, dueDate: DateTime.parse(due));

Payment pay(String id, String student, double amount, String date, {String? installmentId, String created = ''}) => Payment(
      id: id,
      receiptNumber: id,
      studentId: student,
      amount: amount,
      method: 'cash',
      date: DateTime.parse(date),
      installmentId: installmentId,
      createdAt: created.isEmpty ? date : created,
    );

TeacherPayout payout(String id, String type, double amount, String m) =>
    TeacherPayout(id: id, teacherId: 't', amount: amount, paymentDate: '$m-28', payoutType: type, periodStart: '$m-01');

void main() {
  test('يوم الغياب = الراتب ÷ أيام دوام الشهر الفعلية', () {
    // 26 يوم دوام بلا الجمعة: 2600 ÷ 26 = 100
    final r = calc(teacher('fixed', 2600), days: [day('2026-11-02', 'absent')]);
    expect([r.workDays, r.dayValue, r.net], [26, 100, 2500]);
    // 22 يوم دوام بلا الجمعة والسبت: 2200 ÷ 22 = 100، لا ÷ 26 ولا ÷ 30
    final w = calc(teacher('fixed', 2200), days: [day('2026-11-02', 'absent')], settings: const PayrollSettings(weekend: [5, 6]));
    expect([w.workDays, w.dayValue, w.net], [22, 100, 2100]);
  });

  test('الصافي بلا تقريب', () {
    final r = calc(
      teacher('fixed', 2603, profile: {
        'allowances': [
          {'name': 'مواصلات', 'amount': 100.5},
        ],
      }),
      entry: const PayrollEntryRow(id: 'e', teacherId: 't', month: month, adjustments: [(label: 'مكافأة', amount: 50), (label: 'كسر', amount: -20.25)]),
    );
    expect([r.gross, r.net, r.payable], [2753.5, 2733.25, 2733.25]);
  });

  test('نسبة المعلم من نصيب مواده بحصصها، وبعدد المواد إن نقصت حصص', () {
    // الرياضيات 6 حصص من 30 في الشعبة: نصيبها خمس الرسوم، والنسبة 50% منه
    final groups = [group('math', 't', 'm', 6), group('ar', 'x', 'a', 8), group('sci', 'y', 's', 16)];
    final rooms = percentRooms(
      teacherIds: {'t'},
      groups: groups,
      rooms: [room],
      students: [student('s1')],
      installments: [inst('i1', 's1', 1000, '2026-11-05')],
      payments: const [],
      month: month,
      percent: 50,
      basis: 'due',
    );
    expect([rooms.single.share, rooms.single.fees, rooms.single.amount], [0.2, 1000, 100]);

    // حصص مادة ناقصة: بالتساوي بين المواد الثلاث، وتنبيه باسمها
    final missing = percentRooms(
      teacherIds: {'t'},
      groups: [group('math', 't', 'm', 6), group('ar', 'x', 'a', null), group('sci', 'y', 's', 16)],
      rooms: [room],
      students: [student('s1')],
      installments: [inst('i1', 's1', 900, '2026-11-05')],
      payments: const [],
      month: month,
      percent: 100,
      basis: 'due',
      subjectNames: {'a': 'العربية'},
    );
    expect([missing.single.amount, missing.single.missing], [300, ['العربية']]);

    // معلم الصف الذي يدرّس كل موادها يأخذ رسومها كاملة
    final all = percentRooms(
      teacherIds: {'t'},
      groups: [group('math', 't', 'm', 6), group('ar', 't', 'a', 8)],
      rooms: [room],
      students: [student('s1')],
      installments: [inst('i1', 's1', 1000, '2026-11-05')],
      payments: const [],
      month: month,
      percent: 10,
      basis: 'due',
    );
    expect(all.single.amount, 100);

    final r = computePayroll(
      teacher: teacher('percent', 0, profile: {'percent': 50}),
      month: month,
      settings: const PayrollSettings(),
      calendar: const [],
      attendance: const [],
      leaves: const [],
      percentRooms: rooms,
    );
    expect(r.net, 100);
  });

  test('الدفعة المقبوضة تُحسب في شهر قسطها، والمتأخرة في شهر قبضها', () {
    // دفع في سبتمبر أقساط سبتمبر ونوفمبر مقدماً، وقسط أكتوبر دفعه متأخراً في نوفمبر
    final installments = [
      inst('sep', 's1', 100, '2026-09-05'),
      inst('oct', 's1', 100, '2026-10-05'),
      inst('nov', 's1', 100, '2026-11-05'),
    ];
    final payments = [
      pay('p1', 's1', 100, '2026-09-01', installmentId: 'sep', created: '2026-09-01T08:00'),
      pay('p2', 's1', 100, '2026-09-01', installmentId: 'nov', created: '2026-09-01T09:00'),
      pay('p3', 's1', 100, '2026-11-10', installmentId: 'oct', created: '2026-11-10T08:00'),
    ];
    double feesIn(String m) => percentRooms(
          teacherIds: {'t'},
          groups: [group('math', 't', 'm', 6)],
          rooms: [room],
          students: [student('s1')],
          installments: installments,
          payments: payments,
          month: m,
          percent: 100,
        ).single.fees;
    // سبتمبر قسطه وحده لا مقدَّم نوفمبر، وأكتوبر لا شيء، ونوفمبر قسطه والمتأخر من أكتوبر
    expect([feesIn('2026-09'), feesIn('2026-10'), feesIn('2026-11')], [100, 0, 200]);
  });

  test('الشهر اللي أكلت السلفة راتبه يتسكّر بلا سند، ويُقتطع من رصيدها', () {
    final r = calc(teacher('fixed', 1000), advance: 1500);
    expect([r.net, r.advance, r.settlesWithoutPayout], [0, 1000, true]);
    expect(calc(teacher('fixed', 1000), advance: 300).settlesWithoutPayout, false);

    // سُوّي أكتوبر بلا سند واقتُطع منه 1000: يبقى 500 لنوفمبر، لا 1500 مرة أخرى
    final payouts = [payout('a1', 'advance', 1500, '2026-10')];
    const settled = PayrollEntryRow(id: 'pe', teacherId: 't', month: '2026-10', hasSnapshot: true, paid: 0, advanceRecovered: 1000);
    expect(advanceBalance(payouts, [settled], month), 500);
    // وبلا تسوية تبقى السلفة كاملة
    expect(advanceBalance(payouts, const [], month), 1500);
  });

  test('ما في صرف مرتين لنفس الشهر', () {
    // سند راتب للشهر
    expect(alreadyPaid([payout('s', 'salary', 2000, month)], const [], month), true);
    // شهر سُوّي بلا سند حين أكلت السلفة راتبه
    const settled = PayrollEntryRow(id: 'pe', teacherId: 't', month: month, hasSnapshot: true, paid: 0, advanceRecovered: 900);
    expect(alreadyPaid(const [], [settled], month), true);
    // سطر محسوب لم يُصرف بعد، والسلفة والمكافأة لا تمنعان صرف الراتب
    const open = PayrollEntryRow(id: 'pe', teacherId: 't', month: month, sessions: 10);
    expect(alreadyPaid([payout('a', 'advance', 300, month), payout('b', 'bonus', 100, month)], [open], month), false);
    // راتب الشهر الماضي لا يمنع هذا الشهر
    expect(alreadyPaid([payout('s', 'salary', 2000, '2026-10')], const [], month), false);
  });

  test('بداية العقد وسط الشهر', () {
    expect(calc(teacher('fixed', 2600, start: '2026-11-16')).net, 1300);
  });

  test('التأخير كسر من أجر اليوم', () {
    final lates = [for (final d in ['02', '03', '04', '05']) day('2026-11-$d', 'late')];
    // 4 تأخيرات × ربع يوم = يوم
    expect(calc(teacher('fixed', 2600), days: lates, settings: const PayrollSettings(lateFraction: 0.25)).net, 2500);
    expect(calc(teacher('fixed', 2600), days: lates).net, 2600);
  });

  test('بالحصة من النصاب، والمرصودة يومياً', () {
    expect(calc(teacher('sessions', 20, weekly: 18), days: [day('2026-11-02', 'absent')]).net, 1500);
    final r = calc(teacher('sessions', 20, weekly: 18),
        days: [day('2026-11-02', 'present', 4), day('2026-11-03', 'late', 3), day('2026-11-04', 'present')],
        settings: const PayrollSettings(sessionsSource: 'daily'));
    expect([r.sessions, r.net, r.warnings], [7, 140, ['أيام بلا عدد حصص: 1']]);
  });

  test('ثابت وحصص', () {
    final r = calc(teacher('mixed', 1300, weekly: 6, profile: {'session_rate': 10}), days: [day('2026-11-02', 'absent')]);
    expect(r.net, 1500);
  });

  test('غياب عدّله المدير، وموظف لا يُخصم غيابه', () {
    final days = [day('2026-11-02', 'absent'), day('2026-11-03', 'absent')];
    const entry = PayrollEntryRow(id: 'e', teacherId: 't', month: month, absentDays: 1);
    expect(calc(teacher('fixed', 2600), days: days, entry: entry).net, 2500);
    expect(calc(teacher('fixed', 2600, profile: {'absence_deduct': false}), days: days).net, 2600);
  });

  test('قسط السلفة الشهري', () {
    final r = calc(teacher('fixed', 2000, profile: {'advance_installment': 300}), advance: 1000);
    expect([r.advance, r.net], [300, 1700]);
  });
}
