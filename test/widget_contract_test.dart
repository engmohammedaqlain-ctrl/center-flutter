import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// أسماء الوسائط في العمق الأول لاستدعاء يبدأ بعد قوسه المفتوح.
List<String> _topLevelArgs(String src, int start) {
  var depth = 1;
  var i = start;
  var token = StringBuffer();
  final names = <String>[];

  while (i < src.length && depth > 0) {
    final ch = src[i];
    if ('([{'.contains(ch)) {
      depth++;
    } else if (')]}'.contains(ch)) {
      depth--;
      if (depth == 0) break;
    } else if (depth == 1) {
      if (ch == ',') {
        token = StringBuffer();
      } else if (ch == ':') {
        final parts = token.toString().trim().split(RegExp(r'\s+'));
        final name = parts.isEmpty ? '' : parts.last;
        if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) names.add(name);
        token = StringBuffer();
      } else {
        token.write(ch);
      }
    }
    i++;
  }
  return names;
}

void main() {
  /// `Container` يرفض `color` و`decoration` معاً وقت التشغيل فقط: المحلّل
  /// يمرّرهما، ثم تسقط الشاشة عند فتحها. هذا الاختبار يمسك الخطأ قبل ذلك.
  test('no Container passes both a color and a decoration', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();

      for (final m in RegExp(r'\bContainer\(').allMatches(src)) {
        final args = _topLevelArgs(src, m.end);
        if (args.contains('color') && args.contains('decoration')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${entity.path.replaceAll(r'\', '/')}:$line');
        }
      }
    }

    expect(offenders, isEmpty, reason: 'حاوية تجمع لوناً وزخرفة:\n${offenders.join('\n')}');
  });
}
