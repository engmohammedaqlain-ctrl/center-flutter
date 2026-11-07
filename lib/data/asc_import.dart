/// ملف aSc TimeTables بصيغته القياسية (XML) — المقابل لـ `ascImport.ts`: teachers وsubjects
/// وlessons، ولكل درس teacherids وsubjectid وperiodsperweek. النصاب = مجموع حصص دروس المعلم
/// في الأسبوع.
library;

import 'dart:math' as math;

import '../models/models.dart';

class AscItem {
  const AscItem({required this.id, required this.name, required this.short});

  final String id;
  final String name;
  final String short;
}

class AscLesson {
  const AscLesson({required this.teacherIds, required this.subjectId, required this.classIds, required this.periods});

  final List<String> teacherIds;
  final String subjectId;
  final List<String> classIds;
  final double periods;
}

class AscFile {
  const AscFile({required this.teachers, required this.subjects, required this.classes, required this.lessons});

  final List<AscItem> teachers;
  final List<AscItem> subjects;
  final List<AscItem> classes;
  final List<AscLesson> lessons;
}

String _decode(String v) => v.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|\w+);'), (m) {
      final e = m[1]!;
      if (e.startsWith('#')) {
        final hex = e[1] == 'x' || e[1] == 'X';
        final code = int.tryParse(e.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
        return code == null ? m[0]! : String.fromCharCode(code);
      }
      return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'"}[e] ?? m[0]!;
    });

List<Map<String, String>> _elements(String xml, String tag) {
  final attr = RegExp(r'''([\w:-]+)\s*=\s*("([^"]*)"|'([^']*)')''');
  return [
    for (final m in RegExp('<$tag\\s([^>]*?)/?>', caseSensitive: false).allMatches(xml))
      {
        for (final a in attr.allMatches(m[1]!)) a[1]!.toLowerCase(): _decode(a[3] ?? a[4] ?? ''),
      },
  ];
}

List<String> _ids(String? v) => (v ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

AscFile parseAsc(String xml) {
  if (!RegExp(r'<lessons?[\s>]', caseSensitive: false).hasMatch(xml) ||
      !RegExp(r'<teachers?[\s>]', caseSensitive: false).hasMatch(xml)) {
    throw const FormatException('ليس ملف aSc');
  }
  AscItem item(Map<String, String> t) =>
      AscItem(id: t['id'] ?? '', name: (t['name'] ?? '').trim(), short: (t['short'] ?? '').trim());
  return AscFile(
    teachers: [for (final t in _elements(xml, 'teacher')) item(t)],
    subjects: [for (final t in _elements(xml, 'subject')) item(t)],
    classes: [for (final t in _elements(xml, 'class')) item(t)],
    lessons: [
      for (final l in _elements(xml, 'lesson'))
        AscLesson(
          teacherIds: _ids(l['teacherids']),
          subjectId: l['subjectid'] ?? '',
          classIds: _ids(l['classids']),
          periods: double.tryParse(l['periodsperweek'] ?? '') ?? 0,
        ),
    ],
  );
}

/// الاسم للمطابقة: بلا تشكيل ولا «ال» التعريف، والهمزات والتاء المربوطة موحّدة — `normName`.
String normName(String s) => s
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w.length > 3 && w.startsWith('ال') ? w.substring(2) : w)
    .join(' ')
    .toLowerCase();

/// مطابقة بالاسم كاملاً، ثم بالاحتواء إن كانت وحيدة — `matchBy`.
T? _matchBy<T>(String name, Iterable<T> list, String Function(T) nameOf) {
  final n = normName(name);
  if (n.isEmpty) return null;
  final exact = [for (final x in list) if (normName(nameOf(x)) == n) x];
  if (exact.length == 1) return exact.first;
  final near = [
    for (final x in list)
      if (normName(nameOf(x)).isNotEmpty && (normName(nameOf(x)).contains(n) || n.contains(normName(nameOf(x))))) x,
  ];
  return near.length == 1 ? near.first : null;
}

class AscTeacherRow {
  const AscTeacherRow({
    required this.ascName,
    required this.periods,
    required this.teacher,
    required this.subjectIds,
    required this.missingSubjects,
  });

  final String ascName;
  final int periods;
  final Teacher? teacher;

  /// مواد المدرسة المطابقة لمواد المعلم في الجدول.
  final List<String> subjectIds;

  /// مواد في الجدول بلا مقابل في المدرسة.
  final List<String> missingSubjects;
}

SubjectItem? _matchSubject(AscItem s, Iterable<SubjectItem> subjects) =>
    _matchBy<SubjectItem>(s.name, subjects, (x) => x.name) ??
    (s.short.isEmpty ? null : _matchBy<SubjectItem>(s.short, subjects, (x) => x.name));

List<AscTeacherRow> planAscImport(AscFile file, Iterable<Teacher> teachers, Iterable<SubjectItem> subjects) {
  final ascSubject = {for (final s in file.subjects) s.id: s};
  final subjectMatch = {for (final s in file.subjects) s.id: _matchSubject(s, subjects)};
  final rows = <AscTeacherRow>[];
  for (final t in file.teachers) {
    final mine = file.lessons.where((l) => l.teacherIds.contains(t.id)).toList();
    final subjectIds = <String>{};
    final missing = <String>{};
    for (final l in mine) {
      final m = subjectMatch[l.subjectId];
      if (m != null) {
        subjectIds.add(m.id);
      } else if (ascSubject[l.subjectId] != null) {
        missing.add(ascSubject[l.subjectId]!.name);
      }
    }
    final periods = mine.fold<double>(0, (a, l) => a + l.periods).round();
    if (periods <= 0) continue;
    rows.add(AscTeacherRow(
      ascName: t.name.isEmpty ? t.short : t.name,
      periods: periods,
      teacher: _matchBy<Teacher>(t.name, teachers, (x) => x.name),
      subjectIds: subjectIds.toList(),
      missingSubjects: missing.toList(),
    ));
  }
  return rows;
}

/// حصص كل مادة في كل شعبة من دروس الجدول، على مجموعة المادة في الشعبة — `planAscPeriods`.
List<({String groupId, int periods})> planAscPeriods(
  AscFile file,
  Iterable<Teacher> teachers,
  Iterable<SubjectItem> subjects,
  Iterable<Classroom> rooms,
  Iterable<Group> groups,
) {
  final roomNames = [
    for (final r in rooms) (name: [r.gradeLevel, r.name].where((x) => x.isNotEmpty).join(' '), room: r),
  ];
  final teacherOf = {for (final t in file.teachers) t.id: _matchBy<Teacher>(t.name, teachers, (x) => x.name)};
  final subjectOf = {for (final s in file.subjects) s.id: _matchSubject(s, subjects)};
  Classroom? roomMatch(AscItem c) {
    final byName = _matchBy(c.name, roomNames, (x) => x.name);
    if (byName != null) return byName.room;
    return c.short.isEmpty ? null : _matchBy(c.short, roomNames, (x) => x.name)?.room;
  }

  final roomOf = {for (final c in file.classes) c.id: roomMatch(c)};
  final byGroup = <String, Map<String, double>>{};
  for (final l in file.lessons) {
    final subject = subjectOf[l.subjectId];
    if (subject == null) continue;
    for (final tid in l.teacherIds) {
      final teacher = teacherOf[tid];
      if (teacher == null) continue;
      for (final cid in l.classIds) {
        final room = roomOf[cid];
        if (room == null) continue;
        final group = groups
            .where((g) =>
                g.status != 'archived' &&
                g.teacherId == teacher.id &&
                g.subjectId == subject.id &&
                (g.roomId == room.id || g.roomIds.contains(room.id)))
            .firstOrNull;
        if (group == null) continue;
        final perRoom = byGroup.putIfAbsent(group.id, () => {});
        perRoom[room.id] = (perRoom[room.id] ?? 0) + l.periods;
      }
    }
  }
  // مجموعة مشتركة بين شعب: حصص الشعبة الواحدة (الأكثر إن اختلفت)
  return [
    for (final e in byGroup.entries)
      if (e.value.values.reduce(math.max).round() > 0)
        (groupId: e.key, periods: e.value.values.reduce(math.max).round()),
  ];
}
