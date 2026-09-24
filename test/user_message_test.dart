import 'package:flutter_test/flutter_test.dart';

import 'package:center_mobile/data/user_message.dart';

void main() {
  test('Arabic messages pass through', () {
    expect(userMessage('لا تملك صلاحية لهذا الإجراء'), 'لا تملك صلاحية لهذا الإجراء');
  });

  test('network errors become short Arabic', () {
    expect(userMessage(Exception('SocketException: Failed host lookup')), 'تعذّر الاتصال بالإنترنت');
  });

  test('RLS JSON becomes short Arabic', () {
    expect(
      userMessage('{"code":"42501","message":"new row violates row-level security policy"}'),
      'لا تملك صلاحية لهذا الإجراء',
    );
  });

  test('syncTableMessage prefixes table', () {
    expect(syncTableMessage('الحضور', 'permission denied'), 'الحضور: لا تملك صلاحية لهذا الإجراء');
  });
}
