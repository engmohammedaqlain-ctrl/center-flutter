import 'package:center_mobile/data/app_update.dart';
import 'package:center_mobile/screens/app_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;

class _NoPatches implements PatchSource {
  @override
  bool get isAvailable => false;

  @override
  Future<PatchStatus> status() async => PatchStatus.upToDate;

  @override
  Future<void> download() async {}
}

/// حالة تحديث مضبوطة يدوياً، بلا شبكة ولا قرص.
AppUpdater _updater({
  UpdatePhase phase = UpdatePhase.idle,
  PatchPhase patch = PatchPhase.none,
  bool buildAvailable = true,
}) =>
    AppUpdater(supported: true, patches: _NoPatches())
      ..installedCode = 4
      ..installedName = '1.2.7'
      ..release = buildAvailable
          ? const AppRelease(
              versionName: '1.2.8',
              versionCode: 5,
              apkUrl: 'https://example.test/center-1.2.8.apk',
              sizeBytes: 20 * _mb,
            )
          : null
      ..phase = phase
      ..patchPhase = patch;

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  // مؤشرات دوّارة لا تستقر: إطارٌ واحد يكفي لقراءة النصوص
  await tester.pump();
}

void main() {
  group('بطاقة تنزيل البناء', () {
    testWidgets('التنزيل يعرض النسبة والحجم والسرعة والوقت الباقي', (tester) async {
      final u = _updater(phase: UpdatePhase.downloading)
        ..received = 5 * _mb
        ..totalBytes = 20 * _mb
        ..progress = 0.25
        ..speed = 2.0 * _mb;

      await _pump(tester, UpdatePanel(updater: u, onLater: () {}));

      expect(find.text('25%'), findsOneWidget);
      expect(find.text('5.0 م.ب من 20.0 م.ب'), findsOneWidget);
      expect(find.textContaining('2.0 م.ب/ث'), findsOneWidget);
      expect(find.textContaining('باقٍ 8 ث'), findsOneWidget, reason: '15 م.ب بسرعة 2 م.ب/ث');
      expect(find.text('إخفاء'), findsOneWidget, reason: 'التنزيل يستمر بعد إغلاق الورقة');
    });

    testWidgets('انقطاع الاتصال يعرض العدّ التنازلي وزر المحاولة الآن', (tester) async {
      final u = _updater(phase: UpdatePhase.retrying)
        ..received = 8 * _mb
        ..totalBytes = 20 * _mb
        ..progress = 0.4
        ..retryIn = 5;

      await _pump(tester, UpdatePanel(updater: u, onLater: () {}));

      expect(find.textContaining('خلال 5 ث'), findsOneWidget);
      expect(find.text('المحاولة الآن'), findsOneWidget);
      expect(find.textContaining('يُستكمل من مكانه'), findsOneWidget);
    });

    testWidgets('التنزيل المتوقف يعرض نسبته وزر الاستكمال', (tester) async {
      final u = _updater(phase: UpdatePhase.paused)
        ..received = 10 * _mb
        ..totalBytes = 20 * _mb
        ..progress = 0.5
        ..error = 'انقطع الاتصال بالإنترنت فتوقف التنزيل';

      await _pump(tester, UpdatePanel(updater: u, onLater: () {}));

      expect(find.text('50%'), findsOneWidget);
      expect(find.text('التنزيل متوقف'), findsOneWidget);
      expect(find.text('استكمال التنزيل'), findsOneWidget);
      expect(find.textContaining('حتى لو أُغلق التطبيق'), findsOneWidget);
    });

    testWidgets('التحقق من الملف يُعرض بعد اكتمال التنزيل', (tester) async {
      final u = _updater(phase: UpdatePhase.verifying)
        ..received = 20 * _mb
        ..totalBytes = 20 * _mb
        ..progress = 1;

      await _pump(tester, UpdatePanel(updater: u, onLater: () {}));

      expect(find.text('جارِ التحقق من سلامة الملف...'), findsOneWidget);
    });
  });

  group('شريط التحديث أعلى التطبيق', () {
    testWidgets('التحديث الصامت يُكتب أنه يُحمَّل في الخلفية', (tester) async {
      await _pump(tester, UpdateStatusStrip(updater: _updater(buildAvailable: false, patch: PatchPhase.downloading)));

      expect(find.text('جارِ تحميل التحديث في الخلفية...'), findsOneWidget);
    });

    testWidgets('بعد تنزيله الصامت: جاهز ويُطبَّق عند الفتح التالي', (tester) async {
      await _pump(tester, UpdateStatusStrip(updater: _updater(buildAvailable: false, patch: PatchPhase.ready)));

      expect(find.text('التحديث جاهز — يُطبَّق عند فتح التطبيق مرة ثانية'), findsOneWidget);
    });

    testWidgets('تنزيل البناء المتوقف يُتابَع من الشريط', (tester) async {
      final u = _updater(phase: UpdatePhase.paused)
        ..received = 10 * _mb
        ..totalBytes = 20 * _mb
        ..progress = 0.5;

      await _pump(tester, UpdateStatusStrip(updater: u));

      expect(find.text('تنزيل التحديث متوقف عند 50% — اضغط للاستكمال'), findsOneWidget);
    });

    testWidgets('لا تحديث: لا شريط', (tester) async {
      await _pump(tester, UpdateStatusStrip(updater: _updater(buildAvailable: false)));

      expect(find.textContaining('التحديث'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
