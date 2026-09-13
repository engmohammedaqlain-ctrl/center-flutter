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

  testWidgets('المركز يرى القاعات لا المراحل والرسوم', (tester) async {
    final s = await _store();
    await s.saveInstitution(type: 'center');
    expect(s.isSchool, isFalse);
    await _pump(tester, s, const Scaffold(body: SettingsScreen()));

    // شريط التبويبات يتمرّر أفقياً، فما خرج منه لا يُبنى حتى يُمرَّر إليه
    await tester.scrollUntilVisible(find.text('القاعات'), 120, scrollable: find.byType(Scrollable).first);
    expect(find.text('القاعات'), findsOneWidget);
    expect(find.text('المراحل والرسوم'), findsNothing);
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

  testWidgets('صلاحيات الحساب المستخدم على الجهاز لا تُعدَّل منه', (tester) async {
    final s = await _store();
    final admin = s.users.firstWhere((u) => u.role == 'admin');
    await s.setDeviceIdentity(admin, '');
    await _pump(tester, s, CapabilitiesScreen(user: admin));

    expect(find.textContaining('فلا تُعدَّل صلاحياته منه'), findsOneWidget);
    expect(find.text('تحديد القسم'), findsNothing);
    expect(find.text('إلغاء القسم'), findsNothing);
    await s.flush();
  });

  testWidgets('تحديد القسم يمنح صلاحياته مع صلاحية العرض التي تعتمد عليها', (tester) async {
    final s = await _store();
    await _pump(tester, s, const UserFormScreen());

    // قالب السكرتير تسع صلاحيات، وليس منها المصروفات
    final list = find.byType(Scrollable).first;
    expect(find.text('9 من 18'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('إدارة المصروفات وصرف الأجور'), 200, scrollable: list);
    // إبعاد السطر عن شريط الحفظ الثابت أسفل الشاشة كي تصل اللمسة إليه
    await tester.drag(list, const Offset(0, -120));
    await tester.pump();
    await tester.tap(find.text('إدارة المصروفات وصرف الأجور'));
    await tester.pump();

    // العدّاد أعلى الصفحة: يُعاد التمرير إليه بعد أن خرج من الشاشة
    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    expect(find.text('10 من 18'), findsOneWidget);
    await s.flush();
  });
}
