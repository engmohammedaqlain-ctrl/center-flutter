import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/payment_form_screen.dart';
import 'package:center_mobile/widgets/form_layout.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _pump(WidgetTester tester, {String? studentId, double width = 360}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s = AppStore.forTesting();
  injectDemoData(s);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: PaymentFormScreen(studentId: studentId ?? s.students.firstWhere((x) => x.isDebtor).id),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return s;
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('نموذج الدفعة بتخطيط نموذج الطالب بلا طفح على عرض ${width.toInt()}', (tester) async {
      final s = await _pump(tester, width: width);

      // لا بطاقة تحبس الحقول: أقسام بعنوان وخط كنموذج الطالب
      expect(find.byType(AppCard), findsNothing);
      expect(find.byType(FormSection), findsNWidgets(2));
      expect(find.byType(FieldPair), findsWidgets);

      // الاعتماد ثابت أسفل الشاشة
      final bar = tester.getRect(find.byType(FormActionBar));
      expect(bar.bottom, closeTo(740, 1));
      expect(find.descendant(of: find.byType(FormActionBar), matching: find.text('اعتماد الدفعة وإصدار الوصل')), findsOneWidget);

      await s.flush();
    });
  }

  testWidgets('بلا طالب محدد: البحث ثم صفوف مسطّحة لا صندوق قائمة', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: PaymentFormScreen()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SearchField), findsOneWidget);
    expect(find.byType(AppCard), findsNothing);
    expect(find.byType(ListView), findsOneWidget, reason: 'قائمة واحدة للصفحة، لا قائمة داخل صندوق');

    await s.flush();
  });
}
