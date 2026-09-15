/// حساب رصيد الطالب من سجلاته — المقابل حرفياً لـ `lib/balanceUtils.ts`.
///
/// بدل تخزين الرصيد رقماً جامداً يُعدَّل مع كل حركة — فيتضارب بين جهازين يعملان
/// بلا اتصال ويفوز آخر من يصل السحابة — يُحسب دائماً من السجلات الأصلية:
///
///   الرصيد = (مجموع السندات النشطة + خصوماتها) − (رسوم التسجيلات النشطة + الأقساط في المدرسة)
///
/// في المدرسة الأقساط (ومنها المستحقات الشهرية ورسم الحجز) هي مصدر المطالبة،
/// **وما حان موعده منها وحده**: الطالب في شهره الأول لا يُطالَب بقسط الشهر
/// القادم لأنه لم يدرسه بعد. من سدّد ما استُحق عليه رصيده صفر، ومن دفع فوقه
/// يظهر الفائض «له» ويُخصم من القسط التالي حين يحلّ.
/// وفي المركز تبقى رسوم التسجيل وحدها، لأن أقساطه غير مربوطة بها.
library;

import 'dart:math' as math;

import '../models/models.dart';

/// أقلّ من قرش لا يُعتدّ به — مطابق لـ `CENT`.
const cent = 0.005;

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
    final unpaid = isInstallmentDue(i, day) ? math.max(0.0, i.amount - i.paidAmount) : 0.0;
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
///
/// تاريخ الحجز هو يوم التسجيل، فبالتاريخ وحده يأتي بعد مستحق الشهر (أوله)،
/// فتذهب الدفعة العامة إلى الشهر ويبقى الحجز معلّقاً على الطالب.
int compareInstallments(Installment a, Installment b) {
  final seatFirst = (b.title == seatTitle ? 1 : 0) - (a.title == seatTitle ? 1 : 0);
  if (seatFirst != 0) return seatFirst;
  final byDate = isoDate(a.dueDate).compareTo(isoDate(b.dueDate));
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

/// توزيع ما دفعه الطالب على أقساطه — مطابق لـ `allocatePaymentsToInstallments`.
///
/// السند المربوط بقسط يُسدِّد قسطه أولاً، وما يزيد يُضاف إلى غير المربوط، ثم
/// يُوزَّع الباقي على الأقدم استحقاقاً. المسدَّد مشتقّ من السندات دائماً، فالإلغاء
/// والدفعة التي تغطي أكثر من شهر يعطيان النتيجة نفسها على كل جهاز.
Map<String, double> allocatePaymentsToInstallments(
  Iterable<Installment> installments,
  Iterable<Payment> payments,
) {
  final ordered = [...installments]..sort(compareInstallments);
  final remaining = {for (final i in ordered) i.id: math.max(0.0, i.amount)};
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

  for (final inst in ordered) {
    if (pool <= cent) break;
    final take = math.min(pool, remaining[inst.id]!);
    remaining[inst.id] = remaining[inst.id]! - take;
    paid[inst.id] = paid[inst.id]! + take;
    pool -= take;
  }

  return paid;
}

/// الرصيد من السجلات — مطابق لـ `balanceFrom`.
///
/// الأقساط المستحقة حتى [today] وحدها تدخل الرصيد.
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
  final day = today ?? startOfToday();
  for (final i in installments) {
    // القسط القادم ليس ديناً بعد؛ يصير كذلك يوم استحقاقه
    if (!isInstallmentDue(i, day)) continue;
    installmentFees += i.amount;
  }

  var totalPaid = 0.0;
  for (final p in payments) {
    if (p.cancelled) continue;
    totalPaid += p.amount + p.discountAmount;
  }

  return totalPaid - enrollmentFees - installmentFees;
}
