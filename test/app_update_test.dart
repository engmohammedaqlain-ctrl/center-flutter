import 'dart:convert';

import 'package:center_mobile/data/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _manifest({
  int versionCode = 5,
  int minSupported = 0,
  bool mandatory = false,
}) =>
    {
      'version': '1.2.0',
      'versionCode': versionCode,
      'minSupported': minSupported,
      'mandatory': mandatory,
      'apkUrl': 'https://example.test/center-1.2.0.apk',
      'notes': 'بوابة ولي الأمر',
      'sha256': 'ABCDEF',
      'sizeBytes': 21 * 1024 * 1024,
    };

void main() {
  group('قرار التحديث', () {
    test('الأحدث يُعرض، والمثبَّت الأحدث أو المساوي لا شيء له', () {
      final release = AppRelease.fromJson(_manifest(versionCode: 5));

      expect(decideUpdate(installed: 4, release: release), UpdateAction.optional);
      expect(decideUpdate(installed: 5, release: release), UpdateAction.none);
      expect(decideUpdate(installed: 6, release: release), UpdateAction.none, reason: 'نسخة تطوير أحدث');
    });

    test('ما دون الحد الأدنى يُلزَم ولو لم يُعلن الناشر الإلزام', () {
      // هجرة قاعدة تكسر التوافق: القديم يفشل بصمت، فالإلزام أصدق من تركه يعمل
      final release = AppRelease.fromJson(_manifest(versionCode: 5, minSupported: 4));

      expect(decideUpdate(installed: 3, release: release), UpdateAction.mandatory);
      expect(decideUpdate(installed: 4, release: release), UpdateAction.optional);
    });

    test('الإلزام الصريح يرفع الاختياري إلى إلزامي', () {
      final release = AppRelease.fromJson(_manifest(versionCode: 5, mandatory: true));
      expect(decideUpdate(installed: 4, release: release), UpdateAction.mandatory);
      expect(decideUpdate(installed: 5, release: release), UpdateAction.none, reason: 'هو المثبَّت أصلاً');
    });

    test('بلا وصف لا قرار', () {
      expect(decideUpdate(installed: 1, release: null), UpdateAction.none);
    });
  });

  group('قراءة ملف الوصف', () {
    test('الحقول تُقرأ كما نُشرت', () {
      final release = AppRelease.fromJson(_manifest())!;

      expect(release.versionName, '1.2.0');
      expect(release.versionCode, 5);
      expect(release.notes, 'بوابة ولي الأمر');
      expect(release.sha256, 'abcdef', reason: 'تُقارن البصمة بحروف صغيرة');
      expect(release.sizeLabel, '21.0 م.ب');
    });

    test('وصفٌ بلا رابط أو بلا رقم إصدار يُتجاهل', () {
      expect(AppRelease.fromJson({..._manifest(), 'apkUrl': ''}), isNull);
      expect(AppRelease.fromJson({..._manifest(), 'versionCode': 0}), isNull);
      expect(AppRelease.fromJson('نص لا كائن'), isNull);
      expect(AppRelease.fromJson(null), isNull);
    });
  });

  group('جلب الوصف من الاستضافة', () {
    test('يُقرأ الوصف المنشور', () async {
      final release = await fetchLatestRelease(
        'https://example.test/mobile-latest.json',
        client: MockClient((_) async => http.Response(
              jsonEncode(_manifest()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

      expect(release?.versionCode, 5);
      expect(release?.notes, 'بوابة ولي الأمر', reason: 'العربية تُقرأ بترميزها');
    });

    test('انقطاعٌ أو ملفٌ تالف أو رابط فارغ: لا شيء، والتطبيق يكمل عمله', () async {
      expect(
        await fetchLatestRelease('https://example.test/x.json',
            client: MockClient((_) async => throw http.ClientException('offline'))),
        isNull,
      );
      expect(
        await fetchLatestRelease('https://example.test/x.json',
            client: MockClient((_) async => http.Response('<html>404</html>', 404))),
        isNull,
      );
      expect(
        await fetchLatestRelease('https://example.test/x.json',
            client: MockClient((_) async => http.Response('ليس JSON', 200))),
        isNull,
      );
      expect(await fetchLatestRelease('   '), isNull);
    });
  });
}
