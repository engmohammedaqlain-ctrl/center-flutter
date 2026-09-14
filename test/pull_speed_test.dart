import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppStore _store() {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore.forTesting()..networkEnabled = true;
  injectDemoData(store);
  store.currentTenant = store.tenants.first;
  SupabaseAuth.restore(
    access: 'token',
    refresh: 'refresh',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    savedClaims: {'role': 'tenant_admin', 'tenant_id': store.currentTenant!.id},
  );
  return store;
}

void main() {
  tearDown(SupabaseAuth.clear);

  group('التشغيل المحدود المتوازي', () {
    test('يحفظ ترتيب النتائج ولا يتجاوز حدّه', () async {
      var active = 0;
      var peak = 0;
      final out = await mapPooled(List.generate(20, (i) => i), 6, (i) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration(milliseconds: 5 + (i * 7) % 11));
        active--;
        return i * 2;
      });

      expect(out, List.generate(20, (i) => i * 2));
      expect(peak, 6);
    });

    test('قائمة فارغة لا تنتظر شيئاً', () async {
      expect(await mapPooled(<int>[], 6, (i) async => i), isEmpty);
    });
  });

  group('السحب', () {
    test('الجداول تُطلب معاً، والصفوف تُطبَّق كما هي', () async {
      final store = _store();
      final tenantId = store.currentTenant!.id;
      final requested = <String>[];
      var inFlight = 0;
      var peak = 0;

      final outcome = await http.runWithClient(
        () => store.sync.pullFromCloud(tenantId),
        () => MockClient((request) async {
          final table = request.url.pathSegments.last;
          requested.add(table);
          inFlight++;
          if (inFlight > peak) peak = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          inFlight--;
          final rows = table == 'rooms'
              ? [
                  {
                    'id': 'room-cloud',
                    'name': 'شعبة (ج)',
                    'grade_level': 'عاشر',
                    'capacity': 30,
                    'teacher_id': null,
                    'notes': '',
                    'tenant_id': tenantId,
                    'created_at': '2026-09-14T10:00:00.000Z',
                    'updated_at': '2026-09-14T10:00:00.000Z',
                    'server_updated_at': '2026-09-14T10:00:00.000Z',
                  },
                ]
              : const <Map<String, dynamic>>[];
          return http.Response(jsonEncode(rows), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      expect(outcome.failedTables, isEmpty);
      expect(store.roomById('room-cloud')?.name, 'شعبة (ج)');
      expect(peak, greaterThan(1), reason: 'لا ينتظر جدولٌ جدولاً');
      expect(peak, lessThanOrEqualTo(pullConcurrency));
      expect(requested, isNot(contains('class_announcements')), reason: 'جدول أُزيل من السحابة');
      expect(requested, isNot(contains('student_attachments')));
    });
  });
}
