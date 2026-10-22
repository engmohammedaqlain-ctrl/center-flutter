import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'supabase.dart';

/// «آخر ظهور» لكل حساب عند المطور — `touch_activity()`
/// (`20261026_usage_tracking.sql` في مستودع الويب).
///
/// يُستدعى عند فتح التطبيق بجلسة وعند عودته للواجهة وبعد كل دخول، ومرة في
/// الساعة على الأكثر لكل حساب على هذا الجهاز. بلا انتظار ولا رسالة: فشله لا
/// يعني المستخدم في شيء.
abstract final class ActivityPing {
  static const _every = Duration(hours: 1);
  static const _roles = {'tenant_admin', 'staff', 'teacher', 'student', 'parent'};

  static bool _running = false;

  static Future<void> touch() async {
    if (_running) return;
    _running = true;
    try {
      if (!SupabaseAuth.signedIn || !_roles.contains(SupabaseAuth.role)) return;
      final uid = authUserId(SupabaseAuth.accessToken);
      if (uid == null) return;
      final key = 'activity_touch_$uid';
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(key) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _every.inMilliseconds) return;
      await supabaseRpcOrThrow('touch_activity', const {});
      await prefs.setInt(key, now);
    } catch (_) {
      // قاعدة لم تُرحَّل أو بلا اتصال: المحاولة التالية عند الفتح القادم
    } finally {
      _running = false;
    }
  }

  /// معرّف حساب Supabase (`sub`) من التوكن نفسه.
  static String? authUserId(String? token) {
    final parts = (token ?? '').split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final sub = payload is Map ? '${payload['sub'] ?? ''}' : '';
      return sub.isEmpty ? null : sub;
    } catch (_) {
      return null;
    }
  }
}
