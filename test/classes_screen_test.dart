import 'package:center_mobile/data/class_tiers.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/classes_screen.dart';
import 'package:center_mobile/screens/room_form_screen.dart';
import 'package:center_mobile/widgets/form_layout.dart';
import 'package:center_mobile/widgets/panels.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// متجر تجريبي، وبجهاز مثبَّت باسم سكرتير يحمل [caps] إن مُرِّرت.
Future<AppStore> _store({List<String>? caps}) async {
  final s = AppStore.forTesting();
  injectDemoData(s);
  if (caps != null) {
    final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
    clerk.capabilities = caps;
    await s.setDeviceIdentity(clerk, '');
  }
  return s;
}

Future<void> _pump(WidgetTester tester, AppStore s, Widget home, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: home)),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('بطاقات الصفوف بلا طفح و«صف جديد» في متناول الإبهام — عرض ${width.toInt()}', (tester) async {
      final s = await _store();
      await _pump(tester, s, const Scaffold(body: ClassesScreen()), width: width);

      expect(find.byType(StatCard), findsNWidgets(3));
      final add = find.text('صف جديد');
      expect(add, findsOneWidget);
      expect(tester.getRect(add).center.dy, greaterThan(740 * 0.75), reason: 'أسفل الشاشة قرب الإبهام، لا في رأسها');

      await s.flush();
    });
  }

  testWidgets('من لا يرى تبويب الصفوف لا يرى «صف جديد»', (tester) async {
    final s = await _store(caps: ['students']);
    await _pump(tester, s, const Scaffold(body: ClassesScreen()));
    expect(find.text('صف جديد'), findsNothing);
    await s.flush();
  });

  testWidgets('الصف يُفتح صفحةً عنوانها اسمه', (tester) async {
    final s = await _store();
    final room = s.rooms.first;
    await _pump(tester, s, const Scaffold(body: ClassesScreen()));

    await tester.tap(find.text(room.name).first);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text(room.name)), findsOneWidget);

    await s.flush();
  });

  testWidgets('نموذج الصف بلا صناديق ويرفض الحفظ بلا مرحلة', (tester) async {
    final s = await _store();
    final before = s.rooms.length;
    await _pump(tester, s, const RoomFormScreen());

    expect(find.byType(AppCard), findsNothing);
    expect(find.byType(FormSection), findsNWidgets(2));
    expect(find.byType(FormActionBar), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'الشعبة (ب)');
    await tester.tap(find.text('إضافة الصف'));
    await tester.pump();
    expect(find.text('يرجى تحديد المرحلة الدراسية التابعة لها هذه الشعبة'), findsNWidgets(2), reason: 'تحت الحقل وفي التنبيه');
    expect(s.rooms.length, before);

    await s.flush();
  });

  testWidgets('تعديل الصف يحفظ الاسم الجديد', (tester) async {
    final s = await _store();
    final room = s.rooms.firstWhere((r) => r.gradeLevel.trim().isNotEmpty);
    await _pump(
      tester,
      s,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomFormScreen(room: room))),
            child: const Text('فتح'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ج');
    await tester.tap(find.text('حفظ التعديلات'));
    await tester.pumpAndSettle();

    // المرحلة في حقلها: يُكتب رمز الشعبة وحده ويُوحَّد شكله «شعبة (ج)»
    expect(s.rooms.firstWhere((r) => r.id == room.id).name, 'شعبة (ج)');
    expect(find.byType(RoomFormScreen), findsNothing, reason: 'يعود بعد الحفظ');

    // انتهاء إشعار الحفظ قبل هدم الشجرة
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await s.flush();
  });

  test('المرحلة الكبرى تُشتق من اسم المرحلة كما في Center', () async {
    final s = await _store();
    s.gradeFees.clear();
    expect(gradeTier(s, 'ثاني عشر علمي'), 'secondary');
    expect(gradeTier(s, 'الصف التاسع'), 'middle');
    expect(gradeTier(s, 'الصف الرابع'), 'primary');
    expect(gradeTier(s, 'روضة'), 'kindergarten');
    expect(gradeTier(s, ''), 'other');
  });
}
