import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
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

  test('a device carrying data from before this feature is grandfathered in', () async {
    final disk = FakeDisk();
    final first = await loggedIn(disk);
    await first.flush();

    // إقلاع بجلسة قائمة وبيانات محلية وبلا علامة تهيئة
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
    await s.login('anas', 'anas2026');
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
    expect(s.myCapabilities, equals(receptionistCapabilities));
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
    expect(s.isAdminSetupPasswordValid('school2026'), isTrue, reason: 'المفتاح العام');
    expect(s.isAdminSetupPasswordValid('anas2026'), isTrue, reason: 'كلمة مرور المطور');
    expect(s.isAdminSetupPasswordValid('amal2026'), isTrue, reason: 'كلمة مرور المنشأة');
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
}
