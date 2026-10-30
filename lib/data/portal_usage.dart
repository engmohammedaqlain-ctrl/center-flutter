/// متابعة الأهل والطلاب والمعلمين للنظام (20261112_portal_usage.sql) — `portalUsage.service.ts`.
///
/// سحابي وحده؛ بلا اتصال أو قبل المهاجرة يعيد null فلا يظهر شيء. كل طلب يُحفظ دقيقتين
/// ويشترك الطالبون المتزامنون فيه: الشاشات تتحدث مع كل مزامنة ولا تعيد الطلب.
library;

import 'supabase.dart';

class UsageSummary {
  const UsageSummary({required this.accounts, required this.ever, required this.today, required this.yesterday, required this.week});

  final int accounts;
  final int ever;
  final int today;
  final int yesterday;
  final int week;
}

class AccountUsage {
  const AccountUsage({required this.role, required this.portalId, this.lastSeen, required this.today, required this.yesterday, required this.days7});

  /// `student` أو `parent` أو `teacher`
  final String role;
  final String portalId;
  final String? lastSeen;
  final bool today;
  final bool yesterday;
  final int days7;
}

const _cacheFor = Duration(minutes: 2);
final _cache = <String, ({DateTime at, Future<Object?> value})>{};

Future<T?> _cached<T>(String key, Future<T?> Function() load) {
  final hit = _cache[key];
  if (hit != null && DateTime.now().difference(hit.at) < _cacheFor) return hit.value.then((v) => v as T?);
  final value = load().then((v) {
    if (v == null) _cache.remove(key); // الفشل لا يُحفظ
    return v;
  });
  _cache[key] = (at: DateTime.now(), value: value);
  return value;
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

Future<Map<String, UsageSummary>?> usageSummary() => _cached('summary', () async {
      final data = await supabaseRpc('portal_usage_summary', const {});
      if (data is! List) return null;
      return {
        for (final r in data.whereType<Map>())
          '${r['role']}': UsageSummary(
            accounts: _int(r['accounts']),
            ever: _int(r['ever']),
            today: _int(r['today']),
            yesterday: _int(r['yesterday']),
            week: _int(r['week']),
          ),
      };
    });

/// سطر لكل حساب؛ المفتاح «الدور:المعرّف» (ولي الأمر بمعرّف ابنه).
Future<Map<String, AccountUsage>?> accountUsage() => _cached('accounts', () async {
      final data = await supabaseRpc('portal_usage', const {});
      if (data is! List) return null;
      final map = <String, AccountUsage>{};
      for (final r in data.whereType<Map>()) {
        final key = '${r['role']}:${r['portal_id']}';
        final last = r['last_seen']?.toString();
        final prev = map[key];
        // أكثر من حساب للمعرّف نفسه: الأحدث يغلب
        if (prev == null || (last ?? '').compareTo(prev.lastSeen ?? '') > 0) {
          map[key] = AccountUsage(
            role: '${r['role']}',
            portalId: '${r['portal_id']}',
            lastSeen: last,
            today: r['today'] == true,
            yesterday: r['yesterday'] == true,
            days7: _int(r['days_7']),
          );
        }
      }
      return map;
    });

/// «اليوم» أو «أمس» أو «منذ 5 أيام» أو «لم يدخل».
String lastSeenLabel(AccountUsage? u, [DateTime? now]) {
  if (u?.lastSeen == null) return 'لم يدخل';
  if (u!.today) return 'اليوم';
  if (u.yesterday) return 'أمس';
  final seen = DateTime.tryParse(u.lastSeen!);
  final days = seen == null ? 1 : ((now ?? DateTime.now()).difference(seen).inHours / 24).round().clamp(1, 100000);
  return 'منذ $days يوم';
}

/// كم حساباً فتح النظام في كل يوم لكل دور (20261114_portal_usage_daily.sql).
Future<List<({String day, String role, int users})>?> usageDaily([int days = 30]) => _cached('daily:$days', () async {
      final data = await supabaseRpc('portal_usage_daily', {'p_days': days});
      if (data is! List) return null;
      return [for (final r in data.whereType<Map>()) (day: '${r['day']}'.substring(0, 10), role: '${r['role']}', users: _int(r['users']))];
    });
