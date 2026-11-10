/// حساب طويل على خيط الواجهة يُقطَّع فلا تتجمّد الشاشة ولا تتقطع دوّارتها.
///
/// الحساب يُكتب مولِّداً (`sync*`) يُنتج `null` عند نقاط آمنة للتوقف؛ المتزامن
/// يمرّ عليه كله دفعة (للاختبارات وللمستدعين القدامى)، و[runSliced] يُفسح للرسم
/// كلما تجاوزت القطعة ميزانيتها. الكود واحد، فالنتيجة واحدة في الحالتين.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';

import '../models/models.dart';

/// ميزانية مشتركة لكل الأعمال الخلفية على خيط الواجهة في الإطار الواحد.
///
/// كل عمل مقطّع كان يأخذ 6ms ثم يُفسح، لكن خمسة أعمال معاً عند الفتح (تحميل
/// الجداول، حساب الرئيسية، الأختام، الأرصدة، المزامنة) تتكدّس في الإطار نفسه
/// فتصير 30ms وتتقطع الشاشة كلها حتى تنتهي. الآن الأعمال كلها تتقاسم ~6ms بعد
/// كل إطار، ثم تنتظر الإطار التالي.
abstract final class UiBudget {
  static const workMs = 6;
  static final _clock = Stopwatch()..start();

  /// نهاية آخر إطار على خيط الواجهة، وآخر استئناف بعد إفساح (بلا إطارات).
  static int _frameEndUs = 0;
  static int _resumedUs = 0;
  static bool _hooked = false;

  /// الاختبارات بلا إطارات حقيقية: تقطيعٌ زمني كما كان، بلا انتظار رسم.
  static final bool _inTests = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static SchedulerBinding? get _framed {
    if (_inTests) return null;
    try {
      final b = SchedulerBinding.instance;
      return b.framesEnabled ? b : null;
    } catch (_) {
      return null;
    }
  }

  static void _hook(SchedulerBinding b) {
    if (_hooked) return;
    _hooked = true;
    // يُضاف بعد رسم الإطار نفسه (الربط سجّل رسمه أولاً)، فيعلّم نهاية عمل الإطار على الخيط
    b.addPersistentFrameCallback((_) => _frameEndUs = _clock.elapsedMicroseconds);
  }

  /// استُهلكت ميزانية هذا الإطار (لكل الأعمال معاً)؟
  static bool get exhausted {
    final now = _clock.elapsedMicroseconds;
    final b = _framed;
    if (b == null) return now - _resumedUs > workMs * 1000;
    _hook(b);
    final since = _frameEndUs > _resumedUs ? _frameEndUs : _resumedUs;
    return now - since > workMs * 1000;
  }

  /// انتظار رسم الإطار التالي أولاً. بلا إطارات (التطبيق في الخلفية أو
  /// الاختبارات) يكفي دور في حلقة الأحداث، ولا يُنتظر إطار أكثر من 50ms.
  /// زمن الانتظار الكلي في [pause] (للقياس): كم أخّر الإفساح العمل نفسه.
  static int pausedUs = 0;
  static int pauses = 0;

  static Future<void> pause() async {
    final t0 = _clock.elapsedMicroseconds;
    pauses++;
    final b = _framed;
    if (b == null) {
      await Future<void>.delayed(Duration.zero);
    } else {
      _hook(b);
      await Future.any([b.endOfFrame, Future<void>.delayed(const Duration(milliseconds: 50))]);
    }
    _resumedUs = _clock.elapsedMicroseconds;
    pausedUs += _resumedUs - t0;
  }

  /// يُفسح فقط إن استُهلكت الميزانية — للحلقات وبين الجداول والصفحات.
  static Future<void> yieldIfNeeded() async {
    if (exhausted) await pause();
  }
}

/// يمرّ على [steps] كلها، ويُفسح للرسم كلما مضت [budgetMs] ملّي ثانية متصلة.
Future<void> runSliced(Iterable<void> steps) async {
  for (final _ in steps) {
    if (UiBudget.exhausted) await UiBudget.pause();
  }
}

/// يمرّ على [steps] كلها دفعة واحدة — النسخة المتزامنة من الحساب نفسه.
void runAll(Iterable<void> steps) {
  for (final _ in steps) {}
}

/// `isoDate` محفوظاً باليوم: يتكرر لآلاف السندات والأقساط في كل حساب، والأيام
/// المختلفة مئات فقط. كان محفوظاً لكل سجل (Expando)، وإعادة ترتيبها حين تكبر لعشرات
/// الآلاف كانت تجمّد خيط الواجهة ~70ms دفعة واحدة على جوال قديم.
final _isoByDay = <int, String>{};

String isoDateOf(Object owner, DateTime date) {
  final key = date.year * 10000 + date.month * 100 + date.day;
  final cached = _isoByDay[key];
  if (cached != null) return cached;
  if (_isoByDay.length > 20000) _isoByDay.clear();
  return _isoByDay[key] = isoDate(date);
}
