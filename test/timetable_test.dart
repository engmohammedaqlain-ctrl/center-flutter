import 'package:center_mobile/data/timetable_model.dart';
import 'package:center_mobile/data/timetable_solver.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Classroom room(String id, {String grade = 'السابع', String homeroom = ''}) =>
    Classroom.fromCloud({'id': id, 'name': id, 'grade_level': grade, 'homeroom_teacher_id': homeroom});

Group group(String id, String teacher, List<String> rooms, int periods, {String? subject}) => Group.fromCloud({
      'id': id,
      'name': id,
      'subject_id': subject ?? 's-$id',
      'teacher_id': teacher,
      'room_ids': rooms,
      'status': 'active',
      'weekly_periods': periods,
    });

Teacher teacher(String id, {List<String> subjects = const []}) =>
    Teacher.fromCloud({'id': id, 'name': id, 'phone': '', 'subject': '', 'subject_ids': subjects});

SolverInput input({
  List<int> days = const [6, 0, 1, 2, 3],
  int periods = 6,
  List<int> breakAfter = const [3],
  required List<SolverRoom> rooms,
  required List<SolverTeacher> teachers,
  required List<SolverLesson> lessons,
  List<SolverFacility> facilities = const [],
  List<SolverEntry> locked = const [],
  bool noDoubleAcrossBreak = false,
  int seed = 1,
}) =>
    SolverInput(
      days: days,
      periodsPerDay: {for (final d in days) d: periods},
      breakAfter: breakAfter,
      rooms: rooms,
      teachers: teachers,
      facilities: facilities,
      lessons: lessons,
      locked: locked,
      homeroomFirst: false,
      noDoubleAcrossBreak: noDoubleAcrossBreak,
      seed: seed,
      timeLimitMs: 20000,
    );

SolverLesson lesson(String g, String r, String t, int count, {bool dbl = false, String? fac}) =>
    SolverLesson(groupId: g, roomId: r, subjectId: 's-$g', teacherId: t, count: count, isDouble: dbl, facilityId: fac);

/// فاحص مستقل عن المولِّد: كل خرق لقيد لازم يُرجع نصاً.
List<String> violations(SolverInput inp, SolverResult res) {
  final out = <String>[];
  final byKey = {for (final l in inp.lessons) '${l.groupId}|${l.roomId}': l};
  final roomOff = {for (final r in inp.rooms) for (final o in r.off) '${r.id}|${o.day}|${o.period}'};
  final teacherOff = {for (final t in inp.teachers) for (final o in t.off) '${t.id}|${o.day}|${o.period}'};
  final cap = {for (final f in inp.facilities) f.id: f.capacity};
  final roomAt = <String>{};
  final teacherAt = <String>{};
  final facAt = <String, int>{};
  final per = <String, int>{};
  for (final e in res.entries) {
    if (!inp.days.contains(e.day) || e.period < 1 || e.period > inp.periodsPerDay[e.day]!) out.add('خانة غير موجودة');
    final rk = '${e.roomId}|${e.day}|${e.period}';
    if (!roomAt.add(rk)) out.add('تعارض شعبة $rk');
    final l = byKey['${e.groupId}|${e.roomId}'];
    if (l == null) continue;
    final tk = '${l.teacherId}|${e.day}|${e.period}';
    if (!teacherAt.add(tk)) out.add('تعارض معلم $tk');
    if (!e.locked && roomOff.contains(rk)) out.add('شعبة في إجازة $rk');
    if (!e.locked && teacherOff.contains(tk)) out.add('معلم في إجازة $tk');
    if (l.facilityId != null && cap.containsKey(l.facilityId)) {
      final fk = '${l.facilityId}|${e.day}|${e.period}';
      facAt[fk] = (facAt[fk] ?? 0) + 1;
      if (facAt[fk]! > cap[l.facilityId]!) out.add('سعة مرفق $fk');
    }
    final key = '${e.groupId}|${e.roomId}';
    per[key] = (per[key] ?? 0) + 1;
  }
  final unplaced = {for (final u in res.unplaced) '${u.groupId}|${u.roomId}': u.count};
  for (final l in inp.lessons) {
    final key = '${l.groupId}|${l.roomId}';
    if ((per[key] ?? 0) + (unplaced[key] ?? 0) != l.count) out.add('عدد حصص $key');
  }
  return out;
}

void main() {
  test('الأسبوع يبدأ السبت ويُسقط العطلة', () {
    expect(schoolDays(const [5]), [6, 0, 1, 2, 3, 4]);
    expect(schoolDays(const [5, 6]), [0, 1, 2, 3, 4]);
  });

  test('درس لكل شعبة من شعب الإسناد بحصصه، والمؤرشف خارجها', () {
    final groups = [group('math', 't1', ['a', 'b'], 5), group('arab', 't2', ['a'], 6)];
    final out = buildLessons(groups, [room('a'), room('b')]).map((l) => '${l.groupId}|${l.roomId}|${l.count}').toList()..sort();
    expect(out, ['arab|a|6', 'math|a|5', 'math|b|5']);
  });

  test('رمز الشعبة: المرحلة/ترتيب الشعبة، والروضة k، والمجهولة باسمها', () {
    final list = [
      Classroom.fromCloud({'id': 'r4c', 'grade_level': 'الرابع', 'name': 'شعبة (ج)'}),
      Classroom.fromCloud({'id': 'r4a', 'grade_level': 'رابع', 'name': 'شعبة (أ)'}),
      Classroom.fromCloud({'id': 'r1b', 'grade_level': 'الصف الأول', 'name': 'ب'}),
      Classroom.fromCloud({'id': 'r1a', 'grade_level': 'الصف الأول', 'name': 'أ'}),
      Classroom.fromCloud({'id': 'kg2', 'grade_level': 'بستان', 'name': 'الورود'}),
      Classroom.fromCloud({'id': 'kg1', 'grade_level': 'روضة', 'name': 'الزهور'}),
      Classroom.fromCloud({'id': 'r11', 'grade_level': 'الحادي عشر', 'name': 'علمي'}),
      Classroom.fromCloud({'id': 'x', 'grade_level': 'تأسيسي', 'name': 'خاص'}),
    ];
    expect(roomCodes(list), {
      'kg1': 'k1',
      'kg2': 'k2',
      'r1a': '1/1',
      'r1b': '1/2',
      'r4a': '4/1',
      'r4c': '4/2',
      'r11': '11/1',
      'x': 'تأسيسي خاص',
    });
  });

  test('الحصة بصيغة الويب: مصفوفة بخمسة عناصر، والرابعة وحدها مقبولة', () {
    final e = TimetableEntry.fromJson(['a', 6, 2, 'g', 1])!;
    expect([e.roomId, e.day, e.period, e.groupId, e.locked], ['a', 6, 2, 'g', true]);
    expect(TimetableEntry.fromJson(['a', 6, 2, 'g'])!.locked, false);
    expect(e.toJson(), ['a', 6, 2, 'g', 1]);
  });

  test('تعارض الخانة: الشعبة والمعلم وخارج الحصص وحد اليوم', () {
    final groups = [group('math', 't1', ['a', 'b'], 5), group('arab', 't2', ['a'], 6)];
    final ctx = PlanContext(
      groups: {for (final g in groups) g.id: g},
      rules: const TimetableRules({}),
      settings: TimetableSettings.fromMap({'day_periods': {'4': 5}}),
      days: schoolDays(const [5]),
    );
    final entries = [const TimetableEntry('a', 6, 1, 'math'), const TimetableEntry('b', 6, 2, 'math')];
    expect(conflictsAt(ctx, entries, 'a', 'arab', 6, 1).map((c) => c.kind), ['room_busy']);
    expect(conflictsAt(ctx, entries, 'a', 'math', 6, 2).map((c) => c.kind), contains('teacher_busy'));
    expect(conflictsAt(ctx, entries, 'a', 'arab', 4, 6).map((c) => c.kind), ['outside']);
    expect(conflictsAt(ctx, entries, 'a', 'math', 6, 3).map((c) => c.kind), ['day_limit']);
    expect(conflictsAt(ctx, entries, 'a', 'arab', 0, 1), isEmpty);
  });

  test('الأوقات الافتراضية سبع حصص واستراحة بعد الرابعة', () {
    final s = TimetableSettings.fromMap(null);
    expect(s.periods.length, 7);
    expect(s.periods.first.start, '07:30');
    expect(s.periods[4].start, '10:50');
    expect(s.breaksAfter, [4]);
    expect(s.coverDailyMax, 2);
  });

  test('مدرسة صغيرة: كل الحصص موضوعة بلا خرق', () {
    final inp = input(
      rooms: const [SolverRoom(id: 'a', name: 'أ'), SolverRoom(id: 'b', name: 'ب'), SolverRoom(id: 'c', name: 'ج')],
      teachers: const [SolverTeacher(id: 't1', name: 'م1'), SolverTeacher(id: 't2', name: 'م2'), SolverTeacher(id: 't3', name: 'م3'), SolverTeacher(id: 't4', name: 'م4')],
      lessons: [
        lesson('m', 'a', 't1', 6),
        lesson('m', 'b', 't1', 6),
        lesson('m', 'c', 't1', 6),
        lesson('ar', 'a', 't2', 6),
        lesson('ar', 'b', 't2', 6),
        lesson('ar', 'c', 't2', 6),
        lesson('sc', 'a', 't3', 5),
        lesson('sc', 'b', 't3', 5),
        lesson('sc', 'c', 't3', 5),
        lesson('en', 'a', 't4', 5),
        lesson('en', 'b', 't4', 5),
      ],
    );
    final res = SolverRun(inp).result();
    expect(violations(inp, res), isEmpty);
    expect(res.unplaced, isEmpty);
    expect(res.entries.length, 61);
  });

  test('البذرة نفسها تعطي النتيجة نفسها', () {
    final inp = input(
      rooms: const [SolverRoom(id: 'a', name: 'أ'), SolverRoom(id: 'b', name: 'ب')],
      teachers: const [SolverTeacher(id: 't1', name: 'م1'), SolverTeacher(id: 't2', name: 'م2')],
      lessons: [lesson('m', 'a', 't1', 5), lesson('m', 'b', 't1', 5), lesson('ar', 'a', 't2', 5), lesson('ar', 'b', 't2', 5)],
    );
    String sig(SolverResult r) => r.entries.map((e) => '${e.roomId}${e.day}${e.period}${e.groupId}').join(',');
    expect(sig(SolverRun(inp).result()), sig(SolverRun(inp).result()));
  });

  test('الإجازات والمثبَّت والمرفق تُحترم', () {
    final inp = input(
      rooms: const [
        SolverRoom(id: 'a', name: 'أ', off: [SolverSlot(6, 6), SolverSlot(0, 6)]),
        SolverRoom(id: 'b', name: 'ب'),
      ],
      teachers: const [
        SolverTeacher(id: 't1', name: 'م1', off: [SolverSlot(6, 1), SolverSlot(6, 2), SolverSlot(6, 3)]),
        SolverTeacher(id: 't2', name: 'م2'),
      ],
      facilities: const [SolverFacility(id: 'lab', name: 'مختبر', capacity: 1)],
      lessons: [lesson('m', 'a', 't1', 5), lesson('m', 'b', 't1', 5), lesson('sc', 'a', 't2', 5, fac: 'lab'), lesson('sc', 'b', 't2', 5, fac: 'lab')],
      locked: const [SolverEntry(roomId: 'a', day: 1, period: 1, groupId: 'm', locked: true)],
    );
    final res = SolverRun(inp).result();
    expect(violations(inp, res), isEmpty);
    expect(res.unplaced, isEmpty);
    expect(res.entries.where((e) => e.locked && e.roomId == 'a' && e.day == 1 && e.period == 1).length, 1);
    expect(res.entries.length, 20);
  });

  test('المزدوجة حصتان متتاليتان، ولا تقطعها الاستراحة إن طُلب', () {
    final inp = input(
      noDoubleAcrossBreak: true,
      rooms: const [SolverRoom(id: 'a', name: 'أ')],
      teachers: const [SolverTeacher(id: 't1', name: 'م1'), SolverTeacher(id: 't2', name: 'م2')],
      lessons: [lesson('sc', 'a', 't1', 4, dbl: true), lesson('ar', 'a', 't2', 5)],
    );
    final res = SolverRun(inp).result();
    expect(violations(inp, res), isEmpty);
    expect(res.unplaced, isEmpty);
    final byDay = <int, List<int>>{};
    for (final e in res.entries.where((e) => e.groupId == 'sc')) {
      (byDay[e.day] ??= []).add(e.period);
    }
    for (final ps in byDay.values) {
      ps.sort();
      for (var i = 0; i + 1 < ps.length; i += 2) {
        expect(ps[i + 1], ps[i] + 1);
        expect(ps[i], isNot(3));
      }
    }
  });

  test('الفحص الفوري يكشف المستحيل، وما لا يتسع يُبلَّغ لا يضيع', () {
    final inp = input(
      periods: 2,
      rooms: const [SolverRoom(id: 'a', name: 'أ')],
      teachers: const [SolverTeacher(id: 't1', name: 'م1')],
      lessons: [lesson('m', 'a', 't1', 12)],
    );
    final kinds = precheck(inp).map((i) => i.kind);
    expect(kinds, containsAll(['CLASS_FULL', 'TEACHER_FULL']));
    final res = SolverRun(inp).result();
    expect(violations(inp, res), isEmpty);
    expect(res.entries.length + res.unplaced.fold<int>(0, (n, u) => n + u.count), 12);
    expect(res.unplaced, isNotEmpty);
  });

  test('مدرسة بلا حصص تنتهي فوراً', () {
    final res = SolverRun(input(rooms: const [SolverRoom(id: 'a', name: 'أ')], teachers: const [], lessons: const [])).result();
    expect(res.entries, isEmpty);
    expect(res.unplaced, isEmpty);
  });

  test('الاحتياط: يُفضَّل من يدرّس المادة، ولا يأخذ معلم حصتين في وقت واحد', () {
    final groups = {
      'math': group('math', 'gone', ['a'], 5, subject: 'math'),
      'sci': group('sci', 'busy', ['b'], 5, subject: 'sci'),
    };
    const entries = [TimetableEntry('a', 1, 2, 'math'), TimetableEntry('a', 1, 3, 'math'), TimetableEntry('b', 1, 2, 'sci')];
    final input = CoverInput(
      day: 1,
      entries: entries,
      groups: groups,
      teachers: [teacher('gone', subjects: const ['math']), teacher('busy'), teacher('free'), teacher('mathy', subjects: const ['math'])],
      rules: const TimetableRules({}),
      absent: const {'gone'},
      today: const [],
      monthCount: const {},
      dailyMax: 1,
    );
    final slots = absentSlots(1, entries, groups, const {'gone'});
    expect(slots.map((s) => s.period), [2, 3]);
    // «busy» يدرّس في الحصة 2، و«mathy» يدرّس المادة فيتقدم على «free»
    expect(coverCandidates(input, slots.first), ['mathy', 'free']);
    final picks = autoAssign(input, slots);
    expect(picks[slots[0].key], 'mathy');
    // حد الاحتياط واحد: الحصة الثانية لغيره
    expect(picks[slots[1].key], isNot('mathy'));
  });
}
