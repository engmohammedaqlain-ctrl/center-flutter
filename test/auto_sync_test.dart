import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// متجر بمزامنة تلقائية مفعّلة وطابور فارغ. لا شبكة في الاختبار: المؤقت يُفحص
/// ويُلغى قبل أن يعمل.
AppStore _auto() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.pendingSyncs.clear();
  s.autoSync = true;
  addTearDown(s.stopAutoSync);
  return s;
}

/// إلغاء أي جدولة سابقة مع إبقاء المزامنة التلقائية مفعّلة.
void _reset(AppStore s) {
  s.stopAutoSync();
  s.autoSync = true;
  s.lastAutoPushDelay = null;
}

PendingSync _op(int id, {int retries = 0, String? error}) => PendingSync(
      id: id,
      tableName: 'payments',
      recordId: 'p$id',
      action: 'INSERT',
      createdAt: '2026-09-15T08:00:00Z',
      retryCount: retries,
      lastError: error,
    );

void main() {
  group('كل تعديل يُجدول رفعاً تلقائياً مهما كان مساره', () {
    test('إضافة دفعة', () {
      final s = _auto();
      s.addPayment(studentId: s.students.first.id, amount: 10, method: 'cash', date: DateTime(2026, 9, 10));

      expect(s.pendingSyncs.where((p) => p.tableName == 'payments'), isNotEmpty);
      expect(s.autoPushScheduled, isTrue);
      expect(s.lastAutoPushDelay, AppStore.autoPushDelay);
    });

    test('رصد الكل حاضراً', () {
      final s = _auto();
      _reset(s);
      final marked = s.markAllPresent('2026-09-11', s.students.take(3).toList());

      expect(marked, greaterThan(0));
      expect(s.autoPushScheduled, isTrue);
    });

    test('توليد رموز البوابة', () {
      final s = _auto();
      final student = s.students.first
        ..portalCode = ''
        ..parentPortalCode = '';
      _reset(s);

      expect(s.ensureStudentPortalCodes([student]), 1);
      expect(s.autoPushScheduled, isTrue);
    });

    test('تعديل عادي عبر الطابور', () {
      final s = _auto();
      _reset(s);
      final student = s.students.first;
      student.notes = 'ملاحظة جديدة';
      s.upsertStudent(student);

      expect(s.autoPushScheduled, isTrue);
    });

    test('بلا مزامنة تلقائية لا يُجدول شيء', () {
      final s = _auto();
      s.stopAutoSync();
      s.addPayment(studentId: s.students.first.id, amount: 10, method: 'cash', date: DateTime(2026, 9, 10));

      expect(s.autoPushScheduled, isFalse);
    });
  });

  group('ما بعد الرفع التلقائي', () {
    test('طابور فرغ: لا شيء', () {
      final next = AppStore.autoPushFollowUp({1: 0}, const [], 0);
      expect(next.delay, isNull);
      expect(next.stalled, isFalse);
    });

    test('عملية أُضيفت أثناء الرفع تُرفع بالمهلة المعتادة', () {
      final next = AppStore.autoPushFollowUp({1: 0}, [_op(2)], 0);
      expect(next.delay, AppStore.autoPushDelay);
      expect(next.stalled, isFalse);
    });

    test('انقطاع أثناء الرفع: إعادة بمهلة تتباعد ولا تتجاوز الدقيقة', () {
      final queue = [_op(1, error: 'تعذّر الاتصال')];
      expect(AppStore.autoPushFollowUp({1: 0}, queue, 0).delay, const Duration(seconds: 5));
      expect(AppStore.autoPushFollowUp({1: 0}, queue, 1).delay, const Duration(seconds: 15));
      expect(AppStore.autoPushFollowUp({1: 0}, queue, 2).delay, const Duration(seconds: 30));
      expect(AppStore.autoPushFollowUp({1: 0}, queue, 3).delay, const Duration(seconds: 60));
      expect(AppStore.autoPushFollowUp({1: 0}, queue, 40).delay, const Duration(seconds: 60));
      expect(AppStore.autoPushFollowUp({1: 0}, queue, 0).stalled, isTrue);
    });

    test('رفض دائم استهلك محاولة لا يُعاد وحده', () {
      final next = AppStore.autoPushFollowUp({1: 0}, [_op(1, retries: 1, error: 'قيد مخالف')], 0);
      expect(next.delay, isNull);
      expect(next.stalled, isFalse);
    });

    test('عملية استنفدت محاولاتها لا تُحسب', () {
      final next = AppStore.autoPushFollowUp({}, [_op(1, retries: maxSyncRetries, error: 'قيد مخالف')], 0);
      expect(next.delay, isNull);
    });
  });
  group('بوابة تهيئة الجهاز', () {
    test('ما تراكم أثناء التهيئة يُرفع فور إغلاقها', () async {
      final s = AppStore.forTesting();
      injectDemoData(s);
      s.currentTenant = s.tenants.first;
      s.loggedIn = true;
      s.pendingSyncs.clear();
      s.autoSync = true;
      addTearDown(s.stopAutoSync);

      // البوابة مفتوحة: حساب مدير المنشأة يُقيَّد ولا يُرفع
      await s.resetInitialSetup();
      expect(s.needsInitialSetup, isTrue);
      s.ensureOwnerAdmin();
      expect(s.pendingSyncs, isNotEmpty);

      await s.completeInitialSetup(s.users.first);

      expect(s.autoPushScheduled, isTrue, reason: 'يُرفع فور إغلاق البوابة');
      expect(s.lastAutoPushDelay, Duration.zero);
      expect(s.lastAutoPullDelay, Duration.zero, reason: 'ويُسحب ما فات');
      await s.flush();
    });
  });
}
