import 'package:center_mobile/data/supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// دالة السيرفر تسمح بـ `authorization, x-client-info, apikey, content-type` فقط.
/// إرسال `Prefer` معها — وهي ترويسة PostgREST — يجعل المتصفح يمنع الطلب في فحصه
/// المسبق، فيظهر الحذف وكأنه انقطاع إنترنت.

void main() {
  setUp(() => SupabaseAuth.restore(
        access: 'token',
        refresh: 'refresh',
        expiry: DateTime.now().add(const Duration(hours: 1)),
        savedClaims: const {'role': 'developer'},
      ));
  tearDown(SupabaseAuth.clear);

  test('استدعاء دالة السيرفر بلا Prefer، ومعه توكن صاحب الجلسة', () async {
    http.BaseRequest? sent;
    await http.runWithClient(
      () => supabaseInvoke('admin-tenants', {'action': 'delete_tenant', 'tenant_id': 't1'}),
      () => MockClient((request) async {
        sent = request;
        return http.Response('{}', 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

    expect(sent!.headers.keys.map((k) => k.toLowerCase()), isNot(contains('prefer')));
    expect(sent!.headers['Authorization'], 'Bearer token');
    expect(sent!.url.path, endsWith('/functions/v1/admin-tenants'));
  });

  test('المخزن كذلك: توقيع رابط بلا Prefer', () async {
    http.BaseRequest? sent;
    await http.runWithClient(
      () => storageSignedUrl('course_materials', 't1/file.pdf'),
      () => MockClient((request) async {
        sent = request;
        return http.Response('{"signedURL":"/object/sign/x"}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

    expect(sent!.headers.keys.map((k) => k.toLowerCase()), isNot(contains('prefer')));
  });

  test('قراءة الجداول تبقى على Prefer — هي ترويسة PostgREST', () {
    expect(SupabaseConfig.headers['Prefer'], 'return=minimal');
    expect(SupabaseConfig.authHeaders.containsKey('Prefer'), isFalse);
    expect(SupabaseConfig.authHeaders['apikey'], isNotNull);
  });
}
