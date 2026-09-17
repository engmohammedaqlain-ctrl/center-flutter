/// حساب رصيد الطالب من سجلاته — المقابل حرفياً لـ `lib/balanceUtils.ts`.
///
/// بدل تخزين الرصيد رقماً جامداً يُعدَّل مع كل حركة — فيتضارب بين جهازين يعملان
/// بلا اتصال ويفوز آخر من يصل السحابة — يُحسب دائماً من السجلات الأصلية:
///
///   الرصيد = (مجموع السندات النشطة + خصوماتها) − (رسوم التسجيلات النشطة + الأقساط المطالَب بها)
///
/// القسط المعفى (`is_exempt`) لا يدخل المطالبة — `chargeableAmount` في الويب.
library;

import 'dart:math' as math;

import '../models/models.dart';

/// أقلّ من قرش لا يُعتدّ به — مطابق لـ `CENT`.
const cent = 0.005;

/// المبلغ المطالَب من القسط — مطابق لـ `chargeableAmount`.
double chargeableAmount(Installment i) => i.isExempt ? 0.0 : i.amount;

/// حالة القسط من مبلغه والمسدَّد منه — مطابق لـ `installmentStatus`.
String installmentStatusFor(double amount, double paid) {
  if (amount <= cent || paid >= amount - cent) return 'paid';
  return paid > cent ? 'partially_paid' : 'unpaid';
}

DateTime startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// القسط مستحق إذا حلّ موعده اليوم أو قبله؛ ما بعده «مجدول» وليس ديناً حالياً.
bool isInstallmentDue(Installment installment, [DateTime? today]) {
  final day = today ?? startOfToday();
  final due = DateTime(installment.dueDate.year, installment.dueDate.month, installment.dueDate.day);
  return !due.isAfter(day);
}

/// المستحق فعلياً لكل طالب له أقساط؛ صاحب الخطة يظهر ولو كان مستحقه صفراً.
Map<String, double> overdueByStudent(Iterable<Installment> installments, [DateTime? today]) {
  final day = today ?? startOfToday();
  final due = <String, double>{};
  for (final i in installments) {
    final unpaid = isInstallmentDue(i, day) ? math.max(0.0, chargeableAmount(i) - i.paidAmount) : 0.0;
    due[i.studentId] = (due[i.studentId] ?? 0) + unpaid;
  }
  return due;
}

/// ما زاد في الدفعة عن المستحق وقت دفعها: رصيد مقدَّم للطالب — `getPaymentAdvance`.
double paymentAdvance(Payment p) {
  final extra = p.amount + p.discountAmount - p.totalDueAtPayment;
  return extra > 0 ? extra : 0;
}

/// عنوان قسط رسم الحجز — مطابق لـ `SEAT_INSTALLMENT_TITLE`.
const seatTitle = 'رسم حجز مقعد';

/// ترتيب السداد: رسم الحجز أولاً ثم الأقدم استحقاقاً — `compareInstallments`.
int compareInstallments(Installment a, Installment b) {
  final seatFirst = (b.title == seatTitle ? 1 : 0) - (a.title == seatTitle ? 1 : 0);
  if (seatFirst != 0) return seatFirst;
  final byDate = isoDate(a.dueDate).compareTo(isoDate(b.dueDate));
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

/// توزيع ما دفعه الطالب على أقساطه — مطابق لـ `allocatePaymentsToInstallments`.
Map<String, double> allocatePaymentsToInstallments(
  Iterable<Installment> installments,
  Iterable<Payment> payments,
) {
  final ordered = [...installments]..sort(compareInstallments);
  final remaining = {for (final i in ordered) i.id: math.max(0.0, chargeableAmount(i))};
  final paid = {for (final i in ordered) i.id: 0.0};

  final active = payments.where((p) => !p.cancelled).toList()
    ..sort((a, b) {
      final byCreated = (a.createdAt ?? '').compareTo(b.createdAt ?? '');
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

  var pool = 0.0;
  for (final p in active) {
    var credit = p.amount + p.discountAmount;
    final target = p.installmentId;
    if (target != null && remaining.containsKey(target)) {
      final take = math.min(credit, remaining[target]!);
      remaining[target] = remaining[target]! - take;
      paid[target] = paid[target]! + take;
      credit -= take;
    }
    pool += credit;
  }

  for (final i in ordered) {
    if (pool <= cent) break;
    final take = math.min(pool, remaining[i.id]!);
    if (take <= cent) continue;
    remaining[i.id] = remaining[i.id]! - take;
    paid[i.id] = paid[i.id]! + take;
    pool -= take;
  }

  return paid;
}

/// الرصيد من السجلات — مطابق لـ `balanceFrom` في الويب.
///
/// في المدرسة تدخل **كل** الأقساط المطالَب بها (غير المعفاة) في الرصيد.
double balanceFrom({
  required Iterable<StudentEnrollment> enrollments,
  required Iterable<Installment> installments,
  required Iterable<Payment> payments,
  DateTime? today,
}) {
  var enrollmentFees = 0.0;
  for (final e in enrollments) {
    if (e.status != 'active' && e.status != 'completed') continue;
    enrollmentFees += e.appliedPrice ?? e.customPrice ?? 0;
  }

  var installmentFees = 0.0;
  for (final i in installments) {
    installmentFees += chargeableAmount(i);
  }

  var totalPaid = 0.0;
  for (final p in payments) {
    if (p.cancelled) continue;
    totalPaid += p.amount + p.discountAmount;
  }

  return totalPaid - enrollmentFees - installmentFees;
}
