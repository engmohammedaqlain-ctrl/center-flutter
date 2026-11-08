/// مولِّد الجدول الأسبوعي — المقابل لـ `solver/model.ts` و`grid.ts` و`precheck.ts` و`solve.ts`.
///
/// بطاقات (حصة مفردة أو مزدوجة) توضع في خانات الأسبوع:
/// 1) الأصعب أولاً بجشع يفضّل أقل عقوبة.
/// 2) إصلاح بسلسلة إزاحة: البطاقة العالقة تُزيح من يعترضها، مع قائمة محظورات تمنع الدوران.
/// 3) تحسين محلي بالتلدين (نقل بطاقة أو تبديل بطاقتين في الشعبة) على القيود المفضّلة.
/// الميزانيات بعدد التكرارات لا بالوقت، فالبذرة نفسها تعطي النتيجة نفسها؛ و`timeLimitMs` سقف أمان.
/// وحدة صافية: تعمل شرائح قصيرة ([SolverRun.step]) فتبقى الواجهة حية بلا عامل منفصل.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class SolverSlot {
  const SolverSlot(this.day, this.period);

  final int day;
  final int period;
}

class SolverEntry {
  const SolverEntry({required this.roomId, required this.day, required this.period, required this.groupId, this.locked = false});

  final String roomId;
  final int day;
  final int period;
  final String groupId;
  final bool locked;
}

class SolverRoom {
  const SolverRoom({required this.id, required this.name, this.homeroomTeacherId, this.off = const []});

  final String id;
  final String name;

  /// مربي الصف: يُفضَّل في الحصة الأولى إن فُعّل `homeroomFirst`.
  final String? homeroomTeacherId;
  final List<SolverSlot> off;
}

class SolverTeacher {
  const SolverTeacher({required this.id, required this.name, this.off = const [], this.maxPerDay});

  final String id;
  final String name;
  final List<SolverSlot> off;

  /// حد مفضّل لحصص المعلم في اليوم: تجاوزه يُنقص النقاط ولا يمنع.
  final int? maxPerDay;
}

class SolverFacility {
  const SolverFacility({required this.id, required this.name, required this.capacity});

  final String id;
  final String name;
  final int capacity;
}

class SolverLesson {
  const SolverLesson({
    required this.groupId,
    required this.roomId,
    required this.subjectId,
    required this.teacherId,
    required this.count,
    this.isDouble = false,
    this.maxPerDay,
    this.facilityId,
  });

  final String groupId;
  final String roomId;
  final String subjectId;
  final String teacherId;
  final int count;
  final bool isDouble;
  final int? maxPerDay;
  final String? facilityId;
}

class SolverInput {
  const SolverInput({
    required this.days,
    required this.periodsPerDay,
    required this.breakAfter,
    required this.rooms,
    required this.teachers,
    required this.facilities,
    required this.lessons,
    required this.locked,
    required this.homeroomFirst,
    required this.noDoubleAcrossBreak,
    required this.seed,
    required this.timeLimitMs,
  });

  final List<int> days;
  final Map<int, int> periodsPerDay;
  final List<int> breakAfter;
  final List<SolverRoom> rooms;
  final List<SolverTeacher> teachers;
  final List<SolverFacility> facilities;
  final List<SolverLesson> lessons;
  final List<SolverEntry> locked;
  final bool homeroomFirst;
  final bool noDoubleAcrossBreak;
  final int seed;
  final int timeLimitMs;

  SolverInput withSeed(int next) => SolverInput(
        days: days,
        periodsPerDay: periodsPerDay,
        breakAfter: breakAfter,
        rooms: rooms,
        teachers: teachers,
        facilities: facilities,
        lessons: lessons,
        locked: locked,
        homeroomFirst: homeroomFirst,
        noDoubleAcrossBreak: noDoubleAcrossBreak,
        seed: next,
        timeLimitMs: timeLimitMs,
      );
}

class SolverUnplaced {
  const SolverUnplaced({required this.groupId, required this.roomId, required this.reason, required this.detail, required this.count});

  final String groupId;
  final String roomId;
  final String reason;
  final String detail;
  final int count;
}

class SolverResult {
  const SolverResult({required this.entries, required this.unplaced, required this.score, required this.stopped});

  final List<SolverEntry> entries;
  final List<SolverUnplaced> unplaced;

  /// نقاط العقوبة على المفضّلات: 0 مثالي، والأقل أفضل.
  final double score;
  final bool stopped;
}

/// مشكلة يكشفها الفحص الفوري: `targetId` معرّف الشعبة أو المعلم أو الإسناد أو المرفق حسب النوع.
class SolverIssue {
  const SolverIssue(this.kind, this.targetId, this.need, this.have);

  final String kind;
  final String targetId;
  final int need;
  final int have;
}

class _GLesson {
  const _GLesson({required this.src, required this.room, required this.teacher, required this.fac, required this.count, required this.isDouble, required this.limit});

  final SolverLesson src;
  final int room;
  final int teacher;

  /// -1 بلا مرفق.
  final int fac;
  final int count;
  final bool isDouble;

  /// حد الحصص في اليوم (لازم).
  final int limit;
}

String _lessonKey(String groupId, String roomId) => '$groupId\u0000$roomId';

/// الحد اليومي الافتراضي أو المعطى، بالحصص — `dayLimit`.
int _dayLimit(int count, bool isDouble, int? maxPerDay, int nDays) {
  final n = math.max(1, nDays);
  if (isDouble) {
    final sessions = (count / 2).ceil();
    final def = sessions <= n ? 2 : 2 * (sessions / n).ceil();
    return math.max(2, maxPerDay ?? def);
  }
  final def = count <= n ? 1 : (count / n).ceil();
  return math.max(1, maxPerDay ?? def);
}

/// الإدخال بعد فهرسته في مصفوفات: الخانة s رقم متسلسل على أيام الأسبوع وحصصها — `Grid`.
class _Grid {
  _Grid(this.input) {
    for (final d in input.days) {
      if (!days.contains(d)) days.add(d);
    }
    D = days.length;
    dayStart = Int32List(D);
    dayLen = Int32List(D);
    var total = 0;
    for (var i = 0; i < D; i++) {
      _dayIdx[days[i]] = i;
      dayStart[i] = total;
      dayLen[i] = math.max(0, input.periodsPerDay[days[i]] ?? 0);
      total += dayLen[i];
    }
    S = total;
    slotDay = Int32List(S);
    slotPeriod = Int32List(S);
    for (var i = 0; i < D; i++) {
      for (var p = 0; p < dayLen[i]; p++) {
        slotDay[dayStart[i] + p] = i;
        slotPeriod[dayStart[i] + p] = p + 1;
      }
    }

    for (final r in input.rooms) {
      _addRoom(r.id, r.name);
    }
    for (final t in input.teachers) {
      _addTeacher(t.id, t.name);
    }
    // إسنادات تشير إلى شعبة أو معلم غير معرّف: يُضافان بلا قيود
    for (final l in input.lessons) {
      _addRoom(l.roomId, l.roomId);
      _addTeacher(l.teacherId, l.teacherId);
    }

    roomOff = Uint8List(roomIds.length * S);
    for (final r in input.rooms) {
      final ri = roomIdx[r.id]!;
      for (final o in r.off) {
        final s = slotOf(o.day, o.period);
        if (s >= 0) roomOff[ri * S + s] = 1;
      }
    }
    teacherOff = Uint8List(teacherIds.length * S);
    teacherMax = Int32List(teacherIds.length)..fillRange(0, teacherIds.length, 99);
    for (final t in input.teachers) {
      final ti = teacherIdx[t.id]!;
      for (final o in t.off) {
        final s = slotOf(o.day, o.period);
        if (s >= 0) teacherOff[ti * S + s] = 1;
      }
      if (t.maxPerDay != null && t.maxPerDay! > 0) teacherMax[ti] = t.maxPerDay!;
    }

    final capById = <String, int>{};
    for (final f in input.facilities) {
      capById[f.id] = math.max(0, f.capacity);
      if (facIdx.containsKey(f.id)) continue;
      facIdx[f.id] = facIds.length;
      facIds.add(f.id);
      facNames.add(f.name);
    }
    facCap = Int32List(facIds.length);
    for (var i = 0; i < facIds.length; i++) {
      facCap[i] = capById[facIds[i]] ?? 0;
    }

    for (final l in input.lessons) {
      final key = _lessonKey(l.groupId, l.roomId);
      final count = math.max(0, l.count);
      if (lessonIdx.containsKey(key) || count == 0) continue;
      lessonIdx[key] = lessons.length;
      lessons.add(_GLesson(
        src: l,
        room: roomIdx[l.roomId]!,
        teacher: teacherIdx[l.teacherId]!,
        fac: l.facilityId != null && facIdx.containsKey(l.facilityId) ? facIdx[l.facilityId]! : -1,
        count: count,
        isDouble: l.isDouble,
        limit: _dayLimit(count, l.isDouble, l.maxPerDay, D),
      ));
    }
    breakAfter = input.breakAfter.toSet();
    noDoubleAcrossBreak = input.noDoubleAcrossBreak;
  }

  final SolverInput input;
  final days = <int>[];
  final _dayIdx = <int, int>{};
  late final int D;
  late final int S;
  late final Int32List dayStart;
  late final Int32List dayLen;
  late final Int32List slotDay;
  late final Int32List slotPeriod;
  late final Set<int> breakAfter;
  late final bool noDoubleAcrossBreak;
  final roomIds = <String>[];
  final roomNames = <String>[];
  final roomIdx = <String, int>{};
  late final Uint8List roomOff;
  final teacherIds = <String>[];
  final teacherNames = <String>[];
  final teacherIdx = <String, int>{};
  late final Uint8List teacherOff;
  late final Int32List teacherMax;
  final facIds = <String>[];
  final facNames = <String>[];
  final facIdx = <String, int>{};
  late final Int32List facCap;
  final lessons = <_GLesson>[];
  final lessonIdx = <String, int>{};

  void _addRoom(String id, String name) {
    if (roomIdx.containsKey(id)) return;
    roomIdx[id] = roomIds.length;
    roomIds.add(id);
    roomNames.add(name);
  }

  void _addTeacher(String id, String name) {
    if (teacherIdx.containsKey(id)) return;
    teacherIdx[id] = teacherIds.length;
    teacherIds.add(id);
    teacherNames.add(name);
  }

  int slotOf(int day, int period) {
    final i = _dayIdx[day];
    if (i == null || period < 1 || period > dayLen[i]) return -1;
    return dayStart[i] + period - 1;
  }

  /// هل تصلح الخانة s بداية لبطاقة بطول len (الإجازات واليوم الواحد والاستراحة)؟ — `startOk`.
  bool startOk(_GLesson l, int s, int len) {
    final d = slotDay[s];
    final p = slotPeriod[s];
    if (p + len - 1 > dayLen[d]) return false;
    final rb = l.room * S;
    final tb = l.teacher * S;
    for (var k = 0; k < len; k++) {
      if (roomOff[rb + s + k] != 0 || teacherOff[tb + s + k] != 0) return false;
      if (k < len - 1 && noDoubleAcrossBreak && breakAfter.contains(p + k)) return false;
    }
    return true;
  }
}

/// مولّد أرقام مبذور: البذرة نفسها تعطي التسلسل نفسه — `mulberry32`.
double Function() _mulberry32(int seed) {
  const mask = 0xFFFFFFFF;
  var a = seed & mask;
  return () {
    a = (a + 0x6d2b79f5) & mask;
    var t = a;
    t = ((t ^ (t >> 15)) * (t | 1)) & mask;
    t = (t ^ ((t + (((t ^ (t >> 7)) * (t | 61)) & mask)) & mask)) & mask;
    return (t ^ (t >> 14)) / 4294967296;
  };
}

/// فحص فوري قبل التوليد: كل ما يجعل الجدول مستحيلاً بالعدّ وحده — `precheck`.
List<SolverIssue> precheck(SolverInput input) => _precheckGrid(_Grid(input));

List<SolverIssue> _precheckGrid(_Grid g) {
  final S = g.S, D = g.D;
  final issues = <SolverIssue>[];
  final R = g.roomIds.length;
  final T = g.teacherIds.length;

  // الشعب: حصصها (مع المثبَّت الذي لا إسناد له) مقابل خاناتها
  final roomLoad = Int32List(R);
  for (final l in g.lessons) {
    roomLoad[l.room] += l.count;
  }
  final seen = <String>{};
  for (final e in g.input.locked) {
    final r = g.roomIdx[e.roomId];
    final s = g.slotOf(e.day, e.period);
    if (r == null || s < 0 || !seen.add('$r:$s')) continue;
    if (!g.lessonIdx.containsKey(_lessonKey(e.groupId, e.roomId))) roomLoad[r]++;
  }
  for (var r = 0; r < R; r++) {
    if (roomLoad[r] == 0) continue;
    var have = 0;
    for (var s = 0; s < S; s++) {
      if (g.roomOff[r * S + s] == 0) have++;
    }
    if (roomLoad[r] > have) issues.add(SolverIssue('CLASS_FULL', g.roomIds[r], roomLoad[r], have));
  }

  // المعلمون: حصصهم مقابل خاناتهم المتاحة
  final teacherLoad = Int32List(T);
  for (final l in g.lessons) {
    teacherLoad[l.teacher] += l.count;
  }
  for (var t = 0; t < T; t++) {
    if (teacherLoad[t] == 0) continue;
    var have = 0;
    for (var s = 0; s < S; s++) {
      if (g.teacherOff[t * S + s] == 0) have++;
    }
    if (teacherLoad[t] > have) issues.add(SolverIssue('TEACHER_FULL', g.teacherIds[t], teacherLoad[t], have));
  }

  // الإسنادات: الوقت المشترك، المزدوجة، والحد اليومي
  for (final l in g.lessons) {
    final perDay = <int>[
      for (var d = 0; d < D; d++)
        () {
          var n = 0;
          for (var k = 0; k < g.dayLen[d]; k++) {
            final s = g.dayStart[d] + k;
            if (g.roomOff[l.room * S + s] == 0 && g.teacherOff[l.teacher * S + s] == 0) n++;
          }
          return n;
        }(),
    ];
    final common = perDay.fold<int>(0, (a, b) => a + b);
    final id = l.src.groupId;
    if (common < l.count) {
      issues.add(SolverIssue('NO_COMMON_SLOT', id, l.count, common));
      continue;
    }
    if (l.isDouble) {
      final need = l.count ~/ 2;
      var have = 0;
      for (var d = 0; d < D; d++) {
        have += math.min(_pairsOnDay(g, l, d), l.limit ~/ 2);
      }
      if (have < need) {
        issues.add(SolverIssue('DOUBLE', id, need, have));
        continue;
      }
    }
    var dayCap = 0;
    for (var d = 0; d < D; d++) {
      dayCap += math.min(l.limit, perDay[d]);
    }
    if (dayCap < l.count) issues.add(SolverIssue('DAY_LIMIT', id, l.count, dayCap));
  }

  // المرافق: الحمل مقابل السعة × الخانات
  final facLoad = Int32List(g.facIds.length);
  for (final l in g.lessons) {
    if (l.fac >= 0) facLoad[l.fac] += l.count;
  }
  for (var f = 0; f < g.facIds.length; f++) {
    final have = g.facCap[f] * S;
    if (facLoad[f] > have) issues.add(SolverIssue('FACILITY', g.facIds[f], facLoad[f], have));
  }
  return issues;
}

/// أكبر عدد أزواج متتالية منفصلة في يوم (لا تعبر الاستراحة إن طُلب).
int _pairsOnDay(_Grid g, _GLesson l, int d) {
  var pairs = 0;
  var run = 0;
  for (var k = 0; k < g.dayLen[d]; k++) {
    final s = g.dayStart[d] + k;
    if (g.roomOff[l.room * g.S + s] == 0 && g.teacherOff[l.teacher * g.S + s] == 0) {
      run++;
      if (g.noDoubleAcrossBreak && g.breakAfter.contains(k + 1)) {
        pairs += run >> 1;
        run = 0;
      }
    } else {
      pairs += run >> 1;
      run = 0;
    }
  }
  return pairs + (run >> 1);
}

const _free = -1;
const _fixed = -2;
const _wGap = 3.0;
const _wOver = 4.0;
const _wAdj = 1.0;
const _wSame = 2.0;
const _wHr = 5.0;
const _tStart = 3.0;
const _tEnd = 0.05;
const _chunk = 256;
const _big = 1e6;

/// تشغيل المولِّد على شرائح — `createSolver`.
class SolverRun {
  SolverRun(this.input) : _g = _Grid(input) {
    _clock.start();
    _limitMs = input.timeLimitMs > 0 ? input.timeLimitMs : 10000;
    _rng = _mulberry32(input.seed);
    _issues = _precheckGrid(_g);
    _setup();
  }

  final SolverInput input;
  final _Grid _g;
  final _clock = Stopwatch();
  late final int _limitMs;
  late final double Function() _rng;
  late final List<SolverIssue> _issues;

  late final int S, D, R, T, F, L, N;
  late final Int32List _roomOcc, _teachOcc, _facUse, _facFixed, _lessonDay, _lessonFixed;
  final _lockedEntries = <SolverEntry>[];
  late final Int32List _cLesson, _cLen, _cRoom, _cTeacher, _cFac;
  final _cDom = <Int32List>[];
  final _cMask = <Uint8List>[];
  late final List<List<int>> _lessonCards, _roomCards, _facCards;
  late final Int32List _lLimit;
  late final Uint8List _lDouble;
  late final Int32List _hrTeacher;
  late final Uint8List _hrApplies;
  late final Int32List _baseAdj, _baseSame;
  late final Int32List _pos;
  var _placed = 0;
  late final Int32List _mark;
  var _stamp = 0;
  final _conf = <int>[];
  final _affTD = <int>[];
  final _affL = <int>[];
  final _affRD = <int>[];

  // الإصلاح
  final _queue = <int>[];
  final _blocked = <int>[];
  late final Int32List _tabu;
  late final int _repairMax;
  var _rIter = 0;
  var _bestUn = 1 << 40;
  late Int32List _bestSnap;
  final _pick = <int>[];

  // التحسين
  late final int _improveMax;
  var _iIter = 0;
  var _curScore = 0.0;
  var _bestKey = double.infinity;
  var _bestScore = 0.0;

  // التشغيل
  var _phase = 'place';
  var _stopped = false;
  SolverResult? _final;

  int get placed => _placed;
  int get total => N;
  String get phase => _phase;
  int get elapsedMs => _clock.elapsedMilliseconds;

  void _setup() {
    final g = _g;
    S = g.S;
    D = g.D;
    R = g.roomIds.length;
    T = g.teacherIds.length;
    F = g.facIds.length;
    L = g.lessons.length;

    _roomOcc = Int32List(R * S)..fillRange(0, R * S, _free);
    _teachOcc = Int32List(T * S)..fillRange(0, T * S, _free);
    _facUse = Int32List(F * S);
    _facFixed = Int32List(F * S);
    _lessonDay = Int32List(L * D);
    _lessonFixed = Int32List(L * D);
    final lockedCount = Int32List(L);

    for (final e in input.locked) {
      final r = g.roomIdx[e.roomId];
      final s = g.slotOf(e.day, e.period);
      if (r == null || s < 0 || _roomOcc[r * S + s] == _fixed) continue;
      _roomOcc[r * S + s] = _fixed;
      _lockedEntries.add(SolverEntry(roomId: e.roomId, day: e.day, period: e.period, groupId: e.groupId, locked: true));
      final li = g.lessonIdx[_lessonKey(e.groupId, e.roomId)];
      if (li == null) continue;
      final l = g.lessons[li];
      _teachOcc[l.teacher * S + s] = _fixed;
      if (l.fac >= 0) {
        _facUse[l.fac * S + s]++;
        _facFixed[l.fac * S + s]++;
      }
      _lessonDay[li * D + g.slotDay[s]]++;
      _lessonFixed[li * D + g.slotDay[s]]++;
      lockedCount[li]++;
    }

    // البطاقات
    final cl = <int>[];
    final cn = <int>[];
    for (var li = 0; li < L; li++) {
      final l = g.lessons[li];
      final rem = math.max(0, l.count - lockedCount[li]);
      if (l.isDouble) {
        for (var i = 0; i < rem >> 1; i++) {
          cl.add(li);
          cn.add(2);
        }
        if (rem & 1 == 1) {
          cl.add(li);
          cn.add(1);
        }
      } else {
        for (var i = 0; i < rem; i++) {
          cl.add(li);
          cn.add(1);
        }
      }
    }
    N = cl.length;
    _cLesson = Int32List.fromList(cl);
    _cLen = Int32List.fromList(cn);
    _cRoom = Int32List(N);
    _cTeacher = Int32List(N);
    _cFac = Int32List(N);
    final domCache = <int, ({Int32List dom, Uint8List mask})>{};
    _lessonCards = [for (var i = 0; i < L; i++) <int>[]];
    _roomCards = [for (var i = 0; i < R; i++) <int>[]];
    _facCards = [for (var i = 0; i < F; i++) <int>[]];
    for (var c = 0; c < N; c++) {
      final li = _cLesson[c];
      final l = g.lessons[li];
      _cRoom[c] = l.room;
      _cTeacher[c] = l.teacher;
      _cFac[c] = l.fac;
      final key = li * 4 + _cLen[c];
      var dm = domCache[key];
      if (dm == null) {
        final list = <int>[];
        final mask = Uint8List(S);
        for (var s = 0; s < S; s++) {
          if (g.startOk(l, s, _cLen[c])) {
            list.add(s);
            mask[s] = 1;
          }
        }
        dm = (dom: Int32List.fromList(list), mask: mask);
        domCache[key] = dm;
      }
      _cDom.add(dm.dom);
      _cMask.add(dm.mask);
      _lessonCards[li].add(c);
      _roomCards[l.room].add(c);
      if (l.fac >= 0) _facCards[l.fac].add(c);
    }
    _lLimit = Int32List.fromList([for (final l in g.lessons) l.limit]);
    _lDouble = Uint8List.fromList([for (final l in g.lessons) l.isDouble ? 1 : 0]);

    // مربي الصف في الحصة الأولى: أي (شعبة، يوم) ينطبق عليه التفضيل
    _hrTeacher = Int32List(R)..fillRange(0, R, -1);
    _hrApplies = Uint8List(R * D);
    if (input.homeroomFirst) {
      for (final room in input.rooms) {
        final hr = room.homeroomTeacherId;
        if (hr == null || hr.isEmpty) continue;
        final r = g.roomIdx[room.id]!;
        final t = g.teacherIdx[hr];
        if (t == null || !_roomCards[r].any((c) => _cTeacher[c] == t)) continue;
        _hrTeacher[r] = t;
        for (var d = 0; d < D; d++) {
          final s = g.dayStart[d];
          if (g.dayLen[d] > 0 && g.roomOff[r * S + s] == 0 && g.teacherOff[t * S + s] == 0) _hrApplies[r * D + d] = 1;
        }
      }
    }

    // ما لا يمكن تجنبه من تجاور الأيام وتكرار اليوم، فلا يُحسب
    _baseAdj = Int32List(L);
    _baseSame = Int32List(L);
    for (var li = 0; li < L; li++) {
      final l = g.lessons[li];
      final sessions = l.isDouble ? (l.count / 2).ceil() : l.count;
      _baseAdj[li] = math.max<int>(0, 2 * math.min<int>(sessions, D) - D - 1);
      _baseSame[li] = math.max(0, sessions - D);
    }

    _pos = Int32List(N)..fillRange(0, N, -1);
    _mark = Int32List(N);
    _tabu = Int32List(N);
    _repairMax = 30000 + N * 300;
    _improveMax = math.min(3000000, 30000 + N * 2000);
    _bestSnap = Int32List.fromList(_pos);
  }

  void _place(int c, int s) {
    _pos[c] = s;
    _placed++;
    final rb = _cRoom[c] * S + s;
    final tb = _cTeacher[c] * S + s;
    final f = _cFac[c];
    for (var k = 0; k < _cLen[c]; k++) {
      _roomOcc[rb + k] = c;
      _teachOcc[tb + k] = c;
      if (f >= 0) _facUse[f * S + s + k]++;
    }
    _lessonDay[_cLesson[c] * D + _g.slotDay[s]] += _cLen[c];
  }

  void _unplace(int c) {
    final s = _pos[c];
    _pos[c] = -1;
    _placed--;
    final rb = _cRoom[c] * S + s;
    final tb = _cTeacher[c] * S + s;
    final f = _cFac[c];
    for (var k = 0; k < _cLen[c]; k++) {
      _roomOcc[rb + k] = _free;
      _teachOcc[tb + k] = _free;
      if (f >= 0) _facUse[f * S + s + k]--;
    }
    _lessonDay[_cLesson[c] * D + _g.slotDay[s]] -= _cLen[c];
  }

  /// يصلح وضع c (غير الموضوعة) في s دون إزاحة أحد؟
  bool _canPlace(int c, int s) {
    final len = _cLen[c];
    if (_lessonDay[_cLesson[c] * D + _g.slotDay[s]] + len > _lLimit[_cLesson[c]]) return false;
    final rb = _cRoom[c] * S + s;
    final tb = _cTeacher[c] * S + s;
    final f = _cFac[c];
    for (var k = 0; k < len; k++) {
      if (_roomOcc[rb + k] != _free || _teachOcc[tb + k] != _free) return false;
      if (f >= 0 && _facUse[f * S + s + k] >= _g.facCap[f]) return false;
    }
    return true;
  }

  /// يملأ `_conf` بمن يجب إزاحته؛ false إن منع الوضعَ شيءٌ ثابت (مثبَّت أو سعة صفرية).
  bool _conflicts(int c, int s) {
    _conf.clear();
    _stamp++;
    final len = _cLen[c];
    final rb = _cRoom[c] * S + s;
    final tb = _cTeacher[c] * S + s;
    for (var k = 0; k < len; k++) {
      final a = _roomOcc[rb + k];
      if (a == _fixed) return false;
      if (a >= 0 && _mark[a] != _stamp) {
        _mark[a] = _stamp;
        _conf.add(a);
      }
      final b = _teachOcc[tb + k];
      if (b == _fixed) return false;
      if (b >= 0 && _mark[b] != _stamp) {
        _mark[b] = _stamp;
        _conf.add(b);
      }
    }
    final f = _cFac[c];
    if (f >= 0) {
      final cap = _g.facCap[f];
      for (var k = 0; k < len; k++) {
        final slot = s + k;
        if (_facFixed[f * S + slot] >= cap) return false;
        var used = _facUse[f * S + slot];
        for (final x in _conf) {
          if (_cFac[x] == f && _pos[x] <= slot && slot < _pos[x] + _cLen[x]) used--;
        }
        if (used < cap) continue;
        for (final x in _facCards[f]) {
          if (used < cap) break;
          if (_mark[x] == _stamp || _pos[x] < 0 || _pos[x] > slot || slot >= _pos[x] + _cLen[x]) continue;
          _mark[x] = _stamp;
          _conf.add(x);
          used--;
        }
      }
    }
    final li = _cLesson[c];
    final d = _g.slotDay[s];
    final lim = _lLimit[li];
    if (_lessonFixed[li * D + d] + len > lim) return false;
    var cur = _lessonDay[li * D + d];
    for (final x in _conf) {
      if (_cLesson[x] == li && _g.slotDay[_pos[x]] == d) cur -= _cLen[x];
    }
    if (cur + len > lim) {
      for (final x in _lessonCards[li]) {
        if (cur + len <= lim) break;
        if (x == c || _mark[x] == _stamp || _pos[x] < 0 || _g.slotDay[_pos[x]] != d) continue;
        _mark[x] = _stamp;
        _conf.add(x);
        cur -= _cLen[x];
      }
    }
    return true;
  }

  double _teacherDayCost(int t, int d) {
    final base = t * S + _g.dayStart[d];
    final n = _g.dayLen[d];
    var cnt = 0;
    var first = -1;
    var last = -1;
    for (var k = 0; k < n; k++) {
      if (_teachOcc[base + k] != _free) {
        cnt++;
        if (first < 0) first = k;
        last = k;
      }
    }
    if (cnt == 0) return 0;
    var gaps = 0;
    for (var k = first + 1; k < last; k++) {
      if (_teachOcc[base + k] == _free && _g.teacherOff[base + k] == 0) gaps++;
    }
    final over = cnt > _g.teacherMax[t] ? cnt - _g.teacherMax[t] : 0;
    return _wGap * gaps + _wOver * over;
  }

  double _lessonCost(int li) {
    var adj = 0;
    var same = 0;
    var prev = false;
    final base = li * D;
    final dbl = _lDouble[li] != 0;
    for (var d = 0; d < D; d++) {
      final p = _lessonDay[base + d];
      final sess = dbl ? (p + 1) >> 1 : p;
      if (sess > 1) same += sess - 1;
      final here = p > 0;
      if (here && prev) adj++;
      prev = here;
    }
    return _wAdj * math.max(0, adj - _baseAdj[li]) + _wSame * math.max(0, same - _baseSame[li]);
  }

  double _roomDayCost(int r, int d) {
    if (_hrApplies[r * D + d] == 0) return 0;
    final v = _roomOcc[r * S + _g.dayStart[d]];
    if (v == _fixed || (v >= 0 && _cTeacher[v] == _hrTeacher[r])) return 0;
    return _wHr;
  }

  void _affReset() {
    _affTD.clear();
    _affL.clear();
    _affRD.clear();
  }

  void _affCard(int c, int s) {
    final d = _g.slotDay[s];
    final td = _cTeacher[c] * D + d;
    if (!_affTD.contains(td)) _affTD.add(td);
    final li = _cLesson[c];
    if (!_affL.contains(li)) _affL.add(li);
    final rd = _cRoom[c] * D + d;
    if (_hrApplies[rd] != 0 && !_affRD.contains(rd)) _affRD.add(rd);
  }

  double _affCost() {
    var x = 0.0;
    for (final k in _affTD) {
      x += _teacherDayCost(k ~/ D, k % D);
    }
    for (final li in _affL) {
      x += _lessonCost(li);
    }
    for (final k in _affRD) {
      x += _roomDayCost(k ~/ D, k % D);
    }
    return x;
  }

  double _fullCost() {
    var x = 0.0;
    for (var t = 0; t < T; t++) {
      for (var d = 0; d < D; d++) {
        x += _teacherDayCost(t, d);
      }
    }
    for (var li = 0; li < L; li++) {
      x += _lessonCost(li);
    }
    for (var r = 0; r < R; r++) {
      for (var d = 0; d < D; d++) {
        x += _roomDayCost(r, d);
      }
    }
    return x;
  }

  double _placeDelta(int c, int s) {
    _affReset();
    _affCard(c, s);
    final before = _affCost();
    _place(c, s);
    final after = _affCost();
    _unplace(c);
    return after - before;
  }

  void _restore(Int32List snap) {
    for (var c = 0; c < N; c++) {
      if (_pos[c] >= 0) _unplace(c);
    }
    for (var c = 0; c < N; c++) {
      if (snap[c] >= 0) _place(c, snap[c]);
    }
  }

  // ── المرحلة 1: الأصعب أولاً ──
  void _greedy() {
    final teacherLoad = Float64List(T);
    final roomLoad = Float64List(R);
    for (var c = 0; c < N; c++) {
      teacherLoad[_cTeacher[c]] += _cLen[c];
      roomLoad[_cRoom[c]] += _cLen[c];
    }
    double tightness(int c) {
      final t = _cTeacher[c];
      final r = _cRoom[c];
      var tAvail = 0;
      var rAvail = 0;
      for (var s = 0; s < S; s++) {
        if (_g.teacherOff[t * S + s] == 0) tAvail++;
        if (_g.roomOff[r * S + s] == 0) rAvail++;
      }
      return math.max(teacherLoad[t] / math.max(1, tAvail), roomLoad[r] / math.max(1, rAvail));
    }

    final key = Float64List(N);
    for (var c = 0; c < N; c++) {
      key[c] = (_cDom[c].length / (1 + 2 * tightness(c))) * (_cLen[c] > 1 ? 0.5 : 1) + _rng() * 0.01;
    }
    final order = List<int>.generate(N, (i) => i)..sort((a, b) => key[a].compareTo(key[b]));
    for (final c in order) {
      var best = -1;
      var bestD = double.infinity;
      for (final s in _cDom[c]) {
        if (!_canPlace(c, s)) continue;
        final dlt = _placeDelta(c, s) + _rng() * 0.5;
        if (dlt < bestD) {
          bestD = dlt;
          best = s;
        }
      }
      if (best >= 0) _place(c, best);
    }
  }

  // ── المرحلة 2: إصلاح بسلسلة إزاحة ──
  void _startRepair() {
    for (var c = 0; c < N; c++) {
      if (_pos[c] < 0) _queue.add(c);
    }
    // الأصعب في آخر الطابور فيُسحب أولاً
    _queue.sort((a, b) => _cDom[b].length - _cDom[a].length);
    _bestUn = _queue.length;
    _bestSnap = Int32List.fromList(_pos);
  }

  bool _repairIter() {
    if (_queue.isEmpty) return true;
    final qi = _rng() < 0.7 ? _queue.length - 1 : (_rng() * _queue.length).floor();
    final c = _queue[qi];
    _queue[qi] = _queue.last;
    _queue.removeLast();
    _rIter++;
    final tenure = 8 + (_rng() * 12).floor();

    var freeS = -1;
    var freeScore = double.infinity;
    for (final s in _cDom[c]) {
      if (!_canPlace(c, s)) continue;
      final sc = _rng();
      if (sc < freeScore) {
        freeScore = sc;
        freeS = s;
      }
    }
    if (freeS >= 0) {
      _place(c, freeS);
      _tabu[c] = _rIter + tenure;
    } else {
      var bestS = -1;
      var bestScore = double.infinity;
      for (final s in _cDom[c]) {
        if (!_conflicts(c, s)) continue;
        var sc = _rng() * 0.5;
        for (final x in _conf) {
          sc += 1 + 8 / _cDom[x].length + (_tabu[x] > _rIter ? 100 : 0);
        }
        if (sc < bestScore) {
          bestScore = sc;
          bestS = s;
          _pick
            ..clear()
            ..addAll(_conf);
        }
      }
      if (bestS < 0) {
        _blocked.add(c);
      } else {
        for (final x in _pick) {
          _unplace(x);
          _queue.add(x);
        }
        _place(c, bestS);
        _tabu[c] = _rIter + tenure;
      }
    }
    final un = _queue.length + _blocked.length;
    if (un < _bestUn) {
      _bestUn = un;
      _bestSnap = Int32List.fromList(_pos);
    }
    return _queue.isEmpty;
  }

  // ── المرحلة 3: تحسين بالتلدين ──
  void _startImprove() {
    _curScore = _fullCost();
    _bestScore = _curScore;
    _bestKey = (N - _placed) * _big + _curScore;
    _bestSnap = Int32List.fromList(_pos);
  }

  bool _accept(double delta, double temp) => delta <= 0 || _rng() < math.exp(-delta / temp);

  void _relocate(double temp) {
    final c = (_rng() * N).floor();
    final old = _pos[c];
    if (old < 0) return;
    final dom = _cDom[c];
    final s = dom[(_rng() * dom.length).floor()];
    if (s == old) return;
    _affReset();
    _affCard(c, old);
    _affCard(c, s);
    final before = _affCost();
    _unplace(c);
    if (!_canPlace(c, s)) {
      _place(c, old);
      return;
    }
    _place(c, s);
    final delta = _affCost() - before;
    if (_accept(delta, temp)) {
      _curScore += delta;
    } else {
      _unplace(c);
      _place(c, old);
    }
  }

  void _swap(double temp) {
    final a = (_rng() * N).floor();
    final sa = _pos[a];
    if (sa < 0) return;
    final list = _roomCards[_cRoom[a]];
    final b = list[(_rng() * list.length).floor()];
    final sb = _pos[b];
    if (b == a || sb < 0 || _cLen[b] != _cLen[a] || _cLesson[b] == _cLesson[a]) return;
    if (_cMask[a][sb] == 0 || _cMask[b][sa] == 0) return;
    _affReset();
    _affCard(a, sa);
    _affCard(a, sb);
    _affCard(b, sa);
    _affCard(b, sb);
    final before = _affCost();
    _unplace(a);
    _unplace(b);
    if (!_canPlace(a, sb)) {
      _place(a, sa);
      _place(b, sb);
      return;
    }
    _place(a, sb);
    if (!_canPlace(b, sa)) {
      _unplace(a);
      _place(a, sa);
      _place(b, sb);
      return;
    }
    _place(b, sa);
    final delta = _affCost() - before;
    if (_accept(delta, temp)) {
      _curScore += delta;
    } else {
      _unplace(a);
      _unplace(b);
      _place(a, sa);
      _place(b, sb);
    }
  }

  /// محاولة وضع ما بقي خارج الجدول في خانة صارت فارغة.
  void _placeLeftovers() {
    for (var c = 0; c < N; c++) {
      if (_pos[c] >= 0) continue;
      var best = -1;
      var bestD = double.infinity;
      for (final s in _cDom[c]) {
        if (!_canPlace(c, s)) continue;
        final dlt = _placeDelta(c, s);
        if (dlt < bestD) {
          bestD = dlt;
          best = s;
        }
      }
      if (best >= 0) {
        _place(c, best);
        _curScore += bestD;
      }
    }
  }

  bool _improveIter() {
    if (_iIter >= _improveMax) return true;
    final temp = _tStart * math.pow(_tEnd / _tStart, _iIter / _improveMax);
    if (_rng() < 0.5) {
      _relocate(temp);
    } else {
      _swap(temp);
    }
    _iIter++;
    if (_placed < N && _iIter % 2048 == 0) _placeLeftovers();
    final key = (N - _placed) * _big + _curScore;
    if (key < _bestKey) {
      _bestKey = key;
      _bestScore = _curScore;
      _bestSnap = Int32List.fromList(_pos);
    }
    return _iIter >= _improveMax;
  }

  /// إيقاف: الخطوة التالية تنهي بأفضل ما وُجد.
  void stop() => _stopped = true;

  /// يعمل حتى [sliceMs] ثم يرجع؛ true عند الانتهاء.
  bool step(int sliceMs) {
    final end = _clock.elapsedMilliseconds + sliceMs;
    while (_phase != 'done') {
      final out = _stopped || _clock.elapsedMilliseconds > _limitMs;
      if (N == 0) {
        _phase = 'done';
        break;
      }
      if (_phase == 'place') {
        _greedy();
        _startRepair();
        _phase = 'repair';
      } else if (_phase == 'repair') {
        if (out) {
          _restore(_bestSnap);
          _curScore = _fullCost();
          _phase = 'done';
          break;
        }
        var done = false;
        for (var i = 0; i < _chunk && !done; i++) {
          done = _repairIter() || _rIter >= _repairMax;
        }
        if (done) {
          _restore(_bestSnap);
          _startImprove();
          _phase = 'improve';
        }
      } else {
        if (out) {
          _restore(_bestSnap);
          _curScore = _bestScore;
          _phase = 'done';
          break;
        }
        var done = false;
        for (var i = 0; i < _chunk && !done; i++) {
          done = _improveIter();
        }
        if (done) {
          _restore(_bestSnap);
          _curScore = _bestScore;
          _phase = 'done';
        }
      }
      if (_clock.elapsedMilliseconds >= end) break;
    }
    return _phase == 'done';
  }

  String _reasonFor(int c) {
    final l = _g.lessons[_cLesson[c]];
    bool has(String kind, String id) => _issues.any((i) => i.kind == kind && i.targetId == id);
    final gid = l.src.groupId;
    if (has('NO_COMMON_SLOT', gid)) return 'NO_COMMON_SLOT';
    if (_cLen[c] > 1 && has('DOUBLE', gid)) return 'DOUBLE';
    if (has('DAY_LIMIT', gid)) return 'DAY_LIMIT';
    if (has('TEACHER_FULL', _g.teacherIds[l.teacher])) return 'TEACHER_FULL';
    if (has('CLASS_FULL', _g.roomIds[l.room])) return 'CLASS_FULL';
    if (l.fac >= 0 && has('FACILITY', _g.facIds[l.fac])) return 'FACILITY';
    if (_cDom[c].isEmpty) return _cLen[c] > 1 ? 'DOUBLE' : 'NO_COMMON_SLOT';
    // ما الذي يسدّ أكثر الخانات الممكنة الآن؟
    final tally = <String, int>{'TEACHER_FULL': 0, 'CLASS_FULL': 0, 'FACILITY': 0, 'DAY_LIMIT': 0};
    for (final s in _cDom[c]) {
      for (var k = 0; k < _cLen[c]; k++) {
        if (_teachOcc[l.teacher * S + s + k] != _free) tally['TEACHER_FULL'] = tally['TEACHER_FULL']! + 1;
        if (_roomOcc[l.room * S + s + k] != _free) tally['CLASS_FULL'] = tally['CLASS_FULL']! + 1;
        if (l.fac >= 0 && _facUse[l.fac * S + s + k] >= _g.facCap[l.fac]) tally['FACILITY'] = tally['FACILITY']! + 1;
      }
      if (_lessonDay[_cLesson[c] * D + _g.slotDay[s]] + _cLen[c] > l.limit) tally['DAY_LIMIT'] = tally['DAY_LIMIT']! + 1;
    }
    var best = 'TEACHER_FULL';
    for (final k in const ['CLASS_FULL', 'FACILITY', 'DAY_LIMIT']) {
      if (tally[k]! > tally[best]!) best = k;
    }
    return best;
  }

  String _detailFor(String reason, int c) {
    final l = _g.lessons[_cLesson[c]];
    final teacher = _g.teacherNames[l.teacher];
    final room = _g.roomNames[l.room];
    return switch (reason) {
      'TEACHER_FULL' => 'وقت $teacher لا يتسع',
      'CLASS_FULL' => 'خانات $room ممتلئة',
      'NO_COMMON_SLOT' => 'لا وقت مشترك بين $teacher و$room',
      'FACILITY' => '${l.fac >= 0 ? _g.facNames[l.fac] : 'المرفق'} محجوز',
      'DAY_LIMIT' => 'حد المادة اليومي لا يكفي',
      _ => 'لا حصتان متتاليتان',
    };
  }

  SolverResult _build() {
    final roomOrder = {for (var i = 0; i < _g.roomIds.length; i++) _g.roomIds[i]: i};
    final rows = <({int r, int s, SolverEntry e})>[
      for (final e in _lockedEntries) (r: roomOrder[e.roomId]!, s: _g.slotOf(e.day, e.period), e: e),
    ];
    for (var c = 0; c < N; c++) {
      if (_pos[c] < 0) continue;
      final l = _g.lessons[_cLesson[c]];
      for (var k = 0; k < _cLen[c]; k++) {
        final s = _pos[c] + k;
        rows.add((
          r: l.room,
          s: s,
          e: SolverEntry(roomId: l.src.roomId, day: _g.days[_g.slotDay[s]], period: _g.slotPeriod[s], groupId: l.src.groupId),
        ));
      }
    }
    rows.sort((a, b) {
      final x = a.r - b.r;
      return x != 0 ? x : a.s - b.s;
    });

    final byLesson = <int, ({int c, int n})>{};
    for (var c = 0; c < N; c++) {
      if (_pos[c] >= 0) continue;
      final v = byLesson[_cLesson[c]];
      byLesson[_cLesson[c]] = v == null ? (c: c, n: _cLen[c]) : (c: v.c, n: v.n + _cLen[c]);
    }
    final unplaced = <SolverUnplaced>[];
    byLesson.forEach((li, v) {
      final reason = _reasonFor(v.c);
      final l = _g.lessons[li];
      unplaced.add(SolverUnplaced(groupId: l.src.groupId, roomId: l.src.roomId, reason: reason, detail: _detailFor(reason, v.c), count: v.n));
    });
    return SolverResult(entries: [for (final x in rows) x.e], unplaced: unplaced, score: _fullCost(), stopped: _stopped);
  }

  SolverResult result() {
    while (_phase != 'done') {
      step(1 << 30);
    }
    return _final ??= _build();
  }
}
