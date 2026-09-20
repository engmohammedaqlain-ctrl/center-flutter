import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/grading.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/grading_scheme_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

AppStore _store() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  return s;
}

Future<void> _pump(WidgetTester tester, AppStore s, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: GradingSchemeTab())),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('علامة النجاح', () {
    test('تُقرأ من الإعدادات وتُكتب معها — الحفظ من الجوال لا يمسح ما ضبطه الويب', () {
      final parsed = GradingSettings.normalize({'mode': 'weighted', 'pass_percent': 60});
      expect(parsed.passPercent, 60);
      expect(parsed.toMap()['pass_percent'], 60);

      // بلا قيمة: 50% كما في `passPercent` على الويب
      expect(GradingSettings.normalize({'mode': 'weighted'}).passPercent, defaultPassPercent);
      expect(GradingSettings.normalize({'pass_percent': 0}).passPercent, defaultPassPercent);
    });

    test('النجاح في التقييم يتبع علامة المدرسة لا 50٪ ثابتة', () async {
      final s = _store();
      final student = s.students.first;
      final e = Evaluation(
        id: 'e1',
        studentId: student.id,
        title: 'اختبار',
        score: 55,
        maxScore: 100,
        type: 'quiz',
        evaluationDate: '2026-09-10',
      );

      expect(s.evaluationPassed(e), isTrue, reason: 'الافتراضي 50%');

      await s.saveGradingSettings(s.gradingSettings.copyWith(passPercent: 60));
      expect(s.evaluationPassed(e), isFalse, reason: 'المدرسة رفعت النجاح إلى 60%');
      await s.flush();
    });
  });

  testWidgets('الفصلان توزيع واحد، و«الفصل الثاني مختلف» يفصلهما', (tester) async {
    final s = _store();
    await _pump(tester, s);

    // محرّر واحد للفصلين ما دام توزيعهما واحداً
    expect(find.text('الفصلان'), findsOneWidget);
    expect(find.text('الفصل الأول'), findsNothing);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('الفصل الأول'), findsOneWidget);
    expect(find.text('الفصل الثاني'), findsOneWidget);
    await s.flush();
  });

  testWidgets('علامة مادة في مرحلة تُكتب في صفّها وتُحفظ بمفتاحها', (tester) async {
    final s = _store();
    final grade = s.gradeFeesInViewedYear.first.gradeName.trim();
    final subject = s.subjectsInViewedYear.first;

    await _pump(tester, s);
    await tester.tap(find.text('علامات المواد'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(subject.name).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(ValueKey('${subjectGradingKey(grade, subject.id)}_mark')), '150');
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(s.gradingSettings.fullMarkForSubject(grade, subject.id), 150);
    // مادة بلا تخصيص تبقى على الافتراضي
    expect(s.gradingSettings.fullMarkForSubject(grade, 'other-subject'), defaultFullMark);
    await s.flush();
  });

  testWidgets('النمط الشهري يستبدل التوزيع بقواعد خصم التفوق', (tester) async {
    final s = _store();
    await _pump(tester, s);

    await tester.tap(find.text('معدل شهري عام'));
    await tester.pumpAndSettle();

    expect(find.text('خصم التفوق'), findsOneWidget);
    expect(find.text('توزيع العلامات'), findsNothing);

    await tester.tap(find.text('قاعدة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(s.gradingSettings.mode, 'monthly');
    expect(s.gradingSettings.monthlyDiscountRules.length, 1);
    expect(s.gradingSettings.monthlyDiscountRules.first.minAverage, 90);
    await s.flush();
  });
}
