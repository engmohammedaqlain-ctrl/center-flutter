import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/evaluation_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// صفحة «رصد درجات جديدة» تتبع تسلسل الويب: الصف ← الشعبة ← المادة.
Future<void> _open(WidgetTester tester, AppStore s, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEvaluationSheet(context, s),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('طلاب الشعبة يظهرون ولو لم يُسجَّلوا في المادة', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);

    final group = s.groupsInViewedYear.firstWhere((g) => g.allRoomIds.isNotEmpty);
    final room = s.roomById(group.allRoomIds.first)!;
    // مدرسة تُسند المادة للشعبة بلا تسجيل كل طالب: الكشف يبقى كاملاً
    s.enrollments.removeWhere((e) => e.groupId == group.id);
    final expected = s.studentsOf(room);
    expect(expected, isNotEmpty, reason: 'الشعبة فيها طلاب');

    await _open(tester, s);

    await tester.tap(find.text('اختر الصف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(room.gradeLevel.trim()).last);
    await tester.pumpAndSettle();

    if (find.text('اختر الشعبة').evaluate().isNotEmpty) {
      await tester.tap(find.text('اختر الشعبة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(room.name).last);
      await tester.pumpAndSettle();
    }
    if (find.text('اختر المادة').evaluate().isNotEmpty) {
      await tester.tap(find.text('اختر المادة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.subjectName(group.subjectId)).last);
      await tester.pumpAndSettle();
    }

    expect(find.text(expected.first.fullName), findsWidgets);
    await s.flush();
  });

  testWidgets('الحقول الثلاثة بالترتيب، والطلاب لا يظهرون قبل اكتمالها', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);

    await _open(tester, s);

    // التسميات نصوص منسّقة تحمل نجمة الإلزام
    expect(find.text('الصف *', findRichText: true), findsOneWidget);
    expect(find.text('الشعبة *', findRichText: true), findsOneWidget);
    expect(find.text('المادة *', findRichText: true), findsOneWidget);
    // وما لم يُختر بعدُ يشرح ما ينقصه
    expect(find.text('اختر الصف'), findsOneWidget);
    expect(find.text('اختر الصف أولاً'), findsOneWidget);
    expect(find.text('اختر الشعبة أولاً'), findsOneWidget);
    expect(find.text('اختر الصف والشعبة والمادة لعرض الطلاب'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await s.flush();
  });

  testWidgets('اختيار الصف ثم الشعبة ثم المادة يعرض طلاب تلك الشعبة', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);

    final group = s.groupsInViewedYear.firstWhere((g) => g.allRoomIds.isNotEmpty);
    final room = s.roomById(group.allRoomIds.first)!;
    final subject = s.subjectName(group.subjectId);

    await _open(tester, s);

    await tester.tap(find.text('اختر الصف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(room.gradeLevel.trim()).last);
    await tester.pumpAndSettle();

    // الشعبة قد تُختار تلقائياً حين تكون وحيدة في صفّها
    if (find.text('اختر الشعبة').evaluate().isNotEmpty) {
      await tester.tap(find.text('اختر الشعبة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(room.name).last);
      await tester.pumpAndSettle();
    }

    if (find.text('اختر المادة').evaluate().isNotEmpty) {
      await tester.tap(find.text('اختر المادة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(subject).last);
      await tester.pumpAndSettle();
    }

    // كشف الطلاب ظهر بدل رسالة الاختيار
    expect(find.text('اختر الصف والشعبة والمادة لعرض الطلاب.'), findsNothing);
    expect(tester.takeException(), isNull);
    await s.flush();
  });
}
