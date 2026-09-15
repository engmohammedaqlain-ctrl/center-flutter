import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Payment _payment({required double amount, required double due, double discount = 0}) => Payment(
      id: 'p1',
      receiptNumber: '2026/1001',
      studentId: 's1',
      studentName: 'طالب',
      amount: amount,
      discountAmount: discount,
      totalDueAtPayment: due,
      method: 'cash',
      date: DateTime(2026, 9, 15),
      purpose: 'دفعة عامة',
    );

void main() {
  group('الرصيد المقدَّم', () {
    test('ما زاد عن المستحق وقت الدفع', () {
      expect(paymentAdvance(_payment(amount: 150, due: 100)), 50);
      expect(paymentAdvance(_payment(amount: 100, due: 100)), 0);
      expect(paymentAdvance(_payment(amount: 80, due: 100)), 0, reason: 'ما زال عليه');
    });

    test('الخصم جزء مما سُدِّد من الذمة', () {
      expect(paymentAdvance(_payment(amount: 90, due: 100, discount: 20)), 10);
    });
  });

  testWidgets('السند يعرض «رصيد مقدم» بمبلغه بدل المتبقي', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await s.flush();
    final payment = _payment(amount: 150, due: 100);

    await tester.pumpWidget(StoreScope(
      store: s,
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ReceiptScreen.open(context, payment),
                child: const Text('افتح السند'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('افتح السند'));
    await tester.pumpAndSettle();

    expect(find.text('رصيد مقدم'), findsOneWidget);
    expect(find.text(money(50)), findsWidgets);
    expect(find.text('المتبقي المستحق'), findsNothing);
    await s.flush();
  });
}
