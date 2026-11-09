import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// سجل أداء خفيف يعمل في النسخة النهائية: مراحل الإقلاع بأزمانها، والإطارات
/// المتأخرة (تقطّع الدوّارة) بمدتها والمرحلة التي حدثت فيها. يُعرض وينسخ من
/// إعدادات المطوّر، لتصل أرقام جوال المدرسة نفسه بدل التخمين.
abstract final class PerfLog {
  static final _clock = Stopwatch()..start();
  static final marks = <({int at, String name})>[];
  static final slowFrames = <({int at, int ms, String phase})>[];
  static String _phase = 'إقلاع';
  static bool _watching = false;

  /// أقصى ما يُحفظ — سجل لا ينمو بلا حد على جوال يبقى مفتوحاً أياماً.
  static const _maxMarks = 200;
  static const _maxFrames = 300;

  /// إطار أطول من هذا يُعدّ تقطّعاً ظاهراً.
  static const slowFrameMs = 50;

  /// علامة مرحلة: «بدء تحميل الرئيسية»، «انتهى حساب الرئيسية»...
  static void mark(String name) {
    _phase = name;
    if (marks.length >= _maxMarks) marks.removeAt(0);
    marks.add((at: _clock.elapsedMilliseconds, name: name));
    // بناء القياس (profile) يطبعها في logcat لتُقرأ والجوال موصول
    if (kProfileMode) debugPrint('PERF ${_clock.elapsedMilliseconds}ms mark: $name');
  }

  /// يبدأ رصد الإطارات بعد إنشاء الربط — مرة واحدة.
  static void watchFrames() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final ms = t.totalSpan.inMilliseconds;
        // في بناء القياس: كل إطار تجاوز الإطار الواحد، مقسوماً بين خيط البناء (UI) وخيط الرسم (raster)
        if (kProfileMode && ms > 20) {
          debugPrint('PERF ${_clock.elapsedMilliseconds}ms frame total=${ms} build=${t.buildDuration.inMilliseconds} '
              'raster=${t.rasterDuration.inMilliseconds} vsyncWait=${t.vsyncOverhead.inMilliseconds} phase=$_phase');
        }
        if (ms < slowFrameMs) continue;
        if (slowFrames.length >= _maxFrames) slowFrames.removeAt(0);
        slowFrames.add((at: _clock.elapsedMilliseconds, ms: ms, phase: _phase));
      }
    });
  }

  /// نص يُنسخ ويُرسل: المراحل بأزمانها ثم أبطأ الإطارات.
  static String report() {
    final b = StringBuffer('سجل الأداء (ms منذ الفتح)\n');
    for (final m in marks) {
      b.writeln('${m.at}\t${m.name}');
    }
    final worst = [...slowFrames]..sort((a, c) => c.ms - a.ms);
    b.writeln('\nأبطأ الإطارات (${slowFrames.length} فوق $slowFrameMs ms):');
    for (final f in worst.take(30)) {
      b.writeln('${f.ms}ms\tعند ${f.at}\t${f.phase}');
    }
    return b.toString();
  }

  @visibleForTesting
  static void reset() {
    marks.clear();
    slowFrames.clear();
    _phase = 'إقلاع';
  }
}
