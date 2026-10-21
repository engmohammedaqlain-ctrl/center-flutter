/// أجهزة التطبيق وإصداراتها لكل مدرسة.
///
/// كل جهاز يبلّغ السحابة عند الفتح وبعد كل دخول (`report_app_install`): معرّف
/// عشوائي ثابت يُنشأ مرة، والإصدار ورقم التحديث الصامت، ونوع النسخة، والمنصة.
/// المنشأة والدور يأخذهما الخادم من الجلسة لا من الجهاز. بلا اسم ولا رقم.
///
/// لوحة المطور تقرأ المجاميع (`app_installs_overview`) وعدّاد صفحة التحميل
/// (`tenant_downloads`) وتنزيلات ملفات GitHub لكل مدرسة. الهجرة:
/// `supabase/migrations/20261022_app_installs.sql`.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_update.dart';
import 'play_store.dart';
import 'school_brand.dart';
import 'supabase.dart';

/// school: نسخة مدرسة من GitHub، general: النسخة العامة، play: Google Play.
String installChannel({required bool play, required bool schoolBuild}) =>
    play ? 'play' : (schoolBuild ? 'school' : 'general');

class AppInstalls {
  AppInstalls._();

  static final instance = AppInstalls._();

  /// في التفضيلات لا في قاعدة الجهاز: تحديث البناء يمسح القاعدة، والجهاز يبقى هو.
  static const _kDevice = 'app_install_device_id';

  /// نفس الحال (الدور والمنشأة والإصدار) لا يُعاد قبلها: تجديد التوكن كل ساعة لا يبلّغ.
  static const _repeatAfter = Duration(hours: 6);

  String? _lastKey;
  DateTime? _lastAt;
  Future<void> _chain = Future.value();

  /// بلا أي أثر عند الفشل: بلا شبكة أو قبل تنفيذ الهجرة يعمل التطبيق كما كان.
  Future<void> report() => _chain = _chain.then((_) => _report()).catchError((Object e) {
        debugPrint('app installs: $e');
      });

  Future<void> _report() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    var device = prefs.getString(_kDevice) ?? '';
    if (device.isEmpty) {
      device = const Uuid().v4();
      await prefs.setString(_kDevice, device);
    }
    final info = await PackageInfo.fromPlatform();
    final patch = await currentPatchNumber();
    await SchoolBrand.instance.readBundled();
    final brand = SchoolBrand.instance;

    final key = [SupabaseAuth.role, SupabaseAuth.tenantId, info.version, info.buildNumber, patch].join('|');
    final last = _lastAt;
    if (key == _lastKey && last != null && DateTime.now().difference(last) < _repeatAfter) return;

    final res = await supabaseRpcError('report_app_install', {
      'p_device_id': device,
      'p_channel': installChannel(play: playStore, schoolBuild: brand.bundled),
      'p_school_code': brand.code,
      'p_platform': defaultTargetPlatform.name,
      'p_version': info.version,
      'p_build': int.tryParse(info.buildNumber) ?? 0,
      'p_patch': patch,
    });
    if (res != null) return;
    _lastKey = key;
    _lastAt = DateTime.now();
  }
}

// ── لوحة المطور ─────────────────────────────────────────────────────────

/// صف من `app_installs_overview`: أجهزة مدرسة على نسخة ومنصة وإصدار واحد.
/// مدرسة بلا أجهزة تأتي بصف واحد [devices] فيه صفر.
class InstallRow {
  const InstallRow({
    required this.tenantId,
    required this.code,
    required this.name,
    required this.channel,
    required this.platform,
    required this.version,
    required this.patch,
    required this.devices,
    required this.recent,
    required this.lastSeen,
  });

  final String? tenantId;
  final String code;
  final String name;
  final String channel;
  final String platform;
  final String version;
  final int patch;
  final int devices;

  /// ظهرت خلال آخر 30 يوماً.
  final int recent;
  final DateTime? lastSeen;

  factory InstallRow.fromMap(Map<String, dynamic> m) => InstallRow(
        tenantId: m['tenant_id'] as String?,
        code: '${m['tenant_code'] ?? ''}'.trim().toUpperCase(),
        name: '${m['tenant_name'] ?? ''}'.trim(),
        channel: '${m['channel'] ?? ''}',
        platform: '${m['platform'] ?? ''}',
        version: '${m['version'] ?? ''}',
        patch: (m['patch'] as num?)?.toInt() ?? 0,
        devices: (m['devices'] as num?)?.toInt() ?? 0,
        recent: (m['recent'] as num?)?.toInt() ?? 0,
        lastSeen: DateTime.tryParse('${m['last_seen'] ?? ''}')?.toLocal(),
      );
}

/// أجزاء الإصدار أرقاماً: `2.9.0` ← [2, 9, 0].
List<int> versionParts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];

/// مقارنة إصدارين بالأجزاء: `2.10` أحدث من `2.9`.
int compareVersions(String a, String b) {
  final x = versionParts(a), y = versionParts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// الإصدار كما يُعرض في التطبيق: `2.9`، ومع التحديث الصامت `2.9.3`.
String installLabel(String version, int patch) {
  final name = displayVersion(version);
  return patch > 0 ? '$name.$patch' : name;
}

/// مدرسة في اللوحة.
class SchoolInstalls {
  SchoolInstalls({required this.key, required this.code, required this.name, this.tenantId});

  final String key;
  final String? tenantId;
  final String code;
  final String name;
  int devices = 0;
  int recent = 0;

  /// على إصدار أقدم من الأحدث.
  int outdated = 0;
  DateTime? lastSeen;

  /// الإصدار المعروض ← عدد الأجهزة، والأحدث أولاً.
  final versions = <String, int>{};

  /// الإصدارات المعروضة القديمة.
  final oldVersions = <String>{};

  /// school / general / play ← عدد الأجهزة.
  final channels = <String, int>{};

  /// صفحة التحميل `/d/<الكود>`: ويندوز وأندرويد.
  int pageDownloads = 0;

  /// ملفات نسخة المدرسة على GitHub (`center-2.9-CODE.apk`)، أو `null` إن تعذّر.
  int? githubDownloads;
}

/// يجمّع الصفوف لكل مدرسة. [latest] أحدث إصدار منشور (`2.9`)؛ إن غاب فأحدث ما بلّغ عنه جهاز.
/// المدارس بلا أجهزة ولا تنزيلات لا تظهر، والترتيب بعدد الأجهزة ثم التنزيلات.
({List<SchoolInstalls> schools, String latest}) groupInstalls(
  List<InstallRow> rows, {
  Map<String, int> pageDownloads = const {},
  Map<String, int>? githubDownloads,
  String? latest,
}) {
  var top = latest ?? '';
  for (final r in rows) {
    if (r.devices > 0 && r.version.isNotEmpty && compareVersions(r.version, top) > 0) top = r.version;
  }

  final byKey = <String, SchoolInstalls>{};
  for (final r in rows) {
    final key = r.tenantId ?? 'code:${r.code}';
    final s = byKey.putIfAbsent(
      key,
      () => SchoolInstalls(
        key: key,
        tenantId: r.tenantId,
        code: r.code,
        name: r.name.isNotEmpty ? r.name : (r.code.isNotEmpty ? r.code : 'بلا مدرسة'),
      ),
    );
    if (r.devices <= 0) continue;
    s.devices += r.devices;
    s.recent += r.recent;
    final seen = r.lastSeen;
    if (seen != null && (s.lastSeen == null || seen.isAfter(s.lastSeen!))) s.lastSeen = seen;
    final label = installLabel(r.version, r.patch);
    s.versions[label] = (s.versions[label] ?? 0) + r.devices;
    if (top.isNotEmpty && compareVersions(r.version, top) < 0) {
      s.outdated += r.devices;
      s.oldVersions.add(label);
    }
    s.channels[r.channel] = (s.channels[r.channel] ?? 0) + r.devices;
  }

  for (final s in byKey.values) {
    final id = s.tenantId;
    if (id != null) s.pageDownloads = pageDownloads[id] ?? 0;
    if (githubDownloads != null && s.code.isNotEmpty) s.githubDownloads = githubDownloads[s.code] ?? 0;
    final sorted = s.versions.entries.toList()..sort((a, b) => compareVersions(b.key, a.key));
    s.versions
      ..clear()
      ..addEntries(sorted);
  }

  int downloads(SchoolInstalls s) => s.pageDownloads + (s.githubDownloads ?? 0);
  final schools = byKey.values.where((s) => s.devices > 0 || downloads(s) > 0).toList()
    ..sort((a, b) {
      final d = b.devices - a.devices;
      return d != 0 ? d : downloads(b) - downloads(a);
    });
  return (schools: schools, latest: top);
}

/// تنزيلات ملفات GitHub من قائمة الإصدارات: كود المدرسة ← المجموع، و`''` للنسخة العامة.
/// والأحدث: وسم آخر إصدار فيه حزمة (`v2.9` ← `2.9`)، لا وسم تحديث صامت.
({Map<String, int> downloads, String? latest}) parseGithubReleases(List<dynamic> releases) {
  final pattern = RegExp(r'^center-\d+(?:\.\d+)*(?:-([A-Za-z0-9_-]+))?\.apk$');
  final downloads = <String, int>{};
  String? latest;
  for (final r in releases) {
    if (r is! Map) continue;
    var hasApk = false;
    for (final a in (r['assets'] as List?) ?? const []) {
      if (a is! Map) continue;
      final m = pattern.firstMatch('${a['name'] ?? ''}');
      if (m == null) continue;
      hasApk = true;
      final code = (m.group(1) ?? '').toUpperCase();
      downloads[code] = (downloads[code] ?? 0) + ((a['download_count'] as num?)?.toInt() ?? 0);
    }
    final tag = '${r['tag_name'] ?? ''}'.replaceFirst(RegExp('^v'), '');
    if (hasApk && RegExp(r'^\d+(\.\d+)*$').hasMatch(tag) && (latest == null || compareVersions(tag, latest) > 0)) {
      latest = tag;
    }
  }
  return (downloads: downloads, latest: latest);
}

const _releasesApi = 'https://api.github.com/repos/engmohammedaqlain-ctrl/center-mobile-releases/releases?per_page=100';

/// كل ما تعرضه اللوحة. [token] جلسة المطور. ما تعذّر من GitHub يبقى فارغاً ولا يوقفها.
Future<({List<SchoolInstalls> schools, String latest})> loadInstallsOverview(String token) async {
  final results = await Future.wait<dynamic>([
    supabaseRpcAs('app_installs_overview', const {}, token: token),
    supabaseRpcAs('tenant_downloads', const {}, token: token).catchError((Object _) => null),
    http
        .get(Uri.parse(_releasesApi), headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10))
        .then<dynamic>((res) => res.statusCode == 200 ? jsonDecode(res.body) : null)
        .catchError((Object _) => null),
  ]);

  final rows = [
    for (final m in (results[0] as List? ?? const []))
      if (m is Map) InstallRow.fromMap(Map<String, dynamic>.from(m)),
  ];
  final page = <String, int>{
    for (final m in (results[1] as List? ?? const []))
      if (m is Map)
        '${m['tenant_id']}': ((m['windows'] as num?)?.toInt() ?? 0) + ((m['android'] as num?)?.toInt() ?? 0),
  };
  final github = results[2] is List ? parseGithubReleases(results[2] as List) : null;
  return groupInstalls(rows, pageDownloads: page, githubDownloads: github?.downloads, latest: github?.latest);
}
