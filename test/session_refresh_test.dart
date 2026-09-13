import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

void main() {
  tearDown(() {
    SupabaseAuth.clear();
    SupabaseAuth.onSessionChanged = null;
    SupabaseAuth.onSessionInvalid = null;
  });

  group('حفظ الجلسة بعد كل تجديد', () {
    test('التوكن المدوَّر يصل القرص، فالإقلاع التالي يجدّد بتوكن صالح', () async {
      final disk = FakeDisk();
      final store = AppStore.forTesting();
      await store.bootstrap(disk);
      injectDemoData(store);
      await store.login('amal', 'amal2026');

      // جلسة وصلت من السحابة عند الدخول
      SupabaseAuth.applySession({
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'expires_in': 3600,
        'user': {'app_metadata': {'role': 'tenant_admin', 'tenant_id': 't1'}},
      });
      await store.flush();
      expect(disk.settings['auth_refresh_token'], 'refresh-1');

      // السحابة تُدوّر التوكن عند التجديد: الجديد يجب أن يُكتب فوق القديم
      SupabaseAuth.applySession({
        'access_token': 'access-2',
        'refresh_token': 'refresh-2',
        'expires_in': 3600,
        'user': {'app_metadata': {'role': 'tenant_admin', 'tenant_id': 't1'}},
      });
      await store.flush();
      expect(disk.settings['auth_refresh_token'], 'refresh-2', reason: 'المستهلك كان يبقى فيفشل كل تجديد لاحق');
      expect(disk.settings['auth_access_token'], 'access-2');

      final next = AppStore.forTesting();
      await next.bootstrap(disk);
      expect(SupabaseAuth.refreshToken, 'refresh-2', reason: 'الإقلاع يستعيد الصالح لا المستهلك');
    });
  });

  group('انتهاء الجلسة نهائياً', () {
    test('رفض توكن التجديد يُخرج الجهاز ويشرح السبب بدل فشل صامت', () async {
      final disk = FakeDisk();
      final store = AppStore.forTesting();
      await store.bootstrap(disk);
      injectDemoData(store);
      await store.login('amal', 'amal2026');
      expect(store.loggedIn, isTrue);

      // بلا توكن تجديد: التجديد يعلن انتهاء الجلسة
      SupabaseAuth.restore(access: 'expired-token', refresh: null, expiry: DateTime.now());
      expect(await SupabaseAuth.refreshSession(), isFalse);

      expect(store.loggedIn, isFalse, reason: 'لا يبقى «داخلاً» وكل رفع يفشل');
      expect(SupabaseAuth.signedIn, isFalse);
      expect(store.sessionExpiredNotice, contains('انتهت جلسة الدخول'));

      // الدخول من جديد يمحو الإشعار
      await store.login('amal', 'amal2026');
      expect(store.sessionExpiredNotice, isNull);
    });

    test('انقطاع الشبكة ليس انتهاءً للجلسة', () async {
      var invalidated = false;
      SupabaseAuth.onSessionInvalid = () async => invalidated = true;
      // مضيف غير موجود: يرمي استثناء شبكة لا رفضاً من السحابة
      SupabaseAuth.restore(access: 'a', refresh: 'r', expiry: DateTime.now());

      expect(await SupabaseAuth.refreshSession(), isFalse);
      expect(invalidated, isFalse, reason: 'الجلسة تبقى حتى يعود الاتصال');
      expect(SupabaseAuth.refreshToken, 'r');
    });
  });
}
