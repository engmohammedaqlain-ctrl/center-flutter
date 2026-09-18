/// نمط المعدل الشهري — المقابل لـ `features/evaluations/monthlyAverages.ts`.
///
/// بعض المدارس تحسب معدل الشهر بنفسها وتُدخله رقماً واحداً لكل طالب. المعدل
/// يُحفظ تقييماً بلا مادة، وتاريخه أول الشهر، ويُستعمل أساساً لخصم تشجيعي على
/// القسط القادم (سند خصم بمبلغ صفر).
library;

import '../models/models.dart';
import 'grading.dart';

const rewardPurpose = 'monthly_reward';

String rewardReference(String month) => 'reward:$month';

String monthDate(String month) => '$month-01';

/// معرّف حتمي لمعدل الطالب في الشهر.
String monthlyAverageId(String studentId, String month) => 'avg_${studentId}_$month';

/// أعلى خصم تستحقه النتيجة من القواعد؛ صفر حين لا قاعدة تنطبق.
double rewardPercent(double average, List<({double minAverage, double discountPercent})> rules) {
  var best = 0.0;
  for (final r in rules) {
    if (r.discountPercent > 0 && average >= r.minAverage) {
      if (r.discountPercent > best) best = r.discountPercent;
    }
  }
  return best;
}

Map<String, List<Evaluation>> monthlyRowsByStudent(Iterable<Evaluation> evaluations, String month) {
  final date = monthDate(month);
  final map = <String, List<Evaluation>>{};
  for (final row in evaluations) {
    if (row.evaluationDate != date || !isMonthlyAverage(row)) continue;
    (map[row.studentId] ??= []).add(row);
  }
  return map;
}

/// معدلات الشهر مفهرسة بالطالب: الأحدث تعديلاً عند التكرار.
Map<String, Evaluation> loadMonthlyAverages(Iterable<Evaluation> evaluations, String month) {
  final map = <String, Evaluation>{};
  for (final entry in monthlyRowsByStudent(evaluations, month).entries) {
    final rows = [...entry.value]..sort((a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? ''));
    map[entry.key] = rows.first;
  }
  return map;
}

Set<String> rewardedStudentIds(Iterable<Payment> payments, String month) {
  final ref = rewardReference(month);
  return {
    for (final p in payments)
      if (p.reference == ref && !p.cancelled && p.studentId.isNotEmpty) p.studentId,
  };
}

bool hasReward(Iterable<Payment> payments, String studentId, String month) {
  final ref = rewardReference(month);
  return payments.any((p) => p.studentId == studentId && p.reference == ref && !p.cancelled);
}
