import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/settings_forms.dart';
import 'package:center_mobile/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _store() async {
  final s = AppStore.forTesting();
  injectDemoData(s);
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

/// التبويبات تُفتح من القائمة الجانبية بـ [SettingsScreen.initialTab] — لا شريط
/// تبويبات داخل الصفحة.
Future<void> _pumpTab(WidgetTester tester, AppStore s, String tab, {double width = 360}) async {
  await _pump(tester, s, Scaffold(body: SettingsScreen(initialTab: tab)), width: width);
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('كل تبويبات الإعدادات بلا طفح وزر إضافة يتبع التبويب — عرض ${width.toInt()}', (tester) async {
      final s = await _store();

      const expected = {
        'grade_fees': 'مرحلة جديدة',
        'payment_methods': 'وسيلة دفع',
        'teachers': 'إضافة مدرس',
        'subjects': 'إضافة مادة',
        'users': 'مستخدم جديد',
      };
      for (final e in expected.entries) {
        await _pumpTab(tester, s, e.key, width: width);
        expect(find.text(e.value), findsOneWidget, reason: e.key);
        expect(tester.takeException(), isNull, reason: e.key);
      }

      await _pumpTab(tester, s, 'backup', width: width);
      for (final label in expected.values) {
        expect(find.text(label), findsNothing, reason: 'تبويب البيانات بلا زر إضافة');
      }

      await s.flush();
    });
  }

  testWidgets('لا زر تسجيل خروج داخل الإعدادات — مكانه القائمة السريعة', (tester) async {
    final s = await _store();
    await _pump(tester, s, const Scaffold(body: SettingsScreen()));
    expect(find.text('تسجيل الخروج'), findsNothing);
    await s.flush();
  });

  testWidgets('نموذج المدرس الفارغ يشير إلى حقوله الناقصة', (tester) async {
    final s = await _store();
    final before = s.teachers.length;
    await _pump(tester, s, const TeacherFormScreen());

    await tester.tap(find.text('إضافة المدرس'));
    await tester.pump();

    expect(find.text('يرجى إدخال اسم المدرس'), findsNWidgets(2), reason: 'تحت الحقل وفي التنبيه');
    expect(find.text('يرجى إدخال رقم هاتف المدرس'), findsOneWidget);
    expect(s.teachers.length, before);
    await s.flush();
  });

  testWidgets('تبويبات الحساب المستخدم على الجهاز لا تُعدَّل منه', (tester) async {
    final s = await _store();
    final admin = s.users.firstWhere((u) => u.role == 'admin');
    await s.setDeviceIdentity(admin, '');
    await _pump(tester, s, UserAccessScreen(user: admin));

    expect(find.text('تبويبات حسابك تُعدَّل من جهاز آخر'), findsOneWidget);
    final before = [...?admin.capabilities];
    await tester.tap(find.text('الطلاب'));
    await tester.pump();
    expect(find.text('${allSections.length} من ${allSections.length}'), findsOneWidget, reason: 'التبديل معطّل');
    expect(admin.capabilities, before);
    await s.flush();
  });

  testWidgets('إتاحة تبويب فرعي تتيح أصله، والدور يملأ القالب', (tester) async {
    final s = await _store();
    await _pump(tester, s, const UserFormScreen());

    // قالب السكرتير خمسة تبويبات، وليس منها المصروفات
    final list = find.byType(Scrollable).first;
    final receptionistCount = roles['receptionist']!.sections.length;
    expect(find.text('$receptionistCount من ${allSections.length}'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('المستخدمون والصلاحيات'), 200, scrollable: list);
    // إبعاد السطر عن شريط الحفظ الثابت أسفل الشاشة كي تصل اللمسة إليه
    await tester.drag(list, const Offset(0, -120));
    await tester.pump();
    await tester.tap(find.text('المستخدمون والصلاحيات'));
    await tester.pump();

    // العدّاد أعلى الصفحة: يُعاد التمرير إليه بعد أن خرج من الشاشة
    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    // الفرع + أصله «الإعدادات»
    expect(
      find.text('${receptionistCount + 2} من ${allSections.length}'),
      findsOneWidget,
      reason: 'المستخدمون ومعه أصله الإعدادات',
    );
    await s.flush();
  });
}
