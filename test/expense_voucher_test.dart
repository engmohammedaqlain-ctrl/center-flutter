import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/printing.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/expense_voucher_screen.dart';
import 'package:center_mobile/screens/finance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('رقم السند ثابت: يُشتق من تاريخه ومعرّفه', () {
    const expense = ExpenseVoucher(
      id: 'abc-123-ef45',
      isPayout: false,
      date: '2026-09-15',
      category: 'قرطاسية',
      description: 'شراء أوراق',
      amount: 120,
    );
    expect(expenseVoucherNumber(expense), 'ص-20260915-EF45');

    const payout = ExpenseVoucher(
      id: 'zz-9a8b',
      isPayout: true,
      date: '2026-10-01T09:00:00Z',
      category: 'أجور تدريس',
      description: 'أ. محمود',
      amount: 500,
    );
    expect(expenseVoucherNumber(payout), 'أ-20261001-9A8B', reason: 'أجر المعلم يبدأ بأ');
  });

  testWidgets('لمس سند الصرف يفتح وصلاً مطبوعاً', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    s.addExpense(
      category: expenseCategories.first,
      description: 'شراء قرطاسية',
      amount: 120,
      expenseDate: '2026-09-05',
      method: 'cash',
    );
    await s.flush();

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: FinanceScreen())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('المصروفات'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('شراء قرطاسية'));
    await tester.pumpAndSettle();

    expect(find.text('سند صرف'), findsOneWidget);
    expect(find.text('المبلغ المصروف'), findsOneWidget);
    expect(find.text('تنزيل السند (PDF)'), findsOneWidget);
    expect(find.text(amountInArabicWords(120)), findsOneWidget, reason: 'كسند القبض');
    await s.flush();
  });
}
