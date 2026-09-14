import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/developer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Tenant _tenant() => Tenant(
      id: 't1',
      name: 'مدرسة الأمل',
      code: 'amal',
      username: 'amal',
      password: '',
      expiresAt: DateTime(2027, 9, 1),
    );

void main() {
  group('تأكيد حذف منشأة — كما في DeveloperDashboardPage', () {
    test('المعرّف أو كلمة «حذف» يؤكدان', () {
      expect(tenantDeleteConfirmed('amal', _tenant()), isTrue);
      expect(tenantDeleteConfirmed('  amal ', _tenant()), isTrue);
      expect(tenantDeleteConfirmed('حذف', _tenant()), isTrue);
    });

    test('غيرهما لا يؤكد، ومنه اسم المنشأة', () {
      expect(tenantDeleteConfirmed('', _tenant()), isFalse);
      expect(tenantDeleteConfirmed('مدرسة الأمل', _tenant()), isFalse);
      expect(tenantDeleteConfirmed('ama', _tenant()), isFalse);
    });

    test('منشأة بلا معرّف لا تُحذف بخانة فارغة', () {
      final t = _tenant()..code = '';
      expect(tenantDeleteConfirmed('', t), isFalse);
      expect(tenantDeleteConfirmed('حذف', t), isTrue);
    });
  });
}
