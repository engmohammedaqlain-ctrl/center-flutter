import '../models/models.dart';
import 'grading.dart';
import 'portal.dart';
import 'supabase.dart';

// مواعيد الرصد في بوابة المعلم — المقابل لـ `features/portal/GradeDeadlineBanner.tsx`.

/// كم يوماً قبل الموعد يظهر الرصد المطلوب.
const _soonDays = 7;

/// رصد مطلوب: مكوّن لم يُرصد في مادة وشعبة، فات موعده أو يحين قريباً.
class DueGrade {
  const DueGrade({
    required this.groupId,
    required this.gradeLevel,
    required this.section,
    required this.component,
    required this.subject,
    required this.due,
    required this.late,
  });

  final String groupId;
  final String gradeLevel;
  final String section;
  final String component;
  final String subject;
  final String due;
  final bool late;
}

/// رصد المعلم المطلوب من مواعيد الرصد، الأقرب أولاً. «رُصد» كما في تقرير الرصد:
/// اختبار واحد للمكوّن في الشعبة. لا جلب حين لا موعد قريب، والجلب أعمدة قليلة
/// للمكوّنات القريبة وحدها.
Future<List<DueGrade>> loadDueGrades(TeacherPortalData data) async {
  final branding = data.branding;
  if (branding.grading.mode == 'monthly' || branding.gradeDeadlines.isEmpty) return const [];
  final now = DateTime.now();
  final today = isoDate(now);
  final soon = isoDate(now.add(const Duration(days: _soonDays)));
  final term = termForDate(today);
  final dueOf = <String, String>{
    for (final d in branding.gradeDeadlines)
      if (d.term == term && d.date.compareTo(soon) <= 0) d.name.trim(): d.date,
  };
  if (dueOf.isEmpty) return const [];

  // المكوّنات القريبة في مواد المعلم وشعبها
  final wanted = <({TeacherClass c, PortalRoom room, GradingComponent comp, String due})>[];
  for (final c in data.classes) {
    for (final room in c.rooms) {
      final grade = room.gradeLevel.isNotEmpty ? room.gradeLevel : c.group.gradeLevel;
      final comps = branding.grading.recordingSchemeForSubject(grade, c.group.subjectId).of(term);
      for (final comp in comps) {
        final due = dueOf[comp.name.trim()];
        if (comp.weight > 0 && due != null) wanted.add((c: c, room: room, comp: comp, due: due));
      }
    }
  }
  if (wanted.isEmpty) return const [];

  final groupIds = {for (final w in wanted) w.c.group.id};
  final componentIds = {for (final w in wanted) w.comp.id};
  final rows = <Map<String, dynamic>>[];
  const page = 1000;
  for (var offset = 0;; offset += page) {
    final batch = await supabaseSelect(
      'student_evaluations',
      columns: 'group_id,student_id,component_id',
      filters: {
        'group_id': 'in.(${groupIds.join(',')})',
        'component_id': 'in.(${componentIds.join(',')})',
        'term': 'eq.$term',
      },
      limit: page,
      offset: offset,
    );
    // بلا شبكة لا يُحكم بأن شيئاً لم يُرصد
    if (batch == null) return const [];
    rows.addAll(batch);
    if (batch.length < page) break;
  }
  final recorded = <String>{
    for (final r in rows) '${r['group_id']}|${r['component_id']}|${r['student_id']}',
  };

  final list = <DueGrade>[];
  for (final w in wanted) {
    final students = w.c.students.where((s) => w.c.rooms.length == 1 || w.c.roomIdFor(s.section) == w.room.id);
    final done = students.any((s) => recorded.contains('${w.c.group.id}|${w.comp.id}|${s.id}'));
    if (done) continue;
    list.add(DueGrade(
      groupId: w.c.group.id,
      gradeLevel: w.room.gradeLevel.isNotEmpty ? w.room.gradeLevel : w.c.group.gradeLevel,
      section: w.room.name,
      component: w.comp.name,
      subject: w.c.subjectName,
      due: w.due,
      late: w.due.compareTo(today) < 0,
    ));
  }
  list.sort((a, b) => a.due.compareTo(b.due));
  return list;
}
