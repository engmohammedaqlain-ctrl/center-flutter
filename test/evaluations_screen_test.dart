import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/evaluations_screen.dart';
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
        home: Directionality(textDirection: TextDirection.rtl, child: EvaluationsScreen()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('الكشف مجموع بالمواد، والمادة تُفتح فتُظهر طلابها ودرجاتهم', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final withGrades = s.evaluations.where((e) => e.groupId.isNotEmpty).toList();
    if (withGrades.isEmpty) return;

    final group = s.groupById(withGrades.first.groupId);
    final subject = s.subjectName(group?.subjectId ?? '');
    final student = s.studentById(withGrades.first.studentId)!;

    await _pump(tester, s);

    // المادة سطر واحد، وطلابها لا يظهرون قبل فتحها
    expect(find.text(subject), findsWidgets);
    expect(find.text(student.fullName), findsNothing);

    await tester.tap(find.text(subject).first);
    await tester.pumpAndSettle();
    expect(find.text(student.fullName), findsWidgets);

    // الطالب يُفتح فتظهر درجاته في المادة
    await tester.tap(find.text(student.fullName).first);
    await tester.pumpAndSettle();
    expect(find.text(withGrades.first.title), findsWidgets);
    expect(tester.takeException(), isNull);

    await s.flush();
  });

  testWidgets('فلاتر الشاشة في ورقة واحدة بلا طفح — عرض 320', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    await _pump(tester, s, width: 320);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.text('المرحلة'), findsOneWidget);
    expect(find.text('الشعبة'), findsOneWidget);
    expect(find.text('المادة'), findsOneWidget);
    expect(find.text('النوع'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await s.flush();
  });
}
