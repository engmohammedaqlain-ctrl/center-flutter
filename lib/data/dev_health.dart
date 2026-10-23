/// متابعة المدارس للمطور: الاستخدام آخر 30 يوماً وتنبيه الهبوط وأخطاء 7 أيام.
/// نفس قاعدة وأعمدة لوحة الويب (`DevHealth.tsx`).
library;

import 'supabase.dart';

/// قاعدة التنبيه الأحمر (للتلميح).
const healthRule =
    'أحمر: لا نشاط منذ 7 أيام، أو نشطو آخر 7 أيام أقل من 40% من نشطي آخر 30 يوماً (إن كانوا 5 فأكثر)';

enum HealthAlert { silent, drop }

class RoleCount {
  const RoleCount({this.total = 0, this.d7 = 0, this.d30 = 0});
  final int total, d7, d30;
}

/// فئات الجدول: طلاب، أهالي، معلمون، إدارة (حساب المدرسة والموظفون).
const healthGroups = <(String, List<String>)>[
  ('طلاب', ['student']),
  ('أهالي', ['parent']),
  ('معلمون', ['teacher']),
  ('إدارة', ['tenant_admin', 'staff']),
];

class SchoolHealth {
  SchoolHealth({
    required this.tenantId,
    required this.name,
    this.totalStudents = 0,
    this.lastActivity,
    this.roles = const {},
  });

  final String tenantId, name;
  final int totalStudents;
  final DateTime? lastActivity;
  final Map<String, RoleCount> roles;

  int _sum(Iterable<String> keys, int Function(RoleCount) f) =>
      keys.fold(0, (n, k) => n + (roles[k] == null ? 0 : f(roles[k]!)));

  int total(List<String> keys) => _sum(keys, (r) => r.total);
  int d7(List<String> keys) => _sum(keys, (r) => r.d7);
  int d30(List<String> keys) => _sum(keys, (r) => r.d30);

  HealthAlert? alert(DateTime now) {
    final all = roles.keys.toList();
    if (total(all) == 0) return null;
    final a7 = d7(all), a30 = d30(all);
    final quiet = lastActivity == null || now.difference(lastActivity!) > const Duration(days: 7);
    if (a7 == 0 && quiet) return HealthAlert.silent;
    if (a30 >= 5 && a7 < a30 * 0.4) return HealthAlert.drop;
    return null;
  }
}

class ErrorRow {
  const ErrorRow({
    required this.tenantId,
    required this.tenantName,
    required this.role,
    required this.platform,
    required this.version,
    required this.route,
    required this.message,
    required this.count,
    required this.lastAt,
  });

  factory ErrorRow.fromMap(Map<String, dynamic> m) => ErrorRow(
        tenantId: m['tenant_id'] as String?,
        tenantName: (m['tenant_name'] as String?) ?? '',
        role: (m['role'] as String?) ?? '',
        platform: (m['platform'] as String?) ?? '',
        version: (m['app_version'] as String?) ?? '',
        route: (m['route'] as String?) ?? '',
        message: (m['message'] as String?) ?? '',
        count: (m['count'] as num?)?.toInt() ?? 0,
        lastAt: DateTime.tryParse('${m['last_at']}'),
      );

  final String? tenantId;
  final String tenantName, role, platform, version, route, message;
  final int count;
  final DateTime? lastAt;
}

/// صفوف المدارس من `tenant_usage` و`tenant_activity`. [names] اسم كل مدرسة نشطة حسب المعرّف.
List<SchoolHealth> buildHealth(Map<String, String> names, List usage, dynamic activity) {
  final roles = <String, Map<String, RoleCount>>{};
  if (activity is Map) {
    for (final m in (activity['users'] as List? ?? const [])) {
      if (m is! Map) continue;
      (roles[m['tenant_id'] as String] ??= {})['${m['role']}'] = RoleCount(
        total: (m['total'] as num?)?.toInt() ?? 0,
        d7: (m['d7'] as num?)?.toInt() ?? 0,
        d30: (m['d30'] as num?)?.toInt() ?? 0,
      );
    }
  }
  final byId = <String, Map>{
    for (final m in usage)
      if (m is Map) m['tenant_id'] as String: m,
  };
  final rows = [
    for (final e in names.entries)
      SchoolHealth(
        tenantId: e.key,
        name: e.value,
        totalStudents: (byId[e.key]?['total_students'] as num?)?.toInt() ?? 0,
        lastActivity: DateTime.tryParse('${byId[e.key]?['last_activity_at']}'),
        roles: roles[e.key] ?? const {},
      ),
  ];
  final now = DateTime.now();
  rows.sort((a, b) {
    final x = (b.alert(now) != null ? 1 : 0) - (a.alert(now) != null ? 1 : 0);
    return x != 0 ? x : b.totalStudents.compareTo(a.totalStudents);
  });
  return rows;
}

/// `null` إن غابت الدالة: يُخفى القسم.
Future<List<ErrorRow>?> loadErrorReports(String token, {int days = 7}) async {
  try {
    // صف لكل بصمة خطأ (20261103_client_errors.sql)؛ يُفرد لكل مدرسة ظهر فيها، فالمفتاح اسمها
    final res = await supabaseRpcAs('dev_client_errors', {'p_days': days}, token: token);
    if (res is! List) return null;
    String join(dynamic v) => v is List ? v.join('، ') : '';
    return [
      for (final m in res)
        if (m is Map)
          for (final String? name in (m['school_names'] is List && (m['school_names'] as List).isNotEmpty
              ? <String?>[for (final e in m['school_names'] as List) '$e']
              : const <String?>[null]))
            ErrorRow(
              tenantId: name,
              tenantName: name ?? '',
              role: join(m['roles']),
              platform: join(m['platforms']),
              version: join(m['versions']),
              route: (m['route'] as String?) ?? '',
              message: (m['message'] as String?) ?? (m['kind'] as String?) ?? '',
              count: (m['occurrences'] as num?)?.toInt() ?? 0,
              lastAt: DateTime.tryParse('${m['last_seen']}'),
            ),
    ];
  } catch (_) {
    return null;
  }
}
