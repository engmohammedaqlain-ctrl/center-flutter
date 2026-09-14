/// مخطط علامات المدرسة — المقابل لـ `features/evaluations/gradingScheme.ts`
/// وحسابه في `gradingCalculation.ts`.
///
/// كل تقييم كان رقماً مستقلاً يدخل بنفس الوزن في متوسط بسيط، فالاختبار النهائي
/// كالواجب سواء. المخطط يجعل لكل فصل مكوّناته وأوزانها، والاسم والوزن حرّان:
/// لا نسبة «رسمية» واحدة تصلح لكل مدرسة ومنهاج.
library;

import 'dart:convert';

import '../models/models.dart';

/// مكوّن موزون ضمن فصل دراسي (شهري، نصفي، نهائي، أعمال…).
class GradingComponent {
  const GradingComponent({required this.id, required this.name, required this.weight});

  final String id;
  final String name;

  /// نسبته من مجموع الفصل (100).
  final double weight;

  GradingComponent copyWith({String? name, double? weight}) =>
      GradingComponent(id: id, name: name ?? this.name, weight: weight ?? this.weight);

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'weight': weight};

  factory GradingComponent.fromMap(Map<String, dynamic> m) => GradingComponent(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        weight: (m['weight'] as num?)?.toDouble() ?? 0,
      );
}

/// فصلا الدراسة ومكوّنات كلٍّ منهما.
class GradingScheme {
  const GradingScheme({this.term1 = const [], this.term2 = const []});

  final List<GradingComponent> term1;
  final List<GradingComponent> term2;

  static const empty = GradingScheme();

  List<GradingComponent> of(String term) => term == 'term_2' ? term2 : term1;

  /// هل عرّفت المدرسة مكوّنات لهذا الفصل؟ إن لم تفعل تبقى شاشات الرصد على
  /// سلوكها القديم: نوع تقييم حرّ بلا وزن.
  bool isConfigured(String term) => of(term).isNotEmpty;

  bool get isEmpty => term1.isEmpty && term2.isEmpty;

  GradingScheme copyWith({List<GradingComponent>? term1, List<GradingComponent>? term2}) =>
      GradingScheme(term1: term1 ?? this.term1, term2: term2 ?? this.term2);

  Map<String, dynamic> toMap() => {
        'term_1': [for (final c in term1) c.toMap()],
        'term_2': [for (final c in term2) c.toMap()],
      };

  String encode() => jsonEncode(toMap());

  /// قراءة آمنة لمخطط قادم من تخزين الجهاز أو من سجل هوية المنشأة.
  factory GradingScheme.fromMap(Map<String, dynamic> m) {
    List<GradingComponent> read(Object? raw) => [
          for (final e in (raw is List ? raw : const []))
            if (e is Map) GradingComponent.fromMap(Map<String, dynamic>.from(e)),
        ];
    return GradingScheme(term1: read(m['term_1']), term2: read(m['term_2']));
  }

  static GradingScheme decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final data = jsonDecode(raw);
      return data is Map ? GradingScheme.fromMap(Map<String, dynamic>.from(data)) : empty;
    } catch (_) {
      return empty;
    }
  }
}

/// المخطط النموذجي: شهري أول 20% + نصفي 20% + شهري ثانٍ 20% + نهائي 40%.
List<GradingComponent> defaultTermComponents(String Function() newId) => [
      GradingComponent(id: newId(), name: 'شهري أول', weight: 20),
      GradingComponent(id: newId(), name: 'نصفي', weight: 20),
      GradingComponent(id: newId(), name: 'شهري ثانٍ', weight: 20),
      GradingComponent(id: newId(), name: 'نهائي', weight: 40),
    ];

GradingScheme defaultGradingScheme(String Function() newId) =>
    GradingScheme(term1: defaultTermComponents(newId), term2: defaultTermComponents(newId));

const gradingTermLabels = {'term_1': 'الفصل الأول', 'term_2': 'الفصل الثاني'};

/// نتيجة مكوّن واحد ضمن فصل.
class ComponentResult {
  const ComponentResult({required this.component, required this.achievedPercent, required this.contribution});

  final GradingComponent component;

  /// `null` يعني أن المكوّن لم يُرصد له تقييم بعد.
  final double? achievedPercent;

  /// مساهمته في مجموع الفصل — النسبة × الوزن ÷ 100.
  final double contribution;
}

/// معدل فصل دراسي لطالب في مادة، وفق مخطط المدرسة.
class TermGrade {
  const TermGrade({
    required this.components,
    required this.isComplete,
    required this.total,
    required this.gradedWeight,
    required this.currentAverage,
  });

  final List<ComponentResult> components;

  /// كل مكوّن بوزن أكبر من صفر رُصد له تقييم واحد على الأقل.
  final bool isComplete;
  final double total;

  /// مجموع أوزان ما رُصد فعلاً.
  final double gradedWeight;

  /// المعدل المتجدّد لما رُصد حتى الآن، أو `null` إن لم يُرصد شيء.
  final double? currentAverage;
}

/// حساب معدل الفصل — المقابل لـ `computeTermGrade`.
///
/// كل مكوّن هو متوسط (الدرجة ÷ العظمى) لكل تقييماته، فيستوي فيه المكوّن الذي
/// يجمع تقييمات عدة (الأعمال) والمكوّن بتقييم واحد (النهائي).
TermGrade computeTermGrade(Iterable<Evaluation> evaluations, GradingScheme scheme, String term) {
  final results = <ComponentResult>[];

  for (final component in scheme.of(term)) {
    final matching = evaluations.where((e) => e.term == term && e.componentId == component.id).toList();
    if (matching.isEmpty) {
      results.add(ComponentResult(component: component, achievedPercent: null, contribution: 0));
      continue;
    }
    final sum = matching.fold<double>(
      0,
      (acc, e) => acc + (e.maxScore > 0 ? (e.score / e.maxScore) * 100 : 0),
    );
    final avg = sum / matching.length;
    results.add(
      ComponentResult(
        component: component,
        achievedPercent: avg,
        contribution: avg * component.weight / 100,
      ),
    );
  }

  final isComplete = results.every((r) => r.component.weight <= 0 || r.achievedPercent != null);
  final total = results.fold<double>(0, (a, r) => a + r.contribution);
  final gradedWeight = results
      .where((r) => r.achievedPercent != null)
      .fold<double>(0, (a, r) => a + r.component.weight);

  return TermGrade(
    components: results,
    isComplete: isComplete,
    total: total,
    gradedWeight: gradedWeight,
    currentAverage: gradedWeight > 0 ? total / gradedWeight * 100 : null,
  );
}

/// معدل السنة = متوسط الفصلين، ولا يُحتسب إلا باكتمالهما.
double? computeYearAverage(TermGrade term1, TermGrade term2) {
  if (!term1.isComplete || !term2.isComplete) return null;
  return (term1.total + term2.total) / 2;
}
