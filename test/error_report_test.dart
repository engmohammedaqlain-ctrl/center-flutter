import 'dart:async';
import 'dart:io';

import 'package:center_mobile/data/error_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('أخطاء الشبكة والجلسة وإلغاء الطلب ليست أعطالاً', () {
    expect(isIgnorableError(errorKind(const SocketException('Failed host lookup')), 'x'), isTrue);
    expect(isIgnorableError(errorKind(TimeoutException('t')), 'x'), isTrue);
    expect(isIgnorableError('Exception', 'Exception: {"code":"PGRST301","message":"JWT expired"}'), isTrue);
    expect(isIgnorableError('ClientException', 'Connection closed before full header was received'), isTrue);
    expect(isIgnorableError('Exception', ''), isTrue);
  });

  test('العطل الحقيقي يُرسل، ونوعه بلا الشرطة', () {
    Object? error;
    try {
      final Object value = 1;
      value as String;
    } catch (e) {
      error = e;
    }
    final kind = errorKind(error!);
    expect(kind.startsWith('_'), isFalse);
    expect(isIgnorableError(kind, '$error'), isFalse);
    expect(isIgnorableError('StateError', 'Bad state: No element'), isFalse);
  });

  test('النص بلا أرقام هوية ولا جوال ولا بريد ولا توكن ولا قيم مفاتيح', () {
    final text = scrubText(
      'Key (national_id)=(403456789) a.b@x.com 0599024136 eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig',
      500,
    );
    expect(text, isNot(matches(RegExp(r'403456789|0599024136|a\.b@x\.com|eyJ'))));
    expect(text, contains(')=(…)'));
    expect(scrubText('x' * 900, 500).length, 500);
  });

  test('الشاشة: أول ملف من التطبيق في مسار الخطأ', () {
    const stack = '#0      List.first (dart:core-patch/growable_array.dart:343:5)\n'
        '#1      _FinanceScreenState.build (package:center_mobile/screens/finance_screen.dart:120:9)\n'
        '#2      StatefulElement.build (package:flutter/src/widgets/framework.dart:5729:27)';
    expect(screenOf(stack), 'screens/finance_screen.dart');
    expect(screenOf('#0 main (dart:core)'), '');
  });
}
