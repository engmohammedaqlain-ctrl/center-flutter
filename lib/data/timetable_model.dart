/// منطق الجدول الصافي — المقابل لـ `types/timetable.ts` و`timetableModel.ts` و`generate.ts` و`covers.ts`:
/// الأيام والحصص، الدروس من الإسناد، فحص التعارض لخانة، والاحتياط. بلا شبكة ولا واجهة.
library;

import '../models/models.dart';
import 'timetable_solver.dart';

const dayNames = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/// الأسبوع المدرسي يبدأ السبت.
const _weekOrder = [6, 0, 1, 2, 3, 4, 5];

/// أيام الدوام بترتيب الأسبوع (ترقيم getDay).
List<int> schoolDays(List<int> weekend) => [
      for (final d in _weekOrder)
        if (!weekend.contains(d)) d,
    ];

/// اليوم بترقيم getDay من تاريخ.
int jsDay(DateTime d) => d.weekday % 7;

class BellPeriod {
  const BellPeriod(this.start, this.end);

  final String start;
  final String end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

final _timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

String addMinutes(String time, int minutes) {
  final p = time.split(':');
  final t = int.parse(p[0]) * 60 + int.parse(p[1]) + minutes;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two((t ~/ 60) % 24)}:${two(t % 60)}';
}

/// سبع حصص من 45 دقيقة تبدأ 7:30، واستراحة 20 دقيقة بعد الرابعة.
List<BellPeriod> _defaultBell() {
  final out = <BellPeriod>[];
  var t = '07:30';
  for (var i = 1; i <= 7; i++) {
    final end = addMinutes(t, 45);
    out.add(BellPeriod(t, end));
    t = i == 4 ? addMinutes(end, 20) : end;
  }
  return out;
}

/// أوقات الحصص وحد الاحتياط — `TimetableSettings` في `settings.timetable`.
class TimetableSettings {
  const TimetableSettings({
    required this.periods,
    required this.breaksAfter,
    required this.dayPeriods,
    required this.coverDailyMax,
  });

  final List<BellPeriod> periods;
  final List<int> breaksAfter;

  /// يوم بحصص أقل من غيره: getDay ← عدد حصصه.
  final Map<String, int> dayPeriods;
  final int coverDailyMax;

  /// `normalizeTimetableSettings`.
  factory TimetableSettings.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final periods = <BellPeriod>[
      if (m['periods'] is List)
        for (final p in m['periods'] as List)
          if (p is Map && _timeRe.hasMatch('${p['start']}') && _timeRe.hasMatch('${p['end']}'))
            BellPeriod('${p['start']}', '${p['end']}'),
    ];
    final kept = periods.take(12).toList();
    final bell = kept.isEmpty ? _defaultBell() : kept;
    final count = bell.length;
    final dayPeriods = <String, int>{};
    if (m['day_periods'] is Map) {
      (m['day_periods'] as Map).forEach((k, v) {
        final d = int.tryParse('$k');
        final c = v is num ? v.floor() : int.tryParse('$v');
        if (d != null && d >= 0 && d <= 6 && c != null && c >= 1 && c < count) dayPeriods['$d'] = c;
      });
    }
    final rawMax = m['cover_daily_max'];
    final cover = rawMax is num ? rawMax.floor() : int.tryParse('$rawMax');
    return TimetableSettings(
      periods: bell,
      breaksAfter: m['breaks_after'] is List
          ? ({
              for (final n in m['breaks_after'] as List)
                if (n is num && n == n.floor() && n >= 1 && n < count) n.toInt(),
            }.toList()
            ..sort())
          : [
              for (final n in const [4])
                if (n < count) n,
            ],
      dayPeriods: dayPeriods,
      coverDailyMax: cover != null && cover >= 0 && cover <= 8 ? cover : 2,
    );
  }

  Map<String, dynamic> toJson() => {
        'periods': [for (final p in periods) p.toJson()],
        'breaks_after': breaksAfter,
        'day_periods': dayPeriods,
        'cover_daily_max': coverDailyMax,
      };

  int periodsOn(int day) => dayPeriods['$day'] ?? periods.length;
}

/// حصة موضوعة — `[الشعبة، اليوم، الحصة، الإسناد، مثبتة]`: مصفوفة في السحابة، عقد مشترك مع الويب.
class TimetableEntry {
  const TimetableEntry(this.roomId, this.day, this.period, this.groupId, {this.locked = false});

  final String roomId;
  final int day;
  final int period;
  final String groupId;
  final bool locked;

  static TimetableEntry? fromJson(Object? raw) {
    if (raw is! List || raw.length < 4) return null;
    final day = raw[1] is num ? (raw[1] as num).toInt() : int.tryParse('${raw[1]}');
    final period = raw[2] is num ? (raw[2] as num).toInt() : int.tryParse('${raw[2]}');
    if (day == null || period == null) return null;
    final lock = raw.length > 4 ? raw[4] : 0;
    return TimetableEntry('${raw[0]}', day, period, '${raw[3]}', locked: lock == 1 || lock == true);
  }

  List<Object> toJson() => [roomId, day, period, groupId, if (locked) 1 else 0];

  bool same(TimetableEntry o) => roomId == o.roomId && day == o.day && period == o.period && groupId == o.groupId;

  TimetableEntry copyWith({int? day, int? period, bool? locked}) =>
      TimetableEntry(roomId, day ?? this.day, period ?? this.period, groupId, locked: locked ?? this.locked);
}

List<TimetableEntry> entriesFromJson(Object? raw) => [
      if (raw is List)
        for (final e in raw)
          if (TimetableEntry.fromJson(e) case final entry?) entry,
    ];

/// خانة في الأسبوع: `<اليوم>:<الحصة>`، و`<اليوم>:*` لليوم كله.
String slotKey(int day, Object period) => '$day:$period';

/// القيود في `timetables.rules`: تبقى خريطة JSON كما يكتبها الويب، وهذه قراءتها.
class TimetableRules {
  const TimetableRules(this.raw);

  factory TimetableRules.fromMap(Object? m) =>
      TimetableRules(m is Map ? Map<String, dynamic>.from(m) : const <String, dynamic>{});

  final Map<String, dynamic> raw;

  List<String> _slots(String key, String id) {
    final map = raw[key];
    final list = map is Map ? map[id] : null;
    return list is List ? [for (final s in list) '$s'] : const [];
  }

  List<String> teacherOffOf(String id) => _slots('teacher_off', id);
  List<String> roomOffOf(String id) => _slots('room_off', id);

  bool _off(List<String> list, int day, int period) => list.contains(slotKey(day, period)) || list.contains(slotKey(day, '*'));

  bool teacherOff(String id, int day, int period) => id.isNotEmpty && _off(teacherOffOf(id), day, period);
  bool roomOff(String id, int day, int period) => _off(roomOffOf(id), day, period);

  int teacherMaxOf(String id) {
    final map = raw['teacher_max_per_day'];
    final v = map is Map ? map[id] : null;
    return v is num ? v.toInt() : 0;
  }

  Map<String, dynamic> lessonOf(String groupId) {
    final map = raw['lessons'];
    final v = map is Map ? map[groupId] : null;
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  List<Map<String, dynamic>> get facilities => [
        if (raw['facilities'] is List)
          for (final f in raw['facilities'] as List)
            if (f is Map) Map<String, dynamic>.from(f),
      ];

  bool get homeroomFirst => raw['homeroom_first'] == true;
  bool get noDoubleAcrossBreak => raw['no_double_across_break'] == true;

  /// نسخة بمفتاح جديد، والقيمة `null` تحذفه.
  TimetableRules withKey(String key, Object? value) {
    final next = {...raw};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return TimetableRules(next);
  }

  /// خريطة تحت مفتاح بعد تعديل عنصر فيها؛ `null` يحذفه.
  TimetableRules withEntry(String key, String id, Object? value) {
    final map = raw[key] is Map ? Map<String, dynamic>.from(raw[key] as Map) : <String, dynamic>{};
    if (value == null) {
      map.remove(id);
    } else {
      map[id] = value;
    }
    return withKey(key, map);
  }
}

/// درس مطلوب: مادة إسناد في شعبة واحدة بعدد حصصها الأسبوعية.
class Lesson {
  const Lesson({required this.groupId, required this.roomId, required this.subjectId, required this.teacherId, required this.count});

  final String groupId;
  final String roomId;
  final String subjectId;
  final String teacherId;
  final int count;
}

String lessonKeyOf(String groupId, String roomId) => '$groupId|$roomId';

// ── ترتيب المدرسة — `schoolOrder.ts` ──

const _gradeSteps = ['تمهيدي', 'روضه', 'بستان', 'اول', 'ثاني', 'ثالث', 'رابع', 'خامس', 'سادس', 'سابع', 'ثامن', 'تاسع', 'عاشر'];

/// رتبة المرحلة في السلم الدراسي: «العاشر» و«عاشر» و«الصف الأول» تُفهم مرحلة واحدة.
int gradeRank(String grade) {
  final g = grade
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAllMapped(RegExp(r'(^|\s)ال'), (m) => m[1] ?? '')
      .replaceAll(RegExp(r'صف\s*'), '')
      .trim();
  if (RegExp(r'حادي\s*عشر').hasMatch(g)) return 13;
  if (RegExp(r'ثاني\s*عشر').hasMatch(g)) return 14;
  final i = _gradeSteps.indexWhere(g.startsWith);
  return i < 0 ? 99 : i;
}

String _sectionKey(String name) =>
    name.replaceAll(RegExp(r'شعبة|شعبه|[()\-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// مقارنة طبيعية: 2 قبل 10، وأ قبل ب.
int _natural(String a, String b) {
  final x = RegExp(r'\d+|\D+').allMatches(a).map((m) => m[0]!).toList();
  final y = RegExp(r'\d+|\D+').allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = int.tryParse(x[i]);
    final ny = int.tryParse(y[i]);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

int compareSchoolRooms(Classroom a, Classroom b) {
  final g = gradeRank(a.gradeLevel.trim()) - gradeRank(b.gradeLevel.trim());
  if (g != 0) return g;
  final n = _natural(a.gradeLevel.trim(), b.gradeLevel.trim());
  if (n != 0) return n;
  return _natural(_sectionKey(a.name), _sectionKey(b.name));
}

/// رمز الشعبة القصير في الجداول العامة: `4/3` (المرحلة/ترتيب الشعبة فيها)، والروضة `k1`.
Map<String, String> roomCodes(List<Classroom> rooms) {
  final out = <String, String>{};
  final seen = <int, int>{};
  var kg = 0;
  final sorted = [...rooms]..sort((a, b) {
      final g = gradeRank(a.gradeLevel) - gradeRank(b.gradeLevel);
      if (g != 0) return g;
      final s = _natural(_sectionKey(a.name), _sectionKey(b.name));
      return s != 0 ? s : compareSchoolRooms(a, b);
    });
  for (final r in sorted) {
    final rank = gradeRank(r.gradeLevel);
    if (rank <= 2) {
      out[r.id] = 'k${++kg}';
    } else if (rank == 99) {
      out[r.id] = [r.gradeLevel, r.name].where((s) => s.isNotEmpty).join(' ');
    } else {
      final n = (seen[rank] ?? 0) + 1;
      seen[rank] = n;
      out[r.id] = '${rank - 2}/$n';
    }
  }
  return out;
}

int _weekly(double? v) => v == null || v.isNaN || v < 0 ? 0 : v.floor();

/// الدروس من الإسناد الفعّال: لكل شعبة من شعبه درس بحصصه الأسبوعية — `buildLessons`.
List<Lesson> buildLessons(List<Group> groups, List<Classroom> rooms) {
  final ids = {for (final r in rooms) r.id};
  return [
    for (final g in groups)
      if (g.status != 'archived')
        for (final roomId in g.allRoomIds)
          if (ids.contains(roomId))
            Lesson(groupId: g.id, roomId: roomId, subjectId: g.subjectId, teacherId: g.teacherId, count: _weekly(g.weeklyPeriods)),
  ];
}

/// الحد اليومي للمادة في الشعبة: المحدد، وإلا واحدة ما لم تزد حصصها على الأيام — `dailyLimit`.
int dailyLimit(TimetableRules rules, String groupId, int count, int days) {
  final rule = rules.lessonOf(groupId);
  final set = rule['max_per_day'];
  if (set is num && set > 0) return set.toInt();
  final d = days < 1 ? 1 : days;
  final c = (count / d).ceil();
  final base = c < 1 ? 1 : c;
  return rule['double'] == true ? (base * 2 < 2 ? 2 : base * 2) : base;
}

class PlanContext {
  const PlanContext({required this.groups, required this.rules, required this.settings, required this.days});

  final Map<String, Group> groups;
  final TimetableRules rules;
  final TimetableSettings settings;
  final List<int> days;
}

/// تعارض وضع حصة في خانة — `Conflict`.
class Conflict {
  const Conflict(this.kind, {this.groupId = '', this.roomId = ''});

  final String kind;
  final String groupId;
  final String roomId;
}

/// تعارضات وضع حصة في خانة، مع تجاهل حصص بعينها (التي تُنقل معها) — `conflictsAt`.
List<Conflict> conflictsAt(
  PlanContext ctx,
  List<TimetableEntry> entries,
  String roomId,
  String groupId,
  int day,
  int period, {
  Set<TimetableEntry> ignore = const {},
}) {
  if (!ctx.days.contains(day) || period < 1 || period > ctx.settings.periodsOn(day)) return const [Conflict('outside')];
  final out = <Conflict>[];
  if (ctx.rules.roomOff(roomId, day, period)) out.add(const Conflict('room_off'));
  final group = ctx.groups[groupId];
  final teacherId = group?.teacherId ?? '';
  if (ctx.rules.teacherOff(teacherId, day, period)) out.add(const Conflict('teacher_off'));

  final facilityId = '${ctx.rules.lessonOf(groupId)['facility_id'] ?? ''}';
  final facility = facilityId.isEmpty ? null : ctx.rules.facilities.where((f) => f['id'] == facilityId).firstOrNull;
  var facilityUse = 0;
  var sameDay = 0;
  for (final e in entries) {
    if (ignore.contains(e)) continue;
    if (e.day == day && e.roomId == roomId && e.groupId == groupId) sameDay++;
    if (e.day != day || e.period != period) continue;
    if (e.roomId == roomId) {
      out.add(Conflict('room_busy', groupId: e.groupId));
    } else if (teacherId.isNotEmpty && ctx.groups[e.groupId]?.teacherId == teacherId) {
      // ومنه الإسناد نفسه في شعبة أخرى: المعلم واحد
      out.add(Conflict('teacher_busy', roomId: e.roomId, groupId: e.groupId));
    }
    if (facility != null && ctx.rules.lessonOf(e.groupId)['facility_id'] == facilityId) facilityUse++;
  }
  if (facility != null) {
    final cap = facility['capacity'] is num ? (facility['capacity'] as num).toInt() : 1;
    if (facilityUse >= (cap < 1 ? 1 : cap)) out.add(const Conflict('facility'));
  }
  final count = _weekly(group?.weeklyPeriods);
  if (sameDay >= dailyLimit(ctx.rules, groupId, count, ctx.days.length)) out.add(const Conflict('day_limit'));
  return out;
}

String conflictText(Conflict c, {required String Function(String) room, required String Function(String) subject}) => switch (c.kind) {
      'outside' => 'خارج حصص اليوم',
      'room_off' => 'خارج دوام الشعبة',
      'teacher_off' => 'المعلم غير متاح',
      'room_busy' => 'الشعبة: ${subject(c.groupId)}',
      'teacher_busy' => 'المعلم في ${room(c.roomId)}',
      'facility' => 'المرفق مشغول',
      _ => 'حد المادة في اليوم',
    };

/// الحصص الموضوعة لكل درس.
Map<String, int> placedCounts(List<TimetableEntry> entries) {
  final out = <String, int>{};
  for (final e in entries) {
    final k = lessonKeyOf(e.groupId, e.roomId);
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

/// خانات الأسبوع خارج ما أُغلق — `slotsFor`.
int slotsFor(List<int> days, TimetableSettings settings, bool Function(int day, int period) offOf) {
  var n = 0;
  for (final d in days) {
    for (var p = 1; p <= settings.periodsOn(d); p++) {
      if (!offOf(d, p)) n++;
    }
  }
  return n;
}

Map<String, int> teacherLoads(List<Lesson> lessons) {
  final out = <String, int>{};
  for (final l in lessons) {
    if (l.teacherId.isNotEmpty) out[l.teacherId] = (out[l.teacherId] ?? 0) + l.count;
  }
  return out;
}

Map<String, int> roomLoads(List<Lesson> lessons) {
  final out = <String, int>{};
  for (final l in lessons) {
    out[l.roomId] = (out[l.roomId] ?? 0) + l.count;
  }
  return out;
}

/// إسقاط ما لم يعد صالحاً: إسناد حُذف أو شعبة خرجت منه، أو خانة خارج الأيام والحصص — `pruneEntries`.
List<TimetableEntry> pruneEntries(List<TimetableEntry> entries, List<Lesson> lessons, List<int> days, TimetableSettings settings) {
  final valid = {for (final l in lessons) lessonKeyOf(l.groupId, l.roomId)};
  return [
    for (final e in entries)
      if (valid.contains(lessonKeyOf(e.groupId, e.roomId)) && days.contains(e.day) && e.period >= 1 && e.period <= settings.periodsOn(e.day)) e,
  ];
}

// ── من بيانات المدرسة إلى المولِّد — `generate.ts` ──

List<SolverSlot> _toSlots(List<String> keys, List<int> days, TimetableSettings settings) {
  final out = <SolverSlot>[];
  for (final k in keys) {
    final parts = k.split(':');
    if (parts.length != 2) continue;
    final day = int.tryParse(parts[0]);
    if (day == null || !days.contains(day)) continue;
    if (parts[1] == '*') {
      for (var i = 1; i <= settings.periodsOn(day); i++) {
        out.add(SolverSlot(day, i));
      }
    } else if (int.tryParse(parts[1]) case final p?) {
      out.add(SolverSlot(day, p));
    }
  }
  return out;
}

/// مدخلات المولِّد. المثبَّت يبقى مكانه ويُحسب من حصص إسناده — `toSolverInput`.
SolverInput toSolverInput({
  required List<int> days,
  required TimetableSettings settings,
  required TimetableRules rules,
  required List<Classroom> rooms,
  required List<Teacher> teachers,
  required List<Lesson> lessons,
  required List<TimetableEntry> entries,
  required int seed,
  int timeLimitMs = 15000,
}) {
  return SolverInput(
    days: days,
    periodsPerDay: {for (final d in days) d: settings.periodsOn(d)},
    breakAfter: settings.breaksAfter,
    rooms: [
      for (final r in rooms)
        SolverRoom(
          id: r.id,
          name: [r.gradeLevel, r.name].where((s) => s.isNotEmpty).join(' '),
          homeroomTeacherId: r.teacherId.isEmpty ? null : r.teacherId,
          off: _toSlots(rules.roomOffOf(r.id), days, settings),
        ),
    ],
    teachers: [
      for (final t in teachers)
        SolverTeacher(
          id: t.id,
          name: t.name,
          off: _toSlots(rules.teacherOffOf(t.id), days, settings),
          maxPerDay: rules.teacherMaxOf(t.id) > 0 ? rules.teacherMaxOf(t.id) : null,
        ),
    ],
    facilities: [
      for (final f in rules.facilities)
        SolverFacility(
          id: '${f['id']}',
          name: '${f['name'] ?? ''}',
          capacity: f['capacity'] is num && (f['capacity'] as num) >= 1 ? (f['capacity'] as num).toInt() : 1,
        ),
    ],
    lessons: [
      for (final l in lessons)
        if (l.count > 0)
          () {
            final rule = rules.lessonOf(l.groupId);
            final max = rule['max_per_day'];
            final fac = '${rule['facility_id'] ?? ''}';
            return SolverLesson(
              groupId: l.groupId,
              roomId: l.roomId,
              subjectId: l.subjectId,
              teacherId: l.teacherId,
              count: l.count,
              isDouble: rule['double'] == true,
              maxPerDay: max is num && max > 0 ? max.toInt() : null,
              facilityId: fac.isEmpty ? null : fac,
            );
          }(),
    ],
    locked: [
      for (final e in entries)
        if (e.locked) SolverEntry(roomId: e.roomId, day: e.day, period: e.period, groupId: e.groupId, locked: true),
    ],
    homeroomFirst: rules.homeroomFirst,
    noDoubleAcrossBreak: rules.noDoubleAcrossBreak,
    seed: seed,
    timeLimitMs: timeLimitMs,
  );
}

/// حصص الجدول من ناتج المولِّد، والمثبَّت يبقى مثبَّتاً — `fromSolverResult`.
List<TimetableEntry> fromSolverResult(SolverResult result) => [
      for (final e in result.entries) TimetableEntry(e.roomId, e.day, e.period, e.groupId, locked: e.locked),
    ];

const issueLabels = <String, String>{
  'CLASS_FULL': 'حصص الشعبة أكثر من خاناتها',
  'TEACHER_FULL': 'حصص المعلم أكثر من خاناته المتاحة',
  'NO_COMMON_SLOT': 'خانات المعلم والشعبة المشتركة أقل من المطلوب',
  'FACILITY': 'المرفق لا يتسع لحصصه',
  'DAY_LIMIT': 'حد اليوم أقل من الحصص',
  'DOUBLE': 'لا خانتان متتاليتان للمزدوجة',
};

// ── الاحتياط — `covers.ts` ──

/// حصة معلم غائب في يوم، ومن يغطيها — `TimetableCover`.
class TimetableCover {
  const TimetableCover({
    required this.date,
    required this.period,
    required this.roomId,
    this.groupId = '',
    required this.absentTeacherId,
    this.coverTeacherId = '',
  });

  factory TimetableCover.fromMap(Map<String, dynamic> m) => TimetableCover(
        date: '${m['date'] ?? ''}'.padRight(10).substring(0, 10).trim(),
        period: m['period'] is num ? (m['period'] as num).toInt() : int.tryParse('${m['period']}') ?? 0,
        roomId: '${m['room_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        absentTeacherId: '${m['absent_teacher_id'] ?? ''}',
        coverTeacherId: '${m['cover_teacher_id'] ?? ''}',
      );

  final String date;
  final int period;
  final String roomId;
  final String groupId;
  final String absentTeacherId;
  final String coverTeacherId;
}

class CoverSlot {
  const CoverSlot({required this.period, required this.roomId, required this.groupId, required this.absentTeacherId});

  final int period;
  final String roomId;
  final String groupId;
  final String absentTeacherId;

  String get key => '$period|$roomId';
}

class CoverInput {
  const CoverInput({
    required this.day,
    required this.entries,
    required this.groups,
    required this.teachers,
    required this.rules,
    required this.absent,
    required this.today,
    required this.monthCount,
    required this.dailyMax,
  });

  final int day;
  final List<TimetableEntry> entries;
  final Map<String, Group> groups;
  final List<Teacher> teachers;
  final TimetableRules rules;
  final Set<String> absent;
  final List<({int period, String roomId, String coverId})> today;
  final Map<String, int> monthCount;
  final int dailyMax;

  CoverInput withToday(List<({int period, String roomId, String coverId})> next) => CoverInput(
        day: day,
        entries: entries,
        groups: groups,
        teachers: teachers,
        rules: rules,
        absent: absent,
        today: next,
        monthCount: monthCount,
        dailyMax: dailyMax,
      );
}

/// حصص الغائبين في اليوم بترتيبها — `absentSlots`.
List<CoverSlot> absentSlots(int day, List<TimetableEntry> entries, Map<String, Group> groups, Set<String> absent) {
  final out = <CoverSlot>[
    for (final e in entries)
      if (e.day == day && absent.contains(groups[e.groupId]?.teacherId ?? ''))
        CoverSlot(period: e.period, roomId: e.roomId, groupId: e.groupId, absentTeacherId: groups[e.groupId]!.teacherId),
  ];
  out.sort((a, b) {
    final p = a.period.compareTo(b.period);
    return p != 0 ? p : a.roomId.compareTo(b.roomId);
  });
  return out;
}

/// المرشحون لحصة بترتيبهم: من يدرّس المادة، ثم من يدرّس الشعبة، ثم الأقل احتياطاً هذا الشهر،
/// ثم الأقل حصصاً في اليوم — `coverCandidates`.
List<String> coverCandidates(CoverInput input, CoverSlot slot) {
  final subjectId = input.groups[slot.groupId]?.subjectId ?? '';
  int covering(String id, [int? period]) => input.today
      .where((c) => c.coverId == id && !(c.period == slot.period && c.roomId == slot.roomId) && (period == null || c.period == period))
      .length;
  int dayLoad(String id) => input.entries.where((e) => e.day == input.day && input.groups[e.groupId]?.teacherId == id).length;
  bool teachesRoom(String id) => input.entries.any((e) => e.roomId == slot.roomId && input.groups[e.groupId]?.teacherId == id);
  bool teaching(String id) =>
      input.entries.any((e) => e.day == input.day && e.period == slot.period && input.groups[e.groupId]?.teacherId == id);

  final scored = <({String id, List<int> score})>[
    for (final t in input.teachers)
      if (!input.absent.contains(t.id) &&
          !teaching(t.id) &&
          !input.rules.teacherOff(t.id, input.day, slot.period) &&
          covering(t.id, slot.period) == 0 &&
          covering(t.id) < input.dailyMax)
        (
          id: t.id,
          score: [
            t.subjectIds.contains(subjectId) ? 0 : 1,
            teachesRoom(t.id) ? 0 : 1,
            (input.monthCount[t.id] ?? 0) + covering(t.id),
            dayLoad(t.id),
          ],
        ),
  ];
  scored.sort((a, b) {
    for (var i = 0; i < a.score.length; i++) {
      if (a.score[i] != b.score[i]) return a.score[i] - b.score[i];
    }
    return 0;
  });
  return [for (final s in scored) s.id];
}

/// «توزيع»: أفضل مرشح لكل حصة بلا بديل، بالتتابع حتى لا يأخذ معلم حصتين في وقت واحد — `autoAssign`.
Map<String, String> autoAssign(CoverInput input, List<CoverSlot> slots) {
  final out = <String, String>{};
  final today = [...input.today];
  for (final slot in slots) {
    final i = today.indexWhere((c) => c.period == slot.period && c.roomId == slot.roomId);
    if (i >= 0 && today[i].coverId.isNotEmpty) continue;
    final list = coverCandidates(input.withToday(today), slot);
    if (list.isEmpty) continue;
    out[slot.key] = list.first;
    final row = (period: slot.period, roomId: slot.roomId, coverId: list.first);
    if (i >= 0) {
      today[i] = row;
    } else {
      today.add(row);
    }
  }
  return out;
}
