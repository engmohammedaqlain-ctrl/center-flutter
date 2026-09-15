import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/expense_form_sheet.dart';
import 'package:center_mobile/screens/payment_form_screen.dart';
import 'package:center_mobile/screens/student_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _pump(WidgetTester tester, Widget Function(AppStore store) home) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s = AppStore.forTesting();
  injectDemoData(s);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: home(s))),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return s;
}

void main() {
  testWidgets('خطأ نموذج الورقة السفلية يظهر فوقها لا خلفها', (tester) async {
    // لمسة لا تصل إلى هدفها تُفشل الاختبار: المحجوب خلف الورقة لا يُلمس
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    final s = await _pump(
      tester,
      (store) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showExpenseSheet(context, store),
            child: const Text('فتح'),
          ),
        ),
      ),
    );
    final before = s.expenses.length;

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ سند الصرف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // كل حقل ناقص برسالته تحته، والتنبيه يحمل رسالة أول ناقص لا جملة عامة
    expect(find.text('البيان / المستفيد مطلوب'), findsNWidgets(2));
    expect(find.text('المبلغ يجب أن يكون أكبر من صفر'), findsOneWidget);

    // والتنبيه فوق الورقة يُلمس ويُغلق، فتبقى رسالة الحقل وحدها
    await tester.tap(find.text('البيان / المستفيد مطلوب').last);
    await tester.pump();
    expect(find.text('البيان / المستفيد مطلوب'), findsOneWidget);

    expect(s.expenses.length, before, reason: 'لا يُحفظ سند ناقص');
    await s.flush();
  });

  testWidgets('نموذج الدفعة بلا طالب ولا مبلغ يشير إلى الحقلين', (tester) async {
    final s = await _pump(tester, (_) => const PaymentFormScreen());
    final before = s.payments.length;

    await tester.tap(find.text('اعتماد الدفعة وإصدار الوصل'));
    await tester.pump();

    // التمرير يذهب إلى أول ناقص — اختيار الطالب — والمبلغ تحت قائمة الطلاب
    expect(find.text('يرجى اختيار الطالب أولاً'), findsNWidgets(2), reason: 'تحت الحقل وفي التنبيه');
    await tester.scrollUntilVisible(
      find.text('يرجى إدخال مبلغ صحيح أكبر من صفر'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('يرجى إدخال مبلغ صحيح أكبر من صفر'), findsOneWidget);
    expect(s.payments.length, before);

    await s.flush();
  });

  testWidgets('نموذج الطالب الفارغ يُظهر كل النواقص تحت حقولها', (tester) async {
    final s = await _pump(tester, (_) => const StudentFormScreen());
    final before = s.students.length;

    await tester.tap(find.text('تسجيل الطالب'));
    await tester.pump();

    // التنبيه يسمّي أول ناقص، فتظهر رسالته مرتين: تحت حقله وفوق الشاشة
    expect(find.text('اسم الطالب مطلوب'), findsNWidgets(2));
    expect(find.text('رقم الهوية مطلوب (9 أرقام)'), findsOneWidget);
    expect(find.text('جوال الطالب مطلوب'), findsOneWidget);
    expect(s.students.length, before);

    // الكتابة في الحقل تُسقط خطأه وحده
    await tester.enterText(find.byType(TextField).first, 'محمد أحمد النجار');
    await tester.pump();
    // التنبيه يبقى لحظات بعد تصحيح الحقل، ثم لا يبقى للرسالة أثر
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('اسم الطالب مطلوب'), findsNothing);
    expect(find.text('جوال الطالب مطلوب'), findsOneWidget);

    await s.flush();
  });
}
