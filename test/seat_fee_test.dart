import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `monthlyDues.test.ts`: رسم الحجز يُسدَّد أولاً، ولا يُطالَب منه
/// بأكثر مما خُصم من المستحقات.

Installment _inst(String id, String title, double amount, DateTime due, {double paid = 0}) => Installment(
      id: id,
      studentId: 's1',
      title: title,
      amount: amount,
      dueDate: due,
      paidAmount: paid,
    );

void main() {
  group('ترتيب السداد', () {
    test('رسم الحجز قبل الأقدم استحقاقاً ولو كان تاريخه بعده', () {
      final seat = _inst('i-seat', seatTitle, 50, DateTime(2026, 9, 20));
      final month = _inst('i-sep', 'رسوم 09/2026', 100, DateTime(2026, 9, 1));
      final next = _inst('i-oct', 'رسوم 10/2026', 100, DateTime(2026, 10, 1));

      final ordered = [next, month, seat]..sort(compareInstallments);
      expect(ordered.map((i) => i.id), ['i-seat', 'i-sep', 'i-oct']);
    });

    test('الدفعة العامة تسدّد الحجز أولاً', () {
      final seat = _inst('i-seat', seatTitle, 50, DateTime(2026, 9, 20));
      final month = _inst('i-sep', 'رسوم 09/2026', 100, DateTime(2026, 9, 1));
      final payment = Payment(
        id: 'p1',
        receiptNumber: '2026/1001',
        studentId: 's1',
        amount: 60,
        method: 'cash',
        date: DateTime(2026, 9, 25),
      );

      final allocated = allocatePaymentsToInstallments([month, seat], [payment]);
      expect(allocated['i-seat'], 50, reason: 'الحجز كاملاً');
      expect(allocated['i-sep'], 10, reason: 'والباقي على الشهر');
    });
  });

  group('سقف رسم الحجز', () {
    Installment seatOf(double amount) => Installment(
          id: 'seat-stu',
          studentId: 'stu',
          title: seatTitle,
          amount: amount,
          dueDate: DateTime(2026, 9, 20),
        );

    AppStore seeded(double seatFee, double monthlyFee) {
      final s = AppStore.forTesting();
      injectDemoData(s);
      s.students.removeWhere((x) => true);
      s.installments.clear();
      s.gradeFees.clear();
      s.gradeFees.add(GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: monthlyFee, orderIndex: 0));
      s.students.add(Student(
        id: 'stu',
        fullName: 'طالب الحجز',
        gradeLevel: 'عاشر',
        section: '',
        phone: '0599000000',
        parentName: 'ولي',
        parentPhone: '0598000000',
        nationalId: '401092599',
        balance: 0,
        status: 'active',
      ));
      s.installments.add(seatOf(seatFee));
      return s;
    }

    test('رسم الحجز يُخصم من مستحق الشهر، ويبقى كما هو إن غطّاه', () async {
      final s = seeded(50, 200);
      await s.saveStudyMonths([9]);

      final result = s.generateMonthlyDues(now: DateTime(2026, 9, 5));

      expect(result.created, 1);
      final due = s.installments.firstWhere((i) => i.id != 'seat-stu');
      expect(due.amount, 150, reason: '200 ناقص رسم الحجز');
      expect(s.installments.firstWhere((i) => i.id == 'seat-stu').amount, 50, reason: 'لم يُمسّ');
      await s.flush();
    });

    test('رسم أكبر من مستحق الشهر: الحجز يُقصّ على ما خُصم فعلاً', () async {
      final s = seeded(50, 30);
      await s.saveStudyMonths([9]);

      s.generateMonthlyDues(now: DateTime(2026, 9, 5));

      final due = s.installments.firstWhere((i) => i.id != 'seat-stu');
      expect(due.amount, 0, reason: 'استُهلك المستحق كله');
      expect(s.installments.firstWhere((i) => i.id == 'seat-stu').amount, 30,
          reason: 'لا يُطالَب بعشرين لم تُخصم له');
      expect(s.pendingSyncs.any((p) => p.recordId == 'seat-stu'), isTrue, reason: 'يصل بقية الأجهزة');
      await s.flush();
    });
  });
}
