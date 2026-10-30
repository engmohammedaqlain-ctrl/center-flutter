/// بيانات التقارير — المقابل لـ `reportsData.ts` و`gradesQuery.ts` و`compareMatrix` في الويب.
/// دوال صافية فوق جداول الجهاز: مجمّعة بالشعبة، والعلامات من شهادات الشعب.
library;

import '../models/models.dart';
import 'academic_matching.dart';
import 'attendance_days.dart';
import 'balance.dart';
import 'grading.dart';
import 'report_cards.dart';
import 'store.dart';

double round1(num n) => (n * 10).round() / 10;

String sectionLabel(Classroom r) => [r.gradeLevel, r.name].where((s) => s.trim().isNotEmpty).join(' - ');

class SectionGroup {
  const SectionGroup({required this.room, required this.label, required this.students});

  final Classroom room;
  final String label;
  final List<Student> students;
}

/// الشعب بترتيب المراحل، ولكل شعبة طلابها (بلا المنسحبين والمؤرشفين) بترتيب الاسم.
List<SectionGroup> groupBySection(AppStore store, {String grade = '', bool activeOnly = false}) {
  final live = store.studentsInViewedYear
      .where((s) => activeOnly ? s.status == 'active' : (s.status != 'withdrawn' && s.status != 'archived'))
      .toList();
  final order = store.gradeOptions;
  int rank(String g) {
    final i = order.indexWhere((x) => isSameGrade(x, g));
    return i < 0 ? order.length : i;
  }

  final rooms = store.roomsInViewedYear.where((r) => grade.isEmpty || r.gradeLevel.trim() == grade).toList()
    ..sort((a, b) {
      final g = rank(a.gradeLevel).compareTo(rank(b.gradeLevel));
      if (g != 0) return g;
      final na = int.tryParse(a.name.replaceAll(RegExp(r'\D'), ''));
      final nb = int.tryParse(b.name.replaceAll(RegExp(r'\D'), ''));
      if (na != null && nb != null && na != nb) return na.compareTo(nb);
      return a.name.compareTo(b.name);
    });
  return [
    for (final room in rooms)
      () {
        final members = live.where((s) => studentBelongsToRoom(s, room)).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
        return SectionGroup(room: room, label: sectionLabel(room), students: members);
      }(),
  ].where((g) => g.students.isNotEmpty).toList();
}

/// الصفوف كما في الإعدادات، لاختيار «الصف» في التقارير.
List<String> reportGrades(AppStore store) {
  final set = {for (final r in store.roomsInViewedYear) if (r.gradeLevel.trim().isNotEmpty) r.gradeLevel.trim()};
  final order = store.gradeOptions;
  int rank(String g) {
    final i = order.indexWhere((x) => isSameGrade(x, g));
    return i < 0 ? order.length : i;
  }

  return set.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
}

/// أيام دوام الشهر (بلا الجمعة).
List<String> monthSchoolDays(String month) {
  final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5, 7));
  final last = DateTime(y, m + 1, 0).day;
  return [
    for (var d = 1; d <= last; d++)
      if (DateTime(y, m, d).weekday != DateTime.friday) '$month-${d.toString().padLeft(2, '0')}',
  ];
}

/// أيام الدوام بين تاريخين شاملين (بلا الجمعة).
List<String> schoolDaysBetween(String from, String to) {
  final out = <String>[];
  if (from.isEmpty || to.isEmpty || to.compareTo(from) < 0) return out;
  var d = DateTime.parse(from);
  for (var guard = 0; guard < 400; guard++) {
    final iso = isoDate(d);
    if (iso.compareTo(to) > 0) break;
    if (d.weekday != DateTime.friday) out.add(iso);
    d = d.add(const Duration(days: 1));
  }
  return out;
}

class StudentAttendance {
  const StudentAttendance({required this.student, required this.byDay, required this.present, required this.absent, required this.excused});

  final Student student;
  final Map<String, String> byDay;
  final int present;
  final int absent;
  final int excused;

  /// نسبة الحضور من الأيام المرصودة؛ 100 بلا رصد فلا يظهر تحت أي حد
  int get rate {
    final marked = present + absent + excused;
    return marked == 0 ? 100 : (present / marked * 100).round();
  }
}

class SectionAttendance {
  const SectionAttendance({required this.group, required this.rows});

  final SectionGroup group;
  final List<StudentAttendance> rows;

  int get present => rows.fold(0, (n, r) => n + r.present);
  int get absent => rows.fold(0, (n, r) => n + r.absent);
  int get excused => rows.fold(0, (n, r) => n + r.excused);

  int? get rate {
    final marked = present + absent + excused;
    return marked == 0 ? null : (present / marked * 100).round();
  }
}

/// حضور كل شعبة في فترة (من - إلى شاملة)، يوماً بيوم.
List<SectionAttendance> attendanceBySection(AppStore store, List<SectionGroup> groups, String from, String to) {
  final sessions = store.sessions.where((s) => s.sessionDate.compareTo(from) >= 0 && s.sessionDate.compareTo(to) <= 0).toList();
  final ids = {for (final s in sessions) s.id};
  final recordsOf = <String, List<AttendanceMark>>{};
  for (final r in store.attendance) {
    if (ids.contains(r.sessionId)) recordsOf.putIfAbsent(r.studentId, () => []).add(r);
  }
  return [
    for (final g in groups)
      SectionAttendance(
        group: g,
        rows: [
          for (final s in g.students)
            () {
              final days = dailyAttendance(recordsOf[s.id] ?? const [], sessions);
              int count(String st) => days.where((d) => d.status == st).length;
              return StudentAttendance(
                student: s,
                byDay: {for (final d in days) d.date: d.status},
                present: count('present'),
                absent: count('absent'),
                excused: count('excused'),
              );
            }(),
        ],
      ),
  ];
}

/// المتأخر على كل طالب نشط (ما حلّ موعده ولم يُدفع).
Map<String, double> duesByStudent(AppStore store) {
  final out = <String, double>{};
  for (final i in store.installments) {
    if (!isInstallmentDue(i)) continue;
    final v = unpaidOf(i);
    if (v > 0.005) out[i.studentId] = (out[i.studentId] ?? 0) + v;
  }
  return out;
}

// ── العلامات ─────────────────────────────────────────────────────────────────

const periodLabels = {'term_1': 'الفصل الأول', 'term_2': 'الفصل الثاني', 'year': 'السنة'};

const bands = ['ممتاز', 'جيد جداً', 'جيد', 'مقبول', 'راسب'];

/// التقدير بحدوده المعتادة: 90، 80، 70، ثم حد النجاح.
int bandOf(double percent, double pass) {
  if (percent < pass) return 4;
  if (percent >= 90) return 0;
  if (percent >= 80) return 1;
  if (percent >= 70) return 2;
  return 3;
}

/// علامة المادة ونسبتها في الفترة؛ null إن لم يُرصد شيء.
({double score, double percent})? subjectResult(SubjectGradeSummary row, String period) {
  if (period == 'year') {
    final y = row.yearGrade;
    return y == null ? null : (score: y.score, percent: y.percent);
  }
  final t = period == 'term_1' ? row.term1 : row.term2;
  if (t.currentAverage == null || t.currentScore == null) return null;
  return (score: t.currentScore!, percent: t.currentAverage!);
}

double? studentAverage(ReportCardStudent card, String period) {
  final p = [for (final r in card.rows) if (subjectResult(r, period) case final res?) res.percent];
  return p.isEmpty ? null : round1(p.reduce((a, b) => a + b) / p.length);
}

class SectionGrades {
  const SectionGrades({required this.id, required this.label, required this.cards});

  final String id;
  final String label;
  final List<ReportCardStudent> cards;
}

/// شهادات كل شعبة في الصف المختار (أو المدرسة).
List<SectionGrades> sectionGrades(AppStore store, {String grade = ''}) => [
      for (final g in groupBySection(store, grade: grade))
        SectionGrades(id: g.room.id, label: g.label, cards: loadClassReportCards(store, roomId: g.room.id).cards),
    ];

List<String> subjectNames(Iterable<ReportCardStudent> cards) =>
    {for (final c in cards) for (final r in c.rows) if (r.subjectName.trim().isNotEmpty) r.subjectName.trim()}.toList()..sort();

class RankRow {
  const RankRow({required this.card, required this.section, required this.value});

  final ReportCardStudent card;
  final String section;
  final double value;
}

/// المقياس: '' المعدل العام، 'prev' معدل السنة الماضية، 'sub:<المادة>' مادة واحدة — `rankStudents`.
List<RankRow> rankStudents(
  List<SectionGrades> sections, {
  required String metric,
  required String period,
  required String order,
  required double pass,
  int min = 0,
  int max = 0,
  int limit = 0,
  List<int> picked = const [],
  Map<String, double> prev = const {},
}) {
  double? valueOf(ReportCardStudent c) {
    if (metric.isEmpty) return studentAverage(c, period);
    if (metric == 'prev') return prev[c.id];
    final name = metric.substring(4);
    final row = c.rows.where((r) => r.subjectName.trim() == name).firstOrNull;
    final res = row == null ? null : subjectResult(row, period);
    return res == null ? null : round1(res.percent);
  }

  final rows = <RankRow>[];
  for (final s in sections) {
    for (final c in s.cards) {
      final v = valueOf(c);
      if (v == null) continue;
      if (order == 'fail' && v >= pass) continue;
      if (min > 0 && v < min) continue;
      if (max > 0 && v > max) continue;
      if (picked.isNotEmpty && !picked.contains(bandOf(v, pass))) continue;
      rows.add(RankRow(card: c, section: s.label, value: v));
    }
  }
  rows.sort((a, b) {
    final byValue = order == 'top' ? b.value.compareTo(a.value) : a.value.compareTo(b.value);
    return byValue != 0 ? byValue : a.card.studentName.compareTo(b.card.studentName);
  });
  return limit > 0 ? rows.take(limit).toList() : rows;
}

class SubjectAnalysis {
  const SubjectAnalysis({required this.name, required this.count, required this.average, required this.passRate, required this.max, required this.min, required this.bandCounts});

  final String name;
  final int count;
  final double average;
  final int passRate;
  final double max;
  final double min;
  final List<int> bandCounts;
}

/// مادة لكل سطر (بالاسم عبر الشعب)، ثم «المعدل العام» للطلاب أنفسهم — `analyzeSubjects`.
({List<SubjectAnalysis> subjects, SubjectAnalysis? overall}) analyzeSubjects(List<ReportCardStudent> cards, String period, double pass) {
  SubjectAnalysis build(String name, List<double> v) {
    final counts = [0, 0, 0, 0, 0];
    for (final x in v) {
      counts[bandOf(x, pass)]++;
    }
    return SubjectAnalysis(
      name: name,
      count: v.length,
      average: round1(v.reduce((a, b) => a + b) / v.length),
      passRate: (v.where((x) => x >= pass).length / v.length * 100).round(),
      max: round1(v.reduce((a, b) => a > b ? a : b)),
      min: round1(v.reduce((a, b) => a < b ? a : b)),
      bandCounts: counts,
    );
  }

  final bySubject = <String, List<double>>{};
  for (final c in cards) {
    for (final r in c.rows) {
      final res = subjectResult(r, period);
      if (res != null) bySubject.putIfAbsent(r.subjectName.trim(), () => []).add(res.percent);
    }
  }
  final subjects = [for (final e in bySubject.entries) build(e.key, e.value)]..sort((a, b) => a.average.compareTo(b.average));
  final avgs = [for (final c in cards) if (studentAverage(c, period) case final a?) a];
  return (subjects: subjects, overall: avgs.isEmpty ? null : build('المعدل العام', avgs));
}

/// مقارنة الشعب: مادة لكل سطر وشعبة لكل عمود، والخلية معدل الشعبة في المادة — `compareMatrix`.
({List<({String name, List<double?> values})> rows, List<double?> overall}) compareMatrix(List<SectionGrades> sections, String period) {
  double? avg(List<double> v) => v.isEmpty ? null : round1(v.reduce((a, b) => a + b) / v.length);
  final names = <String>{};
  final cell = <String, List<double>>{};
  for (final s in sections) {
    for (final c in s.cards) {
      for (final r in c.rows) {
        final res = subjectResult(r, period);
        if (res == null) continue;
        final name = r.subjectName.trim();
        names.add(name);
        cell.putIfAbsent('$name|${s.id}', () => []).add(res.percent);
      }
    }
  }
  final rows = [
    for (final name in names.toList()..sort()) (name: name, values: [for (final s in sections) avg(cell['$name|${s.id}'] ?? const [])]),
  ];
  final overall = [
    for (final s in sections) avg([for (final c in s.cards) if (studentAverage(c, period) case final a?) a]),
  ];
  return (rows: rows, overall: overall);
}

class ExamDecline {
  const ExamDecline({required this.studentId, required this.subjectId, required this.before, required this.after, required this.diff});

  final String studentId;
  final String subjectId;
  final ({String title, String date, double percent}) before;
  final ({String title, String date, double percent}) after;
  final double diff;
}

/// آخر اختبارين للطالب في كل مادة؛ ما نزلت نسبته [minDrop]% فأكثر، الأشد أولاً — `examDeclines`.
List<ExamDecline> examDeclines(Iterable<Evaluation> evaluations, double minDrop) {
  final bySubject = <String, Map<String, ({String title, String date, double percent})>>{};
  for (final e in evaluations) {
    if (e.subjectId.isEmpty || !(e.maxScore > 0)) continue;
    bySubject.putIfAbsent('${e.studentId}|${e.subjectId}', () => {})['${e.evaluationDate}|${e.title}'] =
        (title: e.title, date: e.evaluationDate, percent: round1(e.score / e.maxScore * 100));
  }
  final out = <ExamDecline>[];
  for (final entry in bySubject.entries) {
    if (entry.value.length < 2) continue;
    final keys = entry.value.keys.toList()..sort();
    final before = entry.value[keys[keys.length - 2]]!;
    final after = entry.value[keys.last]!;
    final diff = round1(after.percent - before.percent);
    if (-diff < minDrop) continue;
    final p = entry.key.split('|');
    out.add(ExamDecline(studentId: p[0], subjectId: p[1], before: before, after: after, diff: diff));
  }
  return out..sort((a, b) => a.diff.compareTo(b.diff));
}

/// معدل السنة الماضية كما سُجّل في ملف الطالب — `parseAverage(s.gpa)`.
Map<String, double> previousAverages(AppStore store) => {
      for (final s in store.students)
        if (double.tryParse(s.gpa.replaceAll('%', '').trim()) case final v? when v > 0 && v <= 100) s.id: v,
    };
