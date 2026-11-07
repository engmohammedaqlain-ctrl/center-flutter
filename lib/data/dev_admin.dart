/// أدوات المطور على المنصة — المقابل لأجزاء `devService.ts`: إعدادات المنصة (الصيانة وأقل بناء)،
/// والإعلانات، وسعر اشتراك كل مدرسة ودفعاتها وملاحظاتها، والسجل، وأرقام النظرة العامة.
/// كلها للمطور وحده (سياسات `is_developer`)، وتحتاج اتصالاً.
library;

import 'supabase.dart';

class PlatformSettings {
  const PlatformSettings({required this.maintenance, required this.message, required this.minBuild});

  final bool maintenance;
  final String message;
  final int minBuild;
}

class PlatformAnnouncement {
  const PlatformAnnouncement({required this.id, this.tenantId, required this.body, required this.level, this.endsAt});

  factory PlatformAnnouncement.fromMap(Map<String, dynamic> m) => PlatformAnnouncement(
        id: '${m['id']}',
        tenantId: m['tenant_id']?.toString(),
        body: '${m['body'] ?? ''}',
        level: '${m['level'] ?? 'info'}',
        endsAt: DateTime.tryParse('${m['ends_at'] ?? ''}'),
      );

  final String id;
  final String? tenantId;
  final String body;
  final String level;
  final DateTime? endsAt;

  bool get active => endsAt == null || endsAt!.isAfter(DateTime.now());
}

class DevLogEntry {
  const DevLogEntry({required this.action, this.tenantName, this.detail, this.createdAt});

  factory DevLogEntry.fromMap(Map<String, dynamic> m) => DevLogEntry(
        action: '${m['action'] ?? ''}',
        tenantName: m['tenant_name']?.toString(),
        detail: m['detail']?.toString(),
        createdAt: DateTime.tryParse('${m['created_at'] ?? ''}')?.toLocal(),
      );

  final String action;
  final String? tenantName;
  final String? detail;
  final DateTime? createdAt;
}

class TenantPaymentRow {
  const TenantPaymentRow({required this.id, required this.amount, required this.paidOn, this.note});

  final String id;
  final double amount;
  final String paidOn;
  final String? note;
}

class TenantNoteRow {
  const TenantNoteRow({required this.id, required this.body, this.createdAt});

  final String id;
  final String body;
  final DateTime? createdAt;
}

/// أرقام النظرة العامة — `DevStats`.
class DevStats {
  const DevStats({required this.growth, required this.activity, required this.auth, required this.revenue});

  final List<({String month, int students, int schools})> growth;
  final Map<String, Map<String, dynamic>> activity;
  final ({int day, int week, int keysDay}) auth;
  final ({double thisMonth, double lastMonth, double monthly}) revenue;
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
int _i(Object? v) => _d(v).round();

class DevAdmin {
  DevAdmin._();

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// ما لا يلتقطه مُطلق السجل في السحابة (الدخول كمدير، الإعدادات). فشله لا يوقف شيئاً — `log`.
  static Future<void> log(String? tenantId, String? tenantName, String action, [String? detail]) async {
    try {
      await supabaseInsert('dev_log', [
        {'tenant_id': tenantId, 'tenant_name': tenantName, 'action': action, 'detail': detail},
      ]);
    } catch (_) {}
  }

  static Future<List<DevLogEntry>?> listLog({int limit = 200}) async {
    final rows = await supabaseSelect('dev_log', order: 'created_at.desc', limit: limit);
    return rows == null ? null : [for (final r in rows) DevLogEntry.fromMap(r)];
  }

  static Future<PlatformSettings?> getSettings() async {
    final rows = await supabaseSelect(
      'platform_settings',
      columns: 'maintenance,maintenance_message,min_build',
      filters: {'id': 'eq.true'},
      limit: 1,
    );
    if (rows == null || rows.isEmpty) return null;
    final m = rows.first;
    return PlatformSettings(maintenance: m['maintenance'] == true, message: '${m['maintenance_message'] ?? ''}', minBuild: _i(m['min_build']));
  }

  static Future<void> saveSettings(Map<String, dynamic> patch) async {
    await supabaseUpdate('platform_settings', {'id': 'eq.true'}, {...patch, 'updated_at': _now()});
    final action = patch.containsKey('maintenance') ? (patch['maintenance'] == true ? 'صيانة عامة' : 'إنهاء الصيانة العامة') : 'إعدادات';
    await log(null, null, action, patch.toString());
  }

  static Future<List<PlatformAnnouncement>> listAnnouncements() async {
    final rows = await supabaseSelect('announcements', order: 'created_at.desc', limit: 50);
    return [for (final r in rows ?? const <Map<String, dynamic>>[]) PlatformAnnouncement.fromMap(r)];
  }

  static Future<void> addAnnouncement({String? tenantId, required String body, required String level, DateTime? endsAt}) =>
      supabaseInsert('announcements', [
        {'tenant_id': tenantId, 'body': body, 'level': level, 'ends_at': endsAt?.toUtc().toIso8601String()},
      ]);

  static Future<void> endAnnouncement(String id) => supabaseUpdate('announcements', {'id': 'eq.$id'}, {'ends_at': _now()});

  static Future<void> deleteAnnouncement(String id) => supabaseDelete('announcements', {'id': 'eq.$id'});

  /// سعر الاشتراك الشهري لكل منشأة — `getPrices`.
  static Future<Map<String, double>> getPrices() async {
    final rows = await supabaseSelect('tenant_billing', columns: 'tenant_id,monthly_price');
    return {
      for (final r in rows ?? const <Map<String, dynamic>>[])
        if (r['monthly_price'] != null) '${r['tenant_id']}': _d(r['monthly_price']),
    };
  }

  static Future<void> setPrice(String tenantId, double? price) => supabaseUpsert('tenant_billing', [
        {'tenant_id': tenantId, 'monthly_price': price, 'updated_at': _now()},
      ], onConflict: 'tenant_id');

  static Future<List<TenantPaymentRow>?> listPayments(String tenantId) async {
    final rows = await supabaseSelect(
      'tenant_payments',
      columns: 'id,tenant_id,amount,paid_on,note',
      filters: {'tenant_id': 'eq.$tenantId'},
      order: 'paid_on.desc',
    );
    return rows == null
        ? null
        : [
            for (final r in rows)
              TenantPaymentRow(id: '${r['id']}', amount: _d(r['amount']), paidOn: '${r['paid_on'] ?? ''}', note: r['note']?.toString()),
          ];
  }

  static Future<void> addPayment({required String tenantId, required double amount, required String paidOn, String? note}) =>
      supabaseInsert('tenant_payments', [
        {'tenant_id': tenantId, 'amount': amount, 'paid_on': paidOn, 'note': note},
      ]);

  static Future<void> deletePayment(String id) => supabaseDelete('tenant_payments', {'id': 'eq.$id'});

  static Future<List<TenantNoteRow>?> listNotes(String tenantId) async {
    final rows = await supabaseSelect(
      'tenant_notes',
      columns: 'id,tenant_id,body,created_at',
      filters: {'tenant_id': 'eq.$tenantId'},
      order: 'created_at.desc',
    );
    return rows == null
        ? null
        : [
            for (final r in rows)
              TenantNoteRow(id: '${r['id']}', body: '${r['body'] ?? ''}', createdAt: DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal()),
          ];
  }

  static Future<void> addNote(String tenantId, String body) => supabaseInsert('tenant_notes', [
        {'tenant_id': tenantId, 'body': body},
      ]);

  static Future<void> deleteNote(String id) => supabaseDelete('tenant_notes', {'id': 'eq.$id'});

  /// صيانة المدرسة وتجميد تحديثها كما في السحابة.
  static Future<({bool maintenance, bool updateHold})?> tenantControls(String tenantId) async {
    final rows = await supabaseSelect('tenants', columns: 'maintenance,update_hold', filters: {'id': 'eq.$tenantId'}, limit: 1);
    if (rows == null || rows.isEmpty) return null;
    return (maintenance: rows.first['maintenance'] == true, updateHold: rows.first['update_hold'] == true);
  }

  static Future<DevStats?> getStats() async {
    try {
      final data = await supabaseRpcOrThrow('dev_stats', const {});
      if (data is! Map) return null;
      final auth = data['auth'] is Map ? data['auth'] as Map : const {};
      final revenue = data['revenue'] is Map ? data['revenue'] as Map : const {};
      return DevStats(
        growth: [
          for (final g in (data['growth'] is List ? data['growth'] as List : const []))
            if (g is Map) (month: '${g['month'] ?? ''}', students: _i(g['students']), schools: _i(g['schools'])),
        ],
        activity: {
          for (final a in (data['activity'] is List ? data['activity'] as List : const []))
            if (a is Map) '${a['tenant_id']}': Map<String, dynamic>.from(a),
        },
        auth: (day: _i(auth['day']), week: _i(auth['week']), keysDay: _i(auth['keys_day'])),
        revenue: (thisMonth: _d(revenue['this_month']), lastMonth: _d(revenue['last_month']), monthly: _d(revenue['monthly'])),
      );
    } catch (_) {
      return null;
    }
  }
}
