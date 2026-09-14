import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مطابقة المزامنة التلقائية لـ `startAutoSync` في sync.ts — صفاً صفاً من جدول
/// الخطة. `tester.pump` يقدّم ساعة وهمية فتُفحص المهل بدقة بلا انتظار حقيقي.
///
/// | الحدث                | الويب                 | الجوال                |
/// | تعديل محلي           | رفع بعد ٣ ث           | رفع بعد ٣ ث           |
/// | رفع ناجح             | إشارة changed         | إشارة changed         |
/// | إشارة من جهاز آخر    | سحب بعد ١٫٥ ث         | سحب بعد ١٫٥ ث         |
/// | الانضمام للقناة       | سحب فوري              | سحب فوري              |
/// | العودة للتطبيق       | سحب، مرة كل ٦٠ ث      | سحب، مرة كل ٦٠ ث      |
/// | عودة الاتصال         | رفع وسحب فوريان       | رفع وسحب فوريان       |

/// متجر بمزامنة تلقائية ومنشأة مسجّلة، وطابور فارغ.
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
  store.pendingSyncs.clear();
  store.autoSync = true;
  return store;
}

/// سحابة تقبل كل رفع وتردّ الصفوف بختمها، وتردّ السحب فارغاً.
MockClient _cloud(List<http.Request> seen) => MockClient((request) async {
      seen.add(request);
      final body = request.method == 'POST' ? jsonDecode(request.body) : null;
      final rows = body is List
          ? [
              for (final r in body) {'id': r['id'], 'server_updated_at': '2026-09-15T10:00:00Z'},
            ]
          : const [];
      return http.Response(jsonEncode(rows), request.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

Future<void> _finish(WidgetTester tester, AppStore store) async {
  store.stopAutoSync();
  await store.flush();
  SupabaseAuth.clear();
}

void main() {
  testWidgets('تعديل محلي: رفع بعد ٣ ثوانٍ لا قبلها، ثم إشارة changed', (tester) async {
    final store = _store();
    final seen = <http.Request>[];

    await http.runWithClient(() async {
      store.upsertRoom(Classroom(id: 'room-auto', name: 'شعبة (د)', gradeLevel: 'عاشر', teacherId: ''));
      expect(store.lastAutoPushDelay, AppStore.autoPushDelay);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(seen.where((r) => r.method == 'POST'), isEmpty, reason: 'التعديلات المتتالية تُجمع');

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump();
    }, () => _cloud(seen));

    expect(seen.where((r) => r.method == 'POST' && r.url.path.endsWith('/rooms')), isNotEmpty);
    expect(store.pendingSyncs, isEmpty, reason: 'رُفع');
    expect(store.peerNotifications, 1, reason: 'الأجهزة الأخرى تُنبَّه لتسحب');
    await _finish(tester, store);
  });

  testWidgets('تعديلات متتالية تُجمع في رفع واحد', (tester) async {
    final store = _store();
    final seen = <http.Request>[];

    await http.runWithClient(() async {
      for (var i = 0; i < 3; i++) {
        store.upsertRoom(Classroom(id: 'room-$i', name: 'شعبة $i', gradeLevel: 'عاشر', teacherId: ''));
        await tester.pump(const Duration(seconds: 2));
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump();
    }, () => _cloud(seen));

    expect(seen.where((r) => r.method == 'POST' && r.url.path.endsWith('/rooms')), hasLength(1));
    expect(store.peerNotifications, 1);
    await _finish(tester, store);
  });

  testWidgets('إشارة من جهاز آخر: سحب بعد ١٫٥ ثانية', (tester) async {
    final store = _store();
    store.handlePeerChanged();

    expect(store.lastAutoPullDelay, AppStore.autoPullDelay);
    expect(AppStore.autoPullDelay, const Duration(milliseconds: 1500));
    expect(store.autoPullScheduled, isTrue);
    await _finish(tester, store);
  });

  testWidgets('الانضمام للقناة: سحب فوري', (tester) async {
    final store = _store();
    store.handleRealtimeJoined();

    expect(store.lastAutoPullDelay, Duration.zero);
    expect(store.lastAutoPushDelay, isNull, reason: 'لا شيء ينتظر الرفع');
    await _finish(tester, store);
  });

  testWidgets('عودة الاتصال: رفع وسحب فوريان لما تعثّر', (tester) async {
    final store = _store();
    store.pendingSyncs.add(PendingSync(
      id: 900,
      tableName: 'rooms',
      recordId: 'room-stalled',
      action: 'INSERT',
      createdAt: '2026-09-15T08:00:00Z',
      lastError: 'تعذّر الاتصال',
    ));
    store.handleRealtimeJoined();

    expect(store.lastAutoPushDelay, Duration.zero);
    expect(store.lastAutoPullDelay, Duration.zero);
    await _finish(tester, store);
  });

  testWidgets('العودة للتطبيق: سحب، ولا أكثر من مرة في الدقيقة', (tester) async {
    final store = _store();
    final t0 = DateTime(2026, 9, 15, 10);

    store.pullOnResume(t0);
    expect(store.lastAutoPullDelay, Duration.zero);

    store.lastAutoPullDelay = null;
    store.pullOnResume(t0.add(const Duration(seconds: 59)));
    expect(store.lastAutoPullDelay, isNull, reason: 'أقل من دقيقة على آخر سحب');

    store.pullOnResume(t0.add(const Duration(seconds: 61)));
    expect(store.lastAutoPullDelay, Duration.zero);
    await _finish(tester, store);
  });

  testWidgets('بعد تسجيل الخروج لا يُجدول شيء', (tester) async {
    final store = _store();
    store.stopAutoSync();
    store.handlePeerChanged();
    store.upsertRoom(Classroom(id: 'room-off', name: 'شعبة (هـ)', gradeLevel: 'عاشر', teacherId: ''));

    expect(store.autoPullScheduled, isFalse);
    expect(store.autoPushScheduled, isFalse);
    await _finish(tester, store);
  });
}
