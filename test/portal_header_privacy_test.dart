import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/screens/portal_chrome.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// كل ما تعرضه الترويسة نصاً — الاسم وتفاصيله في `Text.rich` واحد.
String _headerText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' | ');

/// ترويسة البوابة تُعرض على شاشة يراها غير صاحبها — فلا رقم هوية.

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('الترويسة: اسم المدرسة وسطر الطالب وصفه بلا رقم هوية', (tester) async {
    await _pump(
      tester,
      PortalChromeHeader(
        branding: const PortalBranding(name: 'نون - نظام الإدارة المدرسي'),
        sub: 'محمود أسعد محمد جعرور · حادي عشر علمي · شعبة (2)',
        onExit: () {},
      ),
    );

    final shown = _headerText(tester);
    expect(shown, contains('نون - نظام الإدارة المدرسي'));
    expect(shown, contains('محمود أسعد محمد جعرور · حادي عشر علمي · شعبة (2)'));
    expect(shown, contains('خروج'));
    expect(shown, isNot(contains('431309616')));
  });

  testWidgets('ترويسة وليّ الأمر كالويب: «ولي الأمر: اسمه» بلا هوية ابنته', (tester) async {
    await _pump(
      tester,
      PortalChromeHeader(
        branding: const PortalBranding(name: 'نون - نظام الإدارة المدرسي'),
        sub: 'ولي الأمر: محمد أبو عطايا',
        onExit: () {},
      ),
    );

    final shown = _headerText(tester);
    expect(shown, contains('ولي الأمر: محمد أبو عطايا'));
    expect(shown, isNot(contains('435877733')));
  });

  testWidgets('سهم الفتح ينقلب في العربية فيشير لليسار', (tester) async {
    await _pump(tester, const AppChevron());

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon!.matchTextDirection, isTrue, reason: 'ينعكس مع اتجاه النص');
    // chevron_left الخام كان ينعكس أيضاً فيشير لليمين — عكس المطلوب
    expect(icon.icon, isNot(Icons.chevron_left));
  });
}
