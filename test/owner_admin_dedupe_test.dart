import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// مدير المنشأة وهوية حساب المدرسة.
///
/// 7 نوفمبر 2026: موظفة أُضيفت بدور مدير وتبويب الطلاب وحده، فحذف «تنظيف التكرار»
/// مدير المنشأة وصار حساب المدرسة باسمها وبتبويبها.
void main() {
  AppStore school() {
    final store = AppStore.forTesting();
    injectDemoData(store);
    store.currentTenant = store.tenants.first;
    return store;
  }

  test('ensureOwnerAdmin لا يُنشئ مديراً ثانياً إن وُجد مدير منشأة مسبقاً', () {
    final store = school();

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

  test('موظف مدير له دخوله لا يغني عن مدير المنشأة', () {
    final store = school();
    store.users
      ..clear()
      ..add(AppUser(id: 'staff-admin', name: 'موظفة', role: 'admin', nationalId: '804753143'));

    final owner = store.ensureOwnerAdmin();
    expect(owner.id, 'owner_${store.tenantId}');
    expect(store.users.any((u) => u.id == 'staff-admin'), isTrue);
  });

  test('حساب المدرسة لا يعمل باسم موظف له دخوله، ومدير المنشأة لا يُحذف', () async {
    final store = school();
    final ownerId = 'owner_${store.tenantId}';
    store.users
      ..clear()
      ..add(AppUser(id: ownerId, name: 'ALMISTER', role: 'admin'))
      ..add(AppUser(id: 'staff-admin', name: 'موظفة', role: 'admin', capabilities: ['students'], authUserId: 'a1'));
    await store.setDeviceIdentity(store.users.last, '');

    expect(await store.adoptOwnerIdentity(create: false), isTrue);
    expect(store.deviceUserId, ownerId);
    expect(store.setupCandidates.any((u) => u.id == ownerId), isTrue);
    expect(store.users.any((u) => u.id == ownerId), isTrue);
    expect(store.pendingSyncs.where((a) => a.recordId == ownerId && a.action == 'DELETE'), isEmpty);
    for (final section in allSections) {
      expect(store.can(section), isTrue, reason: section);
    }
  });
}
