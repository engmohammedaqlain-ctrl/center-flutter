import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

void main() {
  group('receipt numbers', () {
    test('maxSerialFor ignores other years and malformed numbers', () {
      expect(AppStore.maxSerialFor(2026, ['2026/1004', '2025/9999', 'REC-2026-7', '']), 1004);
      expect(AppStore.maxSerialFor(2026, const []), 1000);
    });

    test('serials never restart below 1001 and never collide locally', () {
      final s = seeded();
      final student = s.students.first;
      final issued = <String>{};
      for (var i = 0; i < 5; i++) {
        final p = s.addPayment(studentId: student.id, amount: 5, method: 'cash', date: DateTime.now());
        expect(issued.add(p.receiptNumber), isTrue, reason: 'لا تكرار في أرقام السندات');
        final serial = int.parse(p.receiptNumber.split('/')[1]);
        expect(serial, greaterThanOrEqualTo(1001));
      }
    });

    test('migration normalises legacy formats exactly once', () async {
      final s = seeded();
      final student = s.students.first;
      final year = DateTime.now().year;

      s.payments.addAll([
        Payment(id: 'a', receiptNumber: 'REC-2025-101', studentId: student.id, amount: 1, method: 'cash', date: DateTime.now()),
        Payment(id: 'b', receiptNumber: 'REC-2025-7', studentId: student.id, amount: 1, method: 'cash', date: DateTime.now()),
        Payment(id: 'c', receiptNumber: '42', studentId: student.id, amount: 1, method: 'cash', date: DateTime.now()),
        Payment(id: 'd', receiptNumber: '$year/1500', studentId: student.id, amount: 1, method: 'cash', date: DateTime.now()),
      ]);

      final changed = await s.migrateReceiptNumbers();
      expect(changed, 3);
      expect(s.payments.firstWhere((p) => p.id == 'a').receiptNumber, '2025/1001');
      expect(s.payments.firstWhere((p) => p.id == 'b').receiptNumber, '2025/1007');
      expect(s.payments.firstWhere((p) => p.id == 'c').receiptNumber, '$year/1042');
      expect(s.payments.firstWhere((p) => p.id == 'd').receiptNumber, '$year/1500',
          reason: 'الأرقام الصحيحة لا تُمس');

      // لا تعمل مرتين — التشغيل المتكرر كان يُنتج تأرجحاً مع السحب
      expect(await s.migrateReceiptNumbers(), 0);
    });
  });

  group('installment status', () {
    test('follows the paid amount through partial payment and cancellation', () {
      final s = seeded();
      final inst = s.installments.firstWhere((i) => i.paidAmount == 0);
      final student = s.studentById(inst.studentId)!;
      expect(inst.status, 'unpaid');

      final half = s.addPayment(
        studentId: student.id,
        amount: inst.amount / 2,
        method: 'cash',
        date: DateTime.now(),
        installmentId: inst.id,
      );
      expect(inst.status, 'partially_paid');
      expect(inst.toCloud()['status'], 'partially_paid');

      final rest = s.addPayment(
        studentId: student.id,
        amount: inst.remaining,
        method: 'cash',
        date: DateTime.now(),
        installmentId: inst.id,
      );
      expect(inst.status, 'paid');
      expect(inst.isPaid, isTrue);

      s.cancelPayment(rest);
      expect(inst.status, 'partially_paid');
      s.cancelPayment(half);
      expect(inst.status, 'unpaid');
      expect(inst.paidAmount, 0);
    });
  });

  group('payment audit trail', () {
    test('records who collected the payment', () async {
      final s = seeded();
      final cashier = s.users.last;
      await s.setDeviceIdentity(cashier, 'أمين الصندوق');
      final p = s.addPayment(
        studentId: s.students.first.id,
        amount: 20,
        method: 'cash',
        date: DateTime.now(),
      );
      expect(p.receivedByUserId, cashier.id);
      expect(p.toCloud()['received_by_user_id'], cashier.id);
      expect(s.receiptReceiver, 'أمين الصندوق');
    });

    test('a payment can be linked to a group', () {
      final s = seeded();
      final p = s.addPayment(
        studentId: s.students.first.id,
        amount: 20,
        method: 'cash',
        date: DateTime.now(),
        groupId: 'grp-1',
      );
      expect(p.groupId, 'grp-1');
      expect(p.toCloud()['group_id'], 'grp-1');
    });

    test('rejects a non-positive amount and an unknown student', () {
      final s = seeded();
      expect(
        () => s.addPayment(studentId: s.students.first.id, amount: 0, method: 'cash', date: DateTime.now()),
        throwsA(isA<StoreException>()),
      );
      expect(
        () => s.addPayment(studentId: 'ghost', amount: 10, method: 'cash', date: DateTime.now()),
        throwsA(isA<StoreException>()),
      );
    });

    test('cancelling twice does not double-revert the balance', () {
      final s = seeded();
      final student = s.students.first;
      final p = s.addPayment(studentId: student.id, amount: 30, method: 'cash', date: DateTime.now());
      final afterPay = student.balance;
      s.cancelPayment(p);
      final afterCancel = student.balance;
      s.cancelPayment(p);
      expect(student.balance, afterCancel);
      expect(afterPay - afterCancel, 30);
    });
  });

  group('due items', () {
    test('an unpaid installment past its due date is late', () {
      final s = seeded();
      final inst = s.installments.firstWhere((i) => i.paidAmount == 0);
      inst.dueDate = DateTime.now().subtract(const Duration(days: 5));
      final item = s.dueItems().firstWhere((d) => d.installmentId == inst.id);
      expect(item.late, isTrue);
      expect(item.stageLabel, 'متأخر عن السداد');
    });

    test('a flexible exception outranks the late label and sorts last', () {
      final s = seeded();
      final inst = s.installments.firstWhere((i) => i.paidAmount == 0);
      inst.dueDate = DateTime.now().subtract(const Duration(days: 5));
      inst.exception = true;
      final items = s.dueItems();
      final item = items.firstWhere((d) => d.installmentId == inst.id);
      expect(item.stageLabel, 'استثناء');
      expect(items.last.exception, isTrue);
    });

    test('a debtor without installments still appears once', () {
      final s = seeded();
      final student = s.students.firstWhere((e) => e.balance < 0);
      s.installments.removeWhere((i) => i.studentId == student.id);
      final mine = s.dueItems().where((d) => d.student.id == student.id).toList();
      expect(mine.length, 1);
      expect(mine.first.title, 'رسوم شهرية مستحقة');
      expect(mine.first.amount, student.balance.abs());
    });
  });

  group('المصروفات وأجور المعلمين', () {
    test('سند الصرف يُسجَّل ويُدرَج في طابور الرفع', () {
      final s = seeded();
      s.pendingSyncs.clear();

      final e = s.addExpense(
        category: 'قرطاسية ومطبوعات',
        description: '  شراء أوراق  ',
        amount: 150,
        expenseDate: '2026-09-10',
        method: 'cash',
        notes: 'دفعة واحدة',
      );

      expect(e.description, 'شراء أوراق', reason: 'الفراغ الزائد يُقلَّم');
      expect(e.syncStatus, 'pending');
      expect(s.expenses.map((x) => x.id), contains(e.id));
      expect(s.totalExpenses, 150);

      final queued = s.pendingSyncs.where((p) => p.tableName == 'expenses').toList();
      expect(queued, hasLength(1));
      expect(queued.single.recordId, e.id);
      expect(queued.single.action, 'INSERT');
    });

    test('سند بلا بيان أو بمبلغ غير موجب يُرفض ولا يترك أثراً', () {
      final s = seeded();
      s.pendingSyncs.clear();

      expect(
        () => s.addExpense(category: 'أخرى', description: '   ', amount: 50, expenseDate: '2026-09-10'),
        throwsA(isA<StoreException>()),
      );
      expect(
        () => s.addExpense(category: 'أخرى', description: 'بيان', amount: 0, expenseDate: '2026-09-10'),
        throwsA(isA<StoreException>()),
      );
      expect(s.expenses, isEmpty);
      expect(s.pendingSyncs, isEmpty);
    });

    test('السجل يرتّب الأحدث أولاً', () {
      final s = seeded();
      s.addExpense(category: 'أخرى', description: 'قديم', amount: 10, expenseDate: '2026-01-01');
      s.addExpense(category: 'أخرى', description: 'حديث', amount: 20, expenseDate: '2026-09-01');
      expect(s.expenses.first.description, 'حديث');
    });

    test('الحذف يُخرج السند ويُدرج عملية حذف', () {
      final s = seeded();
      final e = s.addExpense(category: 'أخرى', description: 'خطأ', amount: 5, expenseDate: '2026-09-10');
      s.pendingSyncs.clear();

      s.deleteExpense(e.id);
      expect(s.expenses, isEmpty);
      expect(s.pendingSyncs.single.action, 'DELETE');
    });

    test('سند الصرف يمرّ عبر شكل السحابة بلا فقدان', () {
      final e = Expense(
        id: 'x1',
        category: 'صيانة ومعدات',
        description: 'تصليح طابعة',
        amount: 320.5,
        expenseDate: '2026-09-10',
        recordedByUserId: 'u1',
        method: 'cheque',
        notes: 'شيك مؤجل',
      );
      final back = Expense.fromCloud(e.toCloud());
      expect(back.category, e.category);
      expect(back.amount, 320.5);
      expect(back.method, 'cheque');
      expect(back.notes, 'شيك مؤجل');
      expect(back.recordedByUserId, 'u1');
    });

    test('دفعة الأجر تمرّ عبر شكل السحابة بلا فقدان', () {
      final p = TeacherPayout(
        id: 'p1',
        teacherId: 't1',
        amount: 900,
        paymentDate: '2026-09-01',
        periodStart: '2026-08-01',
        periodEnd: '2026-08-31',
        method: 'bank_transfer',
      );
      final back = TeacherPayout.fromCloud(p.toCloud());
      expect(back.teacherId, 't1');
      expect(back.amount, 900);
      expect(back.periodStart, '2026-08-01');
      expect(back.method, 'bank_transfer');
    });

    test('طرق الصرف أضيق من طرق القبض', () {
      // المحافظ الإلكترونية للقبض لا للصرف — مطابق لـ types/payment.ts
      expect(expenseMethodNames.keys.toList(), ['cash', 'bank_transfer', 'cheque', 'other']);
      expect(expenseCategoryLabel('أخرى'), 'مصاريف أخرى');
      expect(expenseCategoryLabel('تشغيل وإيجار'), 'تشغيل وإيجار');
    });
  });
}
