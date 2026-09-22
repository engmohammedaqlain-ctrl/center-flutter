import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensureOwnerAdmin لا يُنشئ مديراً ثانياً إن وُجد مدير مسبقاً', () {
    final store = AppStore.forTesting();
    injectDemoData(store);
    store.currentTenant = store.tenants.first;

    final before = store.users.where((u) => normalizeRole(u.role) == 'admin').length;
    expect(before, greaterThan(0));

    final returned = store.ensureOwnerAdmin();
    expect(normalizeRole(returned.role), 'admin');
    expect(
      store.users.where((u) => normalizeRole(u.role) == 'admin').length,
      before,
      reason: 'لا يُضاف owner_ فوق مدير موجود',
    );
    expect(store.users.any((u) => u.id == 'owner_${store.tenantId}'), isFalse);
  });

  test('dedupeOwnerAdmins يحذف owner_ المكرر ويبقي المدير الأصلي', () {
    final store = AppStore.forTesting();
    injectDemoData(store);
    store.currentTenant = store.tenants.first;
    final tid = store.tenantId!;

    final original = store.users.firstWhere((u) => normalizeRole(u.role) == 'admin');
    store.users.add(
      AppUser(
        id: 'owner_$tid',
        name: original.name,
        role: 'admin',
        capabilities: [...allSections],
      ),
    );

    expect(store.dedupeOwnerAdmins(), 1);
    expect(store.users.any((u) => u.id == 'owner_$tid'), isFalse);
    expect(store.users.any((u) => u.id == original.id), isTrue);
  });
}
