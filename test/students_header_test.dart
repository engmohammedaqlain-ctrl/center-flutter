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

Finder _filterIcon() => find.byIcon(Icons.tune_rounded);

void main() {
  testWidgets('البحث والتصفية والعدد في سطر واحد بلا طفح', (tester) async {
    final s = await _pump(tester);

    final search = tester.getRect(find.byType(SearchField));
    final filter = tester.getRect(_filterIcon());
    expect(filter.center.dy, closeTo(search.center.dy, 1), reason: 'أيقونة التصفية بجانب البحث');
    expect(search.width, greaterThan(40), reason: 'البحث يبقى مرئياً بجانب أيقونة التصفية');

    // العدد داخل حقل البحث لا في سطر مستقل (قد يظهر مرئي/كل عند إخفاء المؤرشفين)
    final visible = s.students.where((x) => x.status != 'archived').length;
    final count = find.descendant(
      of: find.byType(SearchField),
      matching: find.textContaining('$visible'),
    );
    expect(count, findsOneWidget);
    expect(find.text('جميع المراحل الدراسية'), findsNothing);
    expect(find.text('كل المراحل'), findsNothing, reason: 'خيارات المرحلة في ورقة التصفية لا في الرأس');
    expect(tester.takeException(), isNull);

    await s.flush();
  });

  testWidgets('اختيار مرحلة يصفّي ويُظهر العدد من الكل', (tester) async {
    final s = await _pump(tester);
    final grade = s.students.first.gradeLevel.trim();
    final yearStudents = s.studentsInViewedYear;
    final expected = yearStudents.where((x) => x.gradeLevel.trim() == grade && x.status != 'archived').length;
    final denom = yearStudents.where((x) => x.status != 'archived').length;

    await tester.tap(_filterIcon());
    await tester.pumpAndSettle();
    expect(find.text('تصفية القائمة'), findsOneWidget);
    await tester.tap(find.text(grade));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق التصفية'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.text('$expected/$denom', findRichText: true),
      ),
      findsOneWidget,
    );
    // شريحة الفلتر النشط تحت البحث
    expect(find.text(grade), findsOneWidget);

    await s.flush();
  });
}
