import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensureStudentPortalCodes يورّث رمز ولي الأمر لنفس العائلة', () {
    final store = AppStore.forTesting();
    injectDemoData(store);

    final siblings = store.students.take(2).toList();
    expect(siblings.length, 2);
    final a = siblings[0];
    final b = siblings[1];
    a
      ..parentNationalId = '900000001'
      ..parentPortalCode = '111111'
      ..portalCode = '222222';
    b
      ..parentNationalId = '900000001'
      ..parentPortalCode = ''
      ..portalCode = '';

    final made = store.ensureStudentPortalCodes([b]);
    expect(made, greaterThan(0));
    expect(b.parentPortalCode, '111111');
    expect(b.portalCode.trim().isNotEmpty, isTrue);
    expect(b.portalCode, isNot(b.parentPortalCode));
  });
}
