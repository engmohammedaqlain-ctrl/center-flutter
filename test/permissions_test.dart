import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability toggling respects dependencies', () {
    test('granting an edit right pulls in the matching view right', () {
      final next = toggleCapability(const [], 'students.edit');
      expect(next, containsAll(['students.edit', 'students.view']));
    });

    test('revoking a view right revokes everything built on it', () {
      final start = ['students.view', 'students.edit', 'students.delete'];
      final next = toggleCapability(start, 'students.view');
      expect(next, isNot(contains('students.view')));
      expect(next, isNot(contains('students.edit')));
      expect(next, isNot(contains('students.delete')));
    });

    test('finance rights all depend on finance.view', () {
      for (final cap in ['finance.collect', 'finance.cancel', 'finance.cashbox']) {
        expect(toggleCapability(const [], cap), contains('finance.view'), reason: cap);
      }
      final stripped = toggleCapability(
        ['finance.view', 'finance.collect', 'finance.cancel', 'finance.cashbox'],
        'finance.view',
      );
      expect(stripped, isEmpty);
    });

    test('a group can be granted and revoked at once', () {
      final caps = capabilityGroups.firstWhere((g) => g.label == 'الطلاب').items.map((i) => i.id).toList();
      final on = toggleCapabilityGroup(const [], caps, false);
      expect(on, containsAll(caps));
      final off = toggleCapabilityGroup(on, caps, true);
      expect(off, isEmpty);
    });

    test('toggling is idempotent in pairs', () {
      final once = toggleCapability(const [], 'attendance.edit');
      final twice = toggleCapability(once, 'attendance.edit');
      expect(twice, isNot(contains('attendance.edit')));
    });
  });

  group('effective capabilities', () {
    test('an account without an explicit list falls back to its role template', () {
      expect(effectiveCapabilities(const [], 'admin'), allCapabilities);
      expect(effectiveCapabilities(const [], 'receptionist'), receptionistCapabilities);
    });

    test('unknown capability strings are dropped', () {
      final caps = effectiveCapabilities(['students.view', 'not.a.real.capability'], 'admin');
      expect(caps, ['students.view']);
    });

    test('role names normalise', () {
      expect(normalizeRole('admin'), 'admin');
      expect(normalizeRole('مدير النظام'), 'admin');
      expect(normalizeRole(null), 'receptionist');
      expect(normalizeRole('anything-else'), 'receptionist');
      expect(roleLabel('admin'), 'مدير النظام');
    });
  });

  group('capabilities are enforced by the store', () {
    AppStore seeded() {
      final s = AppStore.forTesting();
      injectDemoData(s);
      return s;
    }

    test('a device with no identity behaves as a full admin', () {
      final s = seeded();
      expect(s.can('settings.users'), isTrue);
      expect(s.canOpenSection('finance'), isTrue);
    });

    test('a receptionist device loses admin-only sections', () async {
      final s = seeded();
      final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
      await s.setDeviceIdentity(clerk, '');
      expect(s.can('students.view'), isTrue);
      expect(s.can('finance.collect'), isTrue);
      expect(s.can('finance.cancel'), isFalse);
      expect(s.can('settings.users'), isFalse);
      expect(s.can('settings.backup'), isFalse);
      expect(s.can('reports.view'), isFalse);
    });

    test('a custom capability list overrides the role template', () async {
      final s = seeded();
      final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
      clerk.capabilities = ['students.view'];
      await s.setDeviceIdentity(clerk, '');
      expect(s.canOpenSection('students'), isTrue);
      expect(s.canOpenSection('finance'), isFalse);
      expect(s.canOpenSection('attendance'), isFalse);
      expect(s.canOpenSection('settings'), isFalse);
    });

    test('a suspended account can do nothing at all', () async {
      final s = seeded();
      final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
      clerk.isActive = false;
      await s.setDeviceIdentity(clerk, '');
      expect(s.myCapabilities, isEmpty);
      expect(s.can('students.view'), isFalse);
      expect(s.canOpenSection('students'), isFalse);
    });

    test('every section maps to a real capability', () {
      for (final entry in sectionCapability.entries) {
        expect(allCapabilities, contains(entry.value), reason: entry.key);
      }
    });
  });
}
