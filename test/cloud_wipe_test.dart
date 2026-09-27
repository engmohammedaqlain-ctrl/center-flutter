import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

/// المسح الشامل — مطابق لـ `clearAllDataIncludingCloud` و`wipeAnnounce.test.ts` في الويب.
void main() {
  Future<AppStore> seeded() async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);
    return s;
  }

  test('جداول المسح هي جداول الويب، والمزامَنة كلها داخلها', () {
    for (final t in syncedTables) {
      expect(AppStore.cloudWipeTables, contains(t));
    }
    // الأبناء قبل الآباء: الطلاب بعد أقساطهم، والمستخدمون آخراً
    final order = AppStore.cloudWipeTables.reversed.toList();
    expect(order.indexOf('installments'), lessThan(order.indexOf('students')));
    expect(order.last, 'users');
  });

  test('بلا اتصال: لا مسح ولا إشارة، والجهاز يبقى كما هو', () async {
    final s = await seeded();
    s.currentTenant = s.tenants.first;
    final students = s.students.length;
    final signals = s.peerNotifications;

    await expectLater(s.wipeAllDataIncludingCloud(developerToken: 'dev'), throwsA(isA<StoreException>()));
    expect(s.students.length, students);
    expect(s.peerNotifications, signals);
  });

  test('بلا منشأة نشطة: يُمسح الجهاز وحده مع هوية المنشأة المحفوظة', () async {
    final s = await seeded();
    s.currentTenant = null;
    await s.db.setSetting(institutionNameKey, 'مدرسة قديمة');

    await s.wipeAllDataIncludingCloud(developerToken: 'dev');

    expect(s.students, isEmpty);
    expect(s.payments, isEmpty);
    expect(s.db.settings[institutionNameKey], isNull);
  });
}
