import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `installmentPlans.test.ts`: رسم الحجز يُسدَّد أولاً، ولا يُطالَب منه
/// بأكثر مما خُصم من أقساط الطالب.

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

    test('الاسم القديم يُحسب حجزاً في الترتيب والتوزيع', () {
      final legacy = _inst('i-old', 'رسم حجز مقعد', 50, DateTime(2026, 9, 20));
      final month = _inst('i-sep', 'رسوم 09/2026', 100, DateTime(2026, 9, 1));
      expect(isSeatInstallmentTitle(legacy.title), isTrue);
      final ordered = [month, legacy]..sort(compareInstallments);
      expect(ordered.first.id, 'i-old');
    });
  });

  group('سقف رسم الحجز على خطة الطالب', () {
    List<StudentPlanRow> planWith({required double seatFee, required double amount, int count = 1}) =>
        buildStudentPlan(
          [
            for (var i = 0; i < count; i++)
              PlanItem(id: 'p$i', title: 'القسط ${i + 1}', amount: amount, dueDate: '2026-1$i-05'),
          ],
          'stu',
          seatFee: seatFee,
          enrollmentDate: '2026-09-01',
        );

    test('يُقتطع من القسط، ويبقى كما هو إن غطّاه', () {
      final rows = planWith(seatFee: 50, amount: 200);

      expect(rows.first.title, seatTitle);
      expect(rows.first.amount, 50, reason: 'لم يُمسّ');
      expect(rows[1].amount, 150, reason: '200 ناقص رسم الحجز');
    });

    test('رسم أكبر من الخطة: الحجز يُقصّ على ما خُصم فعلاً', () {
      final rows = planWith(seatFee: 50, amount: 30);

      expect(rows.first.amount, 30, reason: 'لا يُطالَب بعشرين لم تُخصم له');
      expect(rows[1].amount, 0, reason: 'استُهلك القسط كله');
    });

    test('ما يزيد عن قسط ينتقل للذي يليه بترتيبها الزمني', () {
      final rows = planWith(seatFee: 50, amount: 30, count: 2);

      expect(rows.first.amount, 50);
      expect(rows.skip(1).map((r) => r.amount), [0, 10]);
    });
  });
}
