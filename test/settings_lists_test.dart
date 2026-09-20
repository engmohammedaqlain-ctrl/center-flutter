import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, AppStore s, String tab, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: SettingsScreen(initialTab: tab)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('قوائم المعلمين والمواد والمراحل بلا طفح — عرض ${width.toInt()}', (tester) async {
      final s = AppStore.forTesting();
      injectDemoData(s);

      for (final tab in ['teachers', 'subjects', 'grade_fees']) {
        await _pump(tester, s, tab, width: width);
        expect(tester.takeException(), isNull, reason: tab);
      }
      await s.flush();
    });
  }

  testWidgets('بطاقة المدرس: اسمه ورقمه وموادّه بلا أزرار متراصّة', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final teacher = s.teachersInViewedYear.first;

    await _pump(tester, s, 'teachers');

    expect(find.text(teacher.name), findsOneWidget);
    // سهم الفتح شِيل: لمس البطاقة نفسه يفتح الملف
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    await s.flush();
  });

  testWidgets('بطاقة المرحلة: الخطة سطر يُلمس، والتعديل والحذف في ورقة', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final fee = s.gradeFeesInViewedYear.first;

    await _pump(tester, s, 'grade_fees');
    expect(find.text(fee.gradeName), findsWidgets);

    // لا زرّي «تعديل» و«حذف» في كل بطاقة
    expect(find.text('حذف'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('تعديل المرحلة'), findsOneWidget);
    expect(find.text('حذف المرحلة'), findsOneWidget);
    await s.flush();
  });

  testWidgets('أقسام الرسوم مطوية بملخّص وتُفتح باللمس', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    await _pump(tester, s, 'grade_fees');

    expect(find.text('الرسوم المحددة والخصومات'), findsOneWidget);
    expect(find.text('رسم حجز المقعد'), findsNothing, reason: 'مطوي');

    await tester.tap(find.text('الرسوم المحددة والخصومات'));
    await tester.pumpAndSettle();
    expect(find.text('رسم حجز المقعد'), findsWidgets);
    await s.flush();
  });
}
