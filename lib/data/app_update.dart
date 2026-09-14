/// تحديث التطبيق — يُوزَّع ملفَ APK لا عبر متجر.
///
/// الملفان معاً في إصدار واحد على الاستضافة: حزمة التثبيت، وملف وصف يقول ما
/// أحدث إصدار وأين يُنزَّل. التطبيق يقرأ الوصف ويقارنه بنفسه، فإن كان أحدث عرض
/// التحديث؛ ولا يفرضه إلا حين يصير القديم غير صالح للعمل مع السحابة.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// وصف أحدث إصدار كما يُنشر بجانب الحزمة.
///
/// `versionCode` هو الفيصل لا الاسم: أندرويد يقارن به، وهو رقم يزيد أبداً،
/// بينما اسم الإصدار نصٌّ للعرض قد يُكتب بأي صيغة.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    this.minSupported = 0,
    this.notes = '',
    this.sha256 = '',
    this.sizeBytes = 0,
    this.mandatory = false,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;

  /// أقدم إصدار ما زال يعمل مع السحابة؛ ما دونه يُلزَم بالتحديث.
  final int minSupported;
  final String notes;

  /// بصمة الحزمة للتحقق منها بعد التنزيل.
  final String sha256;
  final int sizeBytes;

  /// إلزامٌ صريح من الناشر، بصرف النظر عن [minSupported].
  final bool mandatory;

  /// حجم الحزمة بالميجابايت لعرضه، أو فارغ إن لم يُنشر.
  String get sizeLabel => sizeBytes <= 0 ? '' : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';

  static AppRelease? fromJson(Object? data) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    final url = '${map['apkUrl'] ?? ''}'.trim();
    final code = (map['versionCode'] as num?)?.toInt() ?? 0;
    // وصفٌ بلا رابط أو بلا رقم لا يصلح لقرار: يُتجاهل بدل أن يُعرض تحديثٌ معطوب
    if (url.isEmpty || code <= 0) return null;
    return AppRelease(
      versionName: '${map['version'] ?? ''}'.trim(),
      versionCode: code,
      apkUrl: url,
      minSupported: (map['minSupported'] as num?)?.toInt() ?? 0,
      notes: '${map['notes'] ?? ''}'.trim(),
      sha256: '${map['sha256'] ?? ''}'.trim().toLowerCase(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      mandatory: map['mandatory'] == true,
    );
  }
}

/// ما ينبغي فعله بالإصدار المنشور مقابل المثبَّت.
enum UpdateAction {
  /// المثبَّت هو الأحدث أو أحدث — لا شيء.
  none,

  /// أحدث منه ويستحق العرض، والعمل يستمر بلا تحديث.
  optional,

  /// المثبَّت لم يعد صالحاً للعمل: يُحجب حتى يُحدَّث.
  mandatory,
}

/// قرار التحديث — يُحسب بلا شبكة ولا واجهة، فيُختبر وحده.
UpdateAction decideUpdate({required int installed, required AppRelease? release}) {
  if (release == null) return UpdateAction.none;
  // القديم الذي لم تعد السحابة تقبله: يُلزَم ولو لم يُعلن الناشر الإلزام
  if (installed < release.minSupported) return UpdateAction.mandatory;
  if (installed >= release.versionCode) return UpdateAction.none;
  return release.mandatory ? UpdateAction.mandatory : UpdateAction.optional;
}

/// جلب وصف أحدث إصدار من الاستضافة.
///
/// يعيد `null` عند أي تعذّر — انقطاع أو ملف تالف: التحديث ميزةٌ إضافية لا
/// تُعطّل تطبيقاً يعمل بلا إنترنت أصلاً.
Future<AppRelease?> fetchLatestRelease(String manifestUrl, {http.Client? client}) async {
  final url = manifestUrl.trim();
  if (url.isEmpty) return null;
  final http = client ?? _defaultClient();
  try {
    final res = await http.get(Uri.parse(url), headers: {'Cache-Control': 'no-cache'});
    if (res.statusCode >= 400) return null;
    return AppRelease.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  } catch (_) {
    return null;
  } finally {
    if (client == null) http.close();
  }
}

http.Client _defaultClient() => http.Client();
