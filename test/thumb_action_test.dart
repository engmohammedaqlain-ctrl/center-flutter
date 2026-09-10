import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/students_screen.dart';
import 'package:center_mobile/widgets/thumb_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

Widget _longList() => ListView.builder(
  itemCount: 60,
  itemBuilder: (_, i) => SizedBox(height: 60, child: Text('صف $i')),
);

void main() {
  testWidgets('الزر يظهر بنصه ويستجيب للّمس', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ThumbActionLayer(
          action: ThumbAction(
            label: 'طالب جديد',
            icon: Icons.add,
            onPressed: () => taps++,
          ),
          child: _longList(),
        ),
      ),
    );

    expect(find.text('طالب جديد'), findsOneWidget);
    await tester.tap(find.text('طالب جديد'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('يصغر عند التمرير للأسفل ويعود عند الصعود', (tester) async {
    await tester.pumpWidget(
      _host(
        ThumbActionLayer(
          action: ThumbAction(
            label: 'دفعة جديدة',
            icon: Icons.add,
            onPressed: () {},
          ),
          child: _longList(),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      find.text('دفعة جديدة'),
      findsNothing,
      reason: 'أيقونة وحدها أثناء النزول',
    );
    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(find.text('دفعة جديدة'), findsOneWidget);
  });

  testWidgets('بلا إجراء لا زر، والمعطّل لا يستجيب', (tester) async {
    await tester.pumpWidget(_host(ThumbActionLayer(child: _longList())));
    expect(
      find
          .byType(Semantics)
          .evaluate()
          .where((e) => (e.widget as Semantics).properties.button == true),
      isEmpty,
    );

    await tester.pumpWidget(
      _host(
        ThumbActionLayer(
          action: const ThumbAction(
            label: 'الكل حاضر',
            icon: Icons.done_all,
            onPressed: null,
          ),
          child: _longList(),
        ),
      ),
    );
    await tester.tap(find.text('الكل حاضر'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('زر الطالب الجديد في أسفل الشاشة يمينها حيث الإبهام', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await tester.pumpWidget(
      StoreScope(store: s, child: _host(const StudentsScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final center = tester.getCenter(find.text('طالب جديد'));
    expect(center.dy, greaterThan(740 * 0.75), reason: 'في الربع السفلي');
    expect(center.dx, greaterThan(360 / 2), reason: 'في الجهة اليمنى');
    expect(tester.takeException(), isNull);

    await s.flush();
  });
}
