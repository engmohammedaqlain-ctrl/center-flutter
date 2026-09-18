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

const defaultFullMark = 100.0;

String subjectGradingKey(String grade, String subjectId) => '${grade.trim()}|$subjectId';

/// تخصيص مادة داخل مرحلة — `SubjectGrading`.
class SubjectGrading {
  const SubjectGrading({this.fullMark, this.scheme});

  final double? fullMark;
  final GradingScheme? scheme;

  Map<String, dynamic> toMap() => {
        if (fullMark != null) 'full_mark': fullMark,
        if (scheme != null) 'scheme': scheme!.toMap(),
      };

  factory SubjectGrading.fromMap(Map<String, dynamic> m) => SubjectGrading(
        fullMark: (m['full_mark'] as num?)?.toDouble(),
        scheme: m['scheme'] is Map
            ? GradingScheme.fromMap(Map<String, dynamic>.from(m['scheme'] as Map))
            : null,
      );
}

/// نظام الرصد الكامل — `GradingSettings` في الويب.
class GradingSettings {
  const GradingSettings({
    this.mode = 'weighted',
    this.scheme = GradingScheme.empty,
    this.subjects = const {},
    this.yearResultMode = 'average',
    this.monthlyDiscountRules = const [],
  });

  static const empty = GradingSettings();

  /// `weighted` أو `monthly`.
  final String mode;
  final GradingScheme scheme;
  final Map<String, SubjectGrading> subjects;

  /// `average` | `term_2_only` | `sum`.
  final String yearResultMode;
  final List<({double minAverage, double discountPercent})> monthlyDiscountRules;

  GradingScheme schemeForSubject(String grade, String subjectId) =>
      subjects[subjectGradingKey(grade, subjectId)]?.scheme ?? scheme;

  double fullMarkForSubject(String grade, String subjectId) =>
      subjects[subjectGradingKey(grade, subjectId)]?.fullMark ?? defaultFullMark;

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'scheme': scheme.toMap(),
        'subjects': {
          for (final e in subjects.entries) e.key: e.value.toMap(),
        },
        'year_result_mode': yearResultMode,
        'monthly_discount_rules': [
          for (final r in monthlyDiscountRules)
            {'min_average': r.minAverage, 'discount_percent': r.discountPercent},
        ],
      };

  static GradingSettings normalize(Object? raw) {
    final value = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final subjectsRaw = value['subjects'];
    final subjects = <String, SubjectGrading>{};
    if (subjectsRaw is Map) {
      for (final e in subjectsRaw.entries) {
        if (e.value is Map) {
          subjects['${e.key}'] = SubjectGrading.fromMap(Map<String, dynamic>.from(e.value as Map));
        }
      }
    }
    final yrm = '${value['year_result_mode'] ?? ''}';
    final rules = <({double minAverage, double discountPercent})>[];
    final rulesRaw = value['monthly_discount_rules'];
    if (rulesRaw is List) {
      for (final e in rulesRaw) {
        if (e is! Map) continue;
        rules.add((
          minAverage: (e['min_average'] as num?)?.toDouble() ?? 0,
          discountPercent: (e['discount_percent'] as num?)?.toDouble() ?? 0,
        ));
      }
    }
    return GradingSettings(
      mode: value['mode'] == 'monthly' ? 'monthly' : 'weighted',
      scheme: value['scheme'] is Map
          ? GradingScheme.fromMap(Map<String, dynamic>.from(value['scheme'] as Map))
          : GradingScheme.empty,
      subjects: subjects,
      yearResultMode: yrm == 'term_2_only' || yrm == 'sum' ? yrm : 'average',
      monthlyDiscountRules: rules,
    );
  }

  GradingSettings copyWith({
    String? mode,
    GradingScheme? scheme,
    Map<String, SubjectGrading>? subjects,
    String? yearResultMode,
    List<({double minAverage, double discountPercent})>? monthlyDiscountRules,
  }) =>
      GradingSettings(
        mode: mode ?? this.mode,
        scheme: scheme ?? this.scheme,
        subjects: subjects ?? this.subjects,
        yearResultMode: yearResultMode ?? this.yearResultMode,
        monthlyDiscountRules: monthlyDiscountRules ?? this.monthlyDiscountRules,
      );
}

/// تقييم مادة مرتبط بشعبة — يُستبعد من قائمة المعدلات الشهرية.
bool isSubjectEvaluation(Evaluation e) => e.subjectId.isNotEmpty && e.groupId.isNotEmpty;

/// معدل شهري عام: نوع `monthly` بلا مادة.
bool isMonthlyAverage(Evaluation e) => e.type == 'monthly' && e.subjectId.isEmpty;

/// نتيجة مكوّن واحد ضمن فصل.
class ComponentResult {
  const ComponentResult({
    required this.component,
    required this.achievedPercent,
    required this.contribution,
    this.achievedScore,
    this.maxScore = 0,
  });

  final GradingComponent component;

  /// `null` يعني أن المكوّن لم يُرصد له تقييم بعد.
  final double? achievedPercent;

  /// مساهمته في مجموع الفصل — النسبة × الوزن ÷ 100.
  final double contribution;
  final double? achievedScore;
  final double maxScore;
}

/// معدل فصل دراسي لطالب في مادة، وفق مخطط المدرسة.
class TermGrade {
  const TermGrade({
    required this.components,
    required this.isComplete,
    required this.total,
    required this.gradedWeight,
    required this.currentAverage,
    this.fullMark = defaultFullMark,
    this.termScore = 0,
    this.currentScore,
  });

  final List<ComponentResult> components;

  /// كل مكوّن بوزن أكبر من صفر رُصد له تقييم واحد على الأقل.
  final bool isComplete;
  final double total;

  /// مجموع أوزان ما رُصد فعلاً.
  final double gradedWeight;

  /// المعدل المتجدّد لما رُصد حتى الآن، أو `null` إن لم يُرصد شيء.
  final double? currentAverage;
  final double fullMark;
  final double termScore;
  final double? currentScore;
}

/// حساب معدل الفصل — المقابل لـ `computeTermGrade`.
TermGrade computeTermGrade(
  Iterable<Evaluation> evaluations,
  GradingScheme scheme,
  String term, {
  double fullMark = defaultFullMark,
}) {
  final components = scheme.of(term);
  final totalWeight = components.fold<double>(0, (a, c) => a + c.weight);
  final weightBase = totalWeight > 0 ? totalWeight : 100.0;
  final results = <ComponentResult>[];

  for (final component in components) {
    final matching = evaluations.where((e) => e.term == term && e.componentId == component.id).toList();
    final componentMax = (component.weight / weightBase) * fullMark;
    if (matching.isEmpty) {
      results.add(ComponentResult(
        component: component,
        achievedPercent: null,
        contribution: 0,
        achievedScore: null,
        maxScore: componentMax,
      ));
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
        achievedScore: (avg / 100) * componentMax,
        maxScore: componentMax,
      ),
    );
  }

  final isComplete = results.every((r) => r.component.weight <= 0 || r.achievedPercent != null);
  final total = results.fold<double>(0, (a, r) => a + r.contribution);
  final gradedWeight = results
      .where((r) => r.achievedPercent != null)
      .fold<double>(0, (a, r) => a + r.component.weight);
  final currentAverage = gradedWeight > 0 ? total / gradedWeight * 100 : null;

  return TermGrade(
    components: results,
    isComplete: isComplete,
    total: total,
    gradedWeight: gradedWeight,
    currentAverage: currentAverage,
    fullMark: fullMark,
    termScore: (total / weightBase) * fullMark,
    currentScore: currentAverage == null ? null : (currentAverage / 100) * fullMark,
  );
}

class YearGrade {
  const YearGrade({required this.percent, required this.score, required this.yearFullMark});

  final double percent;
  final double score;
  final double yearFullMark;
}

double _termPercent(TermGrade term) {
  final tw = term.components.fold<double>(0, (s, r) => s + r.component.weight);
  final base = tw > 0 ? tw : 100.0;
  return (term.total / base) * 100;
}

/// نتيجة السنة — `computeYearGrade`.
YearGrade? computeYearGrade(
  TermGrade term1,
  TermGrade term2, {
  double fullMark = defaultFullMark,
  String mode = 'average',
}) {
  final t1Defined = term1.components.isNotEmpty;
  final t2Defined = term2.components.isNotEmpty;
  if (!t1Defined && !t2Defined) return null;
  if (mode == 'term_2_only' && !t2Defined) return null;
  if (mode != 'term_2_only' && (!t1Defined || !t2Defined)) {
    final only = t1Defined ? term1 : term2;
    if (!only.isComplete) return null;
    final pct = _termPercent(only);
    return YearGrade(percent: pct, score: (pct / 100) * fullMark, yearFullMark: fullMark);
  }

  if (mode == 'term_2_only') {
    if (!term2.isComplete) return null;
    final pct = _termPercent(term2);
    return YearGrade(percent: pct, score: (pct / 100) * fullMark, yearFullMark: fullMark);
  }
  if (mode == 'sum') {
    if (!term1.isComplete || !term2.isComplete) return null;
    final score1 = (_termPercent(term1) / 100) * fullMark;
    final score2 = (_termPercent(term2) / 100) * fullMark;
    final totalScore = score1 + score2;
    final yearFm = fullMark * 2;
    return YearGrade(percent: (totalScore / yearFm) * 100, score: totalScore, yearFullMark: yearFm);
  }
  if (!term1.isComplete || !term2.isComplete) return null;
  final percent = (_termPercent(term1) + _termPercent(term2)) / 2;
  return YearGrade(percent: percent, score: (percent / 100) * fullMark, yearFullMark: fullMark);
}

/// معدل السنة = متوسط الفصلين (توافق قديم).
double? computeYearAverage(TermGrade term1, TermGrade term2, {String mode = 'average'}) {
  final year = computeYearGrade(term1, term2, mode: mode);
  return year?.percent;
}

/// ملخص علامات طالب في مادة واحدة — مطابق لـ `subjectGradeSummaries` في الويب.
class SubjectGradeSummary {
  const SubjectGradeSummary({
    required this.subjectId,
    required this.subjectName,
    required this.term1,
    required this.term2,
    required this.fullMark,
    this.yearGrade,
  });

  final String subjectId;
  final String subjectName;
  final TermGrade term1;
  final TermGrade term2;
  final double fullMark;
  final YearGrade? yearGrade;

  /// توافق شاشات تعرض النسبة فقط.
  double? get yearAverage => yearGrade?.percent;
}

/// معدل موزون لكل مادة من التقييمات المرتبطة بمخطط العلامات.
///
/// التقييمات بلا فصل أو مكوّن تبقى في القائمة فقط ولا تدخل الملخص.
/// نمط المعدل الشهري لا يُنتج ملخصاً موزوناً.
List<SubjectGradeSummary> subjectGradeSummaries(
  Iterable<Evaluation> evaluations,
  GradingScheme scheme,
  String Function(String subjectId) subjectNameOf, {
  GradingSettings? grading,
  String gradeLevel = '',
}) {
  final settings = grading ?? GradingSettings.empty;
  if (settings.mode == 'monthly') return const [];

  final bySubject = <String, List<Evaluation>>{};
  for (final ev in evaluations) {
    if (ev.term.isEmpty || ev.componentId.isEmpty || ev.subjectId.isEmpty) continue;
    (bySubject[ev.subjectId] ??= []).add(ev);
  }

  return [
    for (final entry in bySubject.entries)
      () {
        final subjectScheme = settings.scheme.isEmpty && settings.subjects.isEmpty
            ? scheme
            : settings.schemeForSubject(gradeLevel, entry.key);
        final fullMark = settings.fullMarkForSubject(gradeLevel, entry.key);
        final term1 = computeTermGrade(entry.value, subjectScheme, 'term_1', fullMark: fullMark);
        final term2 = computeTermGrade(entry.value, subjectScheme, 'term_2', fullMark: fullMark);
        return SubjectGradeSummary(
          subjectId: entry.key,
          subjectName: subjectNameOf(entry.key),
          term1: term1,
          term2: term2,
          fullMark: fullMark,
          yearGrade: computeYearGrade(term1, term2, fullMark: fullMark, mode: settings.yearResultMode),
        );
      }(),
  ].where((s) => s.term1.components.isNotEmpty || s.term2.components.isNotEmpty).toList();
}
