import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/main.dart';
import 'package:center_mobile/screens/portal_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// فتح التطبيق بجلسة محفوظة: من الشعار إلى البوابة مباشرةً.
///
/// كان نموذج الدخول يظهر كاملاً بينهما — تُطفأ شاشة الإقلاع ثم تنزلق البوابة
/// فوقه بحركة انتقال — فيظن المستخدم أنه مطالَب بالدخول من جديد.

const _teacher = PortalUser(
  id: 't1',
  name: 'أ. وفاء الأشقر',
  nationalId: '401234723',
  portalCode: '433333',
  role: 'teacher',
  tenantId: 'tenant',
);

/// كل نداء يفشل: يحاكي فتح التطبيق بلا إنترنت.
http.Client _deadClient() => MockClient((_) async => throw Exception('offline'));

Future<AppStore> _storeWithSession() async {
  final store = AppStore.forTesting();
  await store.bootstrap(NoPersistence());
  await store.savePortalSession(
    nationalId: _teacher.nationalId,
    code: _teacher.portalCode,
    userId: _teacher.id,
    user: _teacher,
  );
  return store;
}

void main() {
  testWidgets('جلسة محفوظة: لا يومض نموذج الدخول بين الشعار والبوابة', (tester) async {
    final store = await _storeWithSession();

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));

      // أول إطار: شاشة الإقلاع لا نموذج الدخول
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('بوابة تسجيل الدخول الرسمية'), findsNothing);

      // كل إطار حتى تُفتح البوابة: النموذج لا يظهر في أيٍّ منها
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.text('بوابة تسجيل الدخول الرسمية'),
          findsNothing,
          reason: 'نموذج الدخول ظهر عند الإطار $i',
        );
        if (tester.any(find.byType(TeacherPortalScreen))) break;
      }

      expect(find.byType(TeacherPortalScreen), findsOneWidget, reason: 'البوابة تُفتح بالحساب المحفوظ بلا شبكة');
      await tester.pumpAndSettle();
    }, _deadClient);
  });

  testWidgets('بلا جلسة محفوظة: نموذج الدخول كالمعتاد', (tester) async {
    final store = AppStore.forTesting();
    await store.bootstrap(NoPersistence());

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);
    }, _deadClient);
  });

  testWidgets('رمز مرفوض من السيرفر: تُنهى الجلسة ويُطلب الدخول', (tester) async {
    final store = await _storeWithSession();

    // ردّ صريح من السيرفر لا انقطاع: الرمز لم يعد صالحاً
    http.Client rejecting() => MockClient((_) async => http.Response(
          '{"error":"رقم الهوية أو كلمة المرور غير صحيحة"}',
          200,
          headers: {'content-type': 'application/json'},
        ));

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
      await tester.pumpAndSettle();

      expect(find.byType(TeacherPortalScreen), findsNothing);
      expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);
      expect(store.portalSession, isNull, reason: 'رفضٌ حقيقي يُنهي الجلسة');
    }, rejecting);
  });

  testWidgets('انقطاع الشبكة لا يُتلف الجلسة المحفوظة', (tester) async {
    final store = await _storeWithSession();

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
      await tester.pumpAndSettle();

      expect(store.portalSession, isNotNull, reason: 'بلا نت يبقى الحساب على الجهاز');
      expect(store.portalSession?.user?.id, 't1');
    }, _deadClient);
  });

}
