import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:center_mobile/data/app_update.dart';
import 'package:center_mobile/data/school_brand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../tool/publish_release.dart';
import '../tool/school_apk.dart';

/// ملف مضغوط صغير بملفين مخزّنين بلا ضغط.
Uint8List _zip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  for (final MapEntry(key: name, value: body) in files.entries) {
    final n = utf8.encode(name);
    final crc = crc32(body);
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, body.length, Endian.little)
      ..setUint32(22, body.length, Endian.little)
      ..setUint16(26, n.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(n)
      ..add(body);
    final record = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, body.length, Endian.little)
      ..setUint32(24, body.length, Endian.little)
      ..setUint16(28, n.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(record.buffer.asUint8List())
      ..add(n);
    offset += 30 + n.length + body.length;
  }
  final c = central.takeBytes();
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, c.length, Endian.little)
    ..setUint32(16, offset, Endian.little);
  out
    ..add(c)
    ..add(end.buffer.asUint8List());
  return out.takeBytes();
}

void main() {
  group('نسخة المدرسة داخل الحزمة', () {
    test('يُستبدل الملف المطلوب ويبقى غيره، وتسقط ملفات توقيع v1', () {
      final zip = _zip({
        schoolAssetEntry: utf8.encode('{}'),
        'classes.dex': [1, 2, 3],
        'META-INF/CERT.RSA': [9],
        'META-INF/MANIFEST.MF': [9],
      });
      final out = rewriteZip(zip, {schoolAssetEntry: schoolAssetBytes('abc')});
      final entries = {for (final e in readZipEntries(out)) e.name: e};
      expect(entries.keys, [schoolAssetEntry, 'classes.dex']);
      expect(utf8.decode(entryContent(out, entries[schoolAssetEntry]!)), '{"code":"ABC"}');
      expect(entries[schoolAssetEntry]!.crc, crc32(utf8.encode('{"code":"ABC"}')));
      expect(entryContent(out, entries['classes.dex']!), [1, 2, 3]);
    });

    test('ملفٌ ليس في الحزمة لا يُستبدل بصمت', () {
      expect(() => rewriteZip(_zip({'a': [1]}), {'b': Uint8List(1)}), throwsA(isA<SchoolApkException>()));
    });

    test('صور الأيقونة تُقرأ من جدول الموارد ولو اختُصرت أسماؤها', () {
      const dump = '''
    resource 0x7f0d0000 mipmap/ic_launcher
      (mdpi) (file) res/9w.png type=PNG
      (xxxhdpi) (file) res/o-.png type=PNG
    resource 0x7f0d0001 mipmap/ic_launcher_round
      (mdpi) (file) res/Ab.png type=PNG
    resource 0x7f080000 drawable/splash_logo_png
      (mdpi) (file) res/zz.png type=PNG
''';
      expect(splashImages(dump), ['res/zz.png']);
      expect(launcherIcons(dump), [
        (path: 'res/9w.png', round: false),
        (path: 'res/o-.png', round: false),
        (path: 'res/Ab.png', round: true),
      ]);
    });

    test('الأيقونة بمقاس الأصل، والشعار SVG لا يُرسم', () {
      final logo = img.Image(width: 40, height: 20, numChannels: 4);
      img.fill(logo, color: img.ColorRgba8(200, 0, 0, 255));
      final decoded = decodeLogo('data:image/png;base64,${base64Encode(img.encodePng(logo))}');
      expect(decoded, isNotNull);
      expect(pngSize(renderLauncherIcon(decoded!, 48)), (width: 48, height: 48));
      expect(decodeLogo('data:image/svg+xml;base64,PHN2Zy8+'), isNull);
      expect(decodeLogo(null), isNull);
    });

    test('مفتاح التوقيع: المسار نسبةً إلى مجلد الملف', () {
      final dir = Directory.systemTemp.createTempSync('key_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/app.jks').writeAsStringSync('x');
      final props = File('${dir.path}/key.properties')
        ..writeAsStringSync('storeFile=app.jks\nstorePassword=a\nkeyAlias=b\nkeyPassword=c\n');
      final key = readSigningKey(props);
      expect(File(key.storeFile).existsSync(), isTrue);
      expect((key.alias, key.storePassword, key.keyPassword), ('b', 'a', 'c'));
      props.writeAsStringSync('storeFile=app.jks\n');
      expect(() => readSigningKey(props), throwsA(isA<SchoolApkException>()));
    });
  });

  group('النشر', () {
    const v = PubVersion(2, 18, 0, 40);

    test('اسم نسخة المدرسة ورابطها بالكود بحروف كبيرة', () {
      expect(schoolApkNameFor(v, 'abc'), 'center-2.18-ABC.apk');
      expect(schoolApkUrlFor(v, 'abc'), endsWith('/releases/download/v2.18/center-2.18-ABC.apk'));
    });

    test('الأكواد من سطر الأوامر: بلا تكرار، والخاطئ يُرفض', () {
      expect(parseSchoolCodes('abc, DEF,abc'), ['ABC', 'DEF']);
      expect(() => parseSchoolCodes('a/b'), throwsArgumentError);
      expect(() => parseSchoolCodes(' , '), throwsArgumentError);
    });

    test('الوصف يحمل نسخ المدارس، ولا يحملها بلا مدارس', () {
      Map<String, dynamic> manifest(Map<String, Map<String, dynamic>> schools) => buildManifest(
            version: v,
            sha256: 'AA',
            sizeBytes: 1,
            notes: '',
            minSupported: 0,
            mandatory: true,
            publishedAt: DateTime.utc(2026),
            schools: schools,
          );
      expect(manifest({}).containsKey('schools'), isFalse);
      final entry = schoolManifestEntry(v, 'ABC', sha256: 'BB', sizeBytes: 2);
      expect(manifest({'ABC': entry})['schools'], {'ABC': entry});
      expect(entry['sha256'], 'bb');
    });
  });

  group('التطبيق', () {
    final json = {
      'version': '2.18',
      'versionCode': 40,
      'apkUrl': 'https://x/center-2.18.apk',
      'sha256': 'generic',
      'sizeBytes': 10,
      'schools': {
        'ABC': {'apkUrl': 'https://x/center-2.18-ABC.apk', 'sha256': 'school', 'sizeBytes': 11},
      },
    };

    test('جهاز المدرسة ينزّل نسختها ببصمتها وحجمها', () {
      final r = AppRelease.fromJson(json, school: 'abc')!;
      expect((r.apkUrl, r.sha256, r.sizeBytes), ('https://x/center-2.18-ABC.apk', 'school', 11));
    });

    test('مدرسة بلا نسخة، أو جهاز بلا مدرسة: النسخة العامة', () {
      for (final school in [null, 'XYZ']) {
        final r = AppRelease.fromJson(json, school: school)!;
        expect((r.apkUrl, r.sha256, r.sizeBytes), ('https://x/center-2.18.apk', 'generic', 10));
      }
    });

    test('هوية المدرسة تُكتب في ملف النسخة وتُقرأ منه', () {
      final raw = utf8.decode(schoolAssetBytes(
        'mister',
        name: 'مدرسة المستر',
        logo: 'data:image/png;base64,AA==',
        colors: schoolColors({'sidebarBg': '#1C3124', 'actionButton': '#15803D', '__discount_rules': {'x': 1}, 'appBg': 'bad'}),
      ));
      expect(parseSchoolAsset(raw), 'MISTER');
      final identity = parseSchoolAssetIdentity(raw)!;
      expect((identity.name, identity.logo), ('مدرسة المستر', 'data:image/png;base64,AA=='));
      expect(identity.colors!.sidebarBg, '#1C3124');
      expect(identity.colors!.actionButton, '#15803D');
      expect(raw.contains('__discount_rules'), isFalse);
      // نسخةٌ أقدم فيها الكود وحده
      expect(parseSchoolAssetIdentity('{"code":"ABC"}'), isNull);
      expect(utf8.decode(schoolAssetBytes('abc')), '{"code":"ABC"}');
    });

    test('ملف النسخة يكفي بلا إنترنت: الاسم والشعار والألوان من أول فتح', () async {
      final brand = SchoolBrand(
        readAsset: () async => '{"code":"ABC","name":"مدرسة النور","logo":"data:image/png;base64,AA==",'
            '"colors":{"sidebarBg":"#052E2B","actionButton":"#059669"}}',
        fetch: (code) async => null,
      );
      await brand.readBundled();
      expect((brand.code, brand.name, brand.colors?.sidebarBg), ('ABC', 'مدرسة النور', '#052E2B'));
    });

    test('كود المدرسة من ملف النسخة', () {
      expect(parseSchoolAsset('{"code":"abc"}'), 'ABC');
      expect(parseSchoolAsset('{}'), isNull);
      expect(parseSchoolAsset('{"code":"a/b"}'), isNull);
      expect(parseSchoolAsset('not json'), isNull);
    });

    test('الهوية تُحمَّل من السحابة بكود النسخة، والنسخة العامة لا تطلبها', () async {
      final asked = <String>[];
      final brand = SchoolBrand(
        readAsset: () async => '{"code":"ABC"}',
        fetch: (code) async {
          asked.add(code);
          return (name: 'مدرسة النور', logo: 'data:image/png;base64,AA==', colors: null);
        },
      );
      await brand.load();
      await Future<void>.delayed(Duration.zero);
      expect((brand.code, brand.name), ('ABC', 'مدرسة النور'));
      expect(asked, ['ABC']);

      final generic = SchoolBrand(readAsset: () async => '{}', fetch: (code) async => throw StateError('no'));
      await generic.load();
      expect((generic.code, generic.name), (null, ''));
    });
  });
}
