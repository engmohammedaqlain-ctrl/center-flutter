import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, AppStore s) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: AppShell()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('المدير يرى زر القائمة لأن فيها بنوداً', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final admin = s.users.firstWhere((u) => u.role == 'admin');
    await s.setDeviceIdentity(admin, '');

    await _pump(tester, s);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsNothing);
    await s.flush();
  });

  testWidgets('من لا بنود له: لا زرّ قائمة، والخروج في الترويسة', (tester) async {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
    // صلاحيات يومية فقط: لا إعدادات ولا درجات ولا مودل
    clerk.capabilities = ['students', 'attendance'];
    await s.setDeviceIdentity(clerk, '');

    await _pump(tester, s);

    expect(find.byIcon(Icons.menu_rounded), findsNothing, reason: 'قائمة فارغة لا تُفتح');
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget, reason: 'الخروج يبقى متاحاً');
    await s.flush();
  });
}
