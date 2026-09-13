import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/main.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/student_form_screen.dart';
import 'package:center_mobile/theme/app_colors.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('شريط العنوان يتبع ألوان الهوية بعد وصولها لا الافتراضية', (tester) async {
    // السمة كانت تُبنى مرة عند الإقلاع قبل وصول الألوان، فبقي كل شريط عنوان كحلياً
    AppColors.reset();
    addTearDown(AppColors.reset);
    final s = AppStore.forTesting();

    await tester.pumpWidget(StoreScope(store: s, child: const CenterApp()));
    await tester.pump();
    Color? appBar() => Theme.of(tester.element(find.byType(Navigator))).appBarTheme.backgroundColor;
    expect(appBar(), const Color(0xFF0B2545));

    AppColors.apply(const InstitutionColors(sidebarBg: '#1C3124', primaryButton: '#1C3124', actionButton: '#15803D'));
    s.notifyListeners();
    // MaterialApp ينتقل إلى السمة الجديدة بحركة قصيرة لا في الإطار نفسه
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(appBar(), const Color(0xFF1C3124), reason: 'لون القائمة الجانبية للهوية');
  });

  testWidgets('خصم الرسوم: النسبة تُحسب على رسم المرحلة ويُحفظ الصافي', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    final student = s.students.firstWhere((x) => s.feeFor(x.gradeLevel) != null);
    final gradeFee = s.feeFor(student.gradeLevel)!.monthlyFee;

    await tester.pumpWidget(StoreScope(
      store: s,
      child: MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: StudentFormScreen(student: student)),
      ),
    ));
    await tester.pump();

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('الرسوم والخصم'), 250, scrollable: list);
    expect(find.text('رسم المرحلة: ${money(gradeFee)}'), findsOneWidget);

    // مطفأ افتراضياً لمن لا خصم له
    expect(find.text('نوع الخصم'), findsNothing);
    await tester.scrollUntilVisible(find.byType(Switch), 250, scrollable: list);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('discountRate')), 250, scrollable: list);
    expect(find.text('نسبة الخصم (%)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('discountRate')), '25');
    await tester.pumpAndSettle();

    final expected = gradeFee - (gradeFee * 0.25).roundToDouble();
    await tester.scrollUntilVisible(find.textContaining('الصافي:'), 250, scrollable: list);
    expect(find.text('الصافي: ${money(expected)}'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('تفوق دراسي'), 250, scrollable: list);
    await tester.tap(find.text('تفوق دراسي'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('حفظ التعديل'));
    await tester.pumpAndSettle();

    final saved = s.studentById(student.id)!;
    expect(saved.academicDiscountApplied, isTrue);
    expect(saved.academicDiscountRate, 25);
    expect(saved.customMonthlyFee, expected);
    expect(saved.exceptionReason, 'تفوق دراسي');

    await s.flush();
  });

  testWidgets('نموذج الطالب: بلا بطاقات، المقدمة يسار الرقم، والحفظ ثابت أسفل الشاشة', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: StudentFormScreen()),
      ),
    ));
    await tester.pump();

    expect(find.byType(AppCard), findsNothing, reason: 'الحقول على الصفحة مباشرة');

    // الرقم يُقرأ من اليسار: المقدمة قبل بقية الرقم
    final prefix = tester.getCenter(find.text('059').first);
    final number = tester.getCenter(find.widgetWithText(TextField, '7 أرقام').first);
    expect(prefix.dx, lessThan(number.dx));

    // العدّاد داخل حقل الهوية لا سطر مستقل
    expect(find.descendant(of: find.byType(TextField), matching: find.text('0/9')), findsOneWidget);

    final save = tester.getCenter(find.text('تسجيل الطالب'));
    expect(save.dy, greaterThan(800 * 0.85), reason: 'زر الحفظ مثبّت أسفل الشاشة');
    expect(tester.takeException(), isNull);

    await s.flush();
  });
}
