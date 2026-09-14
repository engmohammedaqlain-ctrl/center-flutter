import 'dart:convert';
import 'dart:io';

import 'package:center_mobile/data/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/publish_release.dart' as publish;

void main() {
  group('رقم الإصدار', () {
    test('رقم البناء يزيد مع أي جزء يُرفع', () {
      const v = publish.PubVersion(1, 0, 3, 7);

      expect('${publish.bumpVersion(v, 'patch')}', '1.0.4+8');
      expect('${publish.bumpVersion(v, 'minor')}', '1.1.0+8');
      expect('${publish.bumpVersion(v, 'major')}', '2.0.0+8');
      expect(() => publish.bumpVersion(v, 'none'), throwsArgumentError, reason: 'وسمٌ مكرر لا يُنشر');
    });

    test('يُقرأ ويُكتب في pubspec ولا يمسّ بقية الملف', () {
      const pubspec = 'name: center_mobile\r\ndescription: x\r\nversion: 1.0.0+1\r\n\r\nenvironment:\r\n';
      final v = publish.parsePubspecVersion(pubspec)!;
      expect('$v', '1.0.0+1');

      final written = publish.writePubspecVersion(pubspec, publish.bumpVersion(v, 'patch'));
      expect(written, pubspec.replaceFirst('1.0.0+1', '1.0.1+2'), reason: 'نهايات الأسطر كما كُتبت');
    });

    test('سطرٌ بلا رقم بناء لا يُقرأ، وملف المشروع يُقرأ', () {
      expect(publish.parsePubspecVersion('name: x\nversion: 1.0.0\n'), isNull);
      expect(publish.parsePubspecVersion(File('pubspec.yaml').readAsStringSync()), isNotNull);
    });
  });

  group('أقدم إصدار مدعوم', () {
    test('بلا قيمة يُورَث من الإصدار السابق', () {
      expect(publish.resolveMinSupported(null, previous: 3, current: 6), 3);
      expect(publish.resolveMinSupported('  ', previous: 3, current: 6), 3);
    });

    test('current يُلزم كل ما قبل هذا الإصدار، والرقم الصريح يُؤخذ كما هو', () {
      expect(publish.resolveMinSupported('current', previous: 3, current: 6), 6);
      expect(publish.resolveMinSupported('4', previous: 3, current: 6), 4);
    });

    test('ما يتجاوز الإصدار نفسه أو ليس رقماً يُرفض', () {
      // حدٌّ أعلى من الإصدار المنشور يحجب حتى من ثبّته
      expect(() => publish.resolveMinSupported('7', previous: 3, current: 6), throwsArgumentError);
      expect(() => publish.resolveMinSupported('أحدث', previous: 3, current: 6), throwsArgumentError);
    });
  });

  group('ملف الوصف', () {
    test('ما ينشره السكربت يقرؤه التطبيق بالحقول نفسها', () {
      const next = publish.PubVersion(1, 0, 1, 2);
      final manifest = publish.buildManifest(
        version: next,
        sha256: 'AB' * 32,
        sizeBytes: 25 * 1024 * 1024,
        notes: '  إصلاح حساب الرصيد\nوتحسين المزامنة\n',
        minSupported: 1,
        mandatory: false,
        publishedAt: DateTime.utc(2026, 9, 14),
      );

      // عبر JSON كما يصل الأجهزة فعلاً
      final release = AppRelease.fromJson(jsonDecode(jsonEncode(manifest)))!;
      expect(release.versionName, '1.0.1');
      expect(release.versionCode, 2);
      expect(release.apkUrl, publish.apkUrlFor(next));
      expect(release.sha256, 'ab' * 32);
      expect(release.sizeBytes, 25 * 1024 * 1024);
      expect(release.notes, 'إصلاح حساب الرصيد\nوتحسين المزامنة');
      expect(release.minSupported, 1);

      expect(decideUpdate(installed: 1, release: release), UpdateAction.optional);
      expect(decideUpdate(installed: 2, release: release), UpdateAction.none);
    });

    test('التطبيق يقرأ من الرابط الذي ينشر عليه السكربت', () {
      expect(releaseManifestUrl, publish.latestManifestUrl);
      expect(
        publish.apkUrlFor(const publish.PubVersion(1, 0, 1, 2)),
        'https://github.com/engmohammedaqlain-ctrl/center-mobile-releases/releases/download/v1.0.1/center-1.0.1.apk',
      );
    });
  });

  test('بصمة الموقّع تُقرأ من مخرجات apksigner', () {
    const output = 'Verifies\n'
        'Verified using v2 scheme (APK Signature Scheme v2): true\n'
        'Signer #1 certificate DN: CN=mohammed abu aqlain, OU=noon, O=noon, L=gaza, ST=gaza, C=97\n'
        'Signer #1 certificate SHA-256 digest: D7A0B1D7C5BCFEA9346AB61DB35C8E96FD2D042C270A06DC8E23E3A1E5302AC8\n'
        'Signer #1 certificate SHA-1 digest: 0011\n';

    expect(publish.signerDigest(output), publish.expectedCertSha256);
    expect(publish.signerDigest('DOES NOT VERIFY'), isNull);
  });
}
