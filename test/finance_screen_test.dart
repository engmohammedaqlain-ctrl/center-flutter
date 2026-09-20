import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/finance_screen.dart';
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

Future<void> _pump(
  WidgetTester tester,
  AppStore s, {
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: FinanceScreen()),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// الأقسام صفحات تُسحب، فالانتقال إليها حركة تُنتظر حتى تستقر.
Future<void> _open(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('المصروفات تكشف الرواتب فتُخفى عمّن لا يملك صلاحيتها — كما في الويب', (tester) async {
    final s = await _store(caps: ['finance.view']);
    await _pump(tester, s);

    // Finance.tsx: canSeeExpenses = enableExpenses && can('finance.expenses')
    expect(find.text('المصروفات'), findsNothing);
    expect(find.text('المقبوضات'), findsOneWidget);

    await s.flush();
  });

  testWidgets('المصروفات تتبع الفترة المختارة لا كل الأعوام', (tester) async {
    final s = await _store();
    final year = await s.ensureCurrentAcademicYear();
    // السند الحالي داخل العام، والقديم قبله بسنوات
    s.expenses.firstWhere((e) => e.description == 'شراء قرطاسية').expenseDate = year.startsOn;
    s.addExpense(
      category: expenseCategories.first,
      description: 'مصروف عام قديم',
      amount: 999,
      expenseDate: '2019-01-10',
      method: 'cash',
    );
    await _pump(tester, s);
    await _open(tester, 'المصروفات');

    expect(find.text('شراء قرطاسية'), findsOneWidget);
    expect(find.text('مصروف عام قديم'), findsNothing, reason: 'خارج عام التشغيل');

    await tester.tap(find.byKey(const ValueKey('finance-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('كل الأعوام'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تم'));
    await tester.pumpAndSettle();

    expect(find.text('مصروف عام قديم'), findsOneWidget);
    await s.flush();
  });

  testWidgets('من يملك صلاحية المصروفات يرى زر سند الصرف', (tester) async {
    final s = await _store();
    await _pump(tester, s);
    await _open(tester, 'المصروفات');
    // زر «+» واحد يفتح ورقة تختار العملية: سند صرف أو صرف رواتب
    await tester.tap(find.text('صرف جديد'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة سند صرف'), findsOneWidget);
    expect(find.text('صرف رواتب'), findsOneWidget);
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
    testWidgets('التبويبات الثلاثة بلا طفح على عرض ${width.toInt()}', (
      tester,
    ) async {
      final s = await _store();
      await _pump(tester, s, width: width);
      for (final tab in ['المستحقات', 'المصروفات', 'المقبوضات']) {
        await _open(tester, tab);
        expect(find.byKey(const ValueKey('finance-filters')), findsOneWidget, reason: tab);
        expect(tester.takeException(), isNull, reason: tab);
      }
      await s.flush();
    });
  }

  testWidgets('المالية تفتح على المستحقات، وترتيب التبويبات كما في الديسكتوب', (
    tester,
  ) async {
    final s = await _store();
    await _pump(tester, s);

    // المستحقات سبب فتح المالية، فهي أول المفتاح المقسّم من اليمين
    final order = [
      for (final t in ['المستحقات', 'المقبوضات', 'المصروفات']) tester.getRect(find.text(t)).center.dx,
    ];
    expect(order[0], greaterThan(order[1]), reason: 'من اليمين لليسار');
    expect(order[1], greaterThan(order[2]));
    expect(find.byKey(const ValueKey('finance-hero')), findsOneWidget);
    expect(find.text('لا مستحقات'), findsNothing);
    await s.flush();
  });

  testWidgets('البحث والتصفية في سطر واحد في المستحقات والمقبوضات', (
    tester,
  ) async {
    final s = await _store();
    await _pump(tester, s);

    final filters = find.byKey(const ValueKey('finance-filters'));
    expect(
      tester.getRect(filters).center.dy,
      closeTo(tester.getRect(find.byType(SearchField)).center.dy, 1),
    );

    await _open(tester, 'المقبوضات');
    expect(
      tester.getRect(filters).center.dy,
      closeTo(tester.getRect(find.byType(SearchField)).center.dy, 1),
    );
    await s.flush();
  });

  testWidgets('المقبوضات: زر واحد يجمع تسديد الدفعة والقبض من غير طالب', (tester) async {
    final s = await _store();
    await _pump(tester, s);

    // المستحقات: التسديد وحده هو زرّها
    expect(find.text('تسديد دفعة'), findsOneWidget);
    await _open(tester, 'المقبوضات');

    await tester.tap(find.text('قبض جديد'));
    await tester.pumpAndSettle();
    expect(find.text('تسديد دفعة'), findsOneWidget);
    expect(find.text('قبض من غير طالب'), findsOneWidget);
    await s.flush();
  });

  testWidgets('السحب أفقياً ينقل بين الأقسام', (tester) async {
    final s = await _store();
    await _pump(tester, s);
    expect(find.text('إجمالي المستحق'), findsOneWidget);

    // العربية من اليمين لليسار: السحب نحو اليمين يُظهر القسم التالي
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('المقبوض في الفترة'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('إجمالي المستحق'), findsOneWidget);
    await s.flush();
  });

  testWidgets('تصفية الحالة تُظهر الملغاة وحدها', (tester) async {
    final s = await _store();
    // الإلغاء لسند اليوم فقط؛ السند الأقدم يُعكس ولا يتحول إلى «ملغى».
    final target = s.addPayment(
      studentId: s.students.first.id,
      amount: 10,
      method: 'cash',
      date: DateTime.now(),
    );
    s.cancelPayment(target);
    await _pump(tester, s);
    await _open(tester, 'المقبوضات');

    await tester.tap(find.byKey(const ValueKey('finance-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ملغاة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تم'));
    await tester.pumpAndSettle();

    final cancelled = s.payments.where((p) => p.cancelled).length;
    expect(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.text('$cancelled/${s.payments.length}'),
      ),
      findsOneWidget,
    );
    expect(find.text('معتمد'), findsNothing);
    await s.flush();
  });
}
