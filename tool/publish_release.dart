/// نشر إصدار جديد من تطبيق الجوال على مستودع الإصدارات.
///
///     dart run tool/publish_release.dart --notes "ما الجديد في هذا الإصدار"
///
/// يبني الحزمة برقم بناء أعلى من المنشور، ويتحقق أنها موقّعة بمفتاح التطبيق،
/// ثم يرفعها مع `mobile-latest.json` — الملف الذي تقرؤه الأجهزة لتعرف أن
/// تحديثاً صدر. رقم الإصدار في `pubspec.yaml` لا يُكتب إلا بعد نجاح الرفع، فنشرٌ
/// فشل في منتصفه لا يترك رقماً محجوزاً بلا حزمة.
///
/// رقم الإصدار جزءان (`2.18`) للبناء، وثلاثة (`2.18.3`) للتحديث الصامت.
///
/// مع `shorebird.yaml` يُبنى الإصدار بـ `shorebird release`، فتستقبل أجهزته بعد
/// ذلك تصليحات كود Dart بصمت: `shorebird patch android --release-version=<الإصدار>`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

const releasesRepo = 'engmohammedaqlain-ctrl/center-mobile-releases';
const manifestName = 'mobile-latest.json';

/// الرابط الثابت الذي تقرؤه الأجهزة — `latest` يحيل دائماً إلى آخر إصدار.
const latestManifestUrl = 'https://github.com/$releasesRepo/releases/latest/download/$manifestName';

/// بصمة شهادة مفتاح التوقيع. حزمةٌ موقّعة بغيره يرفض أندرويد تثبيتها فوق
/// التطبيق الموجود، فنشرها يعطّل التحديث على كل الأجهزة.
const expectedCertSha256 = 'd7a0b1d7c5bcfea9346ab61db35c8e96fd2d042c270a06dc8e23e3a1e5302ac8';

const _usage = '''
نشر إصدار جديد من تطبيق الجوال

  dart run tool/publish_release.dart --notes "ما الجديد"

  --notes "..."               ما الجديد، يظهر للمستخدم في ورقة التحديث
  --notes-file <ملف>          بديل --notes لنصٍّ من عدة أسطر
  --version <رقم>             رقم الإصدار بنفسك. عدد أجزائه يحدد النوع:
                                2.18     جزءان = بناء APK جديد يثبّته المستخدم
                                2.18.3   ثلاثة أجزاء = تحديث صامت (Shorebird) مهما كبر رقمه
  --patch                     تحديث صامت على آخر إصدار منشور، برقمه التالي تلقائياً
  --bump minor|major          بلا --version: الجزء الذي يزيد في البناء (minor افتراضياً)
  --min-supported <رقم>|current
                              أقدم رقم بناء يبقى يعمل؛ ما دونه يُلزَم بالتحديث.
                              بلا هذا الخيار يبقى كما في الإصدار السابق
  --mandatory                 إلزام كل من لم يحدّث بهذا الإصدار
  --dry-run                   يبني ويجهّز الملفات في build/release بلا رفع
  --allow-dirty               النشر مع تعديلات لم تُحفظ بكوميت
''';

/// رقم إصدار بصيغة pubspec: `الاسم+رقم البناء`.
class PubVersion {
  const PubVersion(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;

  /// `versionCode` في أندرويد — به وحده تقارن الأجهزة.
  final int build;

  /// الاسم كما يراه المستخدم ويُنشر به: جزءان.
  String get name => '$major.$minor';

  /// صيغة pubspec وأندرويد: ثلاثة أجزاء دائماً، والثالث صفرٌ للبناء.
  String get semver => '$major.$minor.$patch';

  @override
  String toString() => '$semver+$build';
}

/// السطر وحده دون ما بعده: نهاية السطر تبقى كما كُتبت.
final _versionLine = RegExp(r'^(version:[ \t]*)(\d+)\.(\d+)\.(\d+)\+(\d+)\b', multiLine: true);

PubVersion? parsePubspecVersion(String pubspec) {
  final m = _versionLine.firstMatch(pubspec);
  if (m == null) return null;
  return PubVersion(int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!));
}

String writePubspecVersion(String pubspec, PubVersion version) =>
    pubspec.replaceFirstMapped(_versionLine, (m) => '${m[1]}$version');

/// رقم البناء يزيد مع كل نشر أياً كان الجزء المرفوع من الاسم: أندرويد يرفض
/// تثبيت رقم بناء لا يزيد عن المثبَّت.
PubVersion bumpVersion(PubVersion v, String part) => switch (part) {
      'major' => PubVersion(v.major + 1, 0, 0, v.build + 1),
      'minor' => PubVersion(v.major, v.minor + 1, 0, v.build + 1),
      _ => throw ArgumentError('--bump يقبل minor أو major، لا "$part"'),
    };

/// أقدم رقم بناء يبقى يعمل.
///
/// بلا قيمة يُورَث من الإصدار السابق: إصدارٌ عادي بعد هجرةٍ كاسرة لا يعيد فتح
/// الباب لأجهزة حُجبت لأن السحابة لم تعد تفهم صيغتها.
int resolveMinSupported(String? value, {required int previous, required int current}) {
  final raw = value?.trim() ?? '';
  final min = raw.isEmpty
      ? previous
      : raw == 'current'
          ? current
          : int.tryParse(raw) ?? (throw ArgumentError('--min-supported يقبل رقماً أو current، لا "$raw"'));
  if (min < 0 || min > current) {
    throw ArgumentError('--min-supported يجب أن يكون بين 0 و$current (رقم بناء هذا الإصدار)');
  }
  return min;
}

String tagFor(PubVersion v) => 'v${v.name}';

String apkNameFor(PubVersion v) => 'center-${v.name}.apk';

String apkUrlFor(PubVersion v) => 'https://github.com/$releasesRepo/releases/download/${tagFor(v)}/${apkNameFor(v)}';

/// ملف الوصف بالحقول التي يقرؤها `AppRelease.fromJson` في التطبيق.
Map<String, dynamic> buildManifest({
  required PubVersion version,
  required String sha256,
  required int sizeBytes,
  required String notes,
  required int minSupported,
  required bool mandatory,
  required DateTime publishedAt,
}) =>
    {
      'version': version.name,
      'versionCode': version.build,
      'minSupported': minSupported,
      'mandatory': mandatory,
      'apkUrl': apkUrlFor(version),
      'notes': notes.trim(),
      'sha256': sha256.toLowerCase(),
      'sizeBytes': sizeBytes,
      'publishedAt': publishedAt.toUtc().toIso8601String(),
    };

/// أمر بناء الحزمة.
///
/// مع Shorebird يُبنى بـ `shorebird release` لا `flutter build`: حزمةٌ بنتها
/// Flutter وحدها لا تقبل أي patch، فتبقى أجهزتها خارج التحديث الصامت. وإصدار
/// Flutter يُثبَّت على إصدار المشروع — Shorebird يبني بأحدث إصدار ما لم يُحدَّد،
/// فتخرج الحزمة بمحرّكٍ لم تُختبر عليه.
({String exe, List<String> args}) buildCommand(PubVersion v, {required bool shorebird, String? flutterVersion}) {
  // أندرويد يشترط اسماً من ثلاثة أجزاء، واسم العرض جزءان: يُبنى بالصيغة الكاملة
  final version = ['--build-name', v.semver, '--build-number', '${v.build}'];
  if (!shorebird) {
    return (exe: 'flutter', args: ['build', 'apk', '--release', '--target-platform', 'android-arm64', ...version]);
  }
  return (
    exe: 'shorebird',
    args: [
      'release', 'android', '--artifact', 'apk', '--target-platform', 'android-arm64', //
      if (flutterVersion != null && flutterVersion.isNotEmpty) ...['--flutter-version', flutterVersion],
      ...version,
    ],
  );
}

/// إصدار Flutter من مخرجات `flutter --version`.
String? flutterVersionOf(String output) => RegExp(r'Flutter (\d+\.\d+\.\d+)').firstMatch(output)?.group(1);

/// نوع النشر.
enum PublishKind {
  /// APK جديد يُرفع على GitHub ويثبّته المستخدم.
  build,

  /// تحديث صامت لكود Dart عبر Shorebird على إصدار منشور.
  patch,
}

/// رقم إصدار كتبه الناشر.
typedef RequestedVersion = ({PublishKind kind, String base, int? patchNumber});

/// النوع من عدد أجزاء الرقم لا من قيمته: جزءان بناء، وثلاثة تحديث صامت.
///
/// لو كان النوع من القيمة — عشري تحديث وصحيح بناء — لصار التحديث العاشر بعد
/// `2.9` بناءً بالخطأ. `2.18.10` يبقى تحديثاً صامتاً مهما كبر رقمه الثالث.
RequestedVersion parseRequestedVersion(String raw) {
  final value = raw.trim();
  final m = RegExp(r'^(\d+\.\d+)(?:\.(\d+))?$').firstMatch(value);
  if (m == null) {
    throw ArgumentError('رقم الإصدار: 2.18 للبناء، أو 2.18.1 للتحديث الصامت — لا "$value"');
  }
  final patch = m[2] == null ? null : int.parse(m[2]!);
  if (patch != null && patch < 1) throw ArgumentError('رقم التحديث الصامت يبدأ من 1');
  return (kind: patch == null ? PublishKind.build : PublishKind.patch, base: m[1]!, patchNumber: patch);
}

/// مقارنة اسمي إصدار جزءاً جزءاً: `2.18` أحدث من `2.9` وإن سبقه نصياً.
///
/// تقبل اسماً قديماً من ثلاثة أجزاء (`1.2.7`) كي تبقى المقارنة مع ما نُشر قبل
/// تغيير الترقيم صحيحة.
int compareVersionNames(String a, String b) {
  List<int> parts(String s) => s.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// `2.18` ← الإصدار الذي يُكتب في pubspec: `2.18.0+<بناء>`.
PubVersion versionFromName(String name, {required int build}) {
  final p = name.split('.').map(int.parse).toList();
  return PubVersion(p[0], p[1], p.length > 2 ? p[2] : 0, build);
}

/// نسخة الإصدار كما يعرفها Shorebird: صيغة pubspec كاملة.
///
/// الأسماء المنشورة قبل تغيير الترقيم من ثلاثة أجزاء، فتُستعمل كما هي.
String shorebirdReleaseVersion(String publishedName, int code) {
  final parts = publishedName.split('.').length;
  return '$publishedName${parts < 3 ? '.0' : ''}+$code';
}

/// رقم التحديث الصامت التالي من مخرجات `shorebird patches list`.
///
/// يُقرأ من الصيغتين معاً — `"number": 2` في JSON و`#2` في النص — بلا فكّ JSON:
/// الأداة تطبع قبله أحياناً تحذيرات تُفسد فكّه.
int nextPatchNumber(String listOutput) {
  var highest = 0;
  for (final m in RegExp(r'"number"\s*:\s*(\d+)|#(\d+)').allMatches(listOutput)) {
    final n = int.parse(m[1] ?? m[2]!);
    if (n > highest) highest = n;
  }
  return highest + 1;
}

/// سبب رفض تحديث صامت، أو `null`.
///
/// Shorebird يرقّم التحديثات بنفسه بالتتابع، والتطبيق يعرض رقمه هو: رقمٌ مكتوب
/// لا يطابق التالي كان سيظهر على الأجهزة بغير ما نشره الناشر.
String? patchProblem({required String base, required int number, required String published, required int next}) {
  if (base != published) {
    return 'التحديث الصامت يكون على آخر إصدار منشور ($published) — اكتب $published.$next';
  }
  if (number != next) return 'التحديث التالي لـ $published رقمه $next — اكتب $published.$next لا $base.$number';
  return null;
}

/// بصمة شهادة الموقِّع الأول من مخرجات `apksigner verify --print-certs`.
String? signerDigest(String apksignerOutput) => RegExp(r'Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]+)')
    .firstMatch(apksignerOutput)
    ?.group(1)
    ?.toLowerCase();

Future<void> main(List<String> arguments) async {
  final args = _Args.parse(arguments);

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync() ||
      !RegExp(r'^name:\s*center_mobile\b', multiLine: true).hasMatch(pubspecFile.readAsStringSync())) {
    _fail('شغّل الأمر من داخل مجلد center-mobile-app');
  }

  if (!args.allowDirty) {
    final status = await _capture('git', ['status', '--porcelain', '--untracked-files=no']);
    if (status.trim().isNotEmpty) {
      _fail('في تعديلات لم تُحفظ بكوميت — الإصدار المنشور لازم يقابل كوميتاً معروفاً.\n'
          '  احفظها أولاً، أو أضف --allow-dirty');
    }
  }

  _step('قراءة آخر إصدار منشور');
  final previous = await _fetchJson(latestManifestUrl);
  final previousCode = (previous?['versionCode'] as num?)?.toInt() ?? 0;
  final previousMin = (previous?['minSupported'] as num?)?.toInt() ?? 0;
  _info(previous == null ? 'لا يوجد إصدار منشور بعد — هذا أول نشر' : 'المنشور: ${previous['version']} (بناء $previousCode)');

  final published = '${previous?['version'] ?? ''}'.trim();
  final requested = args.version == null ? null : _orFail(() => parseRequestedVersion(args.version!));

  // تحديث صامت: رقم من أربعة أجزاء، أو --patch
  if (args.patch || requested?.kind == PublishKind.patch) {
    await _publishPatch(args, requested, published, previousCode);
    return;
  }
  if (args.notes.trim().isEmpty) _fail('اكتب ما الجديد في هذا الإصدار: --notes "..."');

  final pubspec = pubspecFile.readAsStringSync();
  final current = parsePubspecVersion(pubspec) ?? _fail('لم أجد سطر version: x.y.z+n في pubspec.yaml');
  if (requested != null && published.isNotEmpty && compareVersionNames(requested.base, published) <= 0) {
    _fail('الإصدار ${requested.base} ليس أحدث من المنشور $published — البناء الجديد رقمه أكبر');
  }
  var next = requested == null
      ? _orFail(() => bumpVersion(current, args.bump))
      : versionFromName(requested.base, build: current.build + 1);
  // pubspec متأخر عن المنشور — نُشر من نسخة أخرى من المشروع: رقم البناء يتجاوزه
  if (next.build <= previousCode) next = PubVersion(next.major, next.minor, next.patch, previousCode + 1);
  final minSupported = _orFail(
    () => resolveMinSupported(args.minSupported, previous: previousMin, current: next.build),
  );
  _info('الجديد: $next · أقدم بناء مدعوم: $minSupported${args.mandatory ? ' · إلزامي' : ''}');

  // Shorebird مُهيّأ: الإصدار يُبنى به كي تستقبل أجهزته الـ patches. التجربة بلا رفع
  // تبني بـ Flutter وحدها، فلا يُسجَّل عند Shorebird إصدارٌ لم يُنشر
  final useShorebird = File('shorebird.yaml').existsSync() && !args.dryRun;
  final flutterVersion =
      useShorebird ? flutterVersionOf(await _capture('flutter', ['--version'], shell: true)) : null;
  if (useShorebird && flutterVersion == null) _fail('تعذّرت قراءة إصدار Flutter للمشروع');
  final build = buildCommand(next, shorebird: useShorebird, flutterVersion: flutterVersion);
  _step(useShorebird ? 'بناء الحزمة وتسجيل الإصدار في Shorebird (Flutter $flutterVersion)' : 'بناء الحزمة');
  await _run(build.exe, build.args, shell: true);
  final built = File('build/app/outputs/flutter-apk/app-release.apk');
  if (!built.existsSync()) _fail('لم أجد الحزمة المبنية في ${built.path}');

  _step('التحقق من التوقيع');
  final apksigner = _findApksigner() ?? _fail('لم أجد apksigner — ثبّت Android SDK Build-Tools');
  final digest = signerDigest(await _capture(apksigner, ['verify', '--print-certs', built.path], shell: true));
  if (digest != expectedCertSha256) {
    _fail('الحزمة ليست موقّعة بمفتاح التطبيق (${digest ?? 'لا توقيع'}).\n'
        '  تحقّق من android/key.properties — أجهزة المستخدمين سترفض تثبيتها');
  }
  _info('موقّعة بمفتاح التطبيق ✓');

  _step('تجهيز ملفات النشر');
  final outDir = Directory('build/release')..createSync(recursive: true);
  final apk = built.copySync('${outDir.path}/${apkNameFor(next)}');
  final size = apk.lengthSync();
  final sha = (await crypto.sha256.bind(apk.openRead()).first).toString();
  final manifest = buildManifest(
    version: next,
    sha256: sha,
    sizeBytes: size,
    notes: args.notes,
    minSupported: minSupported,
    mandatory: args.mandatory,
    publishedAt: DateTime.now(),
  );
  final manifestFile = File('${outDir.path}/$manifestName')
    ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  // النص عبر ملف لا عبر سطر الأوامر: العربية والأسطر المتعددة تصل كما كُتبت
  final notesFile = File('${outDir.path}/notes.md')..writeAsStringSync(args.notes.trim());
  _info('${apk.path} (${(size / (1024 * 1024)).toStringAsFixed(1)} MB)');
  _info('sha256 $sha');

  if (args.dryRun) {
    _step('تجربة بلا رفع — الملفات في ${outDir.path}');
    return;
  }

  _step('الرفع إلى GitHub');
  await _ensureRepoHasCommit();
  await _run('gh', [
    'release', 'create', tagFor(next), apk.path, manifestFile.path, //
    '--repo', releasesRepo, '--title', next.name, '--notes-file', notesFile.path, '--latest',
  ]);

  _step('التأكد من أن الأجهزة ترى الإصدار');
  final live = await _fetchJson(latestManifestUrl);
  if ((live?['versionCode'] as num?)?.toInt() == next.build) {
    _info('الأجهزة ستجد التحديث عند فحصها التالي ✓');
  } else {
    _warn('الرابط الثابت لم يُرجع الإصدار الجديد بعد. افتحه بعد دقيقة للتأكد:\n    $latestManifestUrl');
  }

  pubspecFile.writeAsStringSync(writePubspecVersion(pubspec, next));
  await _run('git', ['commit', '--only', 'pubspec.yaml', '-m', 'Release ${next.name}'], allowFailure: true);

  _step('تم نشر ${next.name}');
  _info('رابط التنزيل المباشر للتثبيت الأول:\n    ${apkUrlFor(next)}');
  if (useShorebird) {
    _info('تصليحات كود Dart لهذا الإصدار تصل الأجهزة بصمت:\n    shorebird patch android --release-version=$next');
  }
}

class _Args {
  String notes = '';
  String bump = 'minor';
  String? version;
  bool patch = false;
  String? minSupported;
  bool mandatory = false;
  bool dryRun = false;
  bool allowDirty = false;

  static _Args parse(List<String> raw) {
    final args = _Args();
    final queue = List.of(raw);
    while (queue.isNotEmpty) {
      final flag = queue.removeAt(0);
      String value() => queue.isEmpty ? _fail('$flag يحتاج قيمة') : queue.removeAt(0);
      switch (flag) {
        case '--notes':
          args.notes = value();
        case '--notes-file':
          args.notes = File(value()).readAsStringSync();
        case '--version':
          args.version = value();
        case '--patch':
          args.patch = true;
        case '--bump':
          args.bump = value();
        case '--min-supported':
          args.minSupported = value();
        case '--mandatory':
          args.mandatory = true;
        case '--dry-run':
          args.dryRun = true;
        case '--allow-dirty':
          args.allowDirty = true;
        case '-h' || '--help':
          stdout.write(_usage);
          exit(0);
        default:
          stderr.write(_usage);
          _fail('خيار غير معروف: $flag');
      }
    }
    return args;
  }
}

/// تحديث صامت: patch على آخر إصدار منشور عبر Shorebird.
///
/// لا يمسّ GitHub ولا `pubspec.yaml`: الحزمة المثبَّتة نفسها تستقبله، ورقمه
/// الرابع يرقّمه Shorebird ويقرؤه التطبيق منه.
Future<void> _publishPatch(_Args args, RequestedVersion? requested, String published, int publishedCode) async {
  if (!File('shorebird.yaml').existsSync()) _fail('التحديث الصامت يحتاج Shorebird: شغّل shorebird init');
  if (published.isEmpty || publishedCode <= 0) {
    _fail('لا يوجد إصدار منشور بعد — انشر بناءً أولاً برقم من جزأين');
  }
  final releaseVersion = shorebirdReleaseVersion(published, publishedCode);

  _step('قراءة التحديثات الصامتة لـ $published');
  final listed = await _capture(
    'shorebird',
    ['patches', 'list', '--release-version', releaseVersion, '--json'],
    shell: true,
  );
  final next = nextPatchNumber(listed);
  final number = requested?.patchNumber ?? next;
  final problem = patchProblem(base: requested?.base ?? published, number: number, published: published, next: next);
  if (problem != null) _fail(problem);
  _info('التحديث: $published.$number');

  _step('بناء التحديث ورفعه إلى Shorebird');
  await _run(
    'shorebird',
    ['patch', 'android', '--release-version', releaseVersion, if (args.dryRun) '--dry-run'],
    shell: true,
  );

  if (args.dryRun) {
    _step('تجربة بلا رفع — لم يُنشر شيء');
    return;
  }
  _step('تم نشر $published.$number');
  _info('يصل الأجهزة بصمت: يُنزَّل عند فتح التطبيق ويُطبَّق عند فتحه التالي');
}

/// GitHub لا ينشئ إصداراً في مستودع بلا كوميت: الوسم يحتاج كوميتاً يشير إليه.
Future<void> _ensureRepoHasCommit() async {
  final empty = await _capture('gh', ['repo', 'view', releasesRepo, '--json', 'isEmpty', '--jq', '.isEmpty']);
  if (empty.trim() != 'true') return;
  _info('المستودع فارغ — إنشاء README أولاً');
  const readme = '# Center Mobile Releases\n\n'
      'حزم تطبيق الجوال، و`mobile-latest.json` الذي تقرؤه الأجهزة لتعرف أن تحديثاً صدر.\n';
  await _capture('gh', [
    'api', '-X', 'PUT', 'repos/$releasesRepo/contents/README.md', //
    '-f', 'message=Initial commit', '-f', 'content=${base64Encode(utf8.encode(readme))}',
  ]);
}

String? _findApksigner() {
  final env = Platform.environment;
  final local = env['LOCALAPPDATA'];
  final sdk = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'] ?? (local == null ? null : '$local\\Android\\Sdk');
  if (sdk == null) return null;
  final tools = Directory('$sdk${Platform.pathSeparator}build-tools');
  if (!tools.existsSync()) return null;

  List<int> parts(Directory d) =>
      d.path.split(RegExp(r'[\\/]')).last.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final dirs = tools.listSync().whereType<Directory>().toList()
    ..sort((a, b) {
      final pa = parts(a), pb = parts(b);
      for (var i = 0; i < pa.length && i < pb.length; i++) {
        if (pa[i] != pb[i]) return pb[i].compareTo(pa[i]);
      }
      return pb.length.compareTo(pa.length);
    });
  for (final dir in dirs) {
    final exe = File('${dir.path}${Platform.pathSeparator}${Platform.isWindows ? 'apksigner.bat' : 'apksigner'}');
    if (exe.existsSync()) return exe.path;
  }
  return null;
}

Future<Map<String, dynamic>?> _fetchJson(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) return null;
    final data = jsonDecode(await response.transform(utf8.decoder).join());
    return data is Map<String, dynamic> ? data : null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// `shell` لملفات .bat على ويندوز (flutter وapksigner)؛ gh وgit ملفات exe تُشغَّل
/// مباشرة فلا يمرّ نصٌّ عربي عبر اقتباسات cmd.
Future<void> _run(String exe, List<String> args, {bool shell = false, bool allowFailure = false}) async {
  final process = await Process.start(
    exe,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: shell && Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0 && !allowFailure) _fail('$exe ${args.first} فشل (رمز الخروج $code)');
}

Future<String> _capture(String exe, List<String> args, {bool shell = false}) async {
  final result = await Process.run(
    exe,
    args,
    runInShell: shell && Platform.isWindows,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) _fail('$exe ${args.first} فشل:\n${result.stderr}${result.stdout}');
  return '${result.stdout}';
}

T _orFail<T>(T Function() body) {
  try {
    return body();
  } on ArgumentError catch (e) {
    _fail('${e.message}');
  }
}

void _step(String message) => stdout.writeln('\n▸ $message');

void _info(String message) => stdout.writeln('  $message');

void _warn(String message) => stdout.writeln('  ! $message');

Never _fail(String message) {
  stderr.writeln('\n✗ $message');
  exit(1);
}
