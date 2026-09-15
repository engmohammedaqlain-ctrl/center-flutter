import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _png = 'data:image/png;base64,iVBORw0KGgo=';

AppStore _store({bool online = true}) {
  SharedPreferences.setMockInitialValues({});
  final s = AppStore.forTesting()..networkEnabled = online;
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  SupabaseAuth.restore(
    access: 'token',
    refresh: 'refresh',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    savedClaims: {'role': 'tenant_admin', 'tenant_id': s.currentTenant!.id},
  );
  s.pendingSyncs.clear();
  return s;
}

MockClient _cloud(List<http.BaseRequest> seen, {int storageStatus = 200, String selectBody = '[]'}) =>
    MockClient((request) async {
      seen.add(request);
      if (request.url.path.startsWith('/storage/')) {
        if (request.method == 'GET' && storageStatus == 200) {
          return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/png'});
        }
        return http.Response('{}', storageStatus);
      }
      if (request.method == 'GET') {
        return http.Response(selectBody, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('[]', 201, headers: {'content-type': 'application/json; charset=utf-8'});
    });

void main() {
  tearDown(SupabaseAuth.clear);

  test('الإشعار يُرفع للحاوية، والصف يحمل مساره لا الصورة', () async {
    final s = _store();
    final tenantId = s.currentTenant!.id;
    final seen = <http.BaseRequest>[];

    await http.runWithClient(() => s.saveFinanceAttachment('pay-1', 'payment', _png), () => _cloud(seen));

    final upload = seen.firstWhere((r) => r.url.path.contains('/storage/v1/object/finance-notices/'));
    expect(upload.url.path, endsWith('$tenantId/pay-1.png'));

    final row = s.financeAttachment('pay-1')!;
    expect(row['storage_path'], '$tenantId/pay-1.png');
    expect(row['sync_status'], 'synced');

    final queued = s.pendingSyncs.firstWhere((p) => p.tableName == 'finance_attachments');
    expect(queued.payload!.containsKey('image'), isFalse, reason: 'الصورة لا تُرفع في الصف');
    expect(queued.payload!['storage_path'], '$tenantId/pay-1.png');
    await s.flush();
  });

  test('بلا اتصال: يبقى على الجهاز ويُرفع عند عودة الاتصال', () async {
    final s = _store(online: false);
    await s.saveFinanceAttachment('pay-2', 'payment', _png);

    expect(s.financeAttachment('pay-2')!['storage_path'], isNull);

    s.networkEnabled = true;
    final seen = <http.BaseRequest>[];
    expect(await http.runWithClient(s.flushPendingNotices, () => _cloud(seen)), 1);
    expect(s.financeAttachment('pay-2')!['storage_path'], endsWith('pay-2.png'));
    await s.flush();
  });

  test('حذف الإشعار يزيل ملفه وصفه', () async {
    final s = _store();
    final seen = <http.BaseRequest>[];

    await http.runWithClient(() async {
      await s.saveFinanceAttachment('pay-3', 'payment', _png);
      await s.saveFinanceAttachment('pay-3', 'payment', null);
      await Future<void>.delayed(Duration.zero);
    }, () => _cloud(seen));

    expect(s.financeAttachment('pay-3'), isNull);
    expect(seen.any((r) => r.method == 'DELETE' && r.url.path.endsWith('/storage/v1/object/finance-notices')), isTrue);
    // صفٌّ لم يصل السحابة بعد: حذفه يُسقط رفعه المعلّق بدل رفعٍ ثم حذف
    expect(s.pendingSyncs.where((p) => p.tableName == 'finance_attachments'), isEmpty);
    await s.flush();
  });

  test('فتح السند ينزّل الصورة من مسارها مرة واحدة', () async {
    final s = _store();
    final path = '${s.currentTenant!.id}/pay-4.png';
    final seen = <http.BaseRequest>[];

    final image = await http.runWithClient(
      () => s.loadNoticeImage('pay-4'),
      () => _cloud(seen, selectBody: jsonEncode([
            {'id': 'pay-4', 'record_type': 'payment', 'storage_path': path},
          ])),
    );

    expect(image, startsWith('data:image/png;base64,'));
    final again = <http.BaseRequest>[];
    expect(await http.runWithClient(() => s.loadNoticeImage('pay-4'), () => _cloud(again)), isNotNull);
    expect(again, isEmpty, reason: 'صارت على الجهاز');
    await s.flush();
  });

  test('جدول الإشعارات مُزامَن ولا يُسحب دورياً', () {
    expect(syncedTables, contains('finance_attachments'));
    expect(tableAllowedColumns['finance_attachments'], contains('storage_path'));
    expect(tableAllowedColumns['finance_attachments'], isNot(contains('image')));
  });
  test('الإشعار يُرفق بسند الصرف وبسند أجر المعلم كما بسند القبض', () async {
    final s = _store();
    final tenantId = s.currentTenant!.id;
    final seen = <http.BaseRequest>[];

    await http.runWithClient(() async {
      await s.saveFinanceAttachment('exp-1', 'expense', _png);
      await s.saveFinanceAttachment('pay-out-1', 'payout', _png);
    }, () => _cloud(seen));

    expect(s.financeAttachment('exp-1')!['record_type'], 'expense');
    expect(s.financeAttachment('pay-out-1')!['record_type'], 'payout');
    expect(
      seen.where((r) => r.url.path.startsWith('/storage/v1/object/finance-notices/$tenantId/')),
      hasLength(2),
    );
    await s.flush();
  });
}
