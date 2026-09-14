/// تحديث التطبيق — يُوزَّع ملفَ APK لا عبر متجر.
///
/// الملفان معاً في إصدار واحد على الاستضافة: حزمة التثبيت، وملف وصف يقول ما
/// أحدث إصدار وأين يُنزَّل. التطبيق يقرأ الوصف ويقارنه بنفسه، فإن كان أحدث عرض
/// التحديث؛ ولا يفرضه إلا حين يصير القديم غير صالح للعمل مع السحابة.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ملف وصف أحدث إصدار — `latest` في GitHub يحيل دائماً إلى آخر إصدار منشور،
/// فالرابط ثابت لا يتغيّر مع كل تحديث.
const releaseManifestUrl =
    'https://github.com/engmohammedaqlain-ctrl/center-mobile-releases/releases/latest/download/mobile-latest.json';

/// حجم بالميجابايت للعرض.
String megabytes(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';

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
  String get sizeLabel => sizeBytes <= 0 ? '' : megabytes(sizeBytes);

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

  Map<String, dynamic> toJson() => {
        'version': versionName,
        'versionCode': versionCode,
        'minSupported': minSupported,
        'mandatory': mandatory,
        'apkUrl': apkUrl,
        'notes': notes,
        'sha256': sha256,
        'sizeBytes': sizeBytes,
      };
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

/// تعذّرٌ في التنزيل رسالته جاهزة للعرض.
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// تنزيل حزمة الإصدار إلى [dir] والتحقق منها قبل تسليمها.
///
/// يُكتب إلى ملف `.part` ولا يُسمّى باسمه النهائي إلا بعد مطابقة الحجم والبصمة:
/// تنزيلٌ انقطع في منتصفه لا يُترك ملفاً يبدو صالحاً فيُعرض على المثبِّت. وحزمةٌ
/// نُزّلت وتحقّقت سابقاً تُعاد كما هي بلا شبكة.
Future<File> downloadRelease(
  AppRelease release,
  Directory dir, {
  http.Client? client,
  void Function(int received, int? total)? onProgress,
}) async {
  final target = File('${dir.path}${Platform.pathSeparator}center-${release.versionCode}.apk');
  if (await target.exists() && await _matches(target, release)) return target;

  final part = File('${target.path}.part');
  final c = client ?? _defaultClient();
  try {
    final res = await c.send(http.Request('GET', Uri.parse(release.apkUrl)));
    if (res.statusCode >= 400) {
      throw UpdateException('تعذّر تنزيل التحديث من الاستضافة (${res.statusCode})');
    }
    final total = res.contentLength ?? (release.sizeBytes > 0 ? release.sizeBytes : null);
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (!await _matches(part, release)) {
      await part.delete();
      throw const UpdateException('الملف المنزَّل لا يطابق الإصدار المنشور فلم يُثبَّت. أعد المحاولة');
    }
    if (await target.exists()) await target.delete();
    return await part.rename(target.path);
  } on UpdateException {
    rethrow;
  } catch (_) {
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
    throw const UpdateException('انقطع التنزيل. تحقّق من الاتصال بالإنترنت وأعد المحاولة');
  } finally {
    if (client == null) c.close();
  }
}

/// الحجم أولاً لأنه مجاني، ثم البصمة. وصفٌ بلا بصمة يُكتفى فيه بالحجم: أندرويد
/// يرفض بنفسه حزمةً موقّعة بغير مفتاح التطبيق، فالبصمة هنا لسلامة الملف لا لهويته.
Future<bool> _matches(File file, AppRelease release) async {
  if (release.sizeBytes > 0 && await file.length() != release.sizeBytes) return false;
  if (release.sha256.isEmpty) return true;
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return digest.toString() == release.sha256;
}

/// مرحلة التحديث الجارية.
enum UpdatePhase { idle, checking, downloading, ready, failed }

/// الإصدار المثبَّت على الجهاز.
typedef InstalledVersion = ({int code, String name});

/// حالة التحديث المشتركة بين الإقلاع والقائمة وورقة التحديث.
///
/// آخر وصفٍ وصل يُحفظ على الجهاز، فيبقى القرار معروفاً بلا إنترنت: جهازٌ عُرف
/// أن إصداره لم يعد مقبولاً يُحجب من أول إطار في الإقلاع التالي، لا بعد أن
/// يرفع تعديلاته بصيغة لم تعد السحابة تفهمها.
class AppUpdater extends ChangeNotifier {
  AppUpdater({
    required this.supported,
    this.manifestUrl = releaseManifestUrl,
    Future<InstalledVersion> Function()? installedVersion,
    Future<Directory> Function()? downloadDir,
    Future<String?> Function(String path)? openInstaller,
    http.Client Function()? client,
    DateTime Function()? clock,
  })  : _installedVersion = installedVersion ?? _packageVersion,
        _downloadDir = downloadDir ?? getTemporaryDirectory,
        _openInstaller = openInstaller ?? _systemInstaller,
        _client = client ?? _defaultClient,
        _clock = clock ?? DateTime.now;

  /// على أندرويد وحده: غيره لا يثبّت حزم APK.
  static final instance = AppUpdater(supported: !kIsWeb && Platform.isAndroid);

  /// لا يُعاد فحص الاستضافة تلقائياً قبل مرور هذه المدة.
  static const checkEvery = Duration(hours: 6);

  static const _kRelease = 'app_update_release';
  static const _kCheckedAt = 'app_update_checked_at';
  static const _kDismissed = 'app_update_dismissed';

  final bool supported;
  final String manifestUrl;
  final Future<InstalledVersion> Function() _installedVersion;
  final Future<Directory> Function() _downloadDir;
  final Future<String?> Function(String path) _openInstaller;
  final http.Client Function() _client;
  final DateTime Function() _clock;

  int installedCode = 0;
  String installedName = '';
  AppRelease? release;
  DateTime? lastChecked;
  UpdatePhase phase = UpdatePhase.idle;

  /// نسبة التنزيل بين 0 و1، أو `null` إن لم يُعرف الحجم.
  double? progress;
  int received = 0;
  String? error;
  String? _readyPath;
  int _dismissed = 0;

  Future<void>? _starting;
  Future<void>? _loading;
  Future<UpdateAction>? _checking;
  Future<void>? _installing;

  UpdateAction get action {
    // إصدارٌ مثبَّت مجهول لا يُقارن: خيرٌ من إلزامٍ خاطئ يحجب التطبيق
    if (!supported || installedCode <= 0) return UpdateAction.none;
    return decideUpdate(installed: installedCode, release: release);
  }

  /// تحديثٌ اختياري لم يُعرض بعد على هذا الجهاز.
  bool get shouldPrompt => action == UpdateAction.optional && release!.versionCode != _dismissed;

  bool get busy => phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  /// يُستدعى مرة عند الإقلاع: يقرأ المحفوظ ثم يفحص إن حان الفحص.
  Future<void> start() => _starting ??= () async {
        if (!supported) return;
        await _load();
        await check();
      }();

  /// قراءة الحالة المحفوظة — مرة واحدة، ينتظرها الإقلاع والفحص كلاهما.
  Future<void> _load() => _loading ??= _readSaved();

  Future<void> _readSaved() async {
    try {
      final v = await _installedVersion();
      installedCode = v.code;
      installedName = v.name;
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kRelease);
      if (cached != null) release = AppRelease.fromJson(jsonDecode(cached));
      lastChecked = DateTime.tryParse(prefs.getString(_kCheckedAt) ?? '');
      _dismissed = prefs.getInt(_kDismissed) ?? 0;
    } catch (_) {
      // قراءة الحالة المحفوظة تعذّرت: يُكمل التطبيق، والفحص التالي يعيد بناءها
    }
    await _cleanOldPackages();
    notifyListeners();
  }

  /// فحص الاستضافة. بلا [force] لا يُعاد قبل [checkEvery] من آخر فحص ناجح.
  Future<UpdateAction> check({bool force = false}) {
    if (!supported) return Future.value(UpdateAction.none);
    return _checking ??= _check(force).whenComplete(() => _checking = null);
  }

  Future<UpdateAction> _check(bool force) async {
    await _load();
    final last = lastChecked;
    if (!force && last != null && _clock().difference(last) < checkEvery) return action;

    final wasDownloading = phase == UpdatePhase.downloading;
    if (!wasDownloading) {
      phase = UpdatePhase.checking;
      error = null;
      notifyListeners();
    }

    final fetched = await fetchLatestRelease(manifestUrl, client: _client());
    if (fetched != null) {
      // إصدار جديد نُشر بعد تنزيل سابق: الحزمة الجاهزة لم تعد هي المطلوبة
      if (release?.versionCode != fetched.versionCode) _readyPath = null;
      release = fetched;
      lastChecked = _clock();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kRelease, jsonEncode(fetched.toJson()));
        await prefs.setString(_kCheckedAt, lastChecked!.toIso8601String());
      } catch (_) {}
    }

    if (!wasDownloading) {
      phase = _readyPath != null ? UpdatePhase.ready : UpdatePhase.idle;
      // الفحص اليدوي وحده يقول إن الاتصال تعذّر؛ التلقائي يصمت ويعيد لاحقاً
      if (fetched == null && force) {
        error = 'تعذّر الوصول إلى خادم التحديثات. تحقّق من الاتصال بالإنترنت';
      }
    }
    notifyListeners();
    return action;
  }

  /// لا يُعرض هذا الإصدار تلقائياً مرة أخرى؛ يبقى متاحاً من القائمة.
  Future<void> dismiss() async {
    final code = release?.versionCode ?? 0;
    if (code <= 0 || code == _dismissed) return;
    _dismissed = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDismissed, code);
    } catch (_) {}
    notifyListeners();
  }

  /// تنزيل الحزمة إن لم تكن جاهزة، ثم فتح مثبِّت النظام.
  Future<void> install() => _installing ??= _install().whenComplete(() => _installing = null);

  Future<void> _install() async {
    final target = release;
    if (target == null || action == UpdateAction.none) return;
    error = null;

    var path = _readyPath;
    if (path == null || !await File(path).exists()) {
      phase = UpdatePhase.downloading;
      progress = 0;
      received = 0;
      notifyListeners();
      try {
        var shown = -1;
        final file = await downloadRelease(
          target,
          await _downloadDir(),
          client: _client(),
          onProgress: (got, total) {
            received = got;
            progress = total == null || total <= 0 ? null : (got / total).clamp(0.0, 1.0);
            // إخطارٌ مع كل جزء يعيد رسم الورقة مئات المرات؛ مرة لكل واحد بالمئة تكفي
            final percent = progress == null ? got ~/ (512 * 1024) : (progress! * 100).floor();
            if (percent != shown) {
              shown = percent;
              notifyListeners();
            }
          },
        );
        path = _readyPath = file.path;
      } on UpdateException catch (e) {
        phase = UpdatePhase.failed;
        error = e.message;
        notifyListeners();
        return;
      }
    }

    phase = UpdatePhase.ready;
    notifyListeners();
    final failure = await _openInstaller(path);
    if (failure != null) {
      error = failure;
      notifyListeners();
    }
  }

  /// حزمٌ نُزّلت لإصدارات صارت مثبّتة: ٢٥ م.ب لكلٍّ منها لا داعي لبقائها.
  Future<void> _cleanOldPackages() async {
    try {
      final dir = await _downloadDir();
      final pattern = RegExp(r'center-(\d+)\.apk(\.part)?$');
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final match = pattern.firstMatch(entity.path);
        if (match == null) continue;
        final code = int.parse(match.group(1)!);
        // المثبَّت وما قبله، وتنزيلٌ ناقص لإصدار لم يعد الأحدث
        if (code <= installedCode || (match.group(2) != null && code != release?.versionCode)) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}

Future<InstalledVersion> _packageVersion() async {
  final info = await PackageInfo.fromPlatform();
  return (code: int.tryParse(info.buildNumber) ?? 0, name: info.version);
}

/// يعيد رسالة للعرض إن تعذّر فتح المثبِّت، أو `null`.
Future<String?> _systemInstaller(String path) async {
  final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  return switch (result.type) {
    ResultType.done => null,
    ResultType.fileNotFound => 'الحزمة المنزَّلة لم تعد موجودة. أعد التنزيل',
    ResultType.permissionDenied => 'اسمح للتطبيق بتثبيت التطبيقات من الإعدادات ثم أعد المحاولة',
    _ => 'تعذّر فتح مثبِّت النظام: ${result.message}',
  };
}
