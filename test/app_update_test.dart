import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:center_mobile/data/app_update.dart';
import 'package:center_mobile/data/download_notification.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// حزمة وهمية بمحتوى معروف تُحسب بصمتها.
List<int> _apk([int length = 3000]) => List<int>.generate(length, (i) => i % 251);

String _sha(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// وصفٌ يطابق الحزمة الوهمية فعلاً.
Map<String, dynamic> _manifestFor(List<int> bytes) => {..._manifest(), 'sha256': _sha(bytes), 'sizeBytes': bytes.length};

AppRelease _release(List<int> bytes, {int code = 5, String? hash}) => AppRelease(
      versionName: '1.2.0',
      versionCode: code,
      apkUrl: 'https://example.test/center-1.2.0.apk',
      sha256: hash ?? _sha(bytes),
      sizeBytes: bytes.length,
    );

/// حزمةٌ تتجاوز حدّ التقسيم، فتُطلب على عدة اتصالات.
const _big = 5 * 1024 * 1024;

/// ما يقابل ترويسة `Range` من الحزمة.
List<int> _slice(List<int> bytes, String header) {
  final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header)!;
  final from = int.parse(m.group(1)!);
  final to = m.group(2)!.isEmpty ? bytes.length - 1 : int.parse(m.group(2)!);
  return bytes.sublist(from, to + 1);
}

/// استضافةٌ تقبل النطاقات كما تفعل استضافة الإصدارات.
MockClient _rangeServer(List<int> bytes, {void Function(String?)? onRange}) =>
    MockClient.streaming((request, _) async {
      final header = request.headers['Range'] ?? request.headers['range'];
      onRange?.call(header);
      if (header == null) {
        return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
      }
      final slice = _slice(bytes, header);
      return http.StreamedResponse(Stream.value(slice), 206, contentLength: slice.length);
    });

/// وصفٌ وحزمة معاً على خادمٍ واحد.
http.Client Function() _apkServer(List<int> bytes) => () => MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('.json')) return _json(_manifestFor(bytes));
      return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
    });

class _FakeNotifier implements DownloadNotifier {
  final shown = <String>[];
  int hidden = 0;
  int finished = 0;

  @override
  Future<void> show(String text, {int percent = -1, String title = ''}) async => shown.add(text);

  @override
  Future<void> finish(String text, {String title = ''}) async => finished++;

  @override
  Future<void> hide() async => hidden++;
}

/// يقدّم الحزمة على دفعات كما تصل من الشبكة.
MockClient _serving(List<int> bytes, {void Function()? onRequest}) => MockClient.streaming((request, _) async {
      onRequest?.call();
      final chunks = [
        for (var i = 0; i < bytes.length; i += 1000) bytes.sublist(i, math.min(i + 1000, bytes.length)),
      ];
      return http.StreamedResponse(Stream.fromIterable(chunks), 200, contentLength: bytes.length);
    });

http.Client Function() _manifestServer(Map<String, dynamic> manifest, {void Function()? onRequest}) =>
    () => MockClient((_) async {
          onRequest?.call();
          return http.Response(
            jsonEncode(manifest),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

http.Client Function() _offline() => () => MockClient((_) async => throw http.ClientException('offline'));

http.StreamedResponse _json(Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
}

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('center_update_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

/// مصدر تحديثات صامتة وهمي — محرّك Shorebird لا يوجد في الاختبارات.
class _FakePatches implements PatchSource {
  _FakePatches(this.statuses, {this.available = true});

  final List<PatchStatus> statuses;
  final bool available;
  bool fail = false;
  int downloads = 0;
  int checks = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<PatchStatus> status() async {
    checks++;
    return statuses.length > 1 ? statuses.removeAt(0) : statuses.first;
  }

  @override
  Future<void> download() async {
    downloads++;
    if (fail) throw Exception('offline');
  }
}

AppUpdater _updater({
  required Directory dir,
  required http.Client Function() client,
  int installed = 4,
  DateTime Function()? clock,
  Future<String?> Function(String path)? installer,
  PatchSource? patches,
  DownloadNotifier? notifier,
}) =>
    AppUpdater(
      supported: true,
      manifestUrl: 'https://example.test/mobile-latest.json',
      installedVersion: () async => (code: installed, name: '1.1.0'),
      downloadDir: () async => dir,
      openInstaller: installer ?? (_) async => null,
      client: client,
      clock: clock,
      patches: patches ?? _FakePatches([PatchStatus.upToDate]),
      notifier: notifier ?? const SilentDownloadNotifier(),
      // العدّ التنازلي بين المحاولات لا ينتظر ثوانٍ حقيقية
      wait: (_) async {},
    );

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

    test('الوصف يُحفظ ويُقرأ كما هو', () {
      final release = AppRelease.fromJson(_manifest(minSupported: 3, mandatory: true))!;
      final again = AppRelease.fromJson(jsonDecode(jsonEncode(release.toJson())))!;

      expect(again.versionCode, release.versionCode);
      expect(again.minSupported, 3);
      expect(again.mandatory, isTrue);
      expect(again.apkUrl, release.apkUrl);
      expect(again.sha256, release.sha256);
      expect(again.sizeBytes, release.sizeBytes);
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

  group('عرض الأرقام', () {
    test('سرعةٌ دون الميجابايت تُكتب بالكيلوبايت لا صفراً', () {
      expect(perSecond(300 * 1024), '300 ك.ب/ث');
      expect(perSecond(3.5 * 1024 * 1024), '3.5 م.ب/ث');
    });
  });

  group('تنزيل الحزمة', () {
    test('تُنزَّل على دفعات وتُطابَق بصمتها ثم تُسمّى باسمها', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      final seen = <int>[];

      final file = await downloadRelease(
        _release(bytes),
        dir,
        client: _serving(bytes),
        onProgress: (got, total) {
          seen.add(got);
          expect(total, bytes.length);
        },
      );

      expect(await file.readAsBytes(), bytes);
      expect(file.path, endsWith('center-5.apk'));
      expect(seen.last, bytes.length);
      expect(File('${file.path}.part').existsSync(), isFalse);
    });

    test('بصمةٌ لا تطابق: لا يُترك ملفٌ يبدو صالحاً', () async {
      final dir = await _tempDir();
      final bytes = _apk();

      await expectLater(
        downloadRelease(_release(bytes, hash: 'ff' * 32), dir, client: _serving(bytes)),
        throwsA(isA<UpdateException>().having((e) => e.retryable, 'retryable', isFalse)),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('انقطاعٌ في منتصف التنزيل يُبقي ما وصل ليُستكمل منه', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      final client = MockClient.streaming((_, _) async {
        final body = Stream<List<int>>.multi((out) {
          out.add(bytes.sublist(0, 1000));
          out.addError(http.ClientException('connection lost'));
          out.close();
        });
        return http.StreamedResponse(body, 200, contentLength: bytes.length);
      });

      await expectLater(
        downloadRelease(_release(bytes), dir, client: client),
        throwsA(isA<UpdateException>().having((e) => e.retryable, 'retryable', isTrue)),
      );
      expect(await partialBytes(_release(bytes), dir), 1000, reason: 'ما نزل لا يُرمى');
      expect(File('${dir.path}/center-5.apk').existsSync(), isFalse, reason: 'لا حزمة ناقصة باسمها النهائي');
    });

    test('الاستكمال يطلب ما بقي وحده ويُتمّ الملف', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      File('${dir.path}/center-5.apk.part').writeAsBytesSync(bytes.sublist(0, 1000));
      String? range;
      final seen = <int>[];
      final client = MockClient.streaming((request, _) async {
        range = request.headers['Range'] ?? request.headers['range'];
        final rest = bytes.sublist(1000);
        return http.StreamedResponse(Stream.value(rest), 206, contentLength: rest.length);
      });

      final file = await downloadRelease(_release(bytes), dir, client: client, onProgress: (got, _) => seen.add(got));

      expect(range, 'bytes=1000-');
      expect(seen.first, 1000, reason: 'النسبة تبدأ مما نزل لا من الصفر');
      expect(await file.readAsBytes(), bytes);
    });

    test('خادمٌ يتجاهل النطاق فيعيد الملف كاملاً: يُكتب من أوله', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      File('${dir.path}/center-5.apk.part').writeAsBytesSync(List.filled(1000, 7));

      final file = await downloadRelease(_release(bytes), dir, client: _serving(bytes));

      expect(await file.readAsBytes(), bytes, reason: 'لا يُلصق الملف الكامل خلف جزءٍ قديم');
    });

    test('رابطٌ لا يوجد: رسالة لا استثناء خام، ولا إعادة محاولة بلا جدوى', () async {
      final dir = await _tempDir();
      await expectLater(
        downloadRelease(_release(_apk()), dir, client: MockClient((_) async => http.Response('', 404))),
        throwsA(isA<UpdateException>()
            .having((e) => e.message, 'message', contains('404'))
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });

    test('حزمةٌ نُزّلت وتحقّقت تُعاد بلا شبكة', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      var requests = 0;
      await downloadRelease(_release(bytes), dir, client: _serving(bytes, onRequest: () => requests++));

      final again = await downloadRelease(
        _release(bytes),
        dir,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      expect(await again.readAsBytes(), bytes);
      expect(requests, 1);
    });
  });

  group('تنزيل حزمة كبيرة على عدة اتصالات', () {
    test('تُطلب نطاقاتٍ متوازية وتُلصق بترتيبها، ولا تبقى ملفاتها', () async {
      final dir = await _tempDir();
      final bytes = _apk(_big);
      final ranges = <String?>[];

      final file = await downloadRelease(_release(bytes), dir, client: _rangeServer(bytes, onRange: ranges.add));

      expect(await file.readAsBytes(), bytes, reason: 'النطاقات تُلصق بترتيبها لا بترتيب وصولها');
      expect(ranges.length, greaterThan(1), reason: 'اتصالٌ واحد لا يملأ خطاً سريعاً');
      expect(ranges.every((r) => r != null && r.startsWith('bytes=')), isTrue);
      expect(dir.listSync().map((e) => e.path), [file.path], reason: 'لا يبقى نطاقٌ ولا ملف مؤقت');
    });

    test('مجموع النطاقات هو ما يُعرض من التقدّم، ويصل إلى الحجم كاملاً', () async {
      final dir = await _tempDir();
      final bytes = _apk(_big);
      final seen = <int>[];

      await downloadRelease(
        _release(bytes),
        dir,
        client: _rangeServer(bytes),
        onProgress: (got, total) {
          seen.add(got);
          expect(total, bytes.length);
        },
      );

      expect(seen.last, bytes.length);
      expect(seen.reduce(math.max), bytes.length, reason: 'لا نسبة تتجاوز المئة');
    });

    test('انقطاعُ نطاقٍ لا يُضيّع ما نزل من غيره', () async {
      final dir = await _tempDir();
      final bytes = _apk(_big);
      var calls = 0;
      final client = MockClient.streaming((request, _) async {
        final slice = _slice(bytes, request.headers['Range']!);
        // نطاقٌ واحد يُقطع في منتصفه، وبقيّتها تصل كاملة
        if (++calls == 3) {
          final body = Stream<List<int>>.multi((out) {
            out.add(slice.sublist(0, 100));
            out.addError(http.ClientException('connection lost'));
            out.close();
          });
          return http.StreamedResponse(body, 206, contentLength: slice.length);
        }
        return http.StreamedResponse(Stream.value(slice), 206, contentLength: slice.length);
      });

      await expectLater(
        downloadRelease(_release(bytes), dir, client: client),
        throwsA(isA<UpdateException>().having((e) => e.retryable, 'retryable', isTrue)),
      );
      final kept = await partialBytes(_release(bytes), dir);
      expect(kept, greaterThan(bytes.length ~/ 2), reason: 'ما نزل من النطاقات السليمة لا يُرمى');
      expect(kept, lessThan(bytes.length));

      var asked = 0;
      final file = await downloadRelease(
        _release(bytes),
        dir,
        client: _rangeServer(bytes, onRange: (r) => asked += _slice(bytes, r!).length),
      );

      expect(await file.readAsBytes(), bytes);
      expect(asked, bytes.length - kept, reason: 'يُطلب ما بقي وحده');
    });

    test('استضافةٌ لا تقبل النطاقات: اتصالٌ واحد من أوله', () async {
      final dir = await _tempDir();
      final bytes = _apk(_big);
      var requests = 0;

      final file = await downloadRelease(
        _release(bytes),
        dir,
        client: MockClient.streaming((_, _) async {
          requests++;
          return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
        }),
      );

      expect(await file.readAsBytes(), bytes);
      expect(requests, 1, reason: 'لا ستة اتصالات كلٌّ يجرّ الملف كاملاً');
    });
  });

  group('إشعار التنزيل', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('يبدأ مع التنزيل ويُرفع بعد أن يُفتح المثبِّت', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      final notifier = _FakeNotifier();
      final updater = _updater(dir: dir, client: _apkServer(bytes), notifier: notifier);

      await updater.start();
      await updater.install();

      expect(notifier.shown, isNotEmpty, reason: 'التنزيل خارج التطبيق يحتاج خدمةً في المقدمة');
      expect(notifier.shown.first, contains('جارِ تنزيل التحديث'));
      expect(notifier.hidden, 1);
      expect(notifier.finished, 0);
    });

    test('اكتمل والمستخدم في تطبيقٍ آخر: إشعارٌ ينتظره ولا مثبِّت يُفتح', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      final notifier = _FakeNotifier();
      var opened = 0;
      final updater = _updater(
        dir: dir,
        client: _apkServer(bytes),
        notifier: notifier,
        installer: (_) async {
          opened++;
          return null;
        },
      )..inForeground = false;

      await updater.start();
      await updater.install();

      expect(opened, 0, reason: 'أندرويد يمنع فتح نافذةٍ من الخلفية فتضيع بلا أثر');
      expect(notifier.finished, 1);
      expect(updater.phase, UpdatePhase.ready);
    });

    test('انقطاعٌ يُنهي التنزيل يرفع الإشعار', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      final notifier = _FakeNotifier();
      http.Client server() => MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('.json')) return _json(_manifestFor(bytes));
            throw http.ClientException('offline');
          });
      final updater = _updater(dir: dir, client: server, notifier: notifier);

      await updater.start();
      await updater.install();

      expect(updater.phase, UpdatePhase.paused);
      expect(notifier.hidden, 1, reason: 'إشعارٌ ثابت بلا تنزيلٍ يعمل خلفه');
    });
  });

  group('حالة التحديث على الجهاز', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('الإلزام يبقى معروفاً بعد إعادة التشغيل بلا إنترنت', () async {
      final dir = await _tempDir();
      final online = _updater(dir: dir, installed: 3, client: _manifestServer(_manifest(minSupported: 4)));
      await online.start();
      expect(online.action, UpdateAction.mandatory);

      final offline = _updater(dir: dir, installed: 3, client: _offline());
      await offline.start();
      expect(offline.action, UpdateAction.mandatory, reason: 'آخر وصفٍ وصل محفوظ على الجهاز');
      expect(offline.error, isNull, reason: 'الفحص التلقائي يصمت عند الانقطاع');
    });

    test('الإصدار المثبَّت المجهول لا يُحجب', () async {
      final dir = await _tempDir();
      final updater = _updater(dir: dir, installed: 0, client: _manifestServer(_manifest(minSupported: 4)));
      await updater.start();
      expect(updater.action, UpdateAction.none);
    });

    test('لا يُعاد الفحص قبل ساعة إلا يدوياً أو عند الإقلاع', () async {
      final dir = await _tempDir();
      var requests = 0;
      var now = DateTime(2026, 9, 14, 8);
      final updater = _updater(
        dir: dir,
        clock: () => now,
        client: _manifestServer(_manifest(), onRequest: () => requests++),
      );

      await updater.start();
      expect(requests, 1);

      now = now.add(const Duration(minutes: 20));
      await updater.check();
      expect(requests, 1, reason: 'العودة إلى التطبيق كل دقيقة لا تطرق الخادم كل مرة');

      await updater.check(force: true);
      expect(requests, 2, reason: 'من ضغط «فحص التحديثات» يريد جواباً الآن');

      now = now.add(const Duration(hours: 2));
      await updater.check();
      expect(requests, 3);
    });

    test('الإقلاع يفحص ولو كان آخر فحص قبل دقائق', () async {
      final dir = await _tempDir();
      var requests = 0;
      var now = DateTime(2026, 9, 14, 8);
      final first = _updater(
        dir: dir,
        clock: () => now,
        client: _manifestServer(_manifest(versionCode: 5), onRequest: () => requests++),
      );
      await first.start();
      expect(requests, 1);

      now = now.add(const Duration(minutes: 10));
      requests = 0;
      final again = _updater(
        dir: dir,
        clock: () => now,
        client: _manifestServer(_manifest(versionCode: 6), onRequest: () => requests++),
      );
      await again.start();
      expect(requests, 1, reason: 'إصدار نُشر بعد فتحٍ سابق يظهر فوراً');
      expect(again.action, UpdateAction.optional);
      expect(again.release?.versionCode, 6);
    });

    test('فشل الفحص لا يمنع إعادة المحاولة عند الإقلاع', () async {
      final dir = await _tempDir();
      var now = DateTime(2026, 9, 14, 8);
      final fail = _updater(dir: dir, clock: () => now, client: _offline());
      await fail.start();
      expect(fail.lastChecked, isNull, reason: 'الفشل لا يُثبِّت وقت الفحص');

      var requests = 0;
      final ok = _updater(
        dir: dir,
        clock: () => now,
        client: _manifestServer(_manifest(versionCode: 5), onRequest: () => requests++),
      );
      await ok.start();
      expect(requests, 1);
      expect(ok.release?.versionCode, 5);
    });

    test('الفحص اليدوي يقول إن الاتصال تعذّر', () async {
      final dir = await _tempDir();
      final updater = _updater(dir: dir, client: _offline());
      await updater.start();
      expect(updater.error, isNull);

      await updater.check(force: true);
      expect(updater.error, contains('تعذّر'));
    });

    test('التحديث الاختياري يُعرض عند كل فتح، والتأجيل لجلسته وحدها', () async {
      final dir = await _tempDir();
      final first = _updater(dir: dir, client: _manifestServer(_manifest(versionCode: 5)));
      await first.start();
      expect(first.shouldPrompt, isTrue);

      await first.dismiss();
      expect(first.shouldPrompt, isFalse, reason: 'لا يُعاد عرضه وهو مفتوح');

      final restarted = _updater(dir: dir, client: _manifestServer(_manifest(versionCode: 5)));
      await restarted.start();
      expect(restarted.shouldPrompt, isTrue, reason: 'فتحٌ جديد يُذكّر به من جديد');
      expect(restarted.action, UpdateAction.optional);
    });

    test('الإلزامي لا يُعرض ورقةً تُؤجَّل', () async {
      final dir = await _tempDir();
      final updater = _updater(dir: dir, client: _manifestServer(_manifest(mandatory: true)));
      await updater.start();
      expect(updater.action, UpdateAction.mandatory);
      expect(updater.shouldPrompt, isFalse, reason: 'تحجبه شاشة كاملة لا ورقة');
    });

    test('التثبيت ينزّل الحزمة ويتحقق منها ثم يفتح المثبِّت', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      http.Client server() => MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('.json')) return _json(_manifestFor(bytes));
            return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
          });
      String? opened;
      final phases = <UpdatePhase>{};
      final updater = _updater(
        dir: dir,
        client: server,
        installer: (path) async {
          opened = path;
          return null;
        },
      );
      updater.addListener(() => phases.add(updater.phase));

      await updater.start();
      await updater.install();

      expect(phases, containsAll([UpdatePhase.downloading, UpdatePhase.verifying]), reason: 'التحقق يُعرض بعد التنزيل');
      expect(updater.phase, UpdatePhase.ready);
      expect(updater.error, isNull);
      expect(opened, endsWith('center-5.apk'));
      expect(await File(opened!).readAsBytes(), bytes);
    });

    test('انقطاعٌ متكرر: محاولاتٌ بعدٍّ تنازلي ثم توقفٌ يُستكمل', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      var apkRequests = 0;
      final phases = <UpdatePhase>{};
      http.Client server() => MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('.json')) return _json(_manifestFor(bytes));
            apkRequests++;
            throw http.ClientException('offline');
          });
      final updater = _updater(dir: dir, client: server);
      updater.addListener(() => phases.add(updater.phase));

      await updater.start();
      await updater.install();

      expect(apkRequests, AppUpdater.maxAttempts);
      expect(phases, contains(UpdatePhase.retrying), reason: 'العدّ التنازلي يُعرض بين المحاولات');
      expect(updater.phase, UpdatePhase.paused, reason: 'يتوقف بانتظار المستخدم بدل استنزاف البطارية');
      expect(updater.error, contains('انقطع'));
    });

    test('يعود الاتصال فتستكمل المحاولة التالية مما نزل ويُفتح المثبِّت', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      var attempts = 0;
      final ranges = <String?>[];
      http.Client server() => MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('.json')) return _json(_manifestFor(bytes));
            attempts++;
            final range = request.headers['Range'] ?? request.headers['range'];
            ranges.add(range);
            if (attempts == 1) {
              final body = Stream<List<int>>.multi((out) {
                out.add(bytes.sublist(0, 1000));
                out.addError(http.ClientException('connection lost'));
                out.close();
              });
              return http.StreamedResponse(body, 200, contentLength: bytes.length);
            }
            final start = int.parse(range!.substring('bytes='.length, range.length - 1));
            final rest = bytes.sublist(start);
            return http.StreamedResponse(Stream.value(rest), 206, contentLength: rest.length);
          });
      String? opened;
      final updater = _updater(
        dir: dir,
        client: server,
        installer: (path) async {
          opened = path;
          return null;
        },
      );

      await updater.start();
      await updater.install();

      expect(attempts, 2);
      expect(ranges.last, 'bytes=1000-', reason: 'لا يُعاد تنزيل ما نزل قبل الانقطاع');
      expect(opened, endsWith('center-5.apk'));
      expect(await File(opened!).readAsBytes(), bytes);
    });

    test('تنزيلٌ أُغلق التطبيق في منتصفه يُعرض متوقفاً عند نسبته', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      SharedPreferences.setMockInitialValues({
        'app_update_release': jsonEncode(AppRelease.fromJson(_manifestFor(bytes))!.toJson()),
      });
      File('${dir.path}/center-5.apk.part').writeAsBytesSync(bytes.sublist(0, 1500));

      final updater = _updater(dir: dir, client: _offline());
      await updater.start();

      expect(updater.phase, UpdatePhase.paused, reason: 'يُعرض ليُستكمل لا يُنسى');
      expect(updater.received, 1500);
      expect(updater.progress, closeTo(0.5, 0.001));
    });

    test('تعذّر فتح المثبِّت يُعرض سببه', () async {
      final dir = await _tempDir();
      final bytes = _apk();
      http.Client server() => MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('.json')) return _json(_manifestFor(bytes));
            return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
          });
      final updater = _updater(dir: dir, client: server, installer: (_) async => 'اسمح للتطبيق بالتثبيت');

      await updater.start();
      await updater.install();

      expect(updater.error, 'اسمح للتطبيق بالتثبيت');
    });

    test('القرار مجهول قبل قراءة المحفوظ: الإقلاع ينتظره فلا يقلب واجهتين', () async {
      final dir = await _tempDir();
      final updater = _updater(dir: dir, client: _offline());

      expect(updater.loaded, isFalse);
      await updater.start();
      expect(updater.loaded, isTrue);
    });

    test('بلا نت لا يعلّق الإقلاع: البوابة تُفتح من المحفوظ خلال المهلة', () async {
      final dir = await _tempDir();
      // طلب لا يكتمل يحاكي انقطاعاً بطيئاً — بلا مهلة كان الإقلاع ينتظر ثوانٍ طويلة
      final pending = Completer<http.Response>();
      final updater = _updater(
        dir: dir,
        client: () => MockClient((_) => pending.future),
      );

      final sw = Stopwatch()..start();
      await updater.start();
      sw.stop();

      expect(updater.loaded, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(updater.action, UpdateAction.none);

      // إنهاء الطلب المعلّق حتى لا يبقى مؤقّت عالقاً بعد الاختبار
      pending.completeError(http.ClientException('offline'));
      await Future<void>.delayed(Duration.zero);
    });

    test('حزم الإصدارات المثبَّتة تُحذف عند الإقلاع', () async {
      final dir = await _tempDir();
      for (final code in [3, 4, 5]) {
        File('${dir.path}/center-$code.apk').writeAsBytesSync([1, 2, 3]);
      }

      final updater = _updater(dir: dir, installed: 4, client: _offline());
      await updater.start();

      expect(File('${dir.path}/center-3.apk').existsSync(), isFalse);
      expect(File('${dir.path}/center-4.apk').existsSync(), isFalse, reason: 'هو المثبَّت الآن');
      expect(File('${dir.path}/center-5.apk').existsSync(), isTrue, reason: 'لم يُثبَّت بعد');
    });

    test('على غير أندرويد لا شيء يُفحص', () async {
      final updater = AppUpdater(supported: false, client: () => throw StateError('لا شبكة في هذا الاختبار'));
      await updater.start();
      expect(await updater.check(force: true), UpdateAction.none);
      expect(updater.action, UpdateAction.none);
    });
  });

  group('التحديث الصامت', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('الإقلاع ينزّل التحديث الصامت تلقائياً بلا فتح الورقة', () async {
      final dir = await _tempDir();
      final patches = _FakePatches([PatchStatus.available]);
      final updater = _updater(dir: dir, client: _offline(), patches: patches);
      final seen = <PatchPhase>[];
      updater.addListener(() {
        if (seen.isEmpty || seen.last != updater.patchPhase) seen.add(updater.patchPhase);
      });

      await updater.start();
      // start يطلق checkPatch في الخلفية — ننتظر نفس العملية
      await updater.checkPatch();

      expect(seen, containsAllInOrder([PatchPhase.downloading, PatchPhase.ready]));
      expect(patches.downloads, 1);
      expect(patches.checks, 1);
    });

    test('تحديثٌ متاح يُنزَّل في الخلفية ثم ينتظر فتح التطبيق التالي', () async {
      final dir = await _tempDir();
      final patches = _FakePatches([PatchStatus.available]);
      final updater = _updater(dir: dir, client: _offline(), patches: patches);
      final seen = <PatchPhase>[];
      updater.addListener(() {
        if (seen.isEmpty || seen.last != updater.patchPhase) seen.add(updater.patchPhase);
      });

      await updater.start();
      await updater.checkPatch();

      expect(seen, containsAllInOrder([PatchPhase.downloading, PatchPhase.ready]));
      expect(patches.downloads, 1);
    });

    test('نزل من قبل وينتظر إعادة الفتح: لا تنزيل جديد', () async {
      final dir = await _tempDir();
      final patches = _FakePatches([PatchStatus.awaitingRestart]);
      final updater = _updater(dir: dir, client: _offline(), patches: patches);

      await updater.start();
      await updater.checkPatch();

      expect(updater.patchPhase, PatchPhase.ready);
      expect(patches.downloads, 0);
    });

    test('انقطاعٌ أثناء التحديث الصامت لا يُظهر خطأ، ويُعاد عند العودة', () async {
      final dir = await _tempDir();
      final patches = _FakePatches([PatchStatus.available])..fail = true;
      final updater = _updater(dir: dir, client: _offline(), patches: patches);

      await updater.start();
      await updater.checkPatch();
      expect(updater.patchPhase, PatchPhase.none);
      expect(updater.error, isNull, reason: 'التحديث الصامت لا يُقلق المستخدم برسالة');

      patches.fail = false;
      final before = patches.downloads;
      // بعد فشل صامت لا يُعاد فوراً عند كل لمسة — force كفتح يدوي / مهلة منتهية
      await updater.checkPatch(force: true);
      expect(updater.patchPhase, PatchPhase.ready, reason: 'إعادة المحاولة بعد الفشل');
      expect(patches.downloads, before + 1, reason: 'محاولة واحدة عند الإعادة');
    });

    test('فاصل الثلاثين دقيقة يمنع إعادة الفحص التلقائي', () async {
      var now = DateTime.utc(2026, 1, 1, 12);
      final dir = await _tempDir();
      final patches = _FakePatches([PatchStatus.upToDate]);
      final updater = _updater(dir: dir, client: _offline(), patches: patches, clock: () => now);

      await updater.start();
      await updater.checkPatch();
      expect(patches.checks, 1);

      await updater.checkPatch();
      expect(patches.checks, 1, reason: 'قبل انتهاء الفاصل لا يُعاد الفحص');

      now = now.add(AppUpdater.patchCheckEvery);
      await updater.checkPatch();
      expect(patches.checks, 2, reason: 'بعد الفاصل يُفحص مجدداً');
    });

    test('لا تحديث صامت: لا شيء يُعرض', () async {
      final dir = await _tempDir();
      final updater = _updater(dir: dir, client: _offline(), patches: _FakePatches([PatchStatus.upToDate]));

      await updater.start();
      await updater.checkPatch();

      expect(updater.patchPhase, PatchPhase.none);
    });

    test('نسخةٌ بلا محرّك Shorebird لا تُسأل', () async {
      final dir = await _tempDir();
      final patches = _FakePatches([PatchStatus.available], available: false);
      final updater = _updater(dir: dir, client: _offline(), patches: patches);

      await updater.start();
      await updater.checkPatch(force: true);

      expect(patches.checks, 0);
      expect(updater.patchPhase, PatchPhase.none);
    });
  });
}
