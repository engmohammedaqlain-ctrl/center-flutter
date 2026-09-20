import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/screens/moodle_admin_screen.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, AppStore s, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: MoodleAdminScreen()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('قائمة الشعب: بحث وزر تصفية واحد بلا قوائم منسدلة — عرض 320', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    await _pump(tester, s, width: 320);

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('المرحلة'), findsOneWidget);
    expect(find.text('المادة'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await s.flush();
  });

  testWidgets('اختيار شعبة يضع اسمها في الترويسة ويظهر الرجوع', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final group = s.groupsInViewedYear.where((g) => g.isActive).firstOrNull;
    if (group == null) return;

    await _pump(tester, s);
    await tester.tap(find.text(cleanGroupName(group.name, group.gradeLevel)).first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.text('الفصل الأول'), findsOneWidget, reason: 'مفتاح الفصل بدل الشرائح');
    expect(find.byType(SearchField), findsNothing, reason: 'البحث للقائمة وحدها');

    await s.flush();
  });
}
