import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/main.dart';
import 'package:center_mobile/screens/portal_screens.dart';
import 'package:center_mobile/screens/teacher_resources_screen.dart';
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

Future<AppStore> _storeWithSession(WidgetTester tester) async {
  final store = AppStore.forTesting();
  // bootstrap يتنفّس بـ Delayed(zero) كي لا يجمّد الواجهة، وساعة اختبار
  // الودجات وهمية فلا يقع ذلك التأخير — يلزمه ساعة حقيقية.
  await tester.runAsync(() => store.bootstrap(NoPersistence()));
  await store.savePortalSession(
    nationalId: _teacher.nationalId,
    code: _teacher.portalCode,
    userId: _teacher.id,
    user: _teacher,
  );
  return store;
}

/// شاشة الإقلاع تدير مؤشراً لا يقف، فـ`pumpAndSettle` لا تعود أبداً.
/// إطاراتٌ معدودة تكفي لتستقرّ الحالة.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('جلسة محفوظة: لا يومض نموذج الدخول بين الشعار والبوابة', (tester) async {
    final store = await _storeWithSession(tester);

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));

      // أول إطار: لا نموذج دخول. (شاشة الإقلاع نفسها تسبق جاهزية المخزن،
      // والمخزن هنا مُقلَع سلفاً، فوجودها من عدمه ليس موضع الاختبار.)
      expect(find.text('بوابة تسجيل الدخول الرسمية'), findsNothing);

      // كل إطار حتى تُفتح البوابة: النموذج لا يظهر في أيٍّ منها
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.text('بوابة تسجيل الدخول الرسمية'),
          findsNothing,
          reason: 'نموذج الدخول ظهر عند الإطار $i',
        );
        if (tester.any(find.byType(TeacherResourcesScreen))) break;
      }

      expect(
        find.byType(TeacherResourcesScreen),
        findsOneWidget,
        reason: 'الحساب المحفوظ يفتح شاشات المعلم لا نموذج الدخول',
      );
      await _settle(tester);
    }, _deadClient);
  });

  testWidgets('بلا جلسة محفوظة: نموذج الدخول كالمعتاد', (tester) async {
    final store = await _storeWithSession(tester);
    await store.clearPortalSession();

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
      await _settle(tester);

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);
    }, _deadClient);
  });

  testWidgets('رمز مرفوض من السيرفر: تُنهى الجلسة ويُطلب الدخول', (tester) async {
    final store = await _storeWithSession(tester);

    // ردّ صريح من السيرفر لا انقطاع: الرمز لم يعد صالحاً
    http.Client rejecting() => MockClient((_) async => http.Response(
          '{"error":"رقم الهوية أو كلمة المرور غير صحيحة"}',
          200,
          headers: {'content-type': 'application/json'},
        ));

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
      // تفتح البوابة فوراً ثم يرفض السيرفر في الخلفية فيُغلق الحساب
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _settle(tester);

      expect(find.byType(TeacherPortalScreen), findsNothing);
      expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);
      expect(store.portalSession, isNull, reason: 'رفضٌ حقيقي يُنهي الجلسة');
    }, rejecting);
  });

  testWidgets('انقطاع الشبكة لا يُتلف الجلسة المحفوظة', (tester) async {
    final store = await _storeWithSession(tester);

    await http.runWithClient(() async {
      await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
      await _settle(tester);

      expect(store.portalSession, isNotNull, reason: 'بلا نت يبقى الحساب على الجهاز');
      expect(store.portalSession?.user?.id, 't1');
    }, _deadClient);
  });

}
