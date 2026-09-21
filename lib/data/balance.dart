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

/// اليوم كعدد `yyyymmdd` — للمقارنة بلا بناء تواريخ ولا تنسيق نصوص.
///
/// المقارنة كانت تُنسَّق نصاً (`isoDate`) أو تبني `DateTime` جديداً في كل نداء.
/// ترتيب عشرة آلاف قسط يُجري مئات آلاف المقارنات، فصار التنسيق وحده يستغرق
/// جزءاً من الثانية في كل إعادة بناء لشاشة المالية.
int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// القسط مستحق إذا حلّ موعده اليوم أو قبله؛ ما بعده «مجدول» وليس ديناً حالياً.
bool isInstallmentDue(Installment installment, [DateTime? today]) {
  final day = today ?? startOfToday();
  return dayKey(installment.dueDate) <= dayKey(day);
}

double unpaidOf(Installment i) => math.max(0.0, chargeableAmount(i) - i.paidAmount);

/// المستحق فعلياً لكل طالب له أقساط؛ صاحب الخطة يظهر ولو كان مستحقه صفراً.
Map<String, double> overdueByStudent(Iterable<Installment> installments, [DateTime? today]) {
  final day = today ?? startOfToday();
  final due = <String, double>{};
  for (final i in installments) {
    final unpaid = isInstallmentDue(i, day) ? unpaidOf(i) : 0.0;
    due[i.studentId] = (due[i.studentId] ?? 0) + unpaid;
  }
  return due;
}

/// المستحق الحالّ والمجدول — مطابق لـ `dueAndScheduled`.
({double due, double scheduled}) dueAndScheduled(
  Iterable<Installment> installments, {
  double? fallbackBalance,
  DateTime? today,
}) {
  final list = installments.toList();
  if (list.isEmpty) {
    return (due: math.max(0.0, -(fallbackBalance ?? 0)), scheduled: 0);
  }
  final day = today ?? startOfToday();
  var due = 0.0;
  var scheduled = 0.0;
  for (final i in list) {
    if (isInstallmentDue(i, day)) {
      due += unpaidOf(i);
    } else {
      scheduled += unpaidOf(i);
    }
  }
  return (due: due, scheduled: scheduled);
}

/// يفصل لكل طالب: ما حلّ موعده وما بقي مجدولاً — `installmentBucketsByStudent`.
({Map<String, double> due, Map<String, double> scheduled}) installmentBucketsByStudent(
  Iterable<Installment> installments, [
  DateTime? today,
]) {
  final day = today ?? startOfToday();
  final due = <String, double>{};
  final scheduled = <String, double>{};
  for (final i in installments) {
    due.putIfAbsent(i.studentId, () => 0);
    scheduled.putIfAbsent(i.studentId, () => 0);
    if (isInstallmentDue(i, day)) {
      due[i.studentId] = due[i.studentId]! + unpaidOf(i);
    } else {
      scheduled[i.studentId] = scheduled[i.studentId]! + unpaidOf(i);
    }
  }
  return (due: due, scheduled: scheduled);
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
  final byDate = dayKey(a.dueDate).compareTo(dayKey(b.dueDate));
  return byDate != 0 ? byDate : a.id.compareTo(b.id);
}

/// توزيع ما دفعه الطالب على أقساطه — مطابق لـ `allocatePaymentsToInstallments`.
///
/// سند خارج (رد/عكس) يُفك أولاً من القسط الذي سدّده السند الأصلي، والباقي من
/// المجمّع؛ وما رُدّ أكثر من المال الحر يُفك من أحدث الأقساط المسددة.
Map<String, double> allocatePaymentsToInstallments(
  Iterable<Installment> installments,
  Iterable<Payment> payments,
) {
  final ordered = [...installments]..sort(compareInstallments);
  final remaining = {for (final i in ordered) i.id: math.max(0.0, chargeableAmount(i))};
  final paid = {for (final i in ordered) i.id: 0.0};

  final all = [...payments];
  final byId = {for (final p in all) p.id: p};
  final active = all.where((p) => !p.cancelled).toList()
    ..sort((a, b) {
      final byCreated = (a.createdAt ?? '').compareTo(b.createdAt ?? '');
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

  var pool = 0.0;
  for (final p in active) {
    var credit = p.amount + p.discountAmount;

    // سند خارج (رد أو عكس): يُفك من القسط الذي سدّده السند الأصلي أولاً
    if (credit < 0) {
      final originId = p.reversesPaymentId;
      final origin = originId == null ? null : byId[originId];
      final back = p.installmentId ?? origin?.installmentId;
      if (back != null && paid.containsKey(back)) {
        final give = math.min(-credit, paid[back]!);
        paid[back] = paid[back]! - give;
        remaining[back] = remaining[back]! + give;
        credit += give;
      }
      pool += credit;
      continue;
    }

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

  // ما رُدّ أكثر من المال الحر يُفك من أحدث الأقساط المسددة
  for (final i in ordered.reversed) {
    if (pool >= -cent) break;
    final give = math.min(-pool, paid[i.id]!);
    paid[i.id] = paid[i.id]! - give;
    remaining[i.id] = remaining[i.id]! + give;
    pool += give;
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
