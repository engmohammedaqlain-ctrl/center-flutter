import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/widgets/table_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

void main() {
  group('تحميل كسول', () {
    test('bootstrap يحمّل النواة فقط ولا ينتظر الجداول المؤجّلة', () async {
      final disk = FakeDisk();
      await disk.saveTable('students', [
        {'id': 's1', 'full_name': 'طالب', 'sync_status': 'synced'},
      ]);
      await disk.saveTable('attendance', [
        {'id': 'a1', 'student_id': 's1', 'status': 'present', 'sync_status': 'synced'},
      ]);
      await disk.saveTable('payments', [
        {'id': 'p1', 'amount': 10, 'sync_status': 'synced'},
      ]);
      await disk.saveTable('installments', [
        {'id': 'i1', 'amount': 100, 'sync_status': 'synced'},
      ]);

      final s = AppStore.forTesting();
      await s.bootstrap(disk);

      expect(s.ready, isTrue);
      expect(s.loadedTables.contains('students'), isTrue);
      expect(s.loadedTables.contains('attendance'), isFalse);
      expect(s.loadedTables.contains('payments'), isFalse);
      expect(s.loadedTables.contains('installments'), isFalse);
      expect(s.attendance, isEmpty);
      expect(s.payments, isEmpty);
    });

    test('ensureTables يحمّل الجدول المؤجّل مرة واحدة من القرص', () async {
      final disk = FakeDisk();
      await disk.saveTable('attendance', [
        {
          'id': 'a1',
          'student_id': 's1',
          'session_id': 'sess1',
          'status': 'present',
          'sync_status': 'synced',
        },
      ]);
      await disk.saveTable('sessions', [
        {
          'id': 'sess1',
          'room_id': 'r1',
          'date': '2026-01-01',
          'sync_status': 'synced',
        },
      ]);

      final s = AppStore.forTesting();
      await s.bootstrap(disk);
      expect(s.tablesReady(const ['attendance', 'sessions']), isFalse);

      await s.ensureTables(const ['attendance', 'sessions']);
      expect(s.tablesReady(const ['attendance', 'sessions']), isTrue);
      expect(s.attendance, isNotEmpty);
      expect(s.sessions, isNotEmpty);

      final before = s.attendance.length;
      await s.ensureTables(const ['attendance', 'sessions']);
      expect(s.attendance.length, before, reason: 'إعادة الاستدعاء لا تعيد التحميل');
    });

    test('hydrateOnPull يكتب المؤجّل للقرص فقط إن لم يُحمَّل', () async {
      final s = AppStore.forTesting();
      await s.bootstrap(FakeDisk());
      expect(s.hydrateOnPull('students'), isTrue);
      expect(s.hydrateOnPull('attendance'), isFalse);

      await s.ensureTables(const ['attendance']);
      expect(s.hydrateOnPull('attendance'), isTrue);
    });

    test('ensureTables يظهر الجداول غير الجاهزة ثم يجهّزها', () async {
      final disk = FakeDisk();
      await disk.saveTable('expenses', [
        {'id': 'e1', 'amount': 5, 'expense_date': '2026-01-01', 'sync_status': 'synced'},
      ]);
      final s = AppStore.forTesting();
      await s.bootstrap(disk);
      expect(s.tablesReady(const ['expenses']), isFalse);
      await s.ensureTables(const ['expenses']);
      expect(s.tablesReady(const ['expenses']), isTrue);
      expect(s.expenses, isNotEmpty);
    });

    test('ensureTables يحمّل التقييمات المؤجّلة من القرص', () async {
      final disk = FakeDisk();
      await disk.saveTable('student_evaluations', [
        {
          'id': 'e1',
          'student_id': 's1',
          'group_id': 'g1',
          'score': 18,
          'max_score': 20,
          'sync_status': 'synced',
        },
      ]);
      final s = AppStore.forTesting();
      await s.bootstrap(disk);
      expect(s.tablesReady(const ['student_evaluations']), isFalse);
      expect(s.evaluations, isEmpty);

      await s.ensureTables(const ['student_evaluations']);
      expect(s.tablesReady(const ['student_evaluations']), isTrue);
      expect(s.evaluations, isNotEmpty);
    });
  });

  group('TableGate', () {
    testWidgets('المحتوى فوري إن الجداول محمّلة مسبقاً', (tester) async {
      final store = AppStore.forTesting();
      // bootstrap يستخدم Delayed(zero) — يحتاج runAsync خارج FakeAsync
      await tester.runAsync(() => store.bootstrap(NoPersistence()));
      store.loadedTables.add('expenses');

      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: const MaterialApp(
            home: Scaffold(
              body: TableGate(
                tables: ['expenses'],
                child: Text('فوري'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('فوري'), findsOneWidget);
    });
  });
}
