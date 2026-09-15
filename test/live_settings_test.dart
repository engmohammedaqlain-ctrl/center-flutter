import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/grading.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/grading_scheme_tab.dart';
import 'package:center_mobile/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ضبطٌ غيّره جهاز آخر يصل بالسحب — وكان لا يظهر حتى تُغلق الصفحة وتُفتح.

Future<AppStore> _openFees(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s = AppStore.forTesting();
  injectDemoData(s);
  await s.setSeatReservationFee(50);
  await s.saveStudyMonths([9]);
  await s.flush();

  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SettingsScreen())),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('المراحل والرسوم'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('الحجز وأشهر الدراسة'));
  await tester.pumpAndSettle();
  return s;
}

String _fieldText(WidgetTester tester) {
  final field = tester.widgetList<TextField>(find.byType(TextField)).firstWhere(
        (f) => f.decoration?.hintText == '0 $currency',
      );
  return field.controller?.text ?? '';
}

void main() {
  testWidgets('رسم الحجز يتبدّل والصفحة مفتوحة', (tester) async {
    final s = await _openFees(tester);
    expect(_fieldText(tester), '50');

    // جهاز آخر غيّره وسحبه الجوال: لا إعادة فتح للصفحة
    await s.setSeatReservationFee(100);
    await tester.pump();

    expect(_fieldText(tester), '100');
    await s.flush();
  });

  testWidgets('ما يكتبه المستخدم لا يُدهس بما يصل من جهاز آخر', (tester) async {
    final s = await _openFees(tester);

    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0 $currency',
    );
    await tester.enterText(field, '75');
    await tester.pump();

    await s.setSeatReservationFee(100);
    await tester.pump();

    expect(_fieldText(tester), '75', reason: 'ما تحت يده لا يتبدّل قبل حفظه');
    await s.flush();
  });

  testWidgets('أشهر الدراسة كذلك', (tester) async {
    final s = await _openFees(tester);
    expect(find.text('الرسوم الشهرية متوقفة'), findsNothing);

    await s.saveStudyMonths([]);
    await tester.pump();

    expect(find.text('الرسوم الشهرية متوقفة'), findsOneWidget);
    await s.flush();
  });
  testWidgets('مخطط العلامات يتبدّل والتبويب مفتوح', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await s.saveGradingScheme(const GradingScheme(term1: [GradingComponent(id: 'c1', name: 'اختبار قصير', weight: 40)]));
    await s.flush();

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: GradingSchemeTab())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('اختبار قصير'), findsOneWidget);

    // ضُبط على جهاز آخر ووصل بالسحب
    await s.saveGradingScheme(const GradingScheme(term1: [GradingComponent(id: 'c1', name: 'امتحان نهائي', weight: 60)]));
    await tester.pump();

    expect(find.text('امتحان نهائي'), findsOneWidget);
    await s.flush();
  });
}
