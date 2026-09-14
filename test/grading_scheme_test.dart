import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/grading.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
// `Evaluation` اسمٌ في `flutter_test` أيضاً (فحص الوصولية)، فيُخفى هنا
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

GradingScheme _scheme() => const GradingScheme(
      term1: [
        GradingComponent(id: 'c1', name: 'شهري أول', weight: 20),
        GradingComponent(id: 'c2', name: 'نصفي', weight: 20),
        GradingComponent(id: 'c3', name: 'نهائي', weight: 60),
      ],
    );

Evaluation _eval(String componentId, double score, {String term = 'term_1', double max = 100}) => Evaluation(
      id: 'e-$componentId-$score',
      studentId: 's1',
      title: 'اختبار',
      score: score,
      maxScore: max,
      term: term,
      componentId: componentId,
    );

void main() {
  group('معدل الفصل بالأوزان', () {
    test('كل مكوّن بوزنه، والمجموع مجموع المساهمات', () {
      final grade = computeTermGrade(
        [_eval('c1', 80), _eval('c2', 90), _eval('c3', 70)],
        _scheme(),
        'term_1',
      );

      expect(grade.isComplete, isTrue);
      expect(grade.total, closeTo(80 * .2 + 90 * .2 + 70 * .6, 0.01));
      expect(grade.gradedWeight, 100);
      expect(grade.currentAverage, closeTo(grade.total, 0.01));
    });

    test('المكوّن بعدة تقييمات يدخل بمتوسطها', () {
      final grade = computeTermGrade(
        [_eval('c1', 60), _eval('c1', 100)],
        _scheme(),
        'term_1',
      );
      expect(grade.components.first.achievedPercent, closeTo(80, 0.01));
    });

    test('المعدل الحالي يُحسب على ما رُصد وحده، والفصل يبقى غير مكتمل', () {
      final grade = computeTermGrade([_eval('c1', 90)], _scheme(), 'term_1');

      expect(grade.isComplete, isFalse, reason: 'بقي النصفي والنهائي');
      expect(grade.gradedWeight, 20);
      expect(grade.currentAverage, closeTo(90, 0.01), reason: 'متجدّد: 90% مما رُصد');
      expect(grade.total, closeTo(18, 0.01), reason: 'مساهمته من المئة');
    });

    test('بلا رصد لا معدل', () {
      final grade = computeTermGrade(const [], _scheme(), 'term_1');
      expect(grade.currentAverage, isNull);
      expect(grade.isComplete, isFalse);
    });

    test('تقييمات فصلٍ آخر لا تدخل الحساب', () {
      final grade = computeTermGrade([_eval('c1', 100, term: 'term_2')], _scheme(), 'term_1');
      expect(grade.currentAverage, isNull);
    });

    test('معدل السنة لا يُحتسب إلا باكتمال الفصلين', () {
      final full = computeTermGrade([_eval('c1', 80), _eval('c2', 80), _eval('c3', 80)], _scheme(), 'term_1');
      final partial = computeTermGrade([_eval('c1', 80)], _scheme(), 'term_1');

      expect(computeYearAverage(full, partial), isNull);
      expect(computeYearAverage(full, full), closeTo(80, 0.01));
    });
  });

  group('حفظ المخطط', () {
    test('يُحفظ ويُقرأ، ويصل بقية الأجهزة في كائن المنشأة', () async {
      final s = AppStore.forTesting();
      injectDemoData(s);
      s.currentTenant = s.tenants.first;
      expect(s.gradingScheme.isEmpty, isTrue, reason: 'المدرسة تبدأ بلا مخطط');

      await s.saveGradingScheme(_scheme());

      expect(s.gradingScheme.term1.map((c) => c.name), ['شهري أول', 'نصفي', 'نهائي']);
      expect(s.gradingScheme.isConfigured('term_1'), isTrue);
      expect(s.gradingScheme.isConfigured('term_2'), isFalse);

      final row = s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);
      final colors = row['colors'] as Map<String, dynamic>;
      expect((colors[AppStore.gradingSchemeColorKey] as Map)['term_1'], hasLength(3));
    });

    test('المخطط القادم من السحابة يُستعاد على الجهاز', () async {
      final s = AppStore.forTesting();
      injectDemoData(s);
      s.currentTenant = s.tenants.first;
      s.extraCloud['institution_settings'] = [
        {
          'id': s.tenantId,
          'institution_name': 'مدرسة',
          'colors': {AppStore.gradingSchemeColorKey: _scheme().toMap()},
        },
      ];

      await s.hydrateInstitution();
      expect(s.gradingScheme.term1, hasLength(3));
    });

    test('المخطط الافتراضي مئة بالمئة لكل فصل', () {
      var n = 0;
      final scheme = defaultGradingScheme(() => 'c${n++}');
      for (final term in ['term_1', 'term_2']) {
        final sum = scheme.of(term).fold<double>(0, (a, c) => a + c.weight);
        expect(sum, 100, reason: term);
      }
    });
  });
}
