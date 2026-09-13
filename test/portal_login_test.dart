import 'dart:convert';

import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// ردّ دالة `portal-login` لوليّ أمر مطابقٌ لما تعيده في السحابة.
Map<String, dynamic> _parentChoice() => {
      'tenant_id': 'tenant-1',
      'tenant_name': 'مدرسة الأمل النموذجية',
      'role': 'parent',
      'user': {
        'id': 'student-1',
        'name': 'أبو نور',
        'student_name': 'نور السوسي',
        'national_id': '401092580',
        'portal_code': '246810',
        'grade_level': 'عاشر',
        'section': 'أ',
      },
    };

void main() {
  tearDown(SupabaseAuth.clear);

  group('دخول البوابة', () {
    test('ولي الأمر يدخل برقم هوية ابنه وكلمة مروره، فتُفتح جلسته', () async {
      final requests = <http.Request>[];
      final result = await http.runWithClient(
        () => const PortalService().login('401092580', '246810'),
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/functions/v1/portal-login')) {
            return http.Response(
              jsonEncode({'token_hash': 'hash-1', 'choice': _parentChoice(), 'tenant': {'id': 'tenant-1'}}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // استبدال الرمز بجلسة — `verifyOtp`
          return http.Response(
            jsonEncode({
              'access_token': 'parent-token',
              'refresh_token': 'parent-refresh',
              'expires_in': 3600,
              'user': {
                'app_metadata': {'role': 'parent', 'tenant_id': 'tenant-1', 'portal_user_id': 'student-1'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(result.ok, isTrue, reason: result.error);
      final user = result.users.single;
      expect(user.isParent, isTrue);
      expect(user.id, 'student-1', reason: 'بيانات البوابة تُجلب بمعرّف الطالب');
      expect(user.name, 'أبو نور');
      expect(user.studentName, 'نور السوسي');
      expect(SupabaseAuth.role, 'parent', reason: 'الجلسة تحمل دوره فتحكمه سياسات القاعدة');

      // الطلب الأول بالمفتاح المنشور: لا جلسة بعد، وتوكن إدارة قديم كان يُرفض
      expect(requests.first.headers['Authorization'], 'Bearer ${SupabaseConfig.key}');
    });

    test('الطلب الأول يبقى بالمفتاح المنشور حتى لو كان على الجهاز توكن قديم', () async {
      SupabaseAuth.restore(access: 'stale-admin-token', refresh: 'r', expiry: DateTime.now());

      final requests = <http.BaseRequest>[];
      await http.runWithClient(
        () => supabaseInvoke('portal-login', const {'national_id': '1'}, anonymous: true),
        () => MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'error': 'رقم الهوية أو كلمة المرور غير صحيحة'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      expect(requests.single.headers['Authorization'], 'Bearer ${SupabaseConfig.key}');
    });

    test('خطأ السيرفر يُعرض كما هو، لا كأنه انقطاع إنترنت', () async {
      final data = await http.runWithClient(
        () => supabaseInvoke('portal-login', const {}, anonymous: true),
        () => MockClient((_) async => http.Response(
              jsonEncode({'error': 'رقم الهوية أو كلمة المرور غير صحيحة'}),
              401,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );
      expect(data['error'], 'رقم الهوية أو كلمة المرور غير صحيحة');
      expect(data['error'], isNot(contains('الإنترنت')));
    });

    test('ردٌّ ليس JSON يذكر رمز الحالة بدل رسالة انقطاع مضللة', () async {
      final data = await http.runWithClient(
        () => supabaseInvoke('portal-login', const {}, anonymous: true),
        () => MockClient((_) async => http.Response('<html>Bad Gateway</html>', 502)),
      );
      expect(data['error'], contains('502'));
      expect(data['error'], isNot(contains('الإنترنت')));
    });

    test('انقطاع الشبكة وحده يقول «تحتاج اتصالاً بالإنترنت»', () async {
      final data = await http.runWithClient(
        () => supabaseInvoke('portal-login', const {}, anonymous: true),
        () => MockClient((_) async => throw http.ClientException('Failed host lookup')),
      );
      expect(data['error'], contains('اتصالاً بالإنترنت'));
    });

    test('تعدّد الحسابات يُعيد الخيارات بلا فتح جلسة', () async {
      final result = await http.runWithClient(
        () => const PortalService().login('401092580', '246810'),
        () => MockClient((_) async => http.Response(
              jsonEncode({
                'choices': [
                  _parentChoice(),
                  {..._parentChoice(), 'role': 'student', 'tenant_id': 'tenant-2'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

      expect(result.users.length, 2);
      expect(result.users.first.roleLabel, 'ولي أمر');
      expect(SupabaseAuth.signedIn, isFalse, reason: 'الجلسة تُفتح بعد الاختيار');
    });
  });
}
