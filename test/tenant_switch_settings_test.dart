import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/tenant_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

/// جهاز انتقل من مدرسة إلى أخرى: إعدادات الأولى لا تظهر تحت الثانية.

void main() {
  setUpAll(() {
    TenantService.masterUsername = 'dev-tester';
    TenantService.masterPassword = 'dev-tester-pass';
  });

  test('رسم الحجز وأشهر الدراسة لا يتسرّبان إلى مدرسة أخرى', () async {
    final disk = FakeDisk();
    final s = AppStore.forTesting();
    await s.bootstrap(disk);
    injectDemoData(s);
    expect(await s.login('dev-tester', 'dev-tester-pass'), isNull);

    // المدرسة الأولى: رسم حجز وأشهر دراسة
    final first = s.tenants.first;
    expect(await s.enterTenantAsDeveloper(first), isNull);
    await s.setSeatReservationFee(500);
    await s.saveStudyMonths([9, 10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8]);
    expect(s.seatReservationFee, 500);
    expect(s.studyMonths, isNotNull);
    s.stopAutoSync();
    await s.flush();

    // مدرسة أخرى على الجهاز نفسه
    final second = s.tenants.firstWhere((t) => t.id != first.id);
    await s.logout();
    expect(await s.login('dev-tester', 'dev-tester-pass'), isNull);
    expect(await s.enterTenantAsDeveloper(second), isNull);

    expect(s.seatReservationFee, 0, reason: 'رسم المدرسة الأولى لا يُطالَب به هنا');
    expect(s.studyMonths, isNull, reason: 'وأشهرها كذلك');
    s.stopAutoSync();
    await s.flush();
  });
}
