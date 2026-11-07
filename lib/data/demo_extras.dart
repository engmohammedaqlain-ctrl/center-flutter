/// تتمة المدرسة التجريبية الشاملة (محمد): ما ينقص مولّد الويب `buildDemoDataset` — شروط رواتب
/// المعلمين (ثابت وبالحصة ومختلط وبدلات وسجل أجر)، وحصص المواد الأسبوعية، وجدول حصص معتمد،
/// ودوام الموظفين وإجازاتهم وسطور رواتب الشهر. للجوال وحده؛ لا يلمس مولّد الويب ولا قاعدة البيانات.
library;

import 'dart:math' as math;

import 'demo_dataset.dart';
import 'staff.dart';
import 'store.dart';
import 'supabase.dart';
import 'timetable_model.dart';
import 'timetable_service.dart';

/// اسم صاحب هذه البيانات: يُكتب على المعلمين وفي الرسالة، ليعرف من يفتح المدرسة أنها بيانات تجربة محمد.
const demoOwnerTag = 'محمد';

/// عدد حصص المادة في الأسبوع بحسب اسمها.
int _weeklyOf(String subject) {
  if (subject.contains('الرياضيات') || subject.contains('العربية')) return 4;
  if (subject.contains('الإنجليزية') || subject.contains('العلوم') || subject.contains('الفيزياء')) return 3;
  return 2;
}

/// حصص أسبوعية كل مجموعة وجدولها المرتب.
class DemoTimetablePlan {
  const DemoTimetablePlan({required this.entries, required this.weekly, required this.unplaced});

  final List<TimetableEntry> entries;

  /// مجموعة ← حصصها الأسبوعية بعد ضبط حِمل المعلم.
  final Map<String, int> weekly;
  final int unplaced;
}

/// يوزّع حصص المجموعات على أيام الأسبوع: لا معلم في حصتين معاً، ولا شعبة بحصتين معاً،
/// وتتفرق حصص المادة الواحدة على الأيام. حتمي: التوليد مرتين يعطي الجدول نفسه.
DemoTimetablePlan planDemoTimetable({
  required List<Map<String, dynamic>> groups,
  required Map<String, String> subjectNames,
  List<int> days = const [0, 1, 2, 3, 4],
  int periods = 7,
  int teacherMax = 24,
}) {
  final weekly = <String, int>{
    for (final g in groups) '${g['id']}': _weeklyOf(subjectNames['${g['subject_id']}'] ?? ''),
  };
  List<String> roomsOf(Map<String, dynamic> g) => [for (final r in (g['room_ids'] as List? ?? const [])) '$r'];

  // حِمل المعلم: كل مجموعة تُدرَّس في كل شعبها
  int load(String teacher) => groups
      .where((g) => '${g['teacher_id']}' == teacher)
      .fold<int>(0, (n, g) => n + weekly['${g['id']}']! * roomsOf(g).length);
  for (final t in {for (final g in groups) '${g['teacher_id']}'}) {
    while (load(t) > teacherMax) {
      final mine = groups.where((g) => '${g['teacher_id']}' == t && weekly['${g['id']}']! > 1).toList()
        ..sort((a, b) => weekly['${b['id']}']!.compareTo(weekly['${a['id']}']!));
      if (mine.isEmpty) break;
      weekly['${mine.first['id']}'] = weekly['${mine.first['id']}']! - 1;
    }
  }

  final lessons = [
    for (final g in groups)
      for (final r in roomsOf(g)) (group: '${g['id']}', room: r, teacher: '${g['teacher_id']}', count: weekly['${g['id']}']!),
  ]..sort((a, b) {
      final byLoad = load(b.teacher).compareTo(load(a.teacher));
      return byLoad != 0 ? byLoad : b.count.compareTo(a.count);
    });

  final teacherBusy = <String>{};
  final roomBusy = <String>{};
  final entries = <TimetableEntry>[];
  var unplaced = 0;
  for (final l in lessons) {
    final usedDays = <int>{};
    for (var k = 0; k < l.count; k++) {
      ({int day, int period})? best;
      var bestScore = double.infinity;
      for (final d in days) {
        final roomDay = entries.where((e) => e.roomId == l.room && e.day == d).length;
        for (var p = 1; p <= periods; p++) {
          if (teacherBusy.contains('${l.teacher}|$d|$p') || roomBusy.contains('${l.room}|$d|$p')) continue;
          final score = (usedDays.contains(d) ? 100 : 0) + roomDay * 3 + p * 0.5 + d * 0.01;
          if (score < bestScore) {
            bestScore = score;
            best = (day: d, period: p);
          }
        }
      }
      if (best == null) {
        unplaced++;
        continue;
      }
      teacherBusy.add('${l.teacher}|${best.day}|${best.period}');
      roomBusy.add('${l.room}|${best.day}|${best.period}');
      usedDays.add(best.day);
      entries.add(TimetableEntry(l.room, best.day, best.period, l.group));
    }
  }
  return DemoTimetablePlan(entries: entries, weekly: weekly, unplaced: unplaced);
}

String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
String _ymd(DateTime d) => '${_ym(d)}-${d.day.toString().padLeft(2, '0')}';

/// قبل الرفع: أجور المعلمين وحصص المجموعات. يُعدّل صفوف المولّد في مكانها ويعيد جدول الحصص.
DemoTimetablePlan enrichDemoDataset(DemoDataset d, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final twoAgo = _ym(DateTime(today.year, today.month - 2));
  final teachers = d.rows['teachers']!;
  final groups = d.rows['groups']!;
  final subjects = {for (final s in d.rows['subjects']!) '${s['id']}': '${s['name']}'};

  // ترتيب المعلمين كما في المولّد: الزهار، عاشور، منصور، النمس، البنا، الحلو، الكرد
  Map<String, dynamic> terms(String type, double rate, {double? weekly, Map<String, dynamic>? profile}) => {
        'contract_type': type,
        'payment_rate': rate,
        'weekly_periods': weekly,
        'pay_profile': profile,
      };
  final pay = <Map<String, dynamic>>[
    terms('fixed', 3400, profile: {
      'allowances': [
        {'name': 'بدل مواصلات', 'amount': 200},
        {'name': 'بدل طبيعة عمل', 'amount': 150},
      ],
    }),
    terms('fixed', 3200, profile: {
      'allowances': [
        {'name': 'بدل مواصلات', 'amount': 180},
      ],
    }),
    terms('sessions', 55, weekly: 15),
    terms('mixed', 1800, weekly: 16, profile: {'session_rate': 35}),
    terms('fixed', 2900, profile: {'advance_installment': 100}),
    terms('mixed', 1500, profile: {'percent': 5, 'percent_basis': 'paid'}),
    terms('sessions', 45, profile: {'per_lesson': true}),
  ];
  for (var i = 0; i < teachers.length && i < pay.length; i++) {
    final t = teachers[i];
    t.addAll(pay[i]);
    // علاوة الزهار قبل شهرين: يظهر الراتب القديم لما قبلها (سجل الأجر)
    if (i == 0) {
      t['salary_history'] = [
        {'from': '0000-00', ...terms('fixed', 3200)},
        {'from': twoAgo, ...pay[0]},
      ];
    }
    final notes = '${t['notes'] ?? ''}'.trim();
    t['notes'] = '$notes — بيانات تجريبية ($demoOwnerTag)';
  }

  final plan = planDemoTimetable(groups: groups, subjectNames: subjects);
  for (final g in groups) {
    g['weekly_periods'] = plan.weekly['${g['id']}']!.toDouble();
  }
  return plan;
}

/// بعد الرفع: الجدول المعتمد ودوام الموظفين وإجازاتهم وسطور الرواتب، وتفعيل ميزتي الجداول
/// وحساب الأجر بالحصة. يعيد ملخصاً بالأعداد.
Future<({int lessons, int attendanceDays, int leaves, int payrollRows})> seedDemoExtras(
  AppStore store,
  String tenantId,
  DemoDataset d,
  DemoTimetablePlan plan, {
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final stamp = today.toUtc().toIso8601String();
  final teachers = d.rows['teachers']!;

  await store.toggleTenantFeature('timetable', true);
  await store.toggleTenantFeature('payroll.per_lesson', true);

  // الجدول: مسودة معتمدة (ما يراه المعلمون)
  final draft = await TimetableService.saveDraft(tenantId: tenantId, yearId: d.currentAcademicYearId, existing: null, entries: plan.entries);
  await TimetableService.publish(tenantId: tenantId, draft: draft, live: null, actor: store.deviceUser?.name ?? 'الإدارة');

  // دوام الموظفين: آخر أربعة أسابيع من أيام الدراسة (الأحد–الخميس). معلم الحصة يُسجَّل له عدد حصص يومه
  final lessonsOf = <String, Map<int, int>>{};
  final teacherOfGroup = {for (final g in d.rows['groups']!) '${g['id']}': '${g['teacher_id']}'};
  for (final e in plan.entries) {
    final t = teacherOfGroup[e.groupId] ?? '';
    lessonsOf.putIfAbsent(t, () => {})[e.day] = (lessonsOf[t]?[e.day] ?? 0) + 1;
  }
  final rnd = math.Random(2026);
  final attendance = <Map<String, dynamic>>[];
  for (var back = 28; back >= 0; back--) {
    final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: back));
    final wd = jsDay(day);
    if (wd > 4 || day.isAfter(today)) continue;
    for (final t in teachers) {
      final roll = rnd.nextDouble();
      final status = roll < 0.06 ? 'absent' : roll < 0.13 ? 'late' : 'present';
      final bySession = (t['pay_profile'] is Map && ((t['pay_profile'] as Map)['session_rate'] != null || (t['pay_profile'] as Map)['per_lesson'] == true)) ||
          t['contract_type'] == 'sessions';
      final periods = bySession && status != 'absent' ? lessonsOf['${t['id']}']?[wd] : null;
      attendance.add({
        'id': staffAttendanceId('${t['id']}', _ymd(day)),
        'tenant_id': tenantId,
        'teacher_id': t['id'],
        'date': _ymd(day),
        'status': status,
        if (periods != null) 'periods': periods.toDouble(),
        'updated_at': stamp,
      });
    }
  }
  await supabaseUpsert('staff_attendance', attendance);

  // إجازات: معلّقة وموافق عليها بأجر وبلا أجر ومرفوضة
  String ago(int n) => _ymd(today.subtract(Duration(days: n)));
  String ahead(int n) => _ymd(today.add(Duration(days: n)));
  Map<String, dynamic> leave(int i, String from, String to, String reason, String status, {bool? paid}) => {
        'id': 'lv_demo_${teachers[i]['id']}_$from',
        'tenant_id': tenantId,
        'teacher_id': teachers[i]['id'],
        'from_date': from,
        'to_date': to,
        'reason': reason,
        'status': status,
        'paid': paid,
        if (status != 'pending') 'decided_by': 'الإدارة',
        if (status != 'pending') 'decided_at': stamp,
        'created_at': stamp,
        'updated_at': stamp,
      };
  final leaves = [
    leave(6, ahead(3), ahead(4), 'موعد طبي', 'pending'),
    leave(0, ago(12), ago(11), 'ظرف عائلي', 'approved', paid: true),
    leave(2, ago(20), ago(19), 'سفر شخصي', 'approved', paid: false),
    leave(4, ago(8), ago(8), 'طلب إجازة يوم الامتحان', 'rejected'),
  ];
  await supabaseUpsert('leave_requests', leaves);

  // سطور رواتب: شهر مفتوح فيه إضافات وخصومات، والماضي بحصصه
  final month = _ym(today);
  final last = _ym(DateTime(today.year, today.month - 1));
  final List<(int, String, List<Map<String, dynamic>>, double?)> rowsDef = [
      (1, month, [
        {'label': 'مكافأة إشراف على الامتحانات', 'amount': 200.0},
      ], null),
      (3, month, [
        {'label': 'مكافأة نشاط علمي', 'amount': 150.0},
      ], null),
      (4, month, [
        {'label': 'خصم تأخر', 'amount': -60.0},
      ], null),
      (2, last, <Map<String, dynamic>>[], 58.0),
      (6, last, <Map<String, dynamic>>[], 62.0),
  ];
  final payroll = <Map<String, dynamic>>[
    for (final p in rowsDef)
      {
        'id': payrollEntryId('${teachers[p.$1]['id']}', p.$2),
        'tenant_id': tenantId,
        'teacher_id': teachers[p.$1]['id'],
        'month': p.$2,
        'adjustments': p.$3,
        if (p.$4 != null) 'sessions': p.$4,
        'created_at': stamp,
        'updated_at': stamp,
      },
  ];
  await supabaseUpsert('payroll_entries', payroll);

  return (lessons: plan.entries.length, attendanceDays: attendance.length, leaves: leaves.length, payrollRows: payroll.length);
}

/// قبل توليد جديد: ما خلّفه توليد سابق في جداول لا يمسحها المسح الشامل. محاولة بلا إلزام.
Future<void> purgeDemoExtras(String tenantId) async {
  for (final table in const ['timetables', 'timetable_covers', 'staff_attendance', 'leave_requests', 'payroll_entries']) {
    try {
      await supabaseDelete(table, {'tenant_id': 'eq.$tenantId'});
    } catch (_) {}
  }
}
