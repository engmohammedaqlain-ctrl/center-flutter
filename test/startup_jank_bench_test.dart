import 'dart:async';
import 'dart:convert';

import 'package:center_mobile/data/dashboard_stats.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/followup.dart';
import 'package:center_mobile/data/school_calendar.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import 'persistence_test.dart' show FakeDisk;

/// قرص بالذاكرة يعيد الصفوف مفكوكة: يحاكي فكّ JSON في خيط منفصل (Isolate.exit بلا نسخ)،
/// فما يُقاس هنا هو ما يجري على خيط الواجهة وحده.
class _MemDisk extends FakeDisk {
  final Map<String, Map<String, Map<String, dynamic>>> rowsByTable = {};

  @override
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows) async {
    rowsByTable[table] = {for (final r in rows) '${r['id']}': r};
  }

  @override
  Future<void> saveRecords(String table, List<Map<String, dynamic>> rows) async {
    final t = rowsByTable.putIfAbsent(table, () => {});
    for (final r in rows) {
      t['${r['id']}'] = r;
    }
  }

  @override
  Future<void> deleteRecords(String table, List<String> ids) async {
    final t = rowsByTable[table];
    if (t == null) return;
    for (final id in ids) {
      t.remove(id);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadTable(String table) async => [...?rowsByTable[table]?.values];

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadTables(Iterable<String> tables) async => {
        for (final t in tables) t: [...?rowsByTable[t]?.values],
      };

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
        for (final e in rowsByTable.entries) e.key: [...e.value.values],
      };

  @override
  Future<int> countTable(String table) async => rowsByTable[table]?.length ?? 0;
}

String phase = 'init';

void main() {
  test('BENCH تقطّع خيط الواجهة عند الإقلاع — مدرسة بحجم المستر', () async {
    // ── بناء مدرسة بحجم المستر وحفظها على القرص ──
    final disk = _MemDisk();
    final s1 = AppStore.forTesting();
    await s1.bootstrap(disk);
    injectDemoData(s1);
    await s1.login('amal', 'amal2026');
    final today = DateTime.now();
    final rooms = s1.rooms;
    const nStudents = 2000;
    for (var i = 0; i < nStudents; i++) {
      final room = rooms[i % rooms.length];
      s1.students.add(Student(
        id: 'm-$i',
        fullName: 'طالب رقم $i محمد',
        gradeLevel: room.gradeLevel,
        section: room.name,
        phone: '05991${i.toString().padLeft(5, '0')}',
        parentName: 'ولي $i',
        parentPhone: '05981${i.toString().padLeft(5, '0')}',
        nationalId: '${800000000 + i}',
        balance: 0,
      ));
      for (var k = 0; k < 6; k++) {
        s1.installments.add(Installment(
          id: 'm-inst-$i-$k',
          studentId: 'm-$i',
          title: 'قسط ${k + 1}',
          amount: 250,
          dueDate: today.subtract(Duration(days: (k * 30) - 60)),
          paidAmount: k.isEven ? 250 : 0,
        ));
      }
      for (var k = 0; k < 5; k++) {
        s1.payments.add(Payment(
          id: 'm-pay-$i-$k',
          receiptNumber: '2026/${100000 + i * 5 + k}',
          studentId: 'm-$i',
          amount: 250,
          method: 'cash',
          date: today.subtract(Duration(days: k * 30)),
          installmentId: 'm-inst-$i-$k',
        ));
      }
    }
    // جلسات 120 يوماً لكل شعبة، و25 يوم رصد لكل طالب ≈ 50 ألف رصد
    for (final room in rooms) {
      for (var d = 0; d < 120; d++) {
        final date = isoDate(today.subtract(Duration(days: d)));
        s1.sessions.add(ClassSession(id: 'ses_room_${room.id}_$date', groupId: '', roomId: room.id, sessionDate: date));
      }
    }
    for (var i = 0; i < nStudents; i++) {
      final room = rooms[i % rooms.length];
      for (var d = 0; d < 25; d++) {
        final date = isoDate(today.subtract(Duration(days: d)));
        final sid = 'ses_room_${room.id}_$date';
        s1.attendance.add(AttendanceMark(
          id: 'att_${sid}_m-$i',
          studentId: 'm-$i',
          date: date,
          status: i % 9 == 0 ? 'absent' : 'present',
          sessionId: sid,
          updatedAt: '${date}T07:30:00.000Z',
        ));
      }
    }
    final evals = s1.extraCloud.putIfAbsent('student_evaluations', () => []);
    for (var i = 0; i < nStudents; i++) {
      for (var k = 0; k < 6; k++) {
        evals.add(Evaluation(
          id: 'm-ev-$i-$k',
          studentId: 'm-$i',
          title: 'اختبار $k',
          score: 70,
          maxScore: 100,
          evaluationDate: isoDate(today.subtract(Duration(days: k * 10))),
          term: 'term_1',
        ).toCloud());
      }
    }
    for (final t in ['students', 'installments', 'payments', 'sessions', 'attendance', 'student_evaluations']) {
      s1.markDirty(t);
    }
    // ختم سيرفر لكل سجل
    void stamp(String table, Iterable<String> ids) =>
        s1.rememberServerStamps(table, {for (final id in ids) id: '2026-10-01T00:00:00.000Z'});
    stamp('students', s1.students.map((x) => x.id));
    stamp('installments', s1.installments.map((x) => x.id));
    stamp('payments', s1.payments.map((x) => x.id));
    stamp('sessions', s1.sessions.map((x) => x.id));
    stamp('attendance', s1.attendance.map((x) => x.id));
    stamp('student_evaluations', evals.map((x) => '${x['id']}'));
    await s1.flush();
    final sizes = {for (final e in disk.rowsByTable.entries) e.key: e.value.length}
      ..removeWhere((k, v) => v < 100);
    // ignore: avoid_print
    print('BENCH القرص: $sizes');

    // ── كلفة فكّ رسالة sqflite على خيط الواجهة (لا يحاكيها _MemDisk) ──
    final attRows = disk.rowsByTable['attendance']!.values.toList();
    int decodeMs(int n) {
      final msg = const StandardMessageCodec().encodeMessage({
        'columns': ['rid', 'table_name', 'data'],
        'rows': [for (var i = 0; i < n; i++) [i, 'attendance', jsonEncode(attRows[i % attRows.length])]],
      });
      final sw = Stopwatch()..start();
      const StandardMessageCodec().decodeMessage(msg);
      return sw.elapsedMilliseconds;
    }
    // ignore: avoid_print
    print('BENCH فكّ رسالة القناة: صفحة 2000 صف ${decodeMs(2000)}ms، رسالة 75000 صف ${decodeMs(75000)}ms');

    // ── مراقب التقطّع: نبضة كل 2ms، والفجوة بين نبضتين = تجمّد خيط الواجهة ──
    final clock = Stopwatch()..start();
    var last = 0;
    final stalls = <(String, int)>[];
    final maxByPhase = <String, int>{};
    final wallByPhase = <String, int>{};
    final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
      final now = clock.elapsedMilliseconds;
      final gap = now - last;
      last = now;
      if (gap > 8) stalls.add((phase, gap));
      if (gap > (maxByPhase[phase] ?? 0)) maxByPhase[phase] = gap;
    });

    Future<void> step(String name, Future<void> Function() body) async {
      phase = name;
      final t0 = clock.elapsedMilliseconds;
      await body();
      // تُترك النبضة تسجّل التجمّد على هذه المرحلة قبل تسمية التالية
      await Future<void>.delayed(const Duration(milliseconds: 6));
      wallByPhase[name] = clock.elapsedMilliseconds - t0;
    }

    final s = AppStore.forTesting();
    await step('1 bootstrap (النواة)', () => s.bootstrap(disk));
    await step('2 afterEnter (هجرات)', () => s.afterEnter());
    await step('3a sessions', () => s.ensureTables(const ['sessions']));
    await step('3b attendance', () => s.ensureTables(const ['attendance']));
    await step('3c payments', () => s.ensureTables(const ['payments']));
    await step('3d installments (+أرصدة)', () => s.ensureTables(const ['installments']));
    await step('4 الأرصدة بالخلفية + هدوء', () => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await step('5 prefetch المالية', () async {
      await s.ensureTables(const ['payments', 'installments', 'expenses', 'teacher_payouts']);
      await s.dueItemsYielding();
      s.expenses;
      s.teacherPayouts;
    });
    await step('6 حساب الرئيسية (buildDashboardAsync)', () async {
      await buildDashboardAsync(
        today: isoDate(today),
        students: s.students,
        rooms: s.roomsInViewedYear,
        sessions: s.sessions,
        attendance: s.attendance,
        installments: s.installments,
        payments: s.payments,
        calendar: s.settings.calendar,
        days: 1,
        chronicPercent: s.settings.followup.chronicPercent,
      );
    });
    await step('7 جداول لاحقة', () => s.ensureTables(const ['student_evaluations', 'audit_log', 'finance_requests']));
    await step('8 الثقيلة (إنذارات/اكتمال/اعتماد)', () async {
      await loadAbsenceAlertsAsync(s);
      await loadCompletionAsync(s);
      s.pendingApprovals;
      final month = isoDate(today).substring(0, 7);
      s.installments.where((i) => isoDate(i.dueDate).startsWith(month)).fold<double>(0, (n, i) => n + i.amount);
    });
    await step('9 flush', () => s.flush());
    timer.cancel();

    stalls.sort((a, b) => b.$2.compareTo(a.$2));
    // ignore: avoid_print
    print('BENCH المراحل (مدة / أطول تجمّد):');
    for (final p in wallByPhase.keys) {
      // ignore: avoid_print
      print('BENCH   $p: ${wallByPhase[p]}ms / ${maxByPhase[p] ?? 0}ms');
    }
    // ignore: avoid_print
    print('BENCH أطول 10 تجمّدات:');
    for (final st in stalls.take(10)) {
      // ignore: avoid_print
      print('BENCH   ${st.$2}ms في ${st.$1}');
    }
    expect(s.students.length, greaterThan(nStudents));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('BENCH تفصيل النواة', () async {
    final disk = _MemDisk();
    final s1 = AppStore.forTesting();
    await s1.bootstrap(disk);
    injectDemoData(s1);
    await s1.login('amal', 'amal2026');
    final rooms = s1.rooms;
    for (var i = 0; i < 2000; i++) {
      final room = rooms[i % rooms.length];
      s1.students.add(Student(id: 'm-$i', fullName: 'طالب $i', gradeLevel: room.gradeLevel, section: room.name, phone: '0599', parentName: 'و', parentPhone: '0598', nationalId: '${800000000 + i}', balance: 0));
    }
    s1.markDirty('students');
    s1.rememberServerStamps('attendance', {for (var i = 0; i < 85000; i++) 'att-$i': '2026-10-01T00:00:00.000Z'});
    for (var i = 0; i < 2000; i++) {
      s1.students[i].notes = 'x';
      s1.markRecord('students', s1.students[i].id);
    }
    await s1.flush();
    final saved = {for (final e in disk.rowsByTable.entries) e.key: Map.of(e.value)};
    Future<int> maxStall(Set<String> drop) async {
      disk.rowsByTable
        ..clear()
        ..addAll({for (final e in saved.entries) if (!drop.contains(e.key)) e.key: e.value});
      final clock = Stopwatch()..start();
      var last = 0;
      var worst = 0;
      final t = Timer.periodic(const Duration(milliseconds: 2), (_) {
        final now = clock.elapsedMilliseconds;
        if (now - last > worst) worst = now - last;
        last = now;
      });
      await AppStore.forTesting().bootstrap(disk);
      await Future<void>.delayed(const Duration(milliseconds: 6));
      t.cancel();
      return worst;
    }
    // ignore: avoid_print
    print('BENCH نواة كاملة: ${await maxStall({})}ms | بلا أختام: ${await maxStall({'__server_stamps'})}ms | بلا طلاب: ${await maxStall({'students'})}ms | بلا طابور: ${await maxStall({'__pending_syncs'})}ms');
    // ignore: avoid_print
    print('BENCH أحجام النواة: ${{for (final e in saved.entries) e.key: e.value.length}..removeWhere((k, v) => v < 50)}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
