import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore seeded() {
  final store = AppStore.forTesting();
  injectDemoData(store);
  return store;
}

void main() {
  test('المدير يوافق طلب إلغاء فينفّذه ثم يغيّر حالة الطلب', () async {
    final store = seeded();
    final student = store.students.first;
    final payment = store.addPayment(
      studentId: student.id,
      amount: 35,
      method: 'cash',
      date: DateTime.now(),
    );
    final clerk = store.users.firstWhere((u) => u.role == 'receptionist');
    await store.setDeviceIdentity(clerk, '');

    final request = store.submitFinanceRequest(
      kind: 'payment_cancel',
      summary: 'إلغاء السند ${payment.receiptNumber}',
      studentId: student.id,
      targetId: payment.id,
      payload: const {},
      amount: payment.amount,
      reason: 'سند مكرر',
    );
    expect(payment.cancelled, isFalse, reason: 'الطلب وحده لا يمس السند');

    final admin = store.users.firstWhere((u) => u.role == 'admin');
    await store.setDeviceIdentity(admin, '');
    store.claimOverride = (_, _, _) async => () async {};
    await store.approveFinanceRequest(request.id);

    expect(payment.cancelled, isTrue);
    expect(request.status, 'approved');
    expect(request.decidedById, admin.id);
    expect(
      store.financeAudit.map((a) => a.action),
      containsAll(['request_submitted', 'payment_cancel', 'request_approved']),
    );
  });

  test('الرد ينشئ سنداً سالباً مستقلاً ويعيد حساب الرصيد', () {
    final store = seeded();
    final student = store.students.first;
    store.addPayment(
      studentId: student.id,
      amount: 80,
      method: 'cash',
      date: DateTime.now(),
    );
    final before = student.balance;

    final refund = store.refundStudentCredit(
      student.id,
      amount: 25,
      method: 'cash',
      reason: 'دفع مكرر',
    );

    expect(refund.amount, -25);
    expect(refund.purpose, 'refund');
    expect(refund.date.day, DateTime.now().day);
    expect(student.balance, closeTo(before - 25, 0.01));
    expect(
      store.pendingSyncs.any(
        (row) => row.tableName == 'payments' && row.recordId == refund.id,
      ),
      isTrue,
    );
  });

  test('الإلغاء يكتب سطر تدقيق بفاعله ومبلغه وسببه', () async {
    final store = seeded();
    final admin = store.users.firstWhere((u) => u.role == 'admin');
    await store.setDeviceIdentity(admin, '');
    final payment = store.addPayment(
      studentId: store.students.first.id,
      amount: 20,
      method: 'cash',
      date: DateTime.now(),
    );
    store.financeAudit.clear();

    store.cancelPayment(payment, 'خطأ في المبلغ');

    final audit = store.financeAudit.single;
    expect(audit.action, 'payment_cancel');
    expect(audit.userId, admin.id);
    expect(audit.amount, 20);
    expect(audit.reason, 'خطأ في المبلغ');
    expect(
      store.pendingSyncs.any(
        (row) => row.tableName == 'audit_log' && row.recordId == audit.id,
      ),
      isTrue,
    );
  });
}
