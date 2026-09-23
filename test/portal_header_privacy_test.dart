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

/// ترويسة البوابة تُعرض على شاشة يراها غير صاحبها — فلا هوية ولا اسم وليّ أمر.

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('الترويسة تُظهر الصف والشعبة بلا رقم هوية', (tester) async {
    await _pump(
      tester,
      PortalChromeHeader(
        branding: const PortalBranding(name: 'نون - نظام الإدارة المدرسي'),
        displayName: 'محمود أسعد محمد جعرور',
        gradeLine: 'حادي عشر علمي · شعبة (2)',
        onExit: () {},
      ),
    );

    final shown = _headerText(tester);
    expect(shown, contains('محمود أسعد محمد جعرور'));
    expect(shown, contains('حادي عشر علمي · شعبة (2)'));
    expect(shown, isNot(contains('431309616')));
  });

  testWidgets('ترويسة وليّ الأمر بلا اسمه ولا هوية ابنته', (tester) async {
    await _pump(
      tester,
      PortalChromeHeader(
        branding: const PortalBranding(name: 'نون - نظام الإدارة المدرسي'),
        displayName: 'زينة محمد عبد الكريم أبو عطايا',
        gradeLine: 'سادس · شعبة (1)',
        onExit: () {},
      ),
    );

    final shown = _headerText(tester);
    expect(shown, contains('زينة محمد عبد الكريم أبو عطايا'));
    expect(shown, isNot(contains('ولي الأمر')));
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
