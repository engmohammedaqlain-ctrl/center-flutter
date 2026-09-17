/// تعديلات أقساط الطالب ذات المعنى — مطابقة لـ `InstallmentAdjustments` في الويب.
library;

import '../models/models.dart';
import 'balance.dart';
import 'fee_plan.dart';
import 'grade_plan_sync.dart';
import 'store.dart';

double _round2(double value) => (value * 100).round() / 100;

enum InstallmentDiscountKind { amount, exempt, none }

class InstallmentDiscountInput {
  const InstallmentDiscountInput.amount(this.amount, this.reason)
    : kind = InstallmentDiscountKind.amount;
  const InstallmentDiscountInput.exempt(this.reason)
    : kind = InstallmentDiscountKind.exempt,
      amount = 0;
  const InstallmentDiscountInput.none()
    : kind = InstallmentDiscountKind.none,
      amount = 0,
      reason = '';

  final InstallmentDiscountKind kind;
  final double amount;
  final String reason;
}

class MoneyMove {
  const MoneyMove({required this.title, required this.amount});
  final String title;
  final double amount;
}

class MoneyMovePreview {
  const MoneyMovePreview({
    required this.paid,
    required this.movesTo,
    required this.credit,
  });

  final double paid;
  final List<MoneyMove> movesTo;
  final double credit;
}

class InstallmentAdjustments {
  const InstallmentAdjustments(this.store);

  final AppStore store;

  static bool canRemove(Installment installment) =>
      isExtraChargeId(installment.id) || installment.id.startsWith('custom_');

  void setDiscount(Installment installment, InstallmentDiscountInput input) {
    store.setInstallmentDiscount(
      installment,
      kind: input.kind.name,
      amount: input.amount,
      reason: input.reason,
    );
  }

  MoneyMovePreview previewDiscount(
    Installment installment,
    InstallmentDiscountInput input,
  ) {
    final installments = store.installments
        .where((i) => i.studentId == installment.studentId)
        .toList();
    final payments = store.payments
        .where((p) => p.studentId == installment.studentId)
        .toList();
    final gross = _round2(installment.amount + installment.discountAmount);
    final changed = Installment(
      id: installment.id,
      studentId: installment.studentId,
      title: installment.title,
      amount: input.kind == InstallmentDiscountKind.amount
          ? _round2((gross - input.amount).clamp(0, double.infinity))
          : gross,
      dueDate: installment.dueDate,
      originalAmount: installment.originalAmount,
      paidAmount: installment.paidAmount,
      isExempt: input.kind == InstallmentDiscountKind.exempt,
      exemptReason: installment.exemptReason,
      discountAmount: installment.discountAmount,
      discountReason: installment.discountReason,
      planDiscountShare: installment.planDiscountShare,
      seatDeduction: installment.seatDeduction,
      academicYearId: installment.academicYearId,
      status: installment.status,
      syncStatus: installment.syncStatus,
      createdAt: installment.createdAt,
      updatedAt: installment.updatedAt,
    );

    final before = allocatePaymentsToInstallments(installments, payments);
    final after = allocatePaymentsToInstallments([
      for (final i in installments)
        if (i.id == installment.id) changed else i,
    ], payments);
    final moves = <MoneyMove>[];
    var moved = 0.0;
    for (final other in installments) {
      if (other.id == installment.id) continue;
      final gain = _round2((after[other.id] ?? 0) - (before[other.id] ?? 0));
      if (gain > cent) {
        moves.add(MoneyMove(title: other.title, amount: gain));
        moved += gain;
      }
    }
    final released = _round2(
      ((before[installment.id] ?? 0) - (after[installment.id] ?? 0)).clamp(
        0,
        double.infinity,
      ),
    );
    return MoneyMovePreview(
      paid: released,
      movesTo: moves,
      credit: _round2((released - moved).clamp(0, double.infinity)),
    );
  }

  void remove(Installment installment, {String reason = ''}) =>
      store.removeInstallmentAdjustment(installment, reason: reason);

  Installment addExtraCharge({
    required String studentId,
    required String title,
    required double amount,
    required DateTime dueDate,
  }) => store.addExtraCharge(
    studentId: studentId,
    title: title,
    amount: amount,
    dueDate: dueDate,
  );

  GradePlanSyncResult setStudentDiscount(
    String studentId,
    PlanDiscount? discount, {
    bool apply = false,
  }) {
    final student = store.studentById(studentId);
    if (student == null) throw StoreException('الطالب غير موجود');
    if (student.usesCustomPlan) {
      throw StoreException('الطالب على خطة مخصصة: عدّل مبالغ خطته مباشرة');
    }
    if (student.gradeLevel.trim().isEmpty) {
      throw StoreException('الطالب بلا مرحلة');
    }
    if (discount != null) {
      if (discount.value <= 0) {
        throw StoreException('أدخل قيمة خصم أكبر من صفر');
      }
      if (discount.percentage && discount.value >= 100) {
        throw StoreException(
          'خصم 100% إعفاء كامل — استخدم الإعفاء على الأقساط',
        );
      }
    }
    if (apply) {
      return store.setStudentPlanDiscountValue(studentId, discount);
    }
    return GradePlanSync.run(
      store,
      student.gradeLevel,
      opts: GradePlanSyncOptions(
        studentIds: {studentId},
        includePaid: true,
        repriceOnly: true,
        discountChange: true,
        discountOverride: {studentId: discount},
        checkPermission: false,
      ),
    );
  }
}
