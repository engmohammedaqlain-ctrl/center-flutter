import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/tenant_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

void main() {
  setUpAll(() {
    TenantService.masterUsername = 'dev-tester';
    TenantService.masterPassword = 'dev-tester-pass';
  });

  test('تحديث البناء يمسح البيانات المحلية ويفتح كجهاز جديد', () async {
    final disk = FakeDisk();

    final v1 = AppStore.forTesting(installedBuildCode: 10);
    await v1.bootstrap(disk);
    injectDemoData(v1);
    await v1.login('amal', 'amal2026');
    await v1.completeInitialSetup(v1.setupCandidates.first);
    await v1.flush();
    expect(v1.students, isNotEmpty);
    expect(v1.loggedIn, isTrue);

    final v2 = AppStore.forTesting(installedBuildCode: 11);
    await v2.bootstrap(disk);
    expect(v2.students, isEmpty, reason: 'بيانات البناء السابق لا تُستعاد');
    expect(v2.users, isEmpty);
    expect(v2.loggedIn, isFalse, reason: 'جلسة البناء السابق انتهت');
    expect(v2.needsInitialSetup, isFalse, reason: 'بلا دخول بعد');
    expect(disk.settings['last_installed_build_code'], '11');
  });

  test('نفس رقم البناء لا يمسح البيانات', () async {
    final disk = FakeDisk();

    final v1 = AppStore.forTesting(installedBuildCode: 12);
    await v1.bootstrap(disk);
    injectDemoData(v1);
    await v1.login('amal', 'amal2026');
    await v1.completeInitialSetup(v1.setupCandidates.first);
    await v1.flush();
    final n = v1.students.length;

    final v2 = AppStore.forTesting(installedBuildCode: 12);
    await v2.bootstrap(disk);
    expect(v2.students.length, n);
    expect(v2.loggedIn, isTrue);
  });

  test('أول تشغيل يكتب رقم البناء بلا مسح', () async {
    final disk = FakeDisk();
    final s = AppStore.forTesting(installedBuildCode: 5);
    injectDemoData(s);
    await s.bootstrap(disk);
    // البيانات حُقنت قبل الإقلاع في الذاكرة فقط؛ المهم أن الإقلاع لا يرمي
    expect(disk.settings['last_installed_build_code'], '5');
  });
}
