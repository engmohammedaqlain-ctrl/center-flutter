import 'package:center_mobile/data/backup.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// طلبات الدفع من ولي الأمر — مطابق لـ `paymentRequests.test.ts` في الويب: الطلب
/// لا يمسّ الحساب، القبول سند قبض عادي، والرفض بسبب يراه ولي الأمر.

AppStore _seeded() {
  final store = AppStore.forTesting();
  injectDemoData(store);
  return store;
}

/// طلب معلق كما يصل من السحابة بالسحب العادي.
Map<String, dynamic> _pending(Student student, {double amount = 20, String id = 'req-1'}) => {
      'id': id,
      'student_id': student.id,
      'student_name': student.fullName,
      'amount': amount,
      'sender_name': 'أبو أحمد',
      'payment_method': 'bop',
      'transfer_channel': 'بنك فلسطين',
      'transfer_date': '2026-09-20',
      'reference_number': 'TX-77',
      'notes': 'عن قسط شهر 9',
      'image_paths': ['t/s/req-1-1.jpg'],
      'status': 'pending',
      'created_at': '2026-09-20T10:00:00Z',
      'updated_at': '2026-09-20T10:00:00Z',
    };

void main() {
  test('الطلب المعلق لا يمسّ حساب الطالب ويُعدّ في الرقابة', () {
    final store = _seeded();
    final student = store.students.first;
    final paymentsBefore = store.payments.length;
    store.putRows('payment_requests', [_pending(student)]);

    expect(store.pendingPaymentRequests, hasLength(1));
    expect(store.payments.length, paymentsBefore);
    final r = store.pendingPaymentRequests.first;
    expect(r.imagePaths, ['t/s/req-1-1.jpg']);
    expect(r.statusLabel, 'قيد المراجعة');
  });

  test('القبول يصدر سند قبض بما في الطلب ويسجّل في سجل الرقابة', () async {
    final store = _seeded();
    final student = store.students.first;
    store.putRows('payment_requests', [_pending(student)]);

    final payment = await store.approvePaymentRequest('req-1', amount: 20, method: 'bop');

    expect(payment.amount, 20);
    expect(payment.studentId, student.id);
    expect(payment.senderName, 'أبو أحمد');
    expect(payment.channel, 'بنك فلسطين');
    expect(payment.reference, 'TX-77');
    expect(payment.notes, contains('طلب من بوابة ولي الأمر'));

    final decided = store.paymentRequests.single;
    expect(decided.status, 'approved');
    expect(decided.paymentId, payment.id);
    expect(store.pendingPaymentRequests, isEmpty);
    expect(store.financeAudit.map((a) => a.action), contains('payment_request_approved'));
    expect(store.pendingSyncs.any((p) => p.tableName == 'payment_requests' && p.action == 'UPDATE'), isTrue);

    await expectLater(store.approvePaymentRequest('req-1'), throwsA(isA<StoreException>()));
  });

  test('المبلغ المصحح يُكتب في السند ويُذكر فرقه في السجل', () async {
    final store = _seeded();
    final student = store.students.first;
    store.putRows('payment_requests', [_pending(student, amount: 25)]);

    final payment = await store.approvePaymentRequest('req-1', amount: 15);
    expect(payment.amount, 15);
    final audit = store.financeAudit.lastWhere((a) => a.action == 'payment_request_approved');
    expect(audit.summary, contains('الطلب'));
  });

  test('الرفض يتطلب سبباً واضحاً ولا يصدر سنداً', () {
    final store = _seeded();
    final student = store.students.first;
    store.putRows('payment_requests', [_pending(student)]);
    final paymentsBefore = store.payments.length;

    expect(() => store.rejectPaymentRequest('req-1', 'خطأ'), throwsA(isA<StoreException>()));
    expect(store.pendingPaymentRequests, hasLength(1));

    store.rejectPaymentRequest('req-1', rejectionReasonPresets.first);
    final r = store.paymentRequests.single;
    expect(r.status, 'rejected');
    expect(r.rejectionReason, rejectionReasonPresets.first);
    expect(store.payments.length, paymentsBefore);
    expect(store.financeAudit.map((a) => a.action), contains('payment_request_rejected'));
  });

  test('الجدول يُزامَن ويُنسخ احتياطياً بأعمدته', () {
    expect(syncedTables, contains('payment_requests'));
    expect(tableAllowedColumns['payment_requests'], containsAll(['image_paths', 'rejection_reason', 'payment_id']));
    expect(BackupService.cloudToDexie['payment_requests'], 'paymentRequests');
    final row = PaymentRequest.fromCloud({'id': 'x', 'student_id': 's', 'amount': '12.5', 'sender_name': 'م'}).toCloud();
    expect(row['amount'], 12.5);
    expect(row['image_paths'], isEmpty);
    expect(row['status'], 'pending');
  });
}
