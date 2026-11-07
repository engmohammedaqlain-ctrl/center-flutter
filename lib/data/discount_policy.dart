/// خصم الإخوة والتفوق وفئات المدرسة — المقابل لـ `discountPolicy.ts`.
///
/// سياسة تضبطها الإدارة ويقترحها نموذج التسجيل للطالب الجديد. لا يُجمع خصمان:
/// يُعطى الأكبر، والموظف يعدّله أو يلغيه قبل الحفظ.
library;

import 'app_settings.dart';

const siblingReason = 'إخوة';
const meritReason = 'تفوق دراسي';

/// متى ينطبق خصم الفئة — `DISCOUNT_CRITERION_LABELS`.
const discountCriterionLabels = <String, String>{
  'orphan': 'كل الأيتام',
  'orphan_father': 'يتيم الأب',
  'orphan_mother': 'يتيم الأم',
  'orphan_both': 'يتيم الأبوين',
  'sick': 'حالة صحية',
};

class DiscountTier {
  const DiscountTier({required this.min, required this.percent});

  final double min;
  final double percent;

  Map<String, dynamic> toMap() => {'min': min, 'percent': percent};
}

class DiscountRule {
  const DiscountRule({this.enabled = false, this.tiers = const []});

  final bool enabled;
  final List<DiscountTier> tiers;

  Map<String, dynamic> toMap() => {'enabled': enabled, 'tiers': [for (final t in tiers) t.toMap()]};

  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static DiscountRule from(Object? raw, DiscountRule fallback) {
    if (raw is! Map) return fallback;
    final tiers = raw['tiers'];
    return DiscountRule(
      enabled: raw['enabled'] == true,
      tiers: [
        if (tiers is List)
          for (final t in tiers)
            if (t is Map) DiscountTier(min: _num(t['min']), percent: _num(t['percent'])),
      ],
    );
  }
}

class DiscountCategory {
  const DiscountCategory({required this.id, required this.name, required this.when, required this.percent});

  final String id;
  final String name;
  final String when;
  final double percent;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'when': when, 'percent': percent};
}

class DiscountPolicy {
  const DiscountPolicy({this.sibling = _defaultSibling, this.merit = _defaultMerit, this.categories = const []});

  static const _defaultSibling = DiscountRule(tiers: [DiscountTier(min: 2, percent: 10)]);
  static const _defaultMerit = DiscountRule(tiers: [DiscountTier(min: 90, percent: 10)]);

  final DiscountRule sibling;
  final DiscountRule merit;
  final List<DiscountCategory> categories;

  Map<String, dynamic> toMap() => {
        'sibling': sibling.toMap(),
        'merit': merit.toMap(),
        'categories': [for (final c in categories) c.toMap()],
      };

  factory DiscountPolicy.from(Object? raw) {
    if (raw is! Map) return const DiscountPolicy();
    final cats = raw['categories'];
    return DiscountPolicy(
      sibling: DiscountRule.from(raw['sibling'], _defaultSibling),
      merit: DiscountRule.from(raw['merit'], _defaultMerit),
      categories: [
        if (cats is List)
          for (final c in cats)
            if (c is Map && discountCriterionLabels.containsKey(c['when']))
              DiscountCategory(
                id: '${c['id'] ?? ''}',
                name: '${c['name'] ?? ''}',
                when: '${c['when']}',
                percent: DiscountRule._num(c['percent']),
              ),
      ],
    );
  }
}

extension DiscountPolicySettings on AppSettings {
  DiscountPolicy get discounts => DiscountPolicy.from(extra['discounts']);
}

/// نسبة أعلى شريحة يبلغها الحد؛ 0 إن لم يبلغ أياً منها — `tierPercent`.
double tierPercent(List<DiscountTier> tiers, double value) {
  if (value.isNaN || value.isInfinite) return 0;
  var best = 0.0;
  var bestMin = double.negativeInfinity;
  for (final t in tiers) {
    if (value >= t.min && t.min >= bestMin) {
      best = t.percent;
      bestMin = t.min;
    }
  }
  return best;
}

/// «92.5%» أو «٩٢٫٥» ← 92.5 — `parseAverage`.
double parseAverage(String? text) {
  final clean = (text ?? '')
      .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!)}')
      .replaceAll(RegExp('[٫,]'), '.')
      .replaceAll(RegExp(r'[^\d.]'), '');
  return clean.isEmpty ? double.nan : double.tryParse(clean) ?? double.nan;
}

bool meetsCriterion(String when, {String orphan = '', bool sick = false}) => switch (when) {
      'orphan' => orphan.isNotEmpty,
      'orphan_father' => orphan == 'father' || orphan == 'both',
      'orphan_mother' => orphan == 'mother' || orphan == 'both',
      'orphan_both' => orphan == 'both',
      'sick' => sick,
      _ => false,
    };

/// الخصم المقترح لطالب جديد — `suggestDiscount`. [siblingsBefore] إخوته المسجلون قبله،
/// فترتيبه = العدد + 1. الأكبر يغلب، وعند التساوي الأسبق.
({double percent, String reason})? suggestDiscount(
  DiscountPolicy policy, {
  required int siblingsBefore,
  required double average,
  String orphan = '',
  bool sick = false,
}) {
  final options = <({double percent, String reason})>[
    if (policy.sibling.enabled && siblingsBefore > 0)
      (percent: tierPercent(policy.sibling.tiers, siblingsBefore + 1), reason: siblingReason),
    if (policy.merit.enabled) (percent: tierPercent(policy.merit.tiers, average), reason: meritReason),
    for (final c in policy.categories)
      if (meetsCriterion(c.when, orphan: orphan, sick: sick)) (percent: c.percent, reason: c.name),
  ];
  ({double percent, String reason})? best;
  for (final o in options) {
    if (o.percent > (best?.percent ?? 0)) best = o;
  }
  return best;
}
