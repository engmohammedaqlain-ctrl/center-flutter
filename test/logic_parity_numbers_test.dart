import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// أرقام اللوجيك مقابل الويب — الرصيد، حصة الخصم الناقصة، وتاريخ الدفع.
void main() {
  group('balanceFrom كالويب', () {
    test('لا يخصم رسوم التسجيل من الرصيد', () {
      final inst = Installment(
        id: 'i1',
        studentId: 's1',
        title: 'قسط',
        amount: 100,
        dueDate: DateTime(2026, 1, 1),
      );
      final pay = Payment(
        id: 'p1',
        receiptNumber: '1',
        studentId: 's1',
        amount: 40,
        method: 'cash',
        date: DateTime(2026, 1, 2),
      );
      final enrollment = StudentEnrollment(
        id: 'e1',
        studentId: 's1',
        groupId: 'g1',
        status: 'active',
        appliedPrice: 500,
      );

      expect(
        balanceFrom(enrollments: [enrollment], installments: [inst], payments: [pay]),
        -60,
      );
      expect(
        balanceFrom(installments: [inst], payments: [pay]),
        -60,
        reason: 'رسوم المجموعة لا تدخل الرصيد',
      );
    });

    test('summarizeInstallments يطابق required/paid/remaining/due', () {
      final today = DateTime(2026, 3, 15);
      final due = Installment(
        id: 'd',
        studentId: 's',
        title: 'حالّ',
        amount: 100,
        paidAmount: 30,
        dueDate: DateTime(2026, 3, 1),
      );
      final later = Installment(
        id: 'l',
        studentId: 's',
        title: 'لاحق',
        amount: 100,
        dueDate: DateTime(2026, 4, 1),
      );
      final sum = summarizeInstallments([due, later], today);
      expect(sum.required, 200);
      expect(sum.paid, 30);
      expect(sum.remaining, 170);
      expect(sum.due, 70);
    });
  });

  group('plan_discount_share الناقص', () {
    test('سجل بلا حصة محفوظة يُعاد تسعيره باتساق لا كـ unexplained', () {
      final s = AppStore.forTesting();
      injectDemoData(s);
      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      final due = isoDate(DateTime.now().add(const Duration(days: 60)));
      fee.planItems = [
        PlanItem(id: 'share_item', title: 'قسط 1', amount: 100, dueDate: due),
      ];

      final student = Student(
        id: s.newId(),
        fullName: 'طالب الحصة الناقصة',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599000111',
        parentName: 'ولي',
        parentPhone: '0598000111',
        balance: 0,
        nationalId: '111222333',
        planDiscountType: 'percentage',
        planDiscountValue: 10,
      );
      s.students.add(student);

      s.installments.add(
        Installment(
          id: planInstallmentId('share_item', student.id),
          studentId: student.id,
          title: 'قسط 1',
          amount: 90,
          originalAmount: 100,
          planDiscountShare: null,
          dueDate: parseIsoDate(due)!,
          academicYearId: s.viewedAcademicYearId,
        ),
      );

      fee.planItems = [
        PlanItem(id: 'share_item', title: 'قسط 1', amount: 200, dueDate: due),
      ];

      final preview = s.syncGradePlan('عاشر', repriceOnly: true);
      expect(preview.unexplained.installments, 0, reason: 'null share ≠ تعديل حر');
      expect(preview.reprice.installments, greaterThan(0));
    });
  });

  group('totalDueAtPayment بتاريخ السند', () {
    test('يحتسب الأقساط الحالّة حتى تاريخ الدفع لا اليوم فقط', () {
      final s = AppStore.forTesting();
      injectDemoData(s);
      final student = s.students.firstWhere((stu) => stu.status == 'active');
      // أزل أقساطه الافتراضية حتى لا تختلط
      s.installments.removeWhere((i) => i.studentId == student.id);

      final past = DateTime.now().subtract(const Duration(days: 40));
      final future = DateTime.now().add(const Duration(days: 40));
      s.installments.addAll([
        Installment(
          id: 'past',
          studentId: student.id,
          title: 'قديم',
          amount: 100,
          dueDate: past,
          academicYearId: s.viewedAcademicYearId,
        ),
        Installment(
          id: 'future',
          studentId: student.id,
          title: 'قادم',
          amount: 100,
          dueDate: future,
          academicYearId: s.viewedAcademicYearId,
        ),
      ]);

      final mid = DateTime.now().subtract(const Duration(days: 10));
      final p = s.addPayment(
        studentId: student.id,
        amount: 50,
        method: 'cash',
        date: mid,
      );
      expect(p.totalDueAtPayment, 100);
    });
  });

  group('الدفعة المقدمة كالويب', () {
    test('الزائد عن المستحق والمجدول يُقبل رصيداً للطالب', () {
      final s = AppStore.forTesting();
      injectDemoData(s);
      final student = s.students.firstWhere((stu) => stu.status == 'active');
      s.installments.removeWhere((i) => i.studentId == student.id);
      final past = DateTime.now().subtract(const Duration(days: 10));
      final future = DateTime.now().add(const Duration(days: 40));
      s.installments.addAll([
        Installment(
          id: 'due1',
          studentId: student.id,
          title: 'مستحق',
          amount: 200,
          dueDate: past,
          academicYearId: s.viewedAcademicYearId,
        ),
        Installment(
          id: 'sch1',
          studentId: student.id,
          title: 'مجدول',
          amount: 300,
          dueDate: future,
          academicYearId: s.viewedAcademicYearId,
        ),
      ]);
      student.balance = s.computeStudentBalance(student.id);

      final ok = s.addPayment(
        studentId: student.id,
        amount: 600,
        method: 'cash',
        date: DateTime.now(),
      );
      expect(ok.amount, 600);
    });
  });
}
