import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/tenant_service.dart';
import 'package:center_mobile/main.dart' show SplashScreen;
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/device_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

Future<AppStore> loggedIn(FakeDisk disk, {bool withStudents = true}) async {
  final s = AppStore.forTesting();
  await s.bootstrap(disk);
  injectDemoData(s);
  if (!withStudents) {
    s.students.clear();
  }
  await s.login('amal', 'amal2026');
  return s;
}

void main() {
  setUpAll(() {
    TenantService.masterUsername = 'dev-tester';
    TenantService.masterPassword = 'dev-tester-pass';
  });

  test('a device holding no local data must be set up first', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    expect(s.needsInitialSetup, isTrue);
  });

  test('every fresh login goes through the identity screen', () async {
    // من يسجّل الخروج غالباً يسلّم الجهاز لغيره، فلا يصحّ أن يرث صلاحية سابقه
    final s = await loggedIn(FakeDisk());
    expect(s.needsInitialSetup, isTrue);
  });

  test('restarting on a stored session skips the identity screen', () async {
    final disk = FakeDisk();
    final first = await loggedIn(disk);
    await first.completeInitialSetup(first.setupCandidates.first);
    await first.flush();
    expect(first.needsInitialSetup, isFalse);

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.loggedIn, isTrue);
    expect(second.needsInitialSetup, isFalse, reason: 'إعادة التشغيل ليست دخولاً جديداً');
  });

  test('a device carrying data and an identity from before this feature is grandfathered in', () async {
    final disk = FakeDisk();
    final first = await loggedIn(disk);
    // جهاز قديم: جلسة وبيانات وهوية مثبّتة، بلا أي علامة تهيئة
    await first.setDeviceIdentity(first.users.first, '');
    await first.db.setSetting('device_setup_pending', null);
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.students, isNotEmpty);
    expect(second.needsInitialSetup, isFalse);
  });

  test('logging out and back in asks for the identity again', () async {
    final disk = FakeDisk();
    final s = await loggedIn(disk);
    await s.completeInitialSetup(s.setupCandidates.first);
    expect(s.needsInitialSetup, isFalse);

    await s.logout();
    expect(s.needsInitialSetup, isFalse, reason: 'لا شاشة تهيئة خارج الجلسة');

    await s.login('amal', 'amal2026');
    expect(s.needsInitialSetup, isTrue);
  });

  test('the work shell never flashes before the identity screen', () async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);

    // ما ستعرضه الشاشة عند كل إخطار أثناء الدخول
    final seen = <String>[];
    s.addListener(() {
      if (!s.loggedIn) {
        seen.add('login');
      } else if (s.isMasterAdmin) {
        seen.add('developer');
      } else if (s.needsInitialSetup) {
        seen.add('setup');
      } else {
        seen.add('shell');
      }
    });

    await s.login('amal', 'amal2026');

    expect(s.needsInitialSetup, isTrue);
    expect(
      seen.contains('shell'),
      isFalse,
      reason: 'ظهرت شاشة العمل قبل شاشة الصلاحية: $seen',
    );
    expect(seen.where((x) => x == 'setup'), isNotEmpty);
  });

  test('the developer portal never sees the setup screen', () async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);
    s.students.clear();
    await s.login('dev-tester', 'dev-tester-pass');
    expect(s.isMasterAdmin, isTrue);
    expect(s.needsInitialSetup, isFalse);
  });

  test('the gate stays shut once the initial pull fills the local store', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    expect(s.needsInitialSetup, isTrue);

    // نجاح السحب الأولي يملأ الطلاب. لو كانت البوابة تُقرأ لحظياً لانقلبت هنا
    // وقفز التطبيق إلى شاشة العمل قبل أن يختار المستخدم هوية الجهاز.
    injectDemoData(s);
    expect(s.students, isNotEmpty);
    expect(s.needsInitialSetup, isTrue, reason: 'البوابة مثبَّتة حتى إتمام الاختيار');
  });

  test('completing setup pins the device identity and clears the gate', () async {
    final disk = FakeDisk();
    final s = await loggedIn(disk, withStudents: false);
    final secretary = s.setupCandidates.firstWhere((u) => u.role == 'receptionist');

    await s.completeInitialSetup(secretary);

    expect(s.needsInitialSetup, isFalse);
    expect(s.deviceUserId, secretary.id);
    expect(s.receiptReceiver, secretary.name);
    expect(s.roleName, 'سكرتير');
    expect(s.mySections, equals(roles['receptionist']!.sections));
    expect(s.can('settings.users'), isFalse);
  });

  test('the pinned identity survives a restart', () async {
    final disk = FakeDisk();
    final first = await loggedIn(disk, withStudents: false);
    final admin = first.setupCandidates.firstWhere((u) => u.role == 'admin');
    await first.completeInitialSetup(admin);
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.needsInitialSetup, isFalse);
    expect(second.deviceUserId, admin.id);
    expect(second.can('settings.users'), isTrue);
  });

  test('pinning an admin requires a valid password', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    expect(s.isAdminSetupPasswordValid(''), isFalse);
    expect(s.isAdminSetupPasswordValid('wrong'), isFalse);
    // المفتاح العام المكتوب في الكود أُلغي: كان سرّاً واحداً يفتح تهيئة أي جهاز
    // في أي مدرسة، ويقرأه كل من يفكّ التطبيق
    expect(s.isAdminSetupPasswordValid('school2026'), isFalse, reason: 'لا مفتاح عام');
    expect(s.isAdminSetupPasswordValid('dev-tester-pass'), isTrue, reason: 'كلمة مرور المطور');
    expect(s.isAdminSetupPasswordValid('amal2026'), isTrue, reason: 'كلمة مرور المنشأة');
  });

  testWidgets('كلمة مرور المدير مطلوبة للسكرتير أيضاً', (tester) async {
    // تعيين جهاز باسم سكرتير بلا كلمة مرور كان يفتح النظام لأي حامل للجهاز
    final s = await loggedIn(FakeDisk(), withStudents: false);
    final clerk = s.users.firstWhere((u) => u.role == 'receptionist');

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Directionality(textDirection: TextDirection.rtl, child: DeviceSetupScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('كلمة مرور المدير الرئيسية:'), findsOneWidget);

    // اختيار السكرتير لا يُخفي الحقل
    final state = tester.state<State>(find.byType(DeviceSetupScreen));
    // ignore: avoid_dynamic_calls
    (state as dynamic).selectedUserId = clerk.id;
    // ignore: invalid_use_of_protected_member
    state.setState(() {});
    await tester.pump();
    expect(find.text('كلمة مرور المدير الرئيسية:'), findsOneWidget);

    // الضغط بلا كلمة مرور يرفض ولا يثبّت الهوية
    // تمدّد البطاقة من حالة التحميل إلى النموذج يأخذ 220ms
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('تأكيد وبدء العمل على الجهاز'));
    await tester.pump();
    await tester.tap(find.text('تأكيد وبدء العمل على الجهاز'));
    await tester.pump();
    expect(find.text('كلمة مرور المدير غير صحيحة'), findsOneWidget);
    expect(s.deviceUserId, isNull);
    expect(s.needsInitialSetup, isTrue);

    await s.flush(); // إلغاء مؤقّت الكتابة المؤجّلة قبل هدم الشجرة
  });

  test('an institution with no users falls back to a deterministic owner admin', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    s.users.clear();
    final candidates = s.setupCandidates;
    expect(candidates, hasLength(1));
    expect(candidates.first.role, 'admin');
    expect(candidates.first.id, 'owner_${s.tenantId}');
    // تهيئة جهاز ثانٍ تتفق على نفس السجل بدل إنشاء مدير مكرر
    expect(s.ensureOwnerAdmin().id, candidates.first.id);
    expect(s.users.where((u) => u.id == candidates.first.id), hasLength(1));
  });

  test('demo accounts leaked locally are dropped without queuing a cloud delete', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    s.users.add(AppUser(id: 'demo1', name: 'مدير تجريبي', role: 'admin', email: 'principal@alamal.edu'));
    s.pendingSyncs.clear();
    s.cleanLocalDemoUsers();
    expect(s.users.any((u) => u.id == 'demo1'), isFalse);
    expect(s.pendingSyncs.where((a) => a.tableName == 'users'), isEmpty);
  });

  test('setup cannot run without a connection', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    s.networkEnabled = false;
    expect(() => s.initialPull(), throwsA(isA<StoreException>()));
  });

  group('لا دخول بلا كلمة مرور بعد تهيئة لم تكتمل', () {
    test('closing the app during the initial download reopens on the setup screen', () async {
      // السحب الأولي يملأ الطلاب قبل اختيار الهوية؛ الإقلاع بعده كان يعدّ
      // الجهاز «قديماً مهيَّأً» فيدخل بصلاحية مدير كاملة بلا كلمة مرور
      final disk = FakeDisk();
      final first = await loggedIn(disk, withStudents: false);
      injectDemoData(first); // ما نزل قبل الانقطاع
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.loggedIn, isTrue);
      expect(second.students, isNotEmpty);
      expect(second.needsInitialSetup, isTrue);
    });

    test('an earlier identity does not carry an unfinished setup through', () async {
      final disk = FakeDisk();
      final first = await loggedIn(disk);
      await first.completeInitialSetup(first.setupCandidates.first);
      await first.logout();
      // دخول جديد ثم إغلاق قبل الاختيار: هوية السابق وعلامة إتمامه باقيتان
      await first.login('amal', 'amal2026');
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.loggedIn, isTrue);
      expect(second.needsInitialSetup, isTrue);
    });

    test('a restored session with no pinned identity must be set up', () async {
      final disk = FakeDisk();
      final first = await loggedIn(disk);
      await first.db.setSetting('device_setup_pending', null); // جلسة من قبل العلامة
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.deviceUser, isNull);
      expect(second.needsInitialSetup, isTrue, reason: 'الجهاز بلا هوية يعمل بصلاحية المدير الكاملة');
    });

    test('reopening setup from settings survives a restart', () async {
      final disk = FakeDisk();
      final first = await loggedIn(disk);
      await first.completeInitialSetup(first.setupCandidates.first);
      await first.resetInitialSetup();
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.needsInitialSetup, isTrue);
    });
  });

  testWidgets('the setup screen fits a narrow phone with the keyboard open', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);

    final s = await loggedIn(FakeDisk(), withStudents: false);
    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: DeviceSetupScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // أي طفح يُفشل الاختبار بنفسه ويسمّي العنصر المسبّب
    expect(find.text('تأكيد وبدء العمل على الجهاز'), findsOneWidget);
    expect(find.text('العودة لتسجيل الدخول'), findsOneWidget);

    await s.flush();
  });

  testWidgets('تبديل المستخدم في المدرسة نفسها لا يُعيد تنزيل البيانات', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // جهاز دخل هذه المنشأة من قبل: بياناتها محفوظة عليه
    final s = await loggedIn(FakeDisk());
    expect(s.hasLocalTenantData, isTrue);

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: DeviceSetupScreen()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // قائمة المستخدمين فوراً: بلا شاشة تنزيل ولا خطأ «تحتاج اتصالاً»
    expect(find.text('المستخدم على هذا الجهاز:'), findsOneWidget);
    expect(find.textContaining('لا يمكن تهيئة الجهاز'), findsNothing);

    await s.flush();
  });

  test('جهازٌ لمنشأة أخرى، أو بلا بيانات، يبدأ بتنزيل كامل', () async {
    final s = await loggedIn(FakeDisk(), withStudents: false);
    s.users.clear();
    expect(s.hasLocalTenantData, isFalse, reason: 'لا بيانات محفوظة لهذه المنشأة');
    await s.flush();
  });

  testWidgets('the splash logo sits exactly where the native splash draws it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    // الشعار الأصلي نفسه الذي يحمله تطبيق سطح المكتب وشاشة البداية الأصلية
    final logo = find.byType(Image);
    expect(tester.getCenter(logo), screen.center(Offset.zero));
    // بمقاس الشعار في launch_background و splash_icon (120dp)
    expect(tester.getSize(logo), const Size.square(SplashScreen.logoSize));
    final image = tester.widget<Image>(logo).image;
    expect(image, isA<ResizeImage>(), reason: 'يُفكّ بمقاس العرض لا بمقاس الأصل');
  });
}
