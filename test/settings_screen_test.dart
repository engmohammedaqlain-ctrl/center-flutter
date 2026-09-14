import 'package:center_mobile/data/demo_data.dart';
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

/// شريط التبويبات يُمرَّر أفقياً، وما خرج عن الشاشة لا يُبنى أصلاً — فيُسحب
/// الشريط حتى يظهر التبويب المطلوب قبل لمسه.
Future<void> _openTab(WidgetTester tester, String label) async {
  final bar = find.byType(Scrollable).first;
  for (var i = 0; i < 14 && find.text(label).evaluate().isEmpty; i++) {
    await tester.drag(bar, const Offset(-70, 0));
    await tester.pump();
  }
  for (var i = 0; i < 20 && find.text(label).evaluate().isEmpty; i++) {
    await tester.drag(bar, const Offset(70, 0));
    await tester.pump();
  }
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('كل تبويبات الإعدادات بلا طفح وزر إضافة يتبع التبويب — عرض ${width.toInt()}', (tester) async {
      final s = await _store();
      await _pump(tester, s, const Scaffold(body: SettingsScreen()), width: width);

      const expected = {
        'المراحل والرسوم': 'مرحلة جديدة',
        'وسائل الدفع': 'وسيلة دفع',
        'المعلمون': 'إضافة مدرس',
        'المواد': 'إضافة مادة',
        'المستخدمون': 'مستخدم جديد',
      };
      for (final e in expected.entries) {
        await _openTab(tester, e.key);
        expect(find.text(e.value), findsOneWidget, reason: e.key);
      }

      await _openTab(tester, 'البيانات والنسخ');
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

    expect(find.text('يرجى إدخال اسم المدرس'), findsOneWidget);
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
    expect(find.text('10 من 10'), findsOneWidget, reason: 'التبديل معطّل');
    expect(admin.capabilities, before);
    await s.flush();
  });

  testWidgets('إتاحة تبويب فرعي تتيح أصله، والدور يملأ القالب', (tester) async {
    final s = await _store();
    await _pump(tester, s, const UserFormScreen());

    // قالب السكرتير أربعة تبويبات، وليس منها المصروفات
    final list = find.byType(Scrollable).first;
    expect(find.text('4 من 10'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('المستخدمون والصلاحيات'), 200, scrollable: list);
    // إبعاد السطر عن شريط الحفظ الثابت أسفل الشاشة كي تصل اللمسة إليه
    await tester.drag(list, const Offset(0, -120));
    await tester.pump();
    await tester.tap(find.text('المستخدمون والصلاحيات'));
    await tester.pump();

    // العدّاد أعلى الصفحة: يُعاد التمرير إليه بعد أن خرج من الشاشة
    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    expect(find.text('6 من 10'), findsOneWidget, reason: 'المستخدمون ومعه أصله الإعدادات');
    await s.flush();
  });
}
