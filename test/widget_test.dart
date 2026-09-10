import 'package:flutter/material.dart';
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
    expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);

    // البوابة هي التبويب الافتراضي، كما في LandingPage
    expect(find.text('دخول البوابة'), findsOneWidget);
    expect(find.text('رقم الهوية:'), findsOneWidget);
    expect(find.text('رمز الدخول (الكود):'), findsOneWidget);
  });

  testWidgets('the admin tab swaps the form without leaving the screen', (tester) async {
    final store = AppStore.forTesting();
    await store.bootstrap(NoPersistence());

    await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('دخول الإدارة'));
    await tester.pumpAndSettle();

    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('اسم المستخدم:'), findsOneWidget);
    expect(find.text('دخول البوابة'), findsNothing);
  });

  testWidgets('neither login form overflows a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = AppStore.forTesting();
    await store.bootstrap(NoPersistence());
    await tester.pumpWidget(StoreScope(store: store, child: const CenterApp()));
    await tester.pumpAndSettle();

    // شريط التبويبين يحمل نصّين عربيين طويلين
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('دخول الإدارة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
