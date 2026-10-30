/// المتابعة: إنذارات الغياب واكتمال رصد العلامات — المقابل لـ `followup.ts` و`followup.service.ts`
/// و`FollowupSettings` في types/settings.ts. الإعدادات في `settings.followup`، يضبطها الويب والجوال.
library;

import '../models/models.dart';
import 'academic_matching.dart';
import 'app_settings.dart';
import 'attendance_days.dart';
import 'grading.dart';
import 'notes.dart';
import 'store.dart';

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// {الطالب} و{الأيام} و{المستوى} تُستبدل عند الإرسال.
const defaultAbsenceMessage = 'نلفت انتباهكم إلى أن {الطالب} غاب {الأيام} أيام منذ بداية العام ({المستوى}). نرجو المتابعة مع المدرسة.';

const absenceAlertAction = 'absence_alert';

class GradeDeadline {
  const GradeDeadline({required this.term, required this.name, required this.date});

  final String term;
  final String name;
  final String date;

  Map<String, dynamic> toMap() => {'term': term, 'name': name, 'date': date};
}

/// - `absence`: إنذارات الغياب بمستويات من أيام غياب العام؛ كل مستوى يُرسل للأهل مرة واحدة.
/// - `chronicPercent`: الغياب المزمن نسبة من أيام الدوام المرصودة في آخر 30 يوماً.
/// - `gradeDeadlines`: موعد رصد كل مكوّن بالاسم في فصله.
class FollowupSettings {
  const FollowupSettings({
    this.absenceEnabled = true,
    this.levels = const [5, 10, 15],
    this.message = defaultAbsenceMessage,
    this.chronicPercent = 10,
    this.gradeDeadlines = const [],
  });

  final bool absenceEnabled;
  final List<int> levels;
  final String message;
  final double chronicPercent;
  final List<GradeDeadline> gradeDeadlines;

  FollowupSettings copyWith({
    bool? absenceEnabled,
    List<int>? levels,
    String? message,
    double? chronicPercent,
    List<GradeDeadline>? gradeDeadlines,
  }) =>
      FollowupSettings(
        absenceEnabled: absenceEnabled ?? this.absenceEnabled,
        levels: levels ?? this.levels,
        message: message ?? this.message,
        chronicPercent: chronicPercent ?? this.chronicPercent,
        gradeDeadlines: gradeDeadlines ?? this.gradeDeadlines,
      );

  Map<String, dynamic> toMap() => {
        'absence': {'enabled': absenceEnabled, 'levels': levels, 'message': message},
        'chronic_percent': chronicPercent,
        'grade_deadlines': [for (final d in gradeDeadlines) d.toMap()],
      };

  /// `normalizeFollowup`.
  factory FollowupSettings.normalize(Object? raw) {
    final v = raw is Map ? raw : const {};
    final a = v['absence'] is Map ? v['absence'] as Map : const {};
    final rawLevels = a['levels'];
    final levels = rawLevels is List
        ? ({
            for (final n in rawLevels)
              if (n is num && n == n.roundToDouble() && n > 0) n.toInt(),
          }.toList()
          ..sort())
        : const [5, 10, 15];
    final chronic = (v['chronic_percent'] as num?)?.toDouble();
    final msg = a['message'];
    final deadlines = v['grade_deadlines'];
    return FollowupSettings(
      absenceEnabled: a['enabled'] == null ? true : a['enabled'] == true,
      levels: levels,
      message: msg is String && msg.trim().isNotEmpty ? msg : defaultAbsenceMessage,
      chronicPercent: chronic != null && chronic > 0 && chronic < 100 ? chronic : 10,
      gradeDeadlines: [
        if (deadlines is List)
          for (final d in deadlines)
            if (d is Map && (d['term'] == 'term_1' || d['term'] == 'term_2') && d['name'] is String && _dateRe.hasMatch('${d['date'] ?? ''}'))
              GradeDeadline(term: '${d['term']}', name: '${d['name']}'.trim(), date: '${d['date']}'),
      ],
    );
  }
}

extension FollowupOfSettings on AppSettings {
  FollowupSettings get followup => FollowupSettings.normalize(extra['followup']);
}

/// اسم المستوى بترتيبه: إنذار أول، ثانٍ، ثالث، ثم نهائي لآخرها — `alertLevelName`.
String alertLevelName(int i, int count) {
  if (i == count - 1 && count > 1) return 'إنذار نهائي';
  const names = ['إنذار أول', 'إنذار ثانٍ', 'إنذار ثالث', 'إنذار رابع'];
  return i < names.length ? names[i] : 'إنذار ${i + 1}';
}

// ── إنذارات الغياب ───────────────────────────────────────────────────────────

class AbsenceAlert {
  const AbsenceAlert({required this.student, required this.days, required this.level, required this.levelName, required this.sentLevel});

  final Student student;
  final int days;

  /// المستوى المستحق الآن (من 0)
  final int level;
  final String levelName;

  /// آخر مستوى أُرسل؛ -1 لم يُرسل شيء
  final int sentLevel;
}

/// من بلغ غيابه مستوى لم يُرسل بعد. من تجاوز مستويين دفعة واحدة يُنذر بالأعلى وحده.
List<AbsenceAlert> dueAbsenceAlerts(List<Student> students, Map<String, int> absentDays, List<int> levels, Map<String, int> sent) {
  final out = <AbsenceAlert>[];
  for (final s in students) {
    final days = absentDays[s.id] ?? 0;
    var level = -1;
    for (var i = 0; i < levels.length; i++) {
      if (days >= levels[i]) level = i;
    }
    final sentLevel = sent[s.id] ?? -1;
    if (level > sentLevel) {
      out.add(AbsenceAlert(student: s, days: days, level: level, levelName: alertLevelName(level, levels.length), sentLevel: sentLevel));
    }
  }
  out.sort((a, b) => b.level != a.level ? b.level - a.level : b.days - a.days);
  return out;
}

String absenceMessage(String template, {required String name, required int days, required String levelName}) =>
    template.replaceAll('{الطالب}', name).replaceAll('{الأيام}', '$days').replaceAll('{المستوى}', levelName);

/// أعلى مستوى أُرسل لكل طالب، من سجل الحركات (المعرّف «<العام>:<المستوى>»).
Map<String, int> sentAlertLevels(Iterable<FinanceAuditEntry> entries, String yearId) {
  final sent = <String, int>{};
  for (final e in entries) {
    if (e.action != absenceAlertAction || e.studentId.isEmpty || e.entityId.isEmpty) continue;
    final parts = e.entityId.split(':');
    if (parts.length != 2 || parts[0] != yearId) continue;
    final n = int.tryParse(parts[1]);
    if (n != null && n > (sent[e.studentId] ?? -1)) sent[e.studentId] = n;
  }
  return sent;
}

/// أيام غياب كل طالب منذ بداية العام المعروض حتى اليوم — `absentDaysThisYear`.
Map<String, int> absentDaysThisYear(AppStore store) {
  final year = store.viewedAcademicYear;
  final today = isoDate(DateTime.now());
  final end = year == null || year.endsOn.isEmpty || today.compareTo(year.endsOn) < 0 ? today : year.endsOn;
  final sessions = store.sessions
      .where((s) => s.sessionDate.compareTo(end) <= 0 && (year == null || year.startsOn.isEmpty || s.sessionDate.compareTo(year.startsOn) >= 0))
      .toList();
  final ids = {for (final s in sessions) s.id};
  final byStudent = <String, List<AttendanceMark>>{};
  for (final r in store.attendance) {
    if (ids.contains(r.sessionId)) byStudent.putIfAbsent(r.studentId, () => []).add(r);
  }
  return {
    for (final e in byStudent.entries) e.key: dailyAttendance(e.value, sessions).where((d) => d.status == 'absent').length,
  };
}

/// الإنذارات المستحقة الآن — `loadAbsenceAlerts`.
List<AbsenceAlert> loadAbsenceAlerts(AppStore store) {
  final f = store.settings.followup;
  if (!f.absenceEnabled || f.levels.isEmpty) return const [];
  return dueAbsenceAlerts(
    store.students.where((s) => s.status == 'active').toList(),
    absentDaysThisYear(store),
    f.levels,
    sentAlertLevels(store.financeAudit, store.viewedAcademicYearId),
  );
}

// ── اكتمال رصد العلامات ─────────────────────────────────────────────────────

class CompletionComponent {
  const CompletionComponent({required this.name, required this.done, required this.late, this.due = '', required this.entries});

  final String name;
  final bool done;
  final bool late;
  final String due;
  final int entries;
}

class CompletionRow {
  const CompletionRow({
    required this.groupId,
    required this.room,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
    required this.components,
    required this.unlinked,
  });

  final String groupId;
  final Classroom room;
  final String subjectName;
  final String teacherId;
  final String teacherName;
  final List<CompletionComponent> components;

  /// علامات بلا مكوّن (أو بمكوّن ليس في نظام المادة): لا تدخل المعدل
  final int unlinked;

  int get done => components.where((c) => c.done).length;
  int get total => components.length;
  int get late => components.where((c) => c.late).length;
}

/// اكتمال رصد الفصل الحالي لكل مادة وشعبة — `gradeCompletion` + `loadCompletion`.
({String term, List<CompletionRow> rows}) loadCompletion(AppStore store) {
  final today = isoDate(DateTime.now());
  final year = store.viewedAcademicYear;
  final term = termForDate(today, term2Start: year?.term2Start);
  final grading = store.gradingForViewedYear;
  // المعدل الشهري لا مكوّنات فيه
  if (grading.mode == 'monthly') return (term: term, rows: const []);
  final deadlines = store.settings.followup.gradeDeadlines;
  final rooms = store.roomsInViewedYear;
  final studentRoom = <String, String>{};
  for (final s in store.students) {
    if (s.status == 'withdrawn' || s.status == 'archived') continue;
    for (final r in rooms) {
      if (studentBelongsToRoom(s, r)) {
        studentRoom[s.id] = r.id;
        break;
      }
    }
  }
  final recorded = <String, Set<String>>{};
  final loose = <String, int>{};
  for (final e in store.evaluations) {
    if (e.groupId.isEmpty) continue;
    if (year != null && year.startsOn.isNotEmpty && (e.evaluationDate.compareTo(year.startsOn) < 0 || e.evaluationDate.compareTo(year.endsOn) > 0)) continue;
    final room = studentRoom[e.studentId];
    if (room == null) continue;
    if (e.term == term && e.componentId.isNotEmpty) {
      recorded.putIfAbsent('${e.groupId}|${e.componentId}|$room', () => <String>{}).add('${e.title}|${e.evaluationDate}');
    } else if (e.term.isEmpty || e.componentId.isEmpty) {
      final key = '${e.groupId}|$room';
      loose[key] = (loose[key] ?? 0) + 1;
    }
  }
  String dueOf(String name) => deadlines.where((d) => d.term == term && d.name == name.trim()).firstOrNull?.date ?? '';

  final rows = <CompletionRow>[];
  for (final g in store.groupsInViewedYear) {
    if (g.status == 'archived') continue;
    for (final roomId in g.allRoomIds) {
      final room = rooms.where((r) => r.id == roomId).firstOrNull;
      if (room == null) continue;
      final scheme = grading.schemeForSubject(room.gradeLevel, g.subjectId);
      final comps = (term == 'term_2' ? scheme.term2 : scheme.term1).where((c) => c.weight > 0).toList();
      final ids = {for (final c in comps) c.id};
      final components = [
        for (final c in comps)
          () {
            final entries = recorded['${g.id}|${c.id}|$roomId']?.length ?? 0;
            final due = dueOf(c.name);
            return CompletionComponent(
              name: c.name,
              done: entries > 0,
              due: due,
              late: entries == 0 && due.isNotEmpty && due.compareTo(today) < 0,
              entries: entries,
            );
          }(),
      ];
      var stray = 0;
      for (final e in recorded.entries) {
        final p = e.key.split('|');
        if (p[0] == g.id && p[2] == roomId && !ids.contains(p[1])) stray += e.value.length;
      }
      if (components.isEmpty) continue;
      rows.add(CompletionRow(
        groupId: g.id,
        room: room,
        subjectName: store.subjectById(g.subjectId)?.name ?? '—',
        teacherId: g.teacherId,
        teacherName: store.teacherById(g.teacherId)?.name ?? '—',
        components: components,
        unlinked: (loose['${g.id}|$roomId'] ?? 0) + stray,
      ));
    }
  }
  rows.sort((a, b) => b.late != a.late ? b.late - a.late : (a.done / a.total).compareTo(b.done / b.total));
  return (term: term, rows: rows);
}

/// يرسل الإنذار رسالةً للأهل (تصل بوابتهم)، ويسجّله في سجل الحركات حتى لا يتكرر.
/// الفشل في طالب لا يوقف البقية — `sendAbsenceAlerts`.
Future<({int sent, int failed})> sendAbsenceAlerts(AppStore store, List<AbsenceAlert> alerts) async {
  final template = store.settings.followup.message;
  final yearId = store.viewedAcademicYearId;
  var sent = 0, failed = 0;
  for (final a in alerts) {
    final name = a.student.fullName;
    try {
      await const NotesService().send(
        studentId: a.student.id,
        audience: 'parent',
        subject: a.levelName,
        body: absenceMessage(template, name: name, days: a.days, levelName: a.levelName),
      );
      store.recordAudit(
        action: absenceAlertAction,
        summary: '${a.levelName}: ${a.days} أيام غياب',
        studentId: a.student.id,
        studentName: name,
        entityId: '$yearId:${a.level}',
      );
      sent++;
    } catch (_) {
      failed++;
    }
  }
  return (sent: sent, failed: failed);
}
