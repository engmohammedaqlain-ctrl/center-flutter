import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _pump(WidgetTester tester) async {
  // خط الاختبار الافتراضي أعرض من خط التطبيق فيفيض الشريط السفلي: لا علاقة له بالرجوع
  final previous = FlutterError.onError;
  FlutterError.onError = (d) {
    if (!d.exceptionAsString().contains('overflowed')) previous!(d);
  };
  addTearDown(() => FlutterError.onError = previous);
  final s = AppStore.forTesting();
  injectDemoData(s);
  await s.setDeviceIdentity(s.users.firstWhere((u) => u.role == 'admin'), '');
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: AppShell()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return s;
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('الرجوع من الطلاب يعود للرئيسية ولا يخرج من التطبيق', (tester) async {
    final s = await _pump(tester);
    await _tapTab(tester, 'الطلاب');
    expect(find.text('طالب جديد'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(handled, isTrue, reason: 'التطبيق يلتقط الرجوع بنفسه');
    expect(find.text('طالب جديد'), findsNothing, reason: 'غادر قسم الطلاب');
    expect(find.byType(AppShell), findsOneWidget, reason: 'ما زال داخل التطبيق');
    await s.flush();
  });

  testWidgets('الرجوع بين عدة أقسام يمشي للخلف قسماً قسماً', (tester) async {
    final s = await _pump(tester);
    await _tapTab(tester, 'الطلاب');
    await _tapTab(tester, 'الصفوف');
    expect(find.text('صف جديد'), findsOneWidget);

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('طالب جديد'), findsOneWidget, reason: 'رجع للطلاب أولاً');
    await s.flush();
  });
}
