/// الشهادة المدرسية — المقابل لـ `ReportCardModal.tsx` و`classReportCards.ts` في الويب.
///
/// شهادة طالب، أو شهادات صف كامل دفعة واحدة (كل طالب في صفحة)، أو كشف نتائج الصف
/// بالترتيب. فصل لم تكتمل مكوّناته يُطبع بعلامته الحالية مع نجمة، فالشهادة صالحة
/// منتصف العام وآخره.
library;

import '../models/models.dart';
import 'academic_matching.dart';
import 'arabic_search.dart';
import 'attendance_days.dart';
import 'grading.dart';
import 'store.dart';

/// الفصل الأول وحده (شهادة منتصف العام) أو الفصلان ونتيجة السنة.
enum ReportCardTerms { term1, both }

class ReportCardStudent {
  const ReportCardStudent({
    required this.id,
    required this.studentName,
    this.gradeLevel = '',
    this.section = '',
    required this.rows,
    this.homeroomName = '',
    this.misses,
  });

  final String id;
  final String studentName;
  final String gradeLevel;
  final String section;
  final List<SubjectGradeSummary> rows;

  /// اسم مربي الشعبة تحت توقيعه.
  final String homeroomName;

  /// أيام الغياب والإذن في العام (`null` = لا يُطبع سطر الغياب).
  final List<({String date, String status})>? misses;
}

/// مواد الطالب بعلامة كل فصل ونتيجة السنة، بنظام علامات العام — `buildReportCardRows`.
/// درجات خارج العام المعروض لا تدخل، والمواد بترتيب أبجدي ثابت فتتطابق شهادات الصف سطراً بسطر.
List<SubjectGradeSummary> buildReportCardRows(
  Iterable<Evaluation> evaluations,
  GradingSettings grading,
  String gradeLevel,
  String Function(String subjectId) subjectName, {
  AcademicYear? year,
}) {
  final inYear = evaluations.where((e) {
    final d = e.evaluationDate.length >= 10 ? e.evaluationDate.substring(0, 10) : e.evaluationDate;
    return year == null || d.isEmpty || (d.compareTo(year.startsOn) >= 0 && d.compareTo(year.endsOn) <= 0);
  });
  return subjectGradeSummaries(inYear, grading.scheme, subjectName, grading: grading, gradeLevel: gradeLevel)
    ..sort((a, b) => compareArabicNames(a.subjectName, b.subjectName));
}

/// علامة فصل للشهادة: المكتمل بعلامته، والجاري بعلامته الحالية ومعه نجمة.
({String text, bool partial, double? pct}) reportTermCell(TermGrade term) {
  if (term.components.isEmpty || term.currentAverage == null) return (text: '—', partial: false, pct: null);
  if (term.isComplete) {
    return (text: '${term.termScore.round()}', partial: false, pct: term.termScore / term.fullMark * 100);
  }
  return (text: '${(term.currentScore ?? 0).round()}*', partial: true, pct: term.currentAverage);
}

int? _avg(Iterable<double> list) => list.isEmpty ? null : (list.reduce((a, b) => a + b) / list.length).round();

String reportResultText(num? pct, double passPercent) => pct == null ? '—' : (pct >= passPercent ? 'ناجح' : 'راسب');

/// معدل الفصل الأول، والثاني، والسنة على الشهادة.
({int? t1, int? t2, int? year}) reportAverages(ReportCardStudent card) => (
      t1: _avg([for (final r in card.rows) if (reportTermCell(r.term1).pct case final p?) p]),
      t2: _avg([for (final r in card.rows) if (reportTermCell(r.term2).pct case final p?) p]),
      year: _avg([for (final r in card.rows) if (r.yearGrade?.percent case final p?) p]),
    );

/// معدل الشهادة: الفصل الأول وحده، أو معدل السنة.
int? reportCardAverage(ReportCardStudent card, ReportCardTerms terms) {
  final a = reportAverages(card);
  return terms == ReportCardTerms.both ? a.year : a.t1;
}

/// الترتيب على الصف بالمعدل؛ المتساويان يأخذان الترتيب نفسه.
Map<String, int> reportClassRanks(List<ReportCardStudent> cards, ReportCardTerms terms) {
  final scored = [
    for (final c in cards)
      if (reportCardAverage(c, terms) case final avg?) (id: c.id, avg: avg),
  ]..sort((a, b) => b.avg.compareTo(a.avg));
  final ranks = <String, int>{};
  for (var i = 0; i < scored.length; i++) {
    ranks[scored[i].id] = i > 0 && scored[i - 1].avg == scored[i].avg ? ranks[scored[i - 1].id]! : i + 1;
  }
  return ranks;
}

/// فصل ثانٍ رُصد له شيء: بدونه الشهادة شهادة الفصل الأول.
bool reportHasTerm2(List<ReportCardStudent> cards) =>
    cards.any((c) => c.rows.any((r) => r.term2.currentAverage != null));

/// شهادات صف أو شعبة — `loadClassReportCards`. الطالب بصفه وشعبته في العام المعروض،
/// ومن انسحب أو أُرشف لا شهادة له، ومن لا علامات له لا تُطبع له صفحة فارغة.
({List<ReportCardStudent> cards, List<String> skipped, String label}) loadClassReportCards(
  AppStore store, {
  String? roomId,
  String grade = '',
}) {
  final rooms = store.roomsInViewedYear;
  final room = roomId == null ? null : rooms.where((r) => r.id == roomId).firstOrNull;
  final gradeLevel = (room?.gradeLevel ?? grade).trim();
  Classroom? roomOf(Student s) =>
      s.section.trim().isEmpty ? null : rooms.where((r) => studentBelongsToRoom(s, r)).firstOrNull;

  final inScope = store.studentsInViewedYear.where((s) {
    if (s.status == 'withdrawn' || s.status == 'archived') return false;
    if (room != null) return roomOf(s)?.id == room.id;
    return gradeLevel.isNotEmpty && s.gradeLevel.trim().isNotEmpty && isSameGrade(s.gradeLevel, gradeLevel);
  }).toList();

  final cards = [for (final s in inScope) studentReportCard(store, s, room: roomOf(s))];
  return (
    cards: [for (final c in cards) if (c.rows.isNotEmpty) c],
    skipped: [for (final c in cards) if (c.rows.isEmpty) c.studentName],
    label: [gradeLevel, room?.name ?? ''].where((x) => x.isNotEmpty).join(' - '),
  );
}

/// شهادة طالب واحد بمربي شعبته وغيابه في العام المعروض.
ReportCardStudent studentReportCard(AppStore store, Student s, {Classroom? room}) {
  final year = store.viewedAcademicYear;
  final homeroom = room ??
      (s.section.trim().isEmpty ? null : store.roomsInViewedYear.where((r) => studentBelongsToRoom(s, r)).firstOrNull);
  final marks = store.attendance.where((a) => a.studentId == s.id);
  final misses = [
    for (final d in dailyAttendance(marks, store.sessions))
      if (d.status != 'present' &&
          (year == null || (d.date.compareTo(year.startsOn) >= 0 && d.date.compareTo(year.endsOn) <= 0)))
        d,
  ];
  return ReportCardStudent(
    id: s.id,
    studentName: s.fullName,
    gradeLevel: s.gradeLevel,
    section: s.section,
    homeroomName: homeroom == null || homeroom.teacherId.isEmpty ? '' : (store.teacherById(homeroom.teacherId)?.name ?? ''),
    misses: misses,
    rows: buildReportCardRows(
      store.evaluations.where((e) => e.studentId == s.id),
      store.gradingForViewedYear,
      s.gradeLevel,
      (id) => store.subjectById(id)?.name ?? 'مادة',
      year: year,
    ),
  );
}
