import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/students_screen.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s = AppStore.forTesting();
  injectDemoData(s);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: StudentsScreen())),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return s;
}

void main() {
  testWidgets('البحث والتصفية والعدد في سطر واحد بلا طفح', (tester) async {
    final s = await _pump(tester);

    final search = tester.getRect(find.byType(SearchField));
    final filter = tester.getRect(find.byType(FilterButton));
    expect(filter.center.dy, closeTo(search.center.dy, 1), reason: 'في السطر نفسه');
    // الحقلان متجاوران فيجب أن يتساوى ارتفاعهما، وإلا بدا أحدهما ناتئاً
    final searchBox = tester.getRect(find.descendant(of: find.byType(SearchField), matching: find.byType(InputDecorator)));
    expect(searchBox.height, closeTo(filter.height, 0.5), reason: 'ارتفاع حقل البحث = ارتفاع زر التصفية');
    expect(search.width, greaterThan(filter.width), reason: 'البحث يأخذ المساحة الأكبر');

    // العدد داخل حقل البحث لا في سطر مستقل
    final count = find.descendant(of: find.byType(SearchField), matching: find.textContaining('${s.students.length}'));
    expect(count, findsOneWidget);
    expect(find.text('جميع المراحل الدراسية'), findsNothing);
    expect(tester.takeException(), isNull);

    await s.flush();
  });

  testWidgets('اختيار مرحلة يصفّي ويُظهر العدد من الكل', (tester) async {
    final s = await _pump(tester);
    final grade = s.students.first.gradeLevel.trim();
    final expected = s.students.where((x) => x.gradeLevel.trim() == grade).length;

    await tester.tap(find.byType(FilterButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, grade));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.text('$expected/${s.students.length}', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: find.byType(FilterButton), matching: find.text(grade)), findsOneWidget);

    await s.flush();
  });
}
