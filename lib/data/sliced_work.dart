/// حساب طويل على خيط الواجهة يُقطَّع فلا تتجمّد الشاشة ولا تتقطع دوّارتها.
///
/// الحساب يُكتب مولِّداً (`sync*`) يُنتج `null` عند نقاط آمنة للتوقف؛ المتزامن
/// يمرّ عليه كله دفعة (للاختبارات وللمستدعين القدامى)، و[runSliced] يُفسح للرسم
/// كلما تجاوزت القطعة ميزانيتها. الكود واحد، فالنتيجة واحدة في الحالتين.
library;

import '../models/models.dart';

/// ميزانية القطعة قبل الإفساح: دون نصف إطار الستين هرتز.
const slicedBudgetMs = 6;

/// يمرّ على [steps] كلها، ويُفسح للرسم كلما مضت [budgetMs] ملّي ثانية متصلة.
Future<void> runSliced(Iterable<void> steps, {int budgetMs = slicedBudgetMs}) async {
  final slice = Stopwatch()..start();
  for (final _ in steps) {
    if (slice.elapsedMilliseconds >= budgetMs) {
      await Future<void>.delayed(Duration.zero);
      slice.reset();
    }
  }
}

/// يمرّ على [steps] كلها دفعة واحدة — النسخة المتزامنة من الحساب نفسه.
void runAll(Iterable<void> steps) {
  for (final _ in steps) {}
}

/// `isoDate` محفوظاً مع تاريخه لكل سجل: يتكرر لآلاف السندات والأقساط في كل حساب.
final _isoCache = Expando<(DateTime, String)>('isoDateOf');

String isoDateOf(Object owner, DateTime date) {
  final cached = _isoCache[owner];
  if (cached != null && cached.$1 == date) return cached.$2;
  final s = isoDate(date);
  _isoCache[owner] = (date, s);
  return s;
}
