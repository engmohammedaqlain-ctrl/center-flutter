/// نسخة المدرسة من حزمة التطبيق: أيقونتها شعارُ المدرسة، وكودها مكتوبٌ داخلها.
///
/// لا يُعاد البناء: تُفتح الحزمة المبنية كملف مضغوط، وتُستبدل صور الأيقونة
/// وملف الكود، ثم تُحاذى وتُوقَّع بمفتاح التطبيق نفسه. التوقيع يغطي الأيقونة،
/// فلا يصحّ تغييرها بعد التوقيع — وإعادة التوقيع بالمفتاح نفسه تُبقي التحديث
/// ممكناً فوق أي نسخة مثبّتة، عامةً كانت أو لمدرسة.
///
/// الاسم على الشاشة يبقى اسم التطبيق للجميع؛ الأيقونة وحدها للمدرسة.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// ملف الكود كما يقرؤه التطبيق (`rootBundle`) — في النسخة العامة `{}`.
const schoolAssetKey = 'assets/school.json';

/// مكانه داخل الحزمة.
const schoolAssetEntry = 'assets/flutter_assets/$schoolAssetKey';

/// كود المدرسة كما في روابط صفحات التحميل (`/d/<الكود>`).
final schoolCodePattern = RegExp(r'^[A-Za-z0-9_-]{1,50}$');

/// الكود بصيغته الموحّدة: السحابة تقارنه بلا حالة أحرف، والملف والمفتاح بحروف كبيرة.
String normalizeSchoolCode(String code) => code.trim().toUpperCase();

/// محتوى ملف الكود لمدرسة.
Uint8List schoolAssetBytes(String code) => Uint8List.fromList(utf8.encode(jsonEncode({'code': normalizeSchoolCode(code)})));

class SchoolApkException implements Exception {
  const SchoolApkException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ── الملف المضغوط ───────────────────────────────────────────────────────────────

/// سجلّ ملفٍ في الفهرس المركزي للملف المضغوط.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.versionMadeBy,
    required this.versionNeeded,
    required this.flags,
    required this.method,
    required this.time,
    required this.date,
    required this.crc,
    required this.compressedSize,
    required this.size,
    required this.internalAttrs,
    required this.externalAttrs,
    required this.localOffset,
  });

  final String name;
  final int versionMadeBy;
  final int versionNeeded;
  final int flags;
  final int method;
  final int time;
  final int date;
  final int crc;
  final int compressedSize;
  final int size;
  final int internalAttrs;
  final int externalAttrs;
  final int localOffset;
}

const _eocdSignature = 0x06054b50;
const _centralSignature = 0x02014b50;
const _localSignature = 0x04034b50;

/// قراءة الفهرس المركزي. الحزم أصغر من 4 جيجا فلا حاجة لـ Zip64.
List<ZipEntry> readZipEntries(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final eocd = _findEocd(data);
  final count = data.getUint16(eocd + 10, Endian.little);
  var at = data.getUint32(eocd + 16, Endian.little);
  final entries = <ZipEntry>[];
  for (var i = 0; i < count; i++) {
    if (data.getUint32(at, Endian.little) != _centralSignature) {
      throw const SchoolApkException('Broken zip: central directory entry not found');
    }
    final nameLength = data.getUint16(at + 28, Endian.little);
    final extraLength = data.getUint16(at + 30, Endian.little);
    final commentLength = data.getUint16(at + 32, Endian.little);
    entries.add(ZipEntry(
      name: utf8.decode(zip.sublist(at + 46, at + 46 + nameLength)),
      versionMadeBy: data.getUint16(at + 4, Endian.little),
      versionNeeded: data.getUint16(at + 6, Endian.little),
      flags: data.getUint16(at + 8, Endian.little),
      method: data.getUint16(at + 10, Endian.little),
      time: data.getUint16(at + 12, Endian.little),
      date: data.getUint16(at + 14, Endian.little),
      crc: data.getUint32(at + 16, Endian.little),
      compressedSize: data.getUint32(at + 20, Endian.little),
      size: data.getUint32(at + 24, Endian.little),
      internalAttrs: data.getUint16(at + 36, Endian.little),
      externalAttrs: data.getUint32(at + 38, Endian.little),
      localOffset: data.getUint32(at + 42, Endian.little),
    ));
    at += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

int _findEocd(ByteData data) {
  final last = data.lengthInBytes - 22;
  final first = math.max(0, last - 0xffff);
  for (var i = last; i >= first; i--) {
    if (data.getUint32(i, Endian.little) == _eocdSignature) return i;
  }
  throw const SchoolApkException('Not a zip file: end of central directory not found');
}

/// بيانات ملفٍ كما هي مخزّنة (مضغوطة أو لا).
Uint8List rawEntryData(Uint8List zip, ZipEntry entry) {
  final data = ByteData.sublistView(zip);
  final at = entry.localOffset;
  if (data.getUint32(at, Endian.little) != _localSignature) {
    throw SchoolApkException('Broken zip: local header of ${entry.name} not found');
  }
  final start = at + 30 + data.getUint16(at + 26, Endian.little) + data.getUint16(at + 28, Endian.little);
  return Uint8List.sublistView(zip, start, start + entry.compressedSize);
}

/// محتوى ملفٍ بعد فكّ ضغطه.
Uint8List entryContent(Uint8List zip, ZipEntry entry) {
  final raw = rawEntryData(zip, entry);
  return switch (entry.method) {
    0 => raw,
    8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(raw)),
    _ => throw SchoolApkException('${entry.name}: unsupported compression ${entry.method}'),
  };
}

/// ملفات توقيع JAR (v1): تُعاد كتابتها عند التوقيع، وبقاء القديمة يُفسد التحقق.
bool isV1SignatureFile(String name) {
  final upper = name.toUpperCase();
  if (!upper.startsWith('META-INF/') || upper.substring(9).contains('/')) return false;
  return upper == 'META-INF/MANIFEST.MF' || RegExp(r'\.(SF|RSA|DSA|EC)$').hasMatch(upper);
}

/// ملفٌ مضغوط جديد بالترتيب نفسه، واستبدال محتوى [replace] (تُخزَّن بلا ضغط).
///
/// كتلة التوقيع القديمة لا تُنقل — تقع بين البيانات والفهرس ولا يمرّ بها النسخ —
/// ولا ملفات توقيع v1. حشو المحاذاة يُترك لـ zipalign بعدها.
Uint8List rewriteZip(Uint8List zip, Map<String, Uint8List> replace) {
  final entries = readZipEntries(zip);
  final missing = replace.keys.where((name) => !entries.any((e) => e.name == name)).toList();
  if (missing.isNotEmpty) throw SchoolApkException('Not in the APK: ${missing.join(', ')}');

  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var written = 0;
  var count = 0;
  for (final entry in entries) {
    if (isV1SignatureFile(entry.name)) continue;
    final replacement = replace[entry.name];
    final body = replacement ?? rawEntryData(zip, entry);
    final method = replacement == null ? entry.method : 0;
    final crc = replacement == null ? entry.crc : crc32(replacement);
    final size = replacement == null ? entry.size : replacement.length;
    // حجمٌ بعد البيانات (bit 3) لا يُكتب: الأحجام معروفة وتُكتب في الترويسة
    final flags = entry.flags & ~0x0008;
    final name = utf8.encode(entry.name);

    final local = ByteData(30)
      ..setUint32(0, _localSignature, Endian.little)
      ..setUint16(4, entry.versionNeeded, Endian.little)
      ..setUint16(6, flags, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, entry.time, Endian.little)
      ..setUint16(12, entry.date, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, body.length, Endian.little)
      ..setUint32(22, size, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    final offset = written;
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(body);
    written += 30 + name.length + body.length;

    final record = ByteData(46)
      ..setUint32(0, _centralSignature, Endian.little)
      ..setUint16(4, entry.versionMadeBy, Endian.little)
      ..setUint16(6, entry.versionNeeded, Endian.little)
      ..setUint16(8, flags, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint16(12, entry.time, Endian.little)
      ..setUint16(14, entry.date, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, body.length, Endian.little)
      ..setUint32(24, size, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint16(36, entry.internalAttrs, Endian.little)
      ..setUint32(38, entry.externalAttrs, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(record.buffer.asUint8List())
      ..add(name);
    count++;
  }

  final centralBytes = central.takeBytes();
  final end = ByteData(22)
    ..setUint32(0, _eocdSignature, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, centralBytes.length, Endian.little)
    ..setUint32(16, written, Endian.little);
  out
    ..add(centralBytes)
    ..add(end.buffer.asUint8List());
  return out.takeBytes();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return c ^ 0xffffffff;
}

// ── الأيقونة ────────────────────────────────────────────────────────────────────

/// صورة أيقونة داخل الحزمة، ودائريّةٌ هي أم مربعة.
typedef LauncherIcon = ({String path, bool round});

/// صور `mipmap/ic_launcher` (والدائرية إن بقيت) من مخرجات `aapt2 dump resources`.
///
/// الأسماء داخل الحزمة لا تُفترض: تحسين الموارد في الإصدار يختصرها (`res/Xy.png`)،
/// فتُقرأ من جدول الموارد نفسه.
List<LauncherIcon> launcherIcons(String dump) {
  final icons = <LauncherIcon>[];
  bool? round;
  for (final line in const LineSplitter().convert(dump)) {
    final resource = RegExp(r'^\s*resource 0x[0-9a-fA-F]+ (\S+)').firstMatch(line);
    if (resource != null) {
      final name = resource[1]!;
      round = name == 'mipmap/ic_launcher' ? false : (name == 'mipmap/ic_launcher_round' ? true : null);
      continue;
    }
    if (round == null) continue;
    final file = RegExp(r'\(file\) (\S+\.png)\b').firstMatch(line);
    if (file != null) icons.add((path: file[1]!, round: round));
  }
  return icons;
}

/// عرض صورة PNG وارتفاعها من ترويستها، بلا فكّها.
({int width, int height}) pngSize(Uint8List png) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (png.length < 24 || !List.generate(8, (i) => png[i] == signature[i]).every((ok) => ok)) {
    throw const SchoolApkException('Launcher icon is not a PNG');
  }
  final data = ByteData.sublistView(png);
  return (width: data.getUint32(16), height: data.getUint32(20));
}

/// الشعار من صيغة `data:image/...;base64,...` كما يُحفظ في إعدادات المدرسة.
///
/// SVG لا يُرسم هنا: يعيد `null`، فتخرج نسخة المدرسة بأيقونة التطبيق العامة.
img.Image? decodeLogo(String? dataUrl) {
  final m = RegExp(r'^data:(image/[a-z0-9.+-]+);base64,(.+)$', caseSensitive: false, dotAll: true)
      .firstMatch(dataUrl?.trim() ?? '');
  if (m == null || m[1]!.toLowerCase().contains('svg')) return null;
  try {
    final image = img.decodeImage(base64Decode(m[2]!.replaceAll(RegExp(r'\s'), '')));
    if (image == null || image.width == 0 || image.height == 0) return null;
    final rgba = image.convert(numChannels: 4);
    // الهوامش الشفافة حول الشعار تصغّره داخل الأيقونة بلا داعٍ
    final trimmed = img.trim(rgba, mode: img.TrimMode.transparent);
    return trimmed.width > 0 && trimmed.height > 0 ? trimmed : rgba;
  } catch (_) {
    return null;
  }
}

/// أيقونة بمقاس [size]: الشعار في وسط خلفية بيضاء كأيقونة التطبيق الحالية.
Uint8List renderLauncherIcon(img.Image logo, int size, {bool round = false}) {
  final white = img.ColorRgba8(255, 255, 255, 255);
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  if (round) {
    img.fillCircle(canvas, x: size ~/ 2, y: size ~/ 2, radius: size ~/ 2, color: white, antialias: true);
  } else {
    img.fill(canvas, color: white);
  }
  // الدائرة تقصّ الزوايا: الشعار فيها أصغر كي لا تُقصّ أطرافه
  final box = size * (round ? 0.68 : 0.84);
  final scale = math.min(box / logo.width, box / logo.height);
  final w = math.max(1, (logo.width * scale).round());
  final h = math.max(1, (logo.height * scale).round());
  final resized = img.copyResize(logo, width: w, height: h, interpolation: img.Interpolation.cubic);
  img.compositeImage(canvas, resized, dstX: (size - w) ~/ 2, dstY: (size - h) ~/ 2);
  return img.encodePng(canvas);
}

/// ما يُستبدل داخل الحزمة لمدرسة: ملف الكود، وصور الأيقونة إن كان للمدرسة شعار يُرسم.
Map<String, Uint8List> schoolReplacements(
  Uint8List apk,
  List<LauncherIcon> icons, {
  required String code,
  required img.Image? logo,
}) {
  final entries = {for (final e in readZipEntries(apk)) e.name: e};
  final replace = <String, Uint8List>{schoolAssetEntry: schoolAssetBytes(code)};
  if (logo == null) return replace;
  for (final icon in icons) {
    final entry = entries[icon.path];
    if (entry == null) throw SchoolApkException('Launcher icon ${icon.path} is not in the APK');
    final size = pngSize(entryContent(apk, entry));
    replace[icon.path] = renderLauncherIcon(logo, size.width, round: icon.round);
  }
  return replace;
}

// ── التوقيع ─────────────────────────────────────────────────────────────────────

/// مفتاح التوقيع من `android/key.properties` — المسار فيه نسبةً إلى مجلد android.
typedef SigningKey = ({String storeFile, String storePassword, String alias, String keyPassword});

SigningKey readSigningKey(File properties) {
  if (!properties.existsSync()) {
    throw SchoolApkException('${properties.path} not found - school copies must be signed with the app key');
  }
  final values = <String, String>{};
  for (final line in const LineSplitter().convert(properties.readAsStringSync())) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) continue;
    final at = trimmed.indexOf('=');
    if (at <= 0) continue;
    values[trimmed.substring(0, at).trim()] = trimmed.substring(at + 1).trim();
  }
  String need(String key) {
    final v = values[key] ?? '';
    if (v.isEmpty) throw SchoolApkException('${properties.path}: $key is missing');
    return v;
  }

  final store = File(need('storeFile')).isAbsolute
      ? File(need('storeFile'))
      : File('${properties.parent.path}${Platform.pathSeparator}${need('storeFile')}');
  if (!store.existsSync()) throw SchoolApkException('Signing key not found at ${store.path}');
  return (
    storeFile: store.absolute.path,
    storePassword: need('storePassword'),
    alias: need('keyAlias'),
    keyPassword: need('keyPassword'),
  );
}

/// أدوات أندرويد التي تلزم نسخ المدارس.
typedef BuildTools = ({String aapt2, String zipalign, String apksigner});

/// يبني نسخة مدرسة من [base] إلى [out]: استبدال، ثم محاذاة، ثم توقيع.
///
/// المحاذاة قبل التوقيع إلزامية: التوقيع v2 يغطي مواضع البيانات، فأي حشوٍ
/// بعده يكسره. والمكتبات غير المضغوطة (.so) تُحاذى على 16 ك.ب كما يطلب أندرويد 15.
Future<void> buildSchoolApk({
  required Uint8List base,
  required List<LauncherIcon> icons,
  required String code,
  required img.Image? logo,
  required File out,
  required BuildTools tools,
  required SigningKey key,
}) async {
  final work = Directory.systemTemp.createTempSync('school_apk_');
  try {
    final unsigned = File('${work.path}${Platform.pathSeparator}unsigned.apk')
      ..writeAsBytesSync(rewriteZip(base, schoolReplacements(base, icons, code: code, logo: logo)));
    final aligned = '${work.path}${Platform.pathSeparator}aligned.apk';
    await _tool(tools.zipalign, ['-f', '-P', '16', '4', unsigned.path, aligned]);
    if (out.existsSync()) out.deleteSync();
    await _tool(
      tools.apksigner,
      [
        'sign',
        '--ks', key.storeFile,
        '--ks-key-alias', key.alias,
        // كلمتا السر عبر البيئة لا سطر الأوامر: لا تظهران في قائمة العمليات
        '--ks-pass', 'env:SCHOOL_APK_STORE_PASS',
        '--key-pass', 'env:SCHOOL_APK_KEY_PASS',
        '--v4-signing-enabled', 'false',
        '--out', out.path,
        aligned,
      ],
      shell: true,
      environment: {'SCHOOL_APK_STORE_PASS': key.storePassword, 'SCHOOL_APK_KEY_PASS': key.keyPassword},
    );
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<String> _tool(String exe, List<String> args, {bool shell = false, Map<String, String>? environment}) async {
  final result = await Process.run(
    exe,
    args,
    runInShell: shell && Platform.isWindows,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw SchoolApkException('${exe.split(RegExp(r'[\\/]')).last} ${args.first} failed:\n${result.stderr}${result.stdout}');
  }
  return '${result.stdout}';
}
