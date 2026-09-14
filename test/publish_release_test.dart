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

  group('رقم الإصدار المكتوب', () {
    test('ثلاثة أجزاء بناء، وأربعة تحديث صامت مهما كبر رقمه', () {
      final build = publish.parseRequestedVersion('1.2.8');
      expect(build.kind, publish.PublishKind.build);
      expect(build.base, '1.2.8');
      expect(build.patchNumber, isNull);

      final tenth = publish.parseRequestedVersion('1.2.7.10');
      expect(tenth.kind, publish.PublishKind.patch, reason: 'التحديث العاشر لا يصير بناءً');
      expect(tenth.base, '1.2.7');
      expect(tenth.patchNumber, 10);
    });

    test('ما ليس ثلاثة أجزاء أو أربعة يُرفض', () {
      for (final bad in ['1.2', '1.2.7.0', 'v1.2.7', '1.2.7.1.2', '1.2.x']) {
        expect(() => publish.parseRequestedVersion(bad), throwsArgumentError, reason: bad);
      }
    });

    test('المقارنة جزءاً جزءاً لا نصياً', () {
      expect(publish.compareVersionNames('1.2.10', '1.2.9'), greaterThan(0));
      expect(publish.compareVersionNames('1.3.0', '1.2.99'), greaterThan(0));
      expect(publish.compareVersionNames('1.2.7', '1.2.7'), 0);
      expect('${publish.versionFromName('1.2.8', build: 5)}', '1.2.8+5');
    });

    test('رقم التحديث التالي يُقرأ من مخرجات Shorebird بصيغتيها', () {
      expect(publish.nextPatchNumber('  42  #1  track: stable\n  43  #2  [no track]\n'), 3);
      expect(publish.nextPatchNumber('[{"id":42,"number":1},{"id":43,"number":2}]'), 3);
      expect(
        publish.nextPatchNumber('Git is not configured to allow long paths.\n[{"number": 4}]'),
        5,
        reason: 'تحذيرٌ يسبق JSON لا يُسقط القراءة',
      );
      expect(publish.nextPatchNumber('[]'), 1, reason: 'أول تحديث على الإصدار');
    });

    test('التحديث على غير آخر إصدار أو برقمٍ غير التالي يُرفض بالرقم الصحيح', () {
      expect(publish.patchProblem(base: '1.2.7', number: 3, published: '1.2.7', next: 3), isNull);
      expect(publish.patchProblem(base: '1.2.6', number: 1, published: '1.2.7', next: 3), contains('1.2.7.3'));
      expect(publish.patchProblem(base: '1.2.7', number: 5, published: '1.2.7', next: 3), contains('1.2.7.3'));
    });
  });

  group('أمر البناء', () {
    test('مع Shorebird يُبنى بإصدار Flutter المشروع كي تقبل الأجهزة الـ patches', () {
      final cmd = publish.buildCommand(const publish.PubVersion(1, 2, 7, 2), shorebird: true, flutterVersion: '3.41.6');

      expect(cmd.exe, 'shorebird');
      expect(cmd.args.take(2), ['release', 'android']);
      expect(cmd.args.join(' '), contains('--artifact apk'));
      expect(cmd.args.join(' '), contains('--flutter-version 3.41.6'), reason: 'لا يُبنى بأحدث Flutter لم يُختبر عليه');
      expect(cmd.args.join(' '), contains('--build-name 1.2.7 --build-number 2'));
      expect(cmd.args.join(' '), contains('--target-platform android-arm64'));
    });

    test('بلا Shorebird بناء Flutter العادي', () {
      final cmd = publish.buildCommand(const publish.PubVersion(1, 2, 7, 2), shorebird: false);

      expect(cmd.exe, 'flutter');
      expect(cmd.args.take(3), ['build', 'apk', '--release']);
      expect(cmd.args.join(' '), contains('--build-name 1.2.7 --build-number 2'));
    });

    test('إصدار Flutter يُقرأ من مخرجات flutter --version', () {
      expect(publish.flutterVersionOf('Flutter 3.41.6 • channel stable • https://github.com/flutter/flutter.git'), '3.41.6');
      expect(publish.flutterVersionOf('command not found'), isNull);
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
