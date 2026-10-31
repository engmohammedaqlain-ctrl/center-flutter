import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ملفات المودل على الجهاز — مطابق لـ `reusableSignedUrl` في `moodle.service.ts`.
///
/// كل فتح كان يوقّع رابطاً جديداً فيُنزَّل الملف كاملاً من السحابة: فتح الطلاب للدروس
/// نفسها مرة بعد مرة كان ثلاثة أرباع نقل السحابة (~1 GB يومياً لمدرسة واحدة).
/// الملف لا يتغير في مساره (اسم فريد لكل رفع)، فيكفيه:
/// - رابط موقّع واحد يُعاد أسبوعاً، فيفتح المتصفح الداخلي (PDF وأوفيس) نسخته.
/// - والصورة تُحفظ في مجلد الجهاز بعد أول عرض، لأن عارض الصور لا يبقي شيئاً بعد إغلاقه.
class MaterialCache {
  MaterialCache._();

  static const signedUrlTtl = Duration(days: 7);

  /// لا يُعطى رابط بقي على انتهائه أقل من ساعة: قد ينتهي والملف مفتوح.
  static const minLeft = Duration(hours: 1);
  static const _key = 'material_signed_urls';
  static const _max = 300;

  /// قابل للاستبدال في الاختبارات.
  static Future<Directory> Function() cacheDir = getApplicationCacheDirectory;

  static Future<Map<String, dynamic>> _read(SharedPreferences prefs) async {
    try {
      final raw = jsonDecode(prefs.getString(_key) ?? '{}');
      return raw is Map<String, dynamic> ? raw : {};
    } catch (_) {
      return {};
    }
  }

  /// رابط موقّع سابق للملف ما زال صالحاً، أو `null`.
  static Future<String?> reusableUrl(String path, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hit = (await _read(prefs))[path];
      if (hit is! Map) return null;
      final exp = hit['exp'];
      final url = hit['url'];
      if (exp is! int || url is! String) return null;
      final left = exp - (now ?? DateTime.now()).millisecondsSinceEpoch;
      return left > minLeft.inMilliseconds ? url : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberUrl(String path, String url, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
      final kept = (await _read(prefs)).entries.where((e) {
        final exp = e.value is Map ? (e.value as Map)['exp'] : null;
        return e.key != path && exp is int && exp > at;
      }).toList()
        ..sort((a, b) => ((b.value as Map)['exp'] as int).compareTo((a.value as Map)['exp'] as int));
      final next = {for (final e in kept.take(_max - 1)) e.key: e.value};
      next[path] = {'url': url, 'exp': at + signedUrlTtl.inMilliseconds};
      await prefs.setString(_key, jsonEncode(next));
    } catch (_) {
      // بلا تخزين: يُوقَّع عند كل فتح كما كان
    }
  }

  static String fileName(String path) => path.replaceAll(RegExp(r'[^\w.\-]'), '_');

  /// بايتات الصورة: من الجهاز إن عُرضت قبل، وإلا تُنزَّل وتُحفظ.
  static Future<Uint8List?> imageBytes(String path, String url) async {
    File? file;
    try {
      file = File('${(await cacheDir()).path}/materials/${fileName(path)}');
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {
      file = null;
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode >= 400 || res.bodyBytes.isEmpty) return null;
    try {
      if (file != null) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(res.bodyBytes, flush: true);
      }
    } catch (_) {
      // امتلاء الجهاز أو مجلد غير متاح: تُعرض الصورة ولا تُحفظ
    }
    return res.bodyBytes;
  }
}
