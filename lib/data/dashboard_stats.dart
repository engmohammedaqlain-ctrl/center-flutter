/// أرقام الرئيسية — المقابل لـ `dashboardStats.ts`: من البيانات المحلية وحدها، دالة صافية
/// تأخذ الجداول وتعيد الأرقام فتُختبر بلا قاعدة.
library;

import '../models/models.dart';
import 'academic_matching.dart';
import 'attendance_days.dart';
import 'balance.dart';
import 'school_calendar.dart';
import 'sliced_work.dart';

class DashCounts {
  int present = 0;
  int absent = 0;
  int excused = 0;

  void add(String status) {
    switch (status) {
      case 'present':
        present++;
      case 'absent':
        absent++;
      case 'excused':
        excused++;
    }
  }

  int get marked => present + absent + excused;
}

/// نسبة الحضور من المرصود، و`null` بلا رصد — `rateOf`.
int? rateOf(DashCounts c) => c.marked > 0 ? (c.present / c.marked * 100).round() : null;

/// طالب غيابه مزمن، واتجاهه: آخر أسبوعين مقابل الأسبوعين قبلهما — `ChronicAbsence`.
class ChronicAbsence {
  const ChronicAbsence({
    required this.student,
    required this.absent,
    required this.marked,
    required this.rate,
    required this.recent,
    required this.before,
  });

  final Student student;
  final int absent;
  final int marked;
  final int rate;
  final int recent;
  final int before;

  String get trend => recent > before ? 'up' : (recent < before ? 'down' : 'same');
}

class DashboardStats {
  const DashboardStats({
    required this.activeStudents,
    required this.newThisMonth,
    required this.holiday,
    required this.today,
    required this.unmarkedToday,
    required this.absentToday,
    required this.roomsMarked,
    required this.roomsTotal,
    required this.dueSoonAmount,
    required this.unmarkedRooms,
    required this.chronic,
    required this.collectedMonth,
    required this.overdueTotal,
    required this.longOverdue,
    required this.debtors,
    required this.upcoming,
    required this.range,
    required this.collectedRange,
    required this.previous,
    required this.collectedPrevious,
    required this.trend,
    required this.collectedTrend,
    required this.expenseTrend,
    required this.enrollTrend,
    required this.byGrade,
  });

  final int activeStudents;
  final int newThisMonth;
  final CalendarEvent? holiday;
  final DashCounts today;
  final int unmarkedToday;

  /// غائبو اليوم، ومعه أيام غيابه المتتالية حتى اليوم (الأطول أولاً).
  final List<({Student student, int streak})> absentToday;
  final int roomsMarked;
  final int roomsTotal;

  /// أقساط تستحق في الأيام السبعة القادمة ولم تُدفع.
  final double dueSoonAmount;

  /// الشعب التي لم يُرصد أحد من طلابها اليوم.
  final List<({Classroom room, int students})> unmarkedRooms;
  final List<ChronicAbsence> chronic;
  final double collectedMonth;
  final double overdueTotal;
  final int longOverdue;
  final int debtors;
  final List<CalendarEvent> upcoming;
  final DashCounts range;
  final double collectedRange;
  final DashCounts previous;
  final double collectedPrevious;

  /// نسبة الحضور يوماً بيوم لآخر 30 يوماً رُصدت.
  final List<({String date, int rate, int absent})> trend;
  final List<({String date, double amount})> collectedTrend;
  final List<({String date, double amount})> expenseTrend;
  final List<({String date, double amount})> enrollTrend;

  /// حضور الفترة لكل مرحلة بترتيب السلم الدراسي.
  final List<({String grade, int rate, int present, int absent, int excused})> byGrade;
}

String _addDays(String date, int days) {
  final d = DateTime.parse(date);
  return isoDate(DateTime(d.year, d.month, d.day + days));
}

const _steps = ['تمهيدي', 'روضه', 'بستان', 'اول', 'ثاني', 'ثالث', 'رابع', 'خامس', 'سادس', 'سابع', 'ثامن', 'تاسع', 'عاشر'];

/// رتبة المرحلة في السلم الدراسي — `gradeRank`.
int _gradeRank(String grade) {
  final g = grade
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAllMapped(RegExp(r'(^|\s)ال'), (m) => m[1] ?? '')
      .replaceAll(RegExp(r'صف\s*'), '')
      .trim();
  if (RegExp(r'حادي\s*عشر').hasMatch(g)) return 13;
  if (RegExp(r'ثاني\s*عشر').hasMatch(g)) return 14;
  final i = _steps.indexWhere(g.startsWith);
  return i < 0 ? 99 : i;
}

/// `buildDashboard`: [days] فترة الحضور والتحصيل (1 اليوم، 7 الأسبوع، 30 الشهر)، و[grade] مرحلة واحدة أو الكل.
DashboardStats buildDashboard({
  required String today,
  required List<Student> students,
  required List<Classroom> rooms,
  required List<ClassSession> sessions,
  required List<AttendanceMark> attendance,
  required List<Installment> installments,
  required List<Payment> payments,
  List<Expense> expenses = const [],
  required List<CalendarEvent> calendar,
  int days = 1,
  String grade = '',
  double chronicPercent = 10,
}) {
  late DashboardStats out;
  runAll(_dashboardSteps(
    today: today,
    students: students,
    rooms: rooms,
    sessions: sessions,
    attendance: attendance,
    installments: installments,
    payments: payments,
    expenses: expenses,
    calendar: calendar,
    days: days,
    grade: grade,
    chronicPercent: chronicPercent,
    done: (r) => out = r,
  ));
  return out;
}

/// [buildDashboard] نفسها مقطّعةً: تُفسح للرسم كل بضع ملّي ثوانٍ فلا تتجمّد الرئيسية
/// ولا تتقطع دوّارتها على جوال قديم. القوائم تُنسخ أولاً: المزامنة قد تضيف إليها
/// صفوفاً أثناء الإفساح، والمرور على قائمة تتغير يُسقط الحساب.
Future<DashboardStats> buildDashboardAsync({
  required String today,
  required List<Student> students,
  required List<Classroom> rooms,
  required List<ClassSession> sessions,
  required List<AttendanceMark> attendance,
  required List<Installment> installments,
  required List<Payment> payments,
  List<Expense> expenses = const [],
  required List<CalendarEvent> calendar,
  int days = 1,
  String grade = '',
  double chronicPercent = 10,
}) async {
  late DashboardStats out;
  await runSliced(_dashboardSteps(
    today: today,
    students: List.of(students),
    rooms: List.of(rooms),
    sessions: List.of(sessions),
    attendance: List.of(attendance),
    installments: List.of(installments),
    payments: List.of(payments),
    expenses: List.of(expenses),
    calendar: List.of(calendar),
    days: days,
    grade: grade,
    chronicPercent: chronicPercent,
    done: (r) => out = r,
  ));
  return out;
}

/// خطوات الحساب: كل `yield` نقطة آمنة للإفساح.
Iterable<void> _dashboardSteps({
  required String today,
  required List<Student> students,
  required List<Classroom> rooms,
  required List<ClassSession> sessions,
  required List<AttendanceMark> attendance,
  required List<Installment> installments,
  required List<Payment> payments,
  required List<Expense> expenses,
  required List<CalendarEvent> calendar,
  required int days,
  required String grade,
  required double chronicPercent,
  required void Function(DashboardStats) done,
}) sync* {
  final month = today.substring(0, 7);
  final span = days < 1 ? 1 : days;
  final rangeStart = _addDays(today, -(span - 1));
  // اليوم يقارَن بآخر يوم رُصد قبله، والأسبوع والشهر بما قبلهما بالطول نفسه
  final prevStart = _addDays(rangeStart, -span);
  bool inGrade(String g) => grade.isEmpty || isSameGrade(g, grade);
  final active = <Student>[];
  var n = 0;
  for (final s in students) {
    if (s.status == 'active' && inGrade(s.gradeLevel)) active.add(s);
    if (++n % 256 == 0) yield null;
  }
  final activeIds = {for (final s in active) s.id};

  final since = _addDays(today, -30);
  final from = prevStart.compareTo(since) < 0 ? prevStart : since;
  final recentSessions = [
    for (final s in sessions)
      if (s.sessionDate.compareTo(from) >= 0 && s.sessionDate.compareTo(today) <= 0) s,
  ];
  final sessionIds = {for (final s in recentSessions) s.id};
  final recentById = sessionMap(recentSessions);
  yield null;
  final recordsByStudent = <String, List<AttendanceMark>>{};
  n = 0;
  for (final r in attendance) {
    if (++n % 2048 == 0) yield null;
    if (!sessionIds.contains(r.sessionId) || !activeIds.contains(r.studentId)) continue;
    (recordsByStudent[r.studentId] ??= []).add(r);
  }

  final todayStatus = <String, String>{};
  final chronic = <ChronicAbsence>[];
  final recentFrom = _addDays(today, -13);
  final beforeFrom = _addDays(today, -27);
  final absentToday = <({Student student, int streak})>[];
  final byDate = <String, DashCounts>{};
  final range = DashCounts();
  final prevByDate = <String, DashCounts>{};
  final gradeRange = <String, DashCounts>{};
  for (final s in active) {
    yield null;
    final daysList = dailyAttendance(recordsByStudent[s.id] ?? const [], recentSessions, calendar: calendar, sessionById: recentById);
    final t = daysList.where((d) => d.date == today).firstOrNull;
    if (t != null) todayStatus[s.id] = t.status;
    if (t?.status == 'absent') {
      // الأيام المرصودة له من الأحدث: ما دام غائباً فهي سلسلة واحدة
      final sorted = [...daysList]..sort((a, b) => b.date.compareTo(a.date));
      var streak = 0;
      for (final d in sorted) {
        if (d.status != 'absent') break;
        streak++;
      }
      absentToday.add((student: s, streak: streak));
    }
    final window30 = daysList.where((d) => d.date.compareTo(since) >= 0).toList();
    final absent = window30.where((d) => d.status == 'absent').length;
    // المزمن بالنسبة لا بالعدد: خمسة أيام مرصودة على الأقل
    if (window30.length >= 5 && absent > 0) {
      final rate = (absent / window30.length * 100).round();
      if (rate >= chronicPercent) {
        final recent = window30.where((d) => d.status == 'absent' && d.date.compareTo(recentFrom) >= 0).length;
        final before = window30
            .where((d) => d.status == 'absent' && d.date.compareTo(beforeFrom) >= 0 && d.date.compareTo(recentFrom) < 0)
            .length;
        chronic.add(ChronicAbsence(student: s, absent: absent, marked: window30.length, rate: rate, recent: recent, before: before));
      }
    }
    final g = s.gradeLevel.trim().isEmpty ? '—' : s.gradeLevel.trim();
    for (final d in daysList) {
      if (d.date.compareTo(rangeStart) < 0) (prevByDate[d.date] ??= DashCounts()).add(d.status);
      if (d.date.compareTo(since) < 0) continue;
      (byDate[d.date] ??= DashCounts()).add(d.status);
      if (d.date.compareTo(rangeStart) >= 0) {
        range.add(d.status);
        (gradeRange[g] ??= DashCounts()).add(d.status);
      }
    }
  }
  yield null;
  // يوم رُصدت فيه شعبة أو اثنتان لا يمثّل المدرسة: يدخل الرسم إن رُصد ثلث الطلاب فأكثر
  final minMarked = active.length * 0.3;
  final trendDates = byDate.keys.where((k) => byDate[k]!.marked >= minMarked).toList()..sort();
  final trend = [
    for (final k in trendDates) (date: k, rate: rateOf(byDate[k]!) ?? 0, absent: byDate[k]!.absent),
  ];
  final prevDates = prevByDate.keys.toList()..sort();
  final prevKeys = span == 1
      ? (prevDates.isEmpty ? const <String>[] : [prevDates.last])
      : prevDates.where((d) => d.compareTo(prevStart) >= 0).toList();
  final previous = DashCounts();
  for (final k in prevKeys) {
    final c = prevByDate[k]!;
    previous
      ..present += c.present
      ..absent += c.absent
      ..excused += c.excused;
  }
  final gradeKeys = gradeRange.keys.toList()
    ..sort((a, b) {
      final r = _gradeRank(a) - _gradeRank(b);
      return r != 0 ? r : a.compareTo(b);
    });
  final byGrade = [
    for (final k in gradeKeys)
      (
        grade: k,
        rate: rateOf(gradeRange[k]!) ?? 0,
        present: gradeRange[k]!.present,
        absent: gradeRange[k]!.absent,
        excused: gradeRange[k]!.excused,
      ),
  ];

  final counts = DashCounts();
  var unmarked = 0;
  for (final s in active) {
    final st = todayStatus[s.id];
    if (st == null) {
      unmarked++;
    } else {
      counts.add(st);
    }
  }
  yield null;

  final holiday = holidayEventOn(calendar, today);
  // طلاب كل مرحلة مرة واحدة: الشعبة ذات المرحلة لا يطابقها إلا طالب من مرحلتها
  // (شرطٌ في كل فروع studentBelongsToRoom)، فتُفحص طلاب مرحلتها وحدهم لا المدرسة كلها
  final byGradeKey = <String, List<Student>>{};
  for (final s in active) {
    final key = normalizeAcademicText(s.gradeLevel);
    if (key.isNotEmpty) (byGradeKey[key] ??= []).add(s);
  }
  yield null;
  final roomState = <({Classroom room, int students, bool marked})>[];
  for (final room in rooms) {
    if (!inGrade(room.gradeLevel)) continue;
    final roomGrade = normalizeAcademicText(room.gradeLevel);
    final candidates = roomGrade.isEmpty ? active : (byGradeKey[roomGrade] ?? const <Student>[]);
    final members = candidates.where((s) => studentBelongsToRoom(s, room)).toList();
    if (members.isNotEmpty) {
      roomState.add((room: room, students: members.length, marked: members.any((s) => todayStatus.containsKey(s.id))));
    }
    yield null;
  }
  final unmarkedRooms = holiday != null
      ? const <({Classroom room, int students})>[]
      : [
          for (final r in roomState)
            if (!r.marked) (room: r.room, students: r.students),
        ];

  // المالية: السندات غير الملغاة، والمتأخر من أقساط الطلاب النشطين. التحصيل للمدرسة كلها
  var collectedMonth = 0.0, collectedRange = 0.0, collectedPrev = 0.0;
  final byDay = <String, double>{};
  n = 0;
  for (final p in payments) {
    if (++n % 512 == 0) yield null;
    if (p.cancelled || p.amount <= 0) continue;
    final date = isoDateOf(p, p.date);
    if (date.startsWith(month)) collectedMonth += p.amount;
    if (date.compareTo(rangeStart) >= 0 && date.compareTo(today) <= 0) collectedRange += p.amount;
    if (date.compareTo(prevStart) >= 0 && date.compareTo(rangeStart) < 0) collectedPrev += p.amount;
    if (date.compareTo(since) >= 0 && date.compareTo(today) <= 0) byDay[date] = (byDay[date] ?? 0) + p.amount;
  }
  List<({String date, double amount})> last30(Map<String, double> m) => [
        for (var i = 0; i < 30; i++) (date: _addDays(today, i - 29), amount: m[_addDays(today, i - 29)] ?? 0),
      ];
  final spentByDay = <String, double>{};
  n = 0;
  for (final e in expenses) {
    if (++n % 512 == 0) yield null;
    // المصروف وحده، بلا المسحوبات والتحويلات
    if (e.cancelled || e.kind != 'expense') continue;
    final date = e.expenseDate.padRight(10).substring(0, 10);
    if (date.compareTo(since) >= 0 && date.compareTo(today) <= 0) spentByDay[date] = (spentByDay[date] ?? 0) + e.amount;
  }
  final enrolledByDay = <String, double>{};
  var newThisMonth = 0;
  for (final s in active) {
    final date = isoDateOf(s, s.enrollmentDate);
    if (date.startsWith(month)) newThisMonth++;
    if (date.compareTo(since) >= 0 && date.compareTo(today) <= 0) enrolledByDay[date] = (enrolledByDay[date] ?? 0) + 1;
  }
  yield null;
  // المستحق الحالّ لكل طالب — `overdueByStudent` نفسها، مقطّعة
  final dueDay = DateTime.parse(today);
  final due = <String, double>{};
  final weekEnd = _addDays(today, 7);
  var dueSoon = 0.0;
  final longCut = _addDays(today, -60);
  final longOverdue = <String>{};
  n = 0;
  for (final i in installments) {
    if (++n % 512 == 0) yield null;
    if (!activeIds.contains(i.studentId)) continue;
    due[i.studentId] = (due[i.studentId] ?? 0) + (isInstallmentDue(i, dueDay) ? unpaidOf(i) : 0.0);
    final d = isoDateOf(i, i.dueDate);
    final unpaid = unpaidOf(i);
    if (unpaid <= 0) continue;
    if (d.compareTo(today) > 0 && d.compareTo(weekEnd) <= 0) dueSoon += unpaid;
    if (d.compareTo(longCut) < 0) longOverdue.add(i.studentId);
  }
  var overdueTotal = 0.0;
  var debtors = 0;
  for (final amount in due.values) {
    if (amount > 0) {
      overdueTotal += amount;
      debtors++;
    }
  }

  absentToday.sort((a, b) => b.streak - a.streak);
  chronic.sort((a, b) {
    final r = b.rate - a.rate;
    return r != 0 ? r : b.recent - a.recent;
  });
  yield null;
  done(DashboardStats(
    activeStudents: active.length,
    newThisMonth: newThisMonth,
    holiday: holiday,
    today: counts,
    unmarkedToday: unmarked,
    absentToday: absentToday,
    roomsMarked: roomState.where((r) => r.marked).length,
    roomsTotal: roomState.length,
    dueSoonAmount: dueSoon,
    unmarkedRooms: unmarkedRooms,
    chronic: chronic,
    collectedMonth: collectedMonth,
    overdueTotal: overdueTotal,
    longOverdue: longOverdue.length,
    debtors: debtors,
    upcoming: upcomingEvents(calendar, today).take(4).toList(),
    range: range,
    collectedRange: collectedRange,
    previous: previous,
    collectedPrevious: collectedPrev,
    trend: trend,
    collectedTrend: last30(byDay),
    expenseTrend: last30(spentByDay),
    enrollTrend: last30(enrolledByDay),
    byGrade: byGrade,
  ));
}
