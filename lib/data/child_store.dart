import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_db.dart';
import 'portal.dart';

/// مخزن أسرار بتشفير النظام (Keystore على أندرويد، Keychain على iOS).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  // الافتراضي منذ الإصدار 10 مشفّر بمفتاح في Keystore
  static const _storage = FlutterSecureStorage();

  // تعطّل الـKeystore (بعد استعادة نسخة مثلاً) لا يُسقط البوابة: كأن لا حسابات محفوظة
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

/// أبناء وليّ الأمر على هذا الجهاز: حساب كل ابن وكلمة المرور في التخزين المشفّر،
/// ونسخة بياناته (حضور، درجات، رسوم) لفتحه بلا شبكة. «نسيان الجهاز» يمحو الاثنين.
class ChildStore {
  ChildStore({SecretStore secrets = const PlatformSecretStore(), required Persistence Function() db})
      : _secrets = secrets,
        _db = db;

  /// يُضبط عند الإقلاع؛ `null` (الاختبارات) = لا حفظ.
  static ChildStore? instance;

  final SecretStore _secrets;
  final Persistence Function() _db;

  static const _kAccounts = 'noon_child_accounts';
  static const _kDataPrefix = 'child_cache_';

  Future<Map<String, dynamic>> _readAccounts() async {
    final raw = await _secrets.read(_kAccounts);
    if (raw == null || raw.isEmpty) return {};
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  /// حفظ حساب ابن مع بيانات دخول وليّ أمره.
  Future<void> saveAccount(PortalUser child, {required String parentId, required String code}) async {
    if (child.id.isEmpty || parentId.isEmpty || code.isEmpty) return;
    final all = await _readAccounts();
    all[child.id] = {
      'parent_id': parentId,
      'code': code,
      'saved_at': DateTime.now().toIso8601String(),
      'user': child.toJson(),
    };
    await _secrets.write(_kAccounts, jsonEncode(all));
  }

  /// الحساب المحفوظ لابن، أو `null`. هوية وليّ الأمر وكلمته تُملآن إن غابتا من الحساب.
  Future<PortalUser?> account(String childId) async {
    final entry = (await _readAccounts())[childId];
    if (entry is! Map || entry['user'] is! Map) return null;
    final json = Map<String, dynamic>.from(entry['user'] as Map);
    if ('${json['portal_code'] ?? ''}'.isEmpty) json['portal_code'] = entry['code'];
    if ('${json['parent_national_id'] ?? ''}'.isEmpty) json['parent_national_id'] = entry['parent_id'];
    return PortalUser.fromJson(json);
  }

  Future<void> saveData(String childId, Map<String, dynamic> raw) => _db().setSetting(
        '$_kDataPrefix$childId',
        jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'raw': raw}),
      );

  ({Map<String, dynamic> raw, DateTime savedAt})? loadData(String childId) {
    final text = _db().settings['$_kDataPrefix$childId'];
    if (text == null || text.isEmpty) return null;
    try {
      final v = jsonDecode(text) as Map<String, dynamic>;
      final raw = v['raw'];
      if (raw is! Map) return null;
      return (
        raw: Map<String, dynamic>.from(raw),
        savedAt: DateTime.tryParse('${v['saved_at']}') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// نسيان الجهاز: كل الحسابات وكلمات المرور ونسخ البيانات.
  Future<void> forgetAll() async {
    await _secrets.delete(_kAccounts);
    final db = _db();
    for (final key in db.settings.keys.where((k) => k.startsWith(_kDataPrefix)).toList()) {
      await db.setSetting(key, null);
    }
  }
}
