import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/tenant_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

/// جهاز مسجّل بحساب المطور العام، ومعه منشآت محفوظة.
Future<AppStore> developer(FakeDisk disk) async {
  final s = AppStore.forTesting();
  await s.bootstrap(disk);
  injectDemoData(s);
  expect(await s.login('dev-tester', 'dev-tester-pass'), isNull);
  expect(s.isMasterAdmin, isTrue);
  return s;
}

void main() {
  setUpAll(() {
    TenantService.masterUsername = 'dev-tester';
    TenantService.masterPassword = 'dev-tester-pass';
  });

  test('المطور يدخل المنشأة بلا كلمة مرورها', () async {
    final s = await developer(FakeDisk());
    final tenant = s.tenants.first..password = '';

    expect(await s.enterTenantAsDeveloper(tenant), isNull);

    expect(s.loggedIn, isTrue);
    expect(s.isMasterAdmin, isFalse);
    expect(s.currentTenant?.id, tenant.id);
    expect(s.needsInitialSetup, isTrue, reason: 'يمرّ على اختيار هوية الجهاز كأي دخول');
    s.stopAutoSync();
    await s.flush();
  });

  test('المنشأة التي دخلها تُستعاد بعد إعادة التشغيل', () async {
    final disk = FakeDisk();
    final first = await developer(disk);
    final tenant = first.tenants.first;
    await first.enterTenantAsDeveloper(tenant);
    first.stopAutoSync();
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.loggedIn, isTrue);
    expect(second.isMasterAdmin, isFalse);
    expect(second.currentTenant?.id, tenant.id);
  });

  test('من ليس مطوراً لا يدخل منشأة من هذا المسار', () async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);
    final tenant = s.tenants.first;

    expect(await s.enterTenantAsDeveloper(tenant), isNotNull);
    expect(s.currentTenant, isNull);
  });

  test('اشتراك منتهٍ لا يُدخل', () async {
    final s = await developer(FakeDisk());
    final tenant = s.tenants.first..expiresAt = DateTime(2020, 1, 1);

    expect(await s.enterTenantAsDeveloper(tenant), isNotNull);
    expect(s.isMasterAdmin, isTrue);
  });
}
