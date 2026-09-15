import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/tenant_service.dart';
import 'package:center_mobile/models/models.dart';
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
  test('خروج ثم دخول بمدرسة أخرى: إعداداتها وحدها', () async {
    final disk = FakeDisk();
    final s = AppStore.forTesting();
    await s.bootstrap(disk);
    injectDemoData(s);

    // المدرسة الأولى: رسم حجز وأشهر ورسوم إضافية
    expect(await s.login('amal', 'amal2026'), isNull);
    await s.setSeatReservationFee(500);
    await s.saveStudyMonths([9, 10, 11]);
    await s.saveFeeItems([
      const FeeItem(id: 'fee-1', name: 'الزي المدرسي', amount: 100, dueDate: '2026-09-15'),
    ]);
    s.stopAutoSync();
    await s.flush();

    // خروج، ثم دخول بحساب مدرسة أخرى على الجهاز نفسه
    await s.logout();
    expect(await s.login('noor', 'noor2026'), isNull);

    expect(s.seatReservationFee, 0, reason: 'رسم حجز المدرسة السابقة');
    expect(s.studyMonths, isNull, reason: 'أشهر المدرسة السابقة');
    expect(s.feeItems, isEmpty, reason: 'رسوم المدرسة السابقة');
    expect(s.gradeFees, isEmpty, reason: 'مراحل المدرسة السابقة');
    s.stopAutoSync();
    await s.flush();
  });
  test('جهاز فقد مؤشر بياناته لا يورّث إعدادات مدرسته السابقة', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    expect(await first.login('amal', 'amal2026'), isNull);
    await first.setSeatReservationFee(500);
    await first.saveStudyMonths([9, 10]);
    await first.saveFeeItems([
      const FeeItem(id: 'fee-1', name: 'الزي المدرسي', amount: 100, dueDate: '2026-09-15'),
    ]);
    first.stopAutoSync();
    await first.flush();

    // نسخة أقدم أو إغلاقٌ قبل الحفظ: المؤشران مفقودان والإعدادات باقية
    await first.db.setSetting('db_tenant_id', null);
    await first.db.setSetting('settings_tenant_id', null);
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    injectDemoData(second);
    expect(await second.login('noor', 'noor2026'), isNull);

    expect(second.seatReservationFee, 0, reason: 'رسم حجز مدرسة أخرى');
    expect(second.studyMonths, isNull);
    expect(second.feeItems, isEmpty);
    second.stopAutoSync();
    await second.flush();
  });
  test('مدرسة حُذفت وأُعيد إنشاؤها بنفس الاسم لا ترث إعدادات سابقتها', () async {
    final disk = FakeDisk();
    final s = AppStore.forTesting();
    await s.bootstrap(disk);
    injectDemoData(s);
    expect(await s.login('amal', 'amal2026'), isNull);
    await s.setSeatReservationFee(500);
    await s.saveStudyMonths([9, 10]);
    s.stopAutoSync();
    await s.flush();

    // جهاز من نسخة أقدم: لا مالك مكتوب مع الإعدادات
    await s.db.setSetting('settings_tenant_id', null);

    // المدرسة أُعيد إنشاؤها: الاسم نفسه، والمعرّف جديد تولّده القاعدة
    final old = s.tenants.firstWhere((t) => t.username == 'amal');
    final recreated = Tenant(
      id: '${old.id}-new',
      name: old.name,
      code: old.code,
      username: old.username,
      password: old.password,
      expiresAt: old.expiresAt,
    );
    s.tenants.add(recreated);

    expect(await s.login('dev-tester', 'dev-tester-pass'), isNull);
    expect(await s.enterTenantAsDeveloper(recreated), isNull);

    expect(s.seatReservationFee, 0, reason: 'مدرسة أخرى وإن تطابق اسمها');
    expect(s.studyMonths, isNull);
    s.stopAutoSync();
    await s.flush();
  });
}
