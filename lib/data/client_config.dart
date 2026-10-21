/// ما يرسله المطور من لوحته (`client_config` في السحابة): صيانة، إعلانات،
/// أقل رقم بناء مقبول، وتجميد التحديث لمدرسة.
///
/// طلب واحد صغير عند الإقلاع، وعند الدخول بحساب آخر، وعند العودة للتطبيق كل
/// 15 دقيقة على الأكثر. أي فشل بلا أثر: يبقى آخر ما عُرف، والتطبيق يعمل.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase.dart';

class Announcement {
  const Announcement({required this.id, required this.body, this.warn = false});

  final String id;
  final String body;

  /// مهم: لون التنبيه بدل اللون العادي.
  final bool warn;
}

class ClientConfig extends ChangeNotifier {
  ClientConfig._();
  static final instance = ClientConfig._();

  static const interval = Duration(minutes: 15);
  static const _dismissedKey = 'dismissed_announcements';

  bool maintenance = false;
  String message = '';

  /// أقل رقم بناء: الأقدم يُجبر على التحديث. 0 = بلا إجبار.
  int minBuild = 0;

  /// المطور جمّد التحديث لهذه المدرسة: لا يُعرض الاختياري.
  bool updateHold = false;

  List<Announcement> announcements = const [];

  Set<String>? _dismissed;
  DateTime? _fetchedAt;
  Future<void>? _fetching;

  List<Announcement> get visible => announcements.where((a) => !(_dismissed ?? const {}).contains(a.id)).toList();

  Future<void> refresh({bool force = false}) {
    final last = _fetchedAt;
    if (!force && last != null && DateTime.now().difference(last) < interval) return Future.value();
    return _fetching ??= _fetch().whenComplete(() => _fetching = null);
  }

  Future<void> _fetch() async {
    _fetchedAt = DateTime.now();
    if (_dismissed == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _dismissed = (prefs.getStringList(_dismissedKey) ?? const []).toSet();
      } catch (_) {
        _dismissed = {};
      }
    }
    final data = await supabaseRpc('client_config', const {});
    if (data is Map) apply(data);
  }

  /// يطبّق رد السحابة — منفصلٌ عن الشبكة ليُختبر وحده.
  @visibleForTesting
  void apply(Map<dynamic, dynamic> data) {
    maintenance = data['maintenance'] == true;
    message = '${data['maintenance_message'] ?? ''}'.trim();
    minBuild = (data['min_build'] as num?)?.toInt() ?? 0;
    updateHold = data['update_hold'] == true;
    final list = data['announcements'];
    announcements = [
      if (list is List)
        for (final a in list)
          if (a is Map && '${a['id'] ?? ''}'.isNotEmpty && '${a['body'] ?? ''}'.trim().isNotEmpty)
            Announcement(id: '${a['id']}', body: '${a['body']}'.trim(), warn: a['level'] == 'warn'),
    ];
    notifyListeners();
  }

  Future<void> dismiss(String id) async {
    final set = {...?_dismissed, id};
    _dismissed = set;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      // آخر 50 فقط: الإعلانات القديمة تنتهي من السحابة على أي حال
      final list = set.toList();
      await prefs.setStringList(_dismissedKey, list.length > 50 ? list.sublist(list.length - 50) : list);
    } catch (_) {}
  }
}
