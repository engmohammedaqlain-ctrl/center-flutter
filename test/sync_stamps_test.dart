import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _room(String id, String name, String tenantId, String serverStamp) => {
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
      'server_updated_at': serverStamp,
    };

/// سحابة وهمية: جداول، ومعها سجل المحذوفات الذي تملؤه القاعدة.
MockClient _cloud(
  Map<String, List<Map<String, dynamic>>> tables, {
  List<Map<String, dynamic>> deleted = const [],
  List<Uri>? seen,
}) {
  return MockClient((request) async {
    seen?.add(request.url);
    final table = request.url.pathSegments.last;
    final rows = table == 'deleted_records' ? deleted : (tables[table] ?? const <Map<String, dynamic>>[]);
    final columns = request.url.queryParameters['select'] ?? '*';
    final projected = columns == '*'
        ? rows
        : [
            for (final r in rows)
              {for (final c in columns.split(',')) c: r[c]},
          ];
    return http.Response(
      jsonEncode(projected),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

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
  store.rooms.clear();
  return store;
}

void main() {
  tearDown(SupabaseAuth.clear);

  group('ما يستحق الجلب', () {
    test('السجل الذي يختلف ختم سيرفره وحده', () {
      final remote = [
        {'id': 'a', 'server_updated_at': '2026-09-13T10:00:00Z'},
        {'id': 'b', 'server_updated_at': '2026-09-13T11:00:00Z'},
      ];
      final local = {'a': '2026-09-13T10:00:00Z'};

      expect(pickChangedIds(remote, local), ['b'], reason: 'ما رفعناه نحن لا يُجلب ثانيةً');
      expect(pickChangedIds(remote, const {}), ['a', 'b'], reason: 'ما لا نملكه يُجلب');
    });

    test('الأحدث بين ختمين', () {
      expect(laterStamp('2026-09-13T10:00:00Z', '2026-09-13T11:00:00Z'), '2026-09-13T11:00:00Z');
      expect(laterStamp('2026-09-13T12:00:00Z', '2026-09-13T11:00:00Z'), '2026-09-13T12:00:00Z');
      expect(laterStamp(null, '2026-09-13T11:00:00Z'), '2026-09-13T11:00:00Z');
      expect(laterStamp('2026-09-13T11:00:00Z', null), '2026-09-13T11:00:00Z');
    });
  });

  group('حذفٌ قادم من سجل المحذوفات', () {
    test('يُطبَّق على المتزامن، ويُترك للمعلّق ولما أُنشئ بعد الحذف', () {
      const deletedAt = '2026-09-13T10:00:00Z';

      expect(
        shouldApplyRemoteDelete(existsLocally: true, localStamp: '2026-09-13T09:00:00Z', deletedAt: deletedAt, isPending: false),
        isTrue,
      );
      expect(
        shouldApplyRemoteDelete(existsLocally: false, localStamp: null, deletedAt: deletedAt, isPending: false),
        isFalse,
        reason: 'ليس عندنا أصلاً',
      );
      expect(
        shouldApplyRemoteDelete(existsLocally: true, localStamp: '2026-09-13T09:00:00Z', deletedAt: deletedAt, isPending: true),
        isFalse,
        reason: 'له تعديل معلّق',
      );
      expect(
        shouldApplyRemoteDelete(existsLocally: true, localStamp: '2026-09-13T11:00:00Z', deletedAt: deletedAt, isPending: false),
        isFalse,
        reason: 'نسخةٌ أُنشئت بعد الحذف',
      );
    });
  });

  group('السحب بختم السيرفر', () {
    test('أول سحب يجلب الجدول كاملاً ويحفظ الأختام والمؤشر', () async {
      final store = _store();
      final tenantId = store.currentTenant!.id;

      await http.runWithClient(
        () => store.sync.pullFromCloud(tenantId),
        () => _cloud({
          'rooms': [_room('r1', 'شعبة (أ)', tenantId, '2026-09-13T10:00:00Z')],
        }),
      );

      expect(store.rooms.map((r) => r.id), ['r1']);
      expect(store.serverStamp('rooms', 'r1'), '2026-09-13T10:00:00Z');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(store.sync.cursorKey(tenantId, 'rooms')), '2026-09-13T10:00:00Z');
    });

    test('السحب التالي لا يجلب إلا ما تغيّر ختمه', () async {
      final store = _store();
      final tenantId = store.currentTenant!.id;
      final cloud = {
        'rooms': [_room('r1', 'شعبة (أ)', tenantId, '2026-09-13T10:00:00Z')],
      };

      await http.runWithClient(() => store.sync.pullFromCloud(tenantId), () => _cloud(cloud));

      // جولة ثانية بلا تغيير: تُجلب المعرّفات والأختام فقط، ولا سجل كامل
      final seen = <Uri>[];
      final outcome = await http.runWithClient(
        () => store.sync.pullFromCloud(tenantId),
        () => _cloud(cloud, seen: seen),
      );

      expect(outcome.pulled, 0, reason: 'لا شيء تغيّر');
      final roomRequests = seen.where((u) => u.pathSegments.last == 'rooms');
      expect(
        roomRequests.every((u) => u.queryParameters['select'] == 'id,server_updated_at'),
        isTrue,
        reason: 'الأختام وحدها تُنزَّل، لا الجدول',
      );

      // تعديلٌ في السحابة بختم أحدث: يصل هذه المرة
      cloud['rooms'] = [_room('r1', 'شعبة (ب)', tenantId, '2026-09-13T12:00:00Z')];
      await http.runWithClient(() => store.sync.pullFromCloud(tenantId), () => _cloud(cloud));
      expect(store.rooms.single.name, 'شعبة (ب)');
    });

    test('سجل المحذوفات يحذف الشعبة من الجهاز بلا جلب الجدول كله', () async {
      final store = _store();
      final tenantId = store.currentTenant!.id;
      final cloud = {
        'rooms': [
          _room('r1', 'شعبة (أ)', tenantId, '2026-09-13T10:00:00Z'),
          _room('r2', 'شعبة (ب)', tenantId, '2026-09-13T10:00:00Z'),
        ],
      };
      await http.runWithClient(() => store.sync.pullFromCloud(tenantId), () => _cloud(cloud));
      expect(store.rooms.length, 2);

      // حُذفت على جهاز آخر: القاعدة سجّلتها في `deleted_records`
      cloud['rooms'] = [_room('r1', 'شعبة (أ)', tenantId, '2026-09-13T10:00:00Z')];
      final outcome = await http.runWithClient(
        () => store.sync.pullFromCloud(tenantId),
        () => _cloud(cloud, deleted: [
          {
            'table_name': 'rooms',
            'record_id': 'r2',
            'deleted_at': '2026-09-13T11:00:00Z',
            'tenant_id': tenantId,
          },
        ]),
      );

      expect(store.rooms.map((r) => r.id), ['r1'], reason: 'الحذف يصل بلا تنزيل المعرّفات كلها');
      expect(outcome.removed, 1);
      expect(store.serverStamp('rooms', 'r2'), isNull, reason: 'ختمه يسقط معه');
    });

    test('الحذف القادم لا يمسّ سجلاً له تعديل معلّق على الجهاز', () async {
      final store = _store();
      final tenantId = store.currentTenant!.id;
      final cloud = {
        'rooms': [_room('r1', 'شعبة (أ)', tenantId, '2026-09-13T10:00:00Z')],
      };
      await http.runWithClient(() => store.sync.pullFromCloud(tenantId), () => _cloud(cloud));

      store.upsertRoom(store.rooms.single..name = 'شعبة معدّلة');

      await http.runWithClient(
        () => store.sync.pullFromCloud(tenantId),
        () => _cloud({'rooms': const []}, deleted: [
          {
            'table_name': 'rooms',
            'record_id': 'r1',
            'deleted_at': '2026-09-13T11:00:00Z',
            'tenant_id': tenantId,
          },
        ]),
      );

      expect(store.rooms.map((r) => r.id), ['r1'], reason: 'تعديل لم يُرفع لا يُمحى');
    });
  });
}
