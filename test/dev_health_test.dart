import 'package:center_mobile/data/dev_health.dart';
import 'package:flutter_test/flutter_test.dart';

SchoolHealth _s({required int total, required int d7, required int d30, DateTime? last}) => SchoolHealth(
      tenantId: 't',
      name: 'م',
      lastActivity: last,
      roles: {'student': RoleCount(total: total, d7: d7, d30: d30)},
    );

void main() {
  final now = DateTime.now();
  test('لا حسابات: بلا تنبيه', () {
    expect(SchoolHealth(tenantId: 't', name: 'م').alert(now), isNull);
  });
  test('لا نشاط منذ 7 أيام: متوقف', () {
    expect(_s(total: 10, d7: 0, d30: 4, last: now.subtract(const Duration(days: 9))).alert(now), HealthAlert.silent);
  });
  test('هبوط: نشطو 7 أيام أقل من 40% من 30 يوماً', () {
    expect(_s(total: 20, d7: 3, d30: 10, last: now).alert(now), HealthAlert.drop);
    expect(_s(total: 20, d7: 4, d30: 10, last: now).alert(now), isNull);
  });
  test('أقل من 5 نشطين لا يعدّ هبوطاً', () {
    expect(_s(total: 20, d7: 1, d30: 4, last: now).alert(now), isNull);
  });
  test('بناء الصفوف وترتيب المنبَّه أولاً', () {
    final rows = buildHealth(
      {'a': 'أ', 'b': 'ب'},
      [
        {'tenant_id': 'a', 'total_students': 50},
        {'tenant_id': 'b', 'total_students': 5, 'last_activity_at': '2020-01-01T00:00:00Z'},
      ],
      {
        'users': [
          {'tenant_id': 'a', 'role': 'student', 'total': 9, 'd7': 9, 'd30': 9},
          {'tenant_id': 'b', 'role': 'teacher', 'total': 2, 'd7': 0, 'd30': 0},
        ],
      },
    );
    expect(rows.first.tenantId, 'b');
    expect(rows.first.alert(DateTime.now()), HealthAlert.silent);
  });
}
