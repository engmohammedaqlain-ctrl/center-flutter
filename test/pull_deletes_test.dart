import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// سحابة وهمية: تردّ على قراءات PostgREST بصفوف الجداول التي نحددها، فيُختبر
/// سلوك السحب نفسه — أن ما حُذف في السحابة يُحذف على الجهاز — بلا اتصال حقيقي.
MockClient _cloud(Map<String, List<Map<String, dynamic>>> tables, {Set<String>? seen}) {
  return MockClient((request) async {
    final table = request.url.pathSegments.last;
    seen?.add(table);
    final rows = tables[table] ?? const <Map<String, dynamic>>[];
    // `select=id` يردّ المعرّفات وحدها كما يفعل PostgREST
    final body = request.url.queryParameters['select'] == 'id' ? [for (final r in rows) {'id': r['id']}] : rows;
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
}

Map<String, dynamic> _roomRow(String id, String name, String tenantId) => {
      'id': id,
      'name': name,
      'grade_level': 'عاشر',
      'capacity': 25,
      'stage_tier': 'secondary',
      'homeroom_teacher_id': null,
      'notes': '',
      'tenant_id': tenantId,
      'created_at': '2026-09-01T00:00:00.000Z',
      'updated_at': '2026-09-01T00:00:00.000Z',
    };

/// متجر داخل منشأة بجلسة صالحة.
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

  test('الشعبة المحذوفة من السحابة تختفي عن الجهاز بعد السحب', () async {
    final store = _store();
    final tenantId = store.currentTenant!.id;

    // شعبتان على الجهاز، ولم يبقَ في السحابة إلا واحدة: الثانية حُذفت هناك
    store.rooms.clear();
    store.putRows('rooms', [
      {..._roomRow('room-kept', 'شعبة (أ)', tenantId), 'sync_status': 'synced'},
      {..._roomRow('room-deleted', 'شعبة (ب)', tenantId), 'sync_status': 'synced'},
    ]);
    expect(store.rooms.length, 2);

    final seen = <String>{};
    final outcome = await http.runWithClient(
      () => store.sync.pullFromCloud(tenantId),
      () => _cloud({
        'rooms': [_roomRow('room-kept', 'شعبة (أ)', tenantId)],
      }, seen: seen),
    );

    expect(outcome.failedTables, isEmpty, reason: 'الجداول كلها وصلت');
    expect(seen.contains('rooms'), isTrue);
    expect(store.rooms.map((r) => r.id), ['room-kept'], reason: 'ما حُذف في السحابة يُحذف هنا');
    expect(outcome.removed, greaterThanOrEqualTo(1), reason: 'يُعلن للمستخدم كم سجلاً حُذف');
  });

  test('الشعبة التي لم تُرفع بعد لا تُحذف عند السحب', () async {
    final store = _store();
    final tenantId = store.currentTenant!.id;

    store.rooms.clear();
    // أُنشئت على الجهاز ولم تصل السحابة بعد
    store.upsertRoom(Classroom(id: 'room-local', name: 'شعبة (ج)', gradeLevel: 'عاشر', teacherId: ''));

    await http.runWithClient(
      () => store.sync.pullFromCloud(tenantId),
      () => _cloud({'rooms': const []}),
    );

    expect(store.rooms.map((r) => r.id), ['room-local'], reason: 'شغل المستخدم لا يُمحى قبل رفعه');
  });

  test('حذفٌ على الجهاز يصل السحابة طلبَ حذف بمعرّفه ومنشأته', () async {
    final store = _store();
    final tenantId = store.currentTenant!.id;

    store.rooms.clear();
    store.putRows('rooms', [
      {..._roomRow('room-gone', 'شعبة (د)', tenantId), 'sync_status': 'synced'},
    ]);
    store.deleteRoom('room-gone');

    final requests = <http.BaseRequest>[];
    final result = await http.runWithClient(
      () => store.sync.pushPendingChanges(tenantId),
      () => MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );

    final delete = requests.firstWhere((r) => r.method == 'DELETE');
    expect(delete.url.path, endsWith('/rest/v1/rooms'));
    expect(delete.url.queryParameters['id'], 'in.(room-gone)');
    expect(delete.url.queryParameters['tenant_id'], 'eq.$tenantId', reason: 'حذفٌ داخل منشأته وحدها');
    expect(result.failed, 0);
    expect(store.pendingSyncs.any((p) => p.recordId == 'room-gone'), isFalse, reason: 'تُسقط من الطابور بعد نجاحها');
  });

  test('السحب التزايدي يوفّق الحذف بجلب المعرّفات وحدها', () async {
    final store = _store();
    final tenantId = store.currentTenant!.id;

    store.rooms.clear();
    store.putRows('rooms', [
      {..._roomRow('room-kept', 'شعبة (أ)', tenantId), 'sync_status': 'synced'},
      {..._roomRow('room-deleted', 'شعبة (ب)', tenantId), 'sync_status': 'synced'},
    ]);

    // ختم سحب سابق بالجلسة نفسها: الجولة القادمة تزايدية
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(store.sync.lastPullKey(tenantId), '2026-09-10T00:00:00.000Z');
    await prefs.setString(store.sync.lastPullAuthKey(tenantId), store.sync.pullMarkFor(signedIn: true));
    expect(await store.sync.getLastPullAt(), isNotNull);

    await http.runWithClient(
      () => store.sync.pullFromCloud(tenantId),
      () => _cloud({
        'rooms': [_roomRow('room-kept', 'شعبة (أ)', tenantId)],
      }),
    );

    expect(store.rooms.map((r) => r.id), ['room-kept']);
  });
}
