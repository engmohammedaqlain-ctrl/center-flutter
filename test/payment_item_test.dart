import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/payment_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// طالب بقسطين: واحد حلّ موعده وآخر قادم — ولا أقساط لغيره.
Future<AppStore> _store(WidgetTester tester, {bool withInstallments = true, double seatFee = 0}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s = AppStore.forTesting();
  injectDemoData(s);
  final student = s.students.first;
  s.installments.removeWhere((i) => i.studentId == student.id);
  if (withInstallments) {
    s.installments.addAll([
      Installment(
        id: 'inst-due',
        studentId: student.id,
        title: 'قسط أيلول',
        amount: 100,
        dueDate: DateTime.now().subtract(const Duration(days: 10)),
      ),
      Installment(
        id: 'inst-next',
        studentId: student.id,
        title: 'قسط تشرين',
        amount: 80,
        dueDate: DateTime.now().add(const Duration(days: 30)),
      ),
    ]);
  }
  if (seatFee > 0) await s.setSeatReservationFee(seatFee);
  await s.flush();
  return s;
}

Future<Student> _pump(WidgetTester tester, AppStore s) async {
  final student = s.students.first;
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: PaymentFormScreen(studentId: student.id)),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return student;
}

/// عنوان حقل أو سطر منسّق — `Text.rich` لا يطابقه `find.text`.
Finder _rich(String text) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final plain = w.data ?? w.textSpan?.toPlainText() ?? '';
      return plain == text || plain == '$text *' || plain.contains(text);
    }, description: 'نص يحوي «$text»');

void main() {
  testWidgets('البند يبدأ على أقدم قسط حلّ موعده، والمبلغ يتبعه', (tester) async {
    final s = await _store(tester);
    await _pump(tester, s);

    expect(_rich('البند'), findsOneWidget);
    expect(_rich('غرض الدفع'), findsNothing, reason: 'حقل واحد بدل حقلين');
    expect(find.textContaining('قسط أيلول'), findsWidgets);
    final amount = tester.widget<TextField>(find.byType(TextField).first);
    expect(amount.controller?.text, '100');
    await s.flush();
  });

  testWidgets('القائمة تُعلّم القسط القادم ولا تقترحه', (tester) async {
    final s = await _store(tester);
    await _pump(tester, s);

    await tester.tap(find.textContaining('قسط أيلول').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('قسط تشرين'), findsWidgets);
    expect(find.textContaining('(قادم)'), findsWidgets, reason: 'لم يحن موعده');
    expect(find.text('دفعة عامة'), findsWidgets);
    await tester.tap(find.text('دفعة عامة').last);
    await tester.pumpAndSettle();
    await s.flush();
  });

  testWidgets('المستحق في الرأس: ما حلّ موعده وحده', (tester) async {
    final s = await _store(tester);
    await _pump(tester, s);

    // ١٠٠ الحالّ، لا ١٨٠ بالقسط القادم
    expect(_rich('المستحق: ${money(100)}'), findsOneWidget);
    expect(_rich('المستحق: ${money(180)}'), findsNothing, reason: 'القادم لا يُطالَب به');
    await s.flush();
  });

  testWidgets('طالب بلا أقساط: رسوم شهرية، وحجز مقعد إن لم يُسدَّد', (tester) async {
    final s = await _store(tester, withInstallments: false, seatFee: 50);
    await _pump(tester, s);

    await tester.tap(find.text('رسوم شهرية').last);
    await tester.pumpAndSettle();
    expect(find.text('حجز مقعد'), findsWidgets);

    await tester.tap(find.text('حجز مقعد').last);
    await tester.pumpAndSettle();
    final amount = tester.widget<TextField>(find.byType(TextField).first);
    expect(amount.controller?.text, '50', reason: 'الرسم من الإعدادات');
    await s.flush();
  });

  testWidgets('«يغطي» يسرد ما تسدده الدفعة، وهو بيان السند', (tester) async {
    final s = await _store(tester);
    final student = await _pump(tester, s);

    // مبلغ يغطي الحالّ وجزءاً من القادم
    await tester.enterText(find.byType(TextField).first, '150');
    await tester.pump();
    expect(find.textContaining('يغطي: قسط أيلول، قسط تشرين (جزء)'), findsOneWidget);

    await tester.tap(find.text('اعتماد الدفعة وإصدار الوصل'));
    await tester.pumpAndSettle();

    final payment = s.paymentsOf(student.id).firstWhere((p) => p.amount == 150);
    expect(payment.purpose, 'قسط أيلول، قسط تشرين (جزء)', reason: 'بيان السند هو ما غطّته');
    await s.flush();
  });
}
