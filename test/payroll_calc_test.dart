import 'package:flutter_test/flutter_test.dart';
import 'package:center_mobile/data/payroll_calc.dart';
import 'package:center_mobile/data/staff.dart';
import 'package:center_mobile/models/models.dart';

// نفس حالات features/finance/__tests__/payrollCalc.test.ts في الويب: الحساب واحد في الطرفين.
// نوفمبر 2026: 26 يوم دوام بلا الجمعة.
const month = '2026-11';

Teacher teacher(String type, double rate, {double? weekly, Map<String, dynamic>? profile, String start = ''}) => Teacher(
      id: 't',
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

void main() {
  test('ثابت: يوم غياب = الراتب ÷ 26، و30 إن اختير', () {
    expect(calc(teacher('fixed', 2600), days: [day('2026-11-02', 'absent')]).net, 2500);
    expect(calc(teacher('fixed', 3000), days: [day('2026-11-02', 'absent')], settings: const PayrollSettings(dayBasis: '30')).net, 2900);
  });

  test('كل 3 تأخيرات = يوم', () {
    final lates = [for (final d in ['02', '03', '04', '05']) day('2026-11-$d', 'late')];
    expect(calc(teacher('fixed', 2600), days: lates, settings: const PayrollSettings(latePerDay: 3)).net, 2500);
  });

  test('بداية العقد وسط الشهر', () {
    expect(calc(teacher('fixed', 2600, start: '2026-11-16')).net, 1300);
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

  test('البدلات والبنود والتقريب، والسلفة لا تزيد على الراتب', () {
    final r = calc(
      teacher('fixed', 2603, profile: {
        'allowances': [
          {'name': 'مواصلات', 'amount': 100},
        ],
      }),
      entry: const PayrollEntryRow(id: 'e', teacherId: 't', month: month, adjustments: [(label: 'مكافأة', amount: 50), (label: 'كسر', amount: -20)]),
      settings: const PayrollSettings(rounding: 10),
    );
    expect([r.gross, r.net], [2753, 2730]);
    expect(calc(teacher('fixed', 1000), advance: 1500).net, 0);
  });
}
