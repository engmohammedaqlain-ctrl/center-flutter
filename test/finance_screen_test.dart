import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/finance_screen.dart';
import 'package:center_mobile/widgets/panels.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// متجر بسند صرف واحد، وبجهاز مثبَّت باسم سكرتير يحمل [caps] إن مُرِّرت.
Future<AppStore> _store({List<String>? caps}) async {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.addExpense(
    category: expenseCategories.first,
    description: 'شراء قرطاسية',
    amount: 120,
    expenseDate: '2026-09-05',
    method: 'cash',
  );
  if (caps != null) {
    final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
    clerk.capabilities = caps;
    await s.setDeviceIdentity(clerk, '');
  }
  return s;
}

Future<void> _pump(WidgetTester tester, AppStore s, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: FinanceScreen())),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _open(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('المصروفات تظهر لمن يفتح المالية ولو بلا صلاحيتها — كما في Center', (tester) async {
    final s = await _store(caps: ['finance.view']);
    await _pump(tester, s);

    expect(find.text('المصروفات'), findsOneWidget);
    await _open(tester, 'المصروفات');
    expect(find.text('شراء قرطاسية'), findsOneWidget);
    expect(find.text('إضافة سند صرف'), findsNothing, reason: 'تسجيل سند الصرف وحده يتطلب صلاحيته');

    await s.flush();
  });

  testWidgets('من يملك صلاحية المصروفات يرى زر سند الصرف', (tester) async {
    final s = await _store();
    await _pump(tester, s);
    await _open(tester, 'المصروفات');
    expect(find.text('إضافة سند صرف'), findsOneWidget);
    await s.flush();
  });

  testWidgets('تعطيل الميزة يُخفي التبويب', (tester) async {
    final s = await _store();
    await s.saveFeatures(enableExpenses: false);
    await _pump(tester, s);
    expect(find.text('المصروفات'), findsNothing);
    await s.flush();
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('التبويبات الثلاثة بلا طفح على عرض ${width.toInt()}', (tester) async {
      final s = await _store();
      await _pump(tester, s, width: width);
      for (final tab in ['المستحقات', 'المصروفات', 'المقبوضات']) {
        await _open(tester, tab);
        expect(find.byType(StatCard), findsWidgets, reason: tab);
      }
      await s.flush();
    });
  }

  testWidgets('البحث والتصفية في سطر واحد في المقبوضات والمستحقات', (tester) async {
    final s = await _store();
    await _pump(tester, s);

    final search = tester.getRect(find.byType(SearchField));
    expect(tester.getRect(find.byType(GroupedFilterButton)).center.dy, closeTo(search.center.dy, 1));

    await _open(tester, 'المستحقات');
    expect(
      tester.getRect(find.byType(FilterButton)).center.dy,
      closeTo(tester.getRect(find.byType(SearchField)).center.dy, 1),
    );
    await s.flush();
  });

  testWidgets('تصفية الحالة تُظهر الملغاة وحدها', (tester) async {
    final s = await _store();
    final target = s.payments.firstWhere((p) => !p.cancelled);
    s.cancelPayment(target);
    await _pump(tester, s);

    await tester.tap(find.byType(GroupedFilterButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ملغاة').last);
    await tester.pumpAndSettle();

    final cancelled = s.payments.where((p) => p.cancelled).length;
    expect(
      find.descendant(of: find.byType(SearchField), matching: find.text('$cancelled/${s.payments.length}')),
      findsOneWidget,
    );
    expect(find.text('معتمد'), findsNothing);
    await s.flush();
  });
}
