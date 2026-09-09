import 'package:flutter_test/flutter_test.dart';

import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/main.dart';

void main() {
  testWidgets('the splash shows while the local store is still loading', (tester) async {
    // مخزن لم يُقلع بعد: الشاشة الأولى إقلاع، لا واجهة فارغة ولا شاشة دخول
    await tester.pumpWidget(
      StoreScope(store: AppStore.forTesting(), child: const CenterApp()),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('login screen renders once loading finishes with no session', (tester) async {
    final store = AppStore.forTesting();
    await store.bootstrap(NoPersistence());

    await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
    await tester.pumpAndSettle();

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);
  });
}
