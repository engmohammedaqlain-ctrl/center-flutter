/// تحديث التطبيق — يُوزَّع ملفَ APK لا عبر متجر.
///
/// الملفان معاً في إصدار واحد على الاستضافة: حزمة التثبيت، وملف وصف يقول ما
/// أحدث إصدار وأين يُنزَّل. التطبيق يقرأ الوصف ويقارنه بنفسه، فإن كان أحدث عرض
/// التحديث؛ ولا يفرضه إلا حين يصير القديم غير صالح للعمل مع السحابة.
///
/// وبجانبه التحديث الصامت (Shorebird): تصليحات كود Dart تُنزَّل في الخلفية
/// وتُطبَّق عند فتح التطبيق التالي، بلا تثبيت.
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
import 'package:shorebird_code_push/shorebird_code_push.dart' as shorebird;

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
  const UpdateException(this.message, {this.retryable = false});
  final String message;

  /// انقطاعٌ يُستكمل التنزيل بعده، لا خللٌ في الملف أو الاستضافة.
  final bool retryable;

  @override
  String toString() => message;
}

String _packagePath(Directory dir, AppRelease release) =>
    '${dir.path}${Platform.pathSeparator}center-${release.versionCode}.apk';

/// ما نزل من حزمة الإصدار قبل انقطاعٍ أو إغلاقٍ للتطبيق، أو 0.
Future<int> partialBytes(AppRelease release, Directory dir) async {
  final part = File('${_packagePath(dir, release)}.part');
  return await part.exists() ? await part.length() : 0;
}

/// تنزيل حزمة الإصدار إلى [dir] والتحقق منها قبل تسليمها.
///
/// يُكتب إلى ملف `.part` ولا يُسمّى باسمه النهائي إلا بعد مطابقة الحجم والبصمة،
/// فلا يُعرض على المثبِّت ملفٌ ناقص. وما نزل منه يبقى عند الانقطاع أو إغلاق
/// التطبيق، فيُطلب ما بعده وحده بدل ٢٥ م.ب من أولها على اتصالٍ متقطع.
/// [onVerifying] يُستدعى حين يكتمل التنزيل ويبدأ التحقق من البصمة.
Future<File> downloadRelease(
  AppRelease release,
  Directory dir, {
  http.Client? client,
  void Function(int received, int? total)? onProgress,
  void Function()? onVerifying,
}) async {
  final target = File(_packagePath(dir, release));
  if (await target.exists() && await _matches(target, release)) return target;

  final part = File('${target.path}.part');
  final c = client ?? _defaultClient();
  try {
    var offset = await part.exists() ? await part.length() : 0;
    if (release.sizeBytes > 0 && offset > release.sizeBytes) {
      await part.delete();
      offset = 0;
    }

    // نزل كاملاً في تشغيلٍ سابق وأُغلق التطبيق قبل التحقق: لا شبكة
    final complete = release.sizeBytes > 0 && offset == release.sizeBytes;
    if (!complete) {
      final request = http.Request('GET', Uri.parse(release.apkUrl));
      if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
      final res = await c.send(request);
      if (res.statusCode == 416) {
        // الجزء المحفوظ لا يقابل الملف على الاستضافة: يُعاد من أوله
        await part.delete();
        throw const UpdateException('يُعاد التنزيل من البداية', retryable: true);
      }
      if (res.statusCode >= 400) {
        throw UpdateException(
          'تعذّر تنزيل التحديث من الاستضافة (${res.statusCode})',
          retryable: res.statusCode >= 500,
        );
      }

      // خادمٌ تجاهل النطاق فأعاد الملف كاملاً: يُكتب من أوله لا فوق ما سبق
      final resumed = offset > 0 && res.statusCode == 206;
      if (!resumed) offset = 0;
      final length = res.contentLength;
      final total = release.sizeBytes > 0 ? release.sizeBytes : (length == null ? null : offset + length);

      final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var received = offset;
      onProgress?.call(received, total);
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
    }

    onVerifying?.call();
    if (!await _matches(part, release)) {
      await part.delete();
      throw const UpdateException('الملف المنزَّل لا يطابق الإصدار المنشور فلم يُثبَّت. أعد المحاولة');
    }
    if (await target.exists()) await target.delete();
    return await part.rename(target.path);
  } on UpdateException {
    rethrow;
  } catch (_) {
    // ما نزل يبقى في `.part`: المحاولة التالية تستكمل منه
    throw const UpdateException('انقطع الاتصال أثناء التنزيل', retryable: true);
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

/// مرحلة تحديث البناء (APK) الجارية.
enum UpdatePhase {
  idle,
  checking,
  downloading,

  /// انقطع الاتصال: محاولة جديدة بعد عدٍّ تنازلي.
  retrying,

  /// توقف التنزيل وما نزل محفوظ — يُستكمل من مكانه ولو أُغلق التطبيق.
  paused,

  /// اكتمل التنزيل ويُتحقق من بصمة الملف.
  verifying,
  ready,
  failed,
}

/// حالة التحديث الصامت (Shorebird).
enum PatchPhase {
  none,

  /// يُنزَّل في الخلفية والتطبيق يعمل.
  downloading,

  /// نزل، ويُطبَّق عند فتح التطبيق التالي.
  ready,
}

/// ما يقوله مصدر التحديثات الصامتة عن هذا الجهاز.
enum PatchStatus { upToDate, available, awaitingRestart }

/// ما يحتاجه التطبيق من Shorebird، مجرَّداً كي يُختبر بلا محرّكه.
abstract class PatchSource {
  /// نسخةٌ بُنيت بغير `shorebird release` لا تحمل محرّكه ولا تستقبل تحديثاً صامتاً.
  bool get isAvailable;
  Future<PatchStatus> status();
  Future<void> download();
}

class ShorebirdPatchSource implements PatchSource {
  ShorebirdPatchSource() : _updater = shorebird.ShorebirdUpdater();

  final shorebird.ShorebirdUpdater _updater;

  @override
  bool get isAvailable => _updater.isAvailable;

  @override
  Future<PatchStatus> status() async => switch (await _updater.checkForUpdate()) {
        shorebird.UpdateStatus.outdated => PatchStatus.available,
        shorebird.UpdateStatus.restartRequired => PatchStatus.awaitingRestart,
        _ => PatchStatus.upToDate,
      };

  @override
  Future<void> download() => _updater.update();
}

/// الإصدار المثبَّت على الجهاز.
typedef InstalledVersion = ({int code, String name});

/// حالة التحديث المشتركة بين الإقلاع والقائمة وورقة التحديث والشريط.
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
    PatchSource? patches,
    Future<void> Function(Duration delay)? wait,
  })  : _installedVersion = installedVersion ?? _packageVersion,
        _downloadDir = downloadDir ?? getTemporaryDirectory,
        _openInstaller = openInstaller ?? _systemInstaller,
        _client = client ?? _defaultClient,
        _clock = clock ?? DateTime.now,
        _patches = patches ?? (supported ? ShorebirdPatchSource() : null),
        _wait = wait ?? Future<void>.delayed;

  /// على أندرويد وحده: غيره لا يثبّت حزم APK.
  static final instance = AppUpdater(supported: !kIsWeb && Platform.isAndroid);

  /// لا يُعاد فحص الاستضافة تلقائياً قبل مرور هذه المدة.
  static const checkEvery = Duration(hours: 6);

  /// التحديث الصامت أخفّ: يُفحص عند العودة إلى التطبيق بعد هذه المدة.
  static const patchCheckEvery = Duration(minutes: 30);

  /// محاولات التنزيل عند انقطاع الاتصال قبل أن يتوقف بانتظار المستخدم.
  static const maxAttempts = 4;

  /// الانتظار قبل كل محاولة: يطول مع تكرار الانقطاع.
  static const retryDelays = [Duration(seconds: 3), Duration(seconds: 8), Duration(seconds: 15)];

  static const _kRelease = 'app_update_release';
  static const _kCheckedAt = 'app_update_checked_at';

  final bool supported;
  final String manifestUrl;
  final Future<InstalledVersion> Function() _installedVersion;
  final Future<Directory> Function() _downloadDir;
  final Future<String?> Function(String path) _openInstaller;
  final http.Client Function() _client;
  final DateTime Function() _clock;
  final PatchSource? _patches;
  final Future<void> Function(Duration delay) _wait;

  int installedCode = 0;
  String installedName = '';
  AppRelease? release;
  DateTime? lastChecked;
  UpdatePhase phase = UpdatePhase.idle;
  PatchPhase patchPhase = PatchPhase.none;

  /// نسبة التنزيل بين 0 و1، أو `null` إن لم يُعرف الحجم.
  double? progress;
  int received = 0;
  int? totalBytes;

  /// سرعة التنزيل بالبايت في الثانية — متوسط الثانية الأخيرة، أو 0 قبل أن تُعرف.
  double speed = 0;

  /// الثواني الباقية قبل المحاولة التالية بعد انقطاع.
  int retryIn = 0;

  /// رقم محاولة التنزيل الجارية.
  int attempt = 0;
  String? error;
  String? _readyPath;
  int _dismissed = 0;

  Future<void>? _starting;
  Future<void>? _loading;
  Future<UpdateAction>? _checking;
  Future<void>? _installing;
  Future<void>? _patching;
  DateTime? _patchCheckedAt;
  bool _retryNow = false;
  DateTime? _speedAt;
  int _speedBytes = 0;
  int _shownPercent = -1;

  UpdateAction get action {
    // إصدارٌ مثبَّت مجهول لا يُقارن: خيرٌ من إلزامٍ خاطئ يحجب التطبيق
    if (!supported || installedCode <= 0) return UpdateAction.none;
    return decideUpdate(installed: installedCode, release: release);
  }

  /// تحديثٌ اختياري لم يُعرض بعد في هذه الجلسة.
  bool get shouldPrompt => action == UpdateAction.optional && release!.versionCode != _dismissed;

  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.retrying ||
      phase == UpdatePhase.verifying;

  /// تنزيل البناء جارٍ أو متوقف في منتصفه — ما يستحق أن يُرى خارج الورقة.
  bool get transferring =>
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.retrying ||
      phase == UpdatePhase.verifying ||
      phase == UpdatePhase.paused;

  /// الوقت الباقي على اكتمال التنزيل بسرعته الحالية.
  Duration? get remaining {
    final total = totalBytes;
    if (total == null || speed <= 0 || phase != UpdatePhase.downloading) return null;
    return Duration(seconds: ((total - received) / speed).ceil());
  }

  /// يُستدعى مرة عند الإقلاع: يقرأ المحفوظ ثم يفحص إن حان الفحص.
  Future<void> start() => _starting ??= () async {
        if (!supported) return;
        await _load();
        unawaited(checkPatch());
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
    } catch (_) {
      // قراءة الحالة المحفوظة تعذّرت: يُكمل التطبيق، والفحص التالي يعيد بناءها
    }
    await _cleanOldPackages();
    await _restoreDownload();
    notifyListeners();
  }

  /// تنزيلٌ انقطع أو أُغلق التطبيق في منتصفه: يُعرض متوقفاً عند نسبته ليُستكمل،
  /// وحزمةٌ اكتمل تنزيلها وتحقّقها تُعرض جاهزة للتثبيت.
  Future<void> _restoreDownload() async {
    final target = release;
    if (target == null || action == UpdateAction.none) return;
    try {
      final dir = await _downloadDir();
      final ready = File(_packagePath(dir, target));
      if (await ready.exists()) {
        _readyPath = ready.path;
        phase = UpdatePhase.ready;
        return;
      }
      final got = await partialBytes(target, dir);
      if (got <= 0) return;
      received = got;
      totalBytes = target.sizeBytes > 0 ? target.sizeBytes : null;
      progress = totalBytes == null ? null : (got / totalBytes!).clamp(0.0, 1.0);
      phase = UpdatePhase.paused;
    } catch (_) {}
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

    // تنزيلٌ جارٍ أو متوقف أو حزمة جاهزة: الفحص لا يمسح حالتها من الشاشة
    final quiet = phase != UpdatePhase.idle && phase != UpdatePhase.failed;
    if (!quiet) {
      phase = UpdatePhase.checking;
      error = null;
      notifyListeners();
    }

    final fetched = await fetchLatestRelease(manifestUrl, client: _client());
    if (fetched != null) {
      // إصدار أحدث نُشر بعد تنزيلٍ سابق: الحزمة الجاهزة أو الناقصة لم تعد المطلوبة
      final replaced = release != null && release!.versionCode != fetched.versionCode;
      if (replaced && !busy) {
        _readyPath = null;
        received = 0;
        progress = null;
        totalBytes = null;
        phase = UpdatePhase.idle;
      }
      release = fetched;
      lastChecked = _clock();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kRelease, jsonEncode(fetched.toJson()));
        await prefs.setString(_kCheckedAt, lastChecked!.toIso8601String());
      } catch (_) {}
    }

    if (!quiet) {
      phase = _readyPath != null ? UpdatePhase.ready : UpdatePhase.idle;
      // الفحص اليدوي وحده يقول إن الاتصال تعذّر؛ التلقائي يصمت ويعيد لاحقاً
      if (fetched == null && force) {
        error = 'تعذّر الوصول إلى خادم التحديثات. تحقّق من الاتصال بالإنترنت';
      }
    }
    notifyListeners();
    return action;
  }

  /// تأجيل العرض التلقائي حتى فتح التطبيق التالي — لا يُحفظ على القرص.
  ///
  /// «لاحقاً» الدائمة كانت تُخفي التحديث إلى الأبد بنقرةٍ واحدة قد تكون سهواً،
  /// فيبقى الجهاز على نسخة قديمة بلا أن يُذكَّر. الآن تسكت هذه الجلسة وحدها،
  /// ويُعرَض عند الفتح التالي ما دام الإصدار متاحاً.
  Future<void> dismiss() async {
    final code = release?.versionCode ?? 0;
    if (code <= 0 || code == _dismissed) return;
    _dismissed = code;
    notifyListeners();
  }

  /// تنزيل الحزمة (أو استكمالها) إن لم تكن جاهزة، ثم فتح مثبِّت النظام.
  Future<void> install() => _installing ??= _install().whenComplete(() => _installing = null);

  /// «المحاولة الآن» أثناء العدّ التنازلي بعد انقطاع.
  void retryNow() => _retryNow = true;

  Future<void> _install() async {
    final target = release;
    if (target == null || action == UpdateAction.none) return;
    error = null;

    var path = _readyPath;
    if (path == null || !await File(path).exists()) {
      final file = await _downloadWithRetries(target);
      if (file == null) return;
      path = _readyPath = file.path;
    }

    phase = UpdatePhase.ready;
    notifyListeners();
    final failure = await _openInstaller(path);
    if (failure != null) {
      error = failure;
      notifyListeners();
    }
  }

  /// التنزيل بمحاولاتٍ متتالية عند الانقطاع، كلٌّ تستكمل مما نزل قبلها.
  ///
  /// بعد [maxAttempts] يتوقف بانتظار المستخدم بدل أن يستنزف البطارية في
  /// محاولاتٍ بلا اتصال، وما نزل يبقى محفوظاً.
  Future<File?> _downloadWithRetries(AppRelease target) async {
    final dir = await _downloadDir();
    for (attempt = 1;; attempt++) {
      phase = UpdatePhase.downloading;
      error = null;
      speed = 0;
      _speedAt = null;
      _shownPercent = -1;
      notifyListeners();
      try {
        return await downloadRelease(
          target,
          dir,
          client: _client(),
          onProgress: _onProgress,
          onVerifying: () {
            phase = UpdatePhase.verifying;
            speed = 0;
            notifyListeners();
          },
        );
      } on UpdateException catch (e) {
        speed = 0;
        if (!e.retryable) {
          phase = UpdatePhase.failed;
          error = e.message;
          notifyListeners();
          return null;
        }
        if (attempt >= maxAttempts) {
          phase = UpdatePhase.paused;
          error = 'انقطع الاتصال بالإنترنت فتوقف التنزيل';
          notifyListeners();
          return null;
        }
        await _countdown(retryDelays[(attempt - 1).clamp(0, retryDelays.length - 1)]);
      }
    }
  }

  Future<void> _countdown(Duration delay) async {
    phase = UpdatePhase.retrying;
    _retryNow = false;
    for (retryIn = delay.inSeconds; retryIn > 0 && !_retryNow; retryIn--) {
      notifyListeners();
      await _wait(const Duration(seconds: 1));
    }
    retryIn = 0;
  }

  void _onProgress(int got, int? total) {
    received = got;
    totalBytes = total;
    progress = total == null || total <= 0 ? null : (got / total).clamp(0.0, 1.0);

    final now = _clock();
    final at = _speedAt;
    var speedChanged = false;
    if (at == null) {
      _speedAt = now;
      _speedBytes = got;
    } else if (now.difference(at) >= const Duration(seconds: 1)) {
      // متوسط الثانية الأخيرة: سرعة كل جزء وحده تقفز بين الصفر وأضعاف الحقيقية
      speed = (got - _speedBytes) / (now.difference(at).inMilliseconds / 1000);
      _speedAt = now;
      _speedBytes = got;
      speedChanged = true;
    }

    // إخطارٌ مع كل جزء يعيد رسم الورقة مئات المرات؛ مرة لكل واحد بالمئة أو ثانية تكفي
    final percent = progress == null ? got ~/ (512 * 1024) : (progress! * 100).floor();
    if (percent != _shownPercent || speedChanged) {
      _shownPercent = percent;
      notifyListeners();
    }
  }

  /// التحديث الصامت: يُنزَّل في الخلفية ويُطبَّق عند فتح التطبيق التالي.
  Future<void> checkPatch({bool force = false}) {
    if (!supported) return Future.value();
    return _patching ??= _checkPatch(force).whenComplete(() => _patching = null);
  }

  Future<void> _checkPatch(bool force) async {
    final source = _patches;
    if (source == null || !source.isAvailable) return;
    // نزل وينتظر إعادة الفتح: لا جديد يُطلب قبل ذلك
    if (patchPhase == PatchPhase.ready) return;
    final last = _patchCheckedAt;
    if (!force && last != null && _clock().difference(last) < patchCheckEvery) return;

    try {
      final status = await source.status();
      _patchCheckedAt = _clock();
      if (status == PatchStatus.awaitingRestart) {
        patchPhase = PatchPhase.ready;
      } else if (status == PatchStatus.available) {
        patchPhase = PatchPhase.downloading;
        notifyListeners();
        await source.download();
        patchPhase = PatchPhase.ready;
      }
    } catch (_) {
      // انقطاعٌ أثناء التنزيل الصامت لا يُقلق المستخدم برسالة: يُعاد عند العودة
      // إلى التطبيق، وShorebird يستكمل ما نزل
      patchPhase = PatchPhase.none;
      _patchCheckedAt = null;
    }
    notifyListeners();
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
  // التحديث الصامت جزءٌ ثالث كما يُكتب عند النشر: 2.18.3. رقم البناء لا يتغيّر
  // به، فالمقارنة مع الإصدارات المنشورة تبقى على رقم البناء وحده
  final patch = await _currentPatchNumber();
  final name = displayVersion(info.version);
  return (code: int.tryParse(info.buildNumber) ?? 0, name: patch > 0 ? '$name.$patch' : name);
}

/// اسم الإصدار كما يُعرض: جزءان. pubspec وأندرويد يكتبانه بثلاثة والثالث صفر.
String displayVersion(String pubspecName) {
  final parts = pubspecName.split('.');
  if (parts.length == 3 && parts[2] == '0') return '${parts[0]}.${parts[1]}';
  return pubspecName;
}

/// رقم التحديث الصامت المثبَّت، أو 0: نسخة بُنيت بغير Shorebird لا تحمل محرّكه.
Future<int> _currentPatchNumber() async {
  try {
    final updater = shorebird.ShorebirdUpdater();
    if (!updater.isAvailable) return 0;
    return (await updater.readCurrentPatch())?.number ?? 0;
  } catch (_) {
    return 0;
  }
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
