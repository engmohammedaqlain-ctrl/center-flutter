import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/grading.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/grading_scheme_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// نظام العلامات يُضبط على الديسكتوب ويصل الجوال داخل سجل هوية المنشأة.
///
/// الحالة المُبلَّغ عنها: المخطط محفوظ بالويب ١٠٠٪، والجوال يقول «لا مكوّنات».

/// صف `institution_settings` كما يكتبه الويب ويصل بالسحب.
Map<String, dynamic> _webRow(String tenantId) => {
      'id': tenantId,
      'institution_name': 'مدرسة الأمل',
      'colors': {
        AppStore.gradingSchemeColorKey: const GradingScheme(
          term1: [
            GradingComponent(id: 'c1', name: 'شهري أول', weight: 20),
            GradingComponent(id: 'c2', name: 'نصفي', weight: 20),
            GradingComponent(id: 'c3', name: 'شهري ثانٍ', weight: 20),
            GradingComponent(id: 'c4', name: 'نهائي', weight: 40),
          ],
        ).toMap(),
      },
    };

AppStore _store() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  return s;
}

void main() {
  test('المخطط القادم من الديسكتوب يُقرأ بعد السحب', () async {
    final s = _store();
    expect(s.gradingScheme.isEmpty, isTrue, reason: 'قبل السحب');

    s.extraCloud['institution_settings'] = [_webRow(s.currentTenant!.id)];
    await s.onPulled();

    final scheme = s.gradingScheme;
    expect(scheme.of('term_1').map((c) => c.name), ['شهري أول', 'نصفي', 'شهري ثانٍ', 'نهائي']);
    expect(scheme.of('term_1').fold<double>(0, (a, c) => a + c.weight), 100);
    expect(jsonDecode(s.db.settings[AppStore.gradingSchemeKey]!), isA<Map<String, dynamic>>());
    await s.flush();
  });

  testWidgets('التبويب يعرضه فور وصوله، بلا إغلاق الصفحة وفتحها', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = _store();
    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: GradingSchemeTab())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('لا مكوّنات'), findsOneWidget);

    // وصل السحب والتبويب مفتوح
    s.extraCloud['institution_settings'] = [_webRow(s.currentTenant!.id)];
    await s.onPulled();
    await tester.pump();

    expect(find.textContaining('لا مكوّنات'), findsNothing);
    expect(find.text('شهري أول'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget, reason: 'مجموع الأوزان كما في الويب');
    await s.flush();
  });
}
