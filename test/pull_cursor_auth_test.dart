import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// متجر داخل منشأة، بتفضيلات جهاز فارغة.
Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  return s;
}

void main() {
  tearDown(SupabaseAuth.clear);

  group('ختم آخر سحب يعرف الجلسة التي سحبت', () {
    test('ختمٌ قديم بلا علامة جلسة لا يُعتمد بعد الدخول: السحب التالي كامل', () async {
      final s = await _store();
      final tid = s.currentTenant!.id;
      final prefs = await SharedPreferences.getInstance();

      // جهاز سحب قبل الانتقال إلى Supabase Auth: الختم وحده بلا علامة، والقاعدة
      // المحمية كانت أعادت له صفر سجل على أنه سحب ناجح
      await prefs.setString(s.sync.lastPullKey(tid), '2026-09-13T10:00:00.000Z');

      SupabaseAuth.restore(access: 'token', refresh: 'refresh', expiry: DateTime.now().add(const Duration(hours: 1)));
      expect(await s.sync.getLastPullAt(), isNull, reason: 'سحب كامل يُعيد السجلات القديمة');
    });

    test('ختمٌ سُجّل بلا دخول لا يُعتمد بعد الدخول', () async {
      final s = await _store();
      final tid = s.currentTenant!.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(s.sync.lastPullKey(tid), '2026-09-13T10:00:00.000Z');
      await prefs.setString(s.sync.lastPullAuthKey(tid), s.sync.pullMarkFor(signedIn: false));

      expect(await s.sync.getLastPullAt(), '2026-09-13T10:00:00.000Z', reason: 'الجلسة نفسها: تزايدي كالمعتاد');

      SupabaseAuth.restore(access: 'token', refresh: 'refresh', expiry: DateTime.now().add(const Duration(hours: 1)));
      expect(await s.sync.getLastPullAt(), isNull);
    });

    test('ختمٌ سُجّل بجلسة دخول يبقى تزايدياً ما دامت الجلسة', () async {
      final s = await _store();
      final tid = s.currentTenant!.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(s.sync.lastPullKey(tid), '2026-09-13T10:00:00.000Z');
      await prefs.setString(s.sync.lastPullAuthKey(tid), s.sync.pullMarkFor(signedIn: true));

      SupabaseAuth.restore(access: 'token', refresh: 'refresh', expiry: DateTime.now().add(const Duration(hours: 1)));
      expect(await s.sync.getLastPullAt(), '2026-09-13T10:00:00.000Z');

      // خرجت الجلسة: لا يُبنى سحب الزائر على ختم الجلسة
      SupabaseAuth.clear();
      expect(await s.sync.getLastPullAt(), isNull);
    });
  });

  group('ختم آخر سحب يعرف الأعمدة التي سُحبت', () {
    test('ختمٌ سُجّل قبل إضافة عمود لا يُعتمد: السحب التالي كامل فيصل العمود في السجلات القديمة', () async {
      final s = await _store();
      final tid = s.currentTenant!.id;
      final prefs = await SharedPreferences.getInstance();

      // جهاز سحب الطلاب قبل `parent_portal_code`: علامة الجلسة وحدها بلا بصمة
      // أعمدة. السحب التزايدي لا يعيد الطالب الذي لم يتغيّر، فتبقى كلمة مرور ولي
      // الأمر فارغة على الهاتف وهي محفوظة في السحابة
      await prefs.setString(s.sync.lastPullKey(tid), '2026-09-13T10:00:00.000Z');
      await prefs.setString(s.sync.lastPullAuthKey(tid), 'session');
      SupabaseAuth.restore(access: 'token', refresh: 'refresh', expiry: DateTime.now().add(const Duration(hours: 1)));
      expect(await s.sync.getLastPullAt(), isNull);

      // وبصمة أعمدة أخرى كذلك
      await prefs.setString(s.sync.lastPullAuthKey(tid), 'session:00000000');
      expect(await s.sync.getLastPullAt(), isNull);
    });

    test('البصمة ثابتة، وتشمل أعمدة الطلاب الجديدة', () {
      expect(pullColumnsSignature, pullColumnsSignature);
      expect(pullColumnsSignature, matches(RegExp(r'^[0-9a-f]+$')));
      expect(tableAllowedColumns['students'], contains('parent_portal_code'));
    });
  });

  group('التوكن المنتهي أثناء المزامنة', () {
    test('ردّ القاعدة على توكن منتهٍ يُعرف من رمزه لا من حالته وحدها', () {
      expect(SupabaseAuth.isExpiredResponse(401, ''), isTrue);
      expect(SupabaseAuth.isExpiredResponse(403, ''), isTrue);
      expect(
        SupabaseAuth.isExpiredResponse(400, '{"code":"PGRST303","message":"JWT expired"}'),
        isTrue,
        reason: 'PostgREST يردّ 400 أحياناً مع PGRST303',
      );
      expect(SupabaseAuth.isExpiredResponse(409, 'duplicate key value'), isFalse);
      expect(SupabaseAuth.isExpiredResponse(200, 'ok'), isFalse);
    });

    test('الطلب يُعاد مرة واحدة بعد تجديد فاشل أو ناجح، لا أكثر', () async {
      // بلا توكن تجديد لا تُجدَّد الجلسة، فلا إعادة محاولة ولا حلقة لا تنتهي
      SupabaseAuth.clear();
      var calls = 0;
      final result = await SupabaseAuth.withRetryOnExpiry<int>(
        () async {
          calls++;
          return 401;
        },
        expired: (r) => r == 401,
      );
      expect(calls, 1, reason: 'التجديد فشل فلا إعادة');
      expect(result, 401);
    });

    test('الطلب الناجح لا يُعاد', () async {
      var calls = 0;
      final result = await SupabaseAuth.withRetryOnExpiry<int>(
        () async {
          calls++;
          return 204;
        },
        expired: (r) => r == 401,
      );
      expect(calls, 1);
      expect(result, 204);
    });

    test('رسالة الخطأ تُقرأ: انتهت الجلسة لا JSON خام', () {
      final message = describeSupabaseError(
        Exception('{"code":"PGRST303","details":null,"hint":null,"message":"JWT expired"}'),
        'rooms',
      );
      expect(message, contains('انتهت جلسة الدخول'));
      expect(message, isNot(contains('PGRST303')));
    });
  });

  group('ترويسات الطلب', () {
    test('تحمل توكن الجلسة لا المفتاح المنشور حين يوجد', () {
      expect(SupabaseConfig.headers['Authorization'], 'Bearer ${SupabaseConfig.key}');

      SupabaseAuth.restore(access: 'session-token', refresh: 'r', expiry: DateTime.now().add(const Duration(hours: 1)));
      expect(SupabaseConfig.headers['Authorization'], 'Bearer session-token');
      expect(SupabaseConfig.headers['apikey'], SupabaseConfig.key, reason: 'المفتاح يبقى معرّف المشروع');
    });

    test('اسم المستخدم يصير بريد الدخول الداخلي كما في النسخة المكتبية', () {
      expect(SupabaseAuth.emailFor('  Noon '), 'noon@login.center-system.app');
      expect(SupabaseAuth.isValidUsername('noon'), isTrue);
      expect(SupabaseAuth.isValidUsername('no'), isFalse, reason: '3 أحرف على الأقل');
      expect(SupabaseAuth.isValidUsername('student-1'), isFalse, reason: 'بادئة محجوزة للبوابات');
      expect(SupabaseAuth.isValidUsername('نون'), isFalse);
    });
  });
}
