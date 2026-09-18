/// خطة أقساط المرحلة، ونسخة الطالب منها — المقابل لـ `finance/feePlan.ts`.
///
/// البديل عن «أشهر الدوام» العامة: كانت تفترض أن كل مراحل المدرسة تدرس نفس
/// الأشهر وأن القسط يُستحق أول الشهر دائماً، فتولّد مستحقاً شهرياً لكل طالب نشط
/// تلقائياً. هنا تُعرَّف الخطة لكل مرحلة بمبالغها وتواريخها، ويأخذ الطالب **نسخة**
/// منها عند تسجيله: تعديل الخطة بعدها لا يمسّ أقساط من سُجّلوا قبله، وتعديل قسط
/// طالب لا يعود يُكتب فوقه في كل تشغيل.
library;

import '../models/models.dart';
import 'balance.dart';

const planIdPrefix = 'plan_';

/// رسم خاص بطالب واحد (كتاب، غرامة...) — خارج خطة المرحلة فلا يمسّه تطبيقها.
const extraIdPrefix = 'extra_';

bool isExtraChargeId(String id) => id.startsWith(extraIdPrefix);

/// أقساط خطة خاصة بطالب واحد — مستقلة عن خطة المرحلة.
const customIdPrefix = 'custom_';

String customInstallmentId(String itemId, String studentId) => '$customIdPrefix${itemId}_$studentId';

bool isCustomInstallmentId(String id) => id.startsWith(customIdPrefix);

/// معرّف حتمي: إعادة تطبيق الخطة لا تكرر القسط على الطالب نفسه.
String planInstallmentId(String itemId, String studentId) => '$planIdPrefix${itemId}_$studentId';

bool isPlanInstallmentId(String id) => id.startsWith(planIdPrefix);

/// قسط من بنود المرحلة — لا يشمل قسط الحجز `plan_seat_…`.
bool isStagePlanInstallmentId(String id) => id.startsWith(planIdPrefix) && !id.startsWith('${planIdPrefix}seat_');

/// معرّف بند الخطة من معرّف قسط الطالب؛ `null` لغير أقساط الخطة ولقسط الحجز.
String? planItemIdOf(String installmentId, String studentId) {
  if (!isStagePlanInstallmentId(installmentId)) return null;
  final suffix = '_$studentId';
  if (!installmentId.endsWith(suffix)) return null;
  final itemId = installmentId.substring(planIdPrefix.length, installmentId.length - suffix.length);
  return itemId.isEmpty ? null : itemId;
}

String seatInstallmentId(String studentId, [String? yearId]) =>
    yearId == null || yearId.isEmpty ? '${planIdPrefix}seat_$studentId' : '${planIdPrefix}seat_${yearId}_$studentId';

/// خصم الطالب المسجَّل على خطته — `StudentPlanDiscount` في الويب.
PlanDiscount? studentDiscountOf(Student? student) {
  if (student == null) return null;
  final value = student.planDiscountValue;
  final type = student.planDiscountType;
  if (type != null && type.isNotEmpty && value > 0) {
    return PlanDiscount(percentage: type == 'percentage', value: value, reason: student.planDiscountReason, from: student.planDiscountFrom);
  }
  final legacyRate = student.academicDiscountRate;
  if ((type == null || type.isEmpty) && student.academicDiscountApplied && legacyRate > 0) {
    return PlanDiscount.percent(legacyRate, reason: student.exceptionReason);
  }
  return null;
}

/// قيمة خصم الطالب من سعر قسط — بنفس تقريب `applyPlanDiscount` للنسبة.
double studentDiscountShare(double planAmount, String dueDate, PlanDiscount? discount) {
  if (discount == null || discount.value <= 0) return 0;
  final from = discount.from;
  if (from != null && from.isNotEmpty) {
    final due = dueDate.length >= 10 ? dueDate.substring(0, 10) : dueDate;
    final start = from.length >= 10 ? from.substring(0, 10) : from;
    if (due.compareTo(start) < 0) return 0;
  }
  if (discount.percentage) {
    return _round2(planAmount * ((discount.value < 100 ? discount.value : 100) / 100));
  }
  return _round2(planAmount < discount.value ? planAmount : discount.value);
}

/// مبلغ قسط الخطة كما يجب أن يكون: سعر الخطة − خصم الطالب − خصم القسط − المقتطع للحجز.
double planInstallmentAmount(double planAmount, String dueDate, PlanDiscount? discount, {double seatDeduction = 0, double discountAmount = 0}) {
  final base = planAmount;
  final expected = _round2(base - studentDiscountShare(base, dueDate, discount) - seatDeduction - discountAmount);
  return expected < 0 ? 0.0 : expected;
}

double planTotal(Iterable<PlanItem> items) {
  var sum = 0.0;
  for (final i in items) {
    sum += i.amount;
  }
  return sum;
}

double _round2(double n) => (n * 100).round() / 100;

/// بداية الفصل الأول، أو تاريخ اليوم حين لم تُضبط تواريخ المرحلة بعد.
String planStartDate(GradeFee? grade, String today) => grade == null || grade.term1Start.isEmpty ? today : grade.term1Start;

/// إضافة أشهر لتاريخ مع تثبيت اليوم؛ يوم 31 في شهر أقصر ينزل لآخر أيامه.
String addMonths(String date, int months) {
  final parts = date.split('-');
  if (parts.length < 3) return date;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return date;

  final target = DateTime(y, m + months, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  final day = d < lastDay ? d : lastDay;
  return '${target.year.toString().padLeft(4, '0')}-'
      '${target.month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// جدول أقساط متساوٍ يبدأ من تاريخ ويتكرر كل [everyMonths] — نقطة بداية تُعدَّل
/// يدوياً بعدها، لا قاعدة مفروضة.
List<PlanItem> generatePlanItems({
  required int count,
  required double amount,
  required String firstDueDate,
  required String Function() newId,
  int everyMonths = 1,
  String titlePrefix = 'القسط',
}) {
  final total = count < 0 ? 0 : count;
  final step = everyMonths < 1 ? 1 : everyMonths;
  return [
    for (var i = 0; i < total; i++) PlanItem(id: newId(), title: '$titlePrefix ${i + 1}', amount: _round2(amount), dueDate: addMonths(firstDueDate, i * step)),
  ];
}

/// خصمٌ على خطة الطالب: نسبة أو مبلغ ثابت.
class PlanDiscount {
  const PlanDiscount({required this.percentage, required this.value, this.reason = '', this.from});

  const PlanDiscount.percent(double value, {String reason = '', String? from}) : this(percentage: true, value: value, reason: reason, from: from);

  const PlanDiscount.fixed(double value, {String reason = '', String? from}) : this(percentage: false, value: value, reason: reason, from: from);

  final bool percentage;
  final double value;
  final String reason;

  /// يسري على الأقساط المستحقة من هذا التاريخ فصاعداً — `plan_discount_from`.
  final String? from;
}

/// صفٌّ في نسخة الطالب من الخطة، قبل أن يصير قسطاً محفوظاً.
class StudentPlanRow {
  const StudentPlanRow({required this.id, required this.title, required this.amount, required this.dueDate, this.originalAmount, this.seatDeduction = 0});

  final String id;
  final String title;
  final double amount;
  final String dueDate;
  final double? originalAmount;
  final double seatDeduction;

  StudentPlanRow copyWith({double? amount, double? originalAmount, double? seatDeduction}) => StudentPlanRow(
    id: id,
    title: title,
    amount: amount ?? this.amount,
    dueDate: dueDate,
    originalAmount: originalAmount ?? this.originalAmount,
    seatDeduction: seatDeduction ?? this.seatDeduction,
  );
}

/// تطبيق خصم على الأقساط — مطابق حرفياً لـ `applyPlanDiscount` في الويب:
/// - نسبة مئوية: تُخصم نفس النسبة من كل قسط.
/// - مبلغ مقطوع: يُخصم نفس المبلغ من كل قسط (لا يتجاوز قيمة القسط).
List<StudentPlanRow> applyPlanDiscount(List<StudentPlanRow> items, PlanDiscount? discount) {
  if (discount == null || discount.value <= 0 || items.isEmpty) return items;

  if (discount.percentage) {
    final rate = (discount.value < 100 ? discount.value : 100) / 100;
    if (rate <= 0) return items;
    return [
      for (final item in items)
        () {
          final amount = item.amount;
          final share = _round2(amount * rate);
          return item.copyWith(amount: _round2(amount - share), originalAmount: amount);
        }(),
    ];
  }

  // مبلغ مقطوع: نفس القيمة من كل قسط — لا يُوزَّع على المجموع
  final perInstallment = discount.value;
  return [
    for (final item in items)
      () {
        final amount = item.amount;
        final share = _round2(amount < perInstallment ? amount : perInstallment);
        return item.copyWith(amount: _round2(amount - share), originalAmount: amount);
      }(),
  ];
}

/// يقتطع رسم الحجز من الأقساط بترتيبها الزمني؛ ما يزيد عن قسط ينتقل للذي يليه.
List<StudentPlanRow> deductSeatFee(List<StudentPlanRow> plan, double fee) {
  var remaining = fee;
  final sorted = [...plan]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return [
    for (final inst in sorted)
      () {
        final cut = _round2(inst.amount < remaining ? inst.amount : remaining);
        remaining -= cut;
        return cut > 0 ? inst.copyWith(amount: _round2(inst.amount - cut), seatDeduction: cut) : inst;
      }(),
  ];
}

/// كيف تُنسَخ خطة المرحلة عند تسجيل الطالب — `EnrollmentPlanMode`.
enum EnrollmentPlanMode {
  /// كل أقساط الخطة بتواريخها.
  full,

  /// أقساط تاريخها ≥ تاريخ الالتحاق فقط — لا يظهر «دين سابق».
  fromEnrollment,
}

/// يُبقي بنود الخطة التي يستحقّها الملتحق المتأخر: أقساط **شهر** تسجيله فما بعد.
///
/// المقارنة بالشهر لا باليوم — مطابق لـ `filterPlanFromEnrollment` في الويب.
List<PlanItem> filterPlanFromEnrollment(List<PlanItem> items, String enrollmentDate) {
  final fromMonth = enrollmentDate.length >= 7 ? enrollmentDate.substring(0, 7) : enrollmentDate;
  if (fromMonth.isEmpty) return items;
  return items.where((i) {
    final dueMonth = i.dueDate.length >= 7 ? i.dueDate.substring(0, 7) : i.dueDate;
    return dueMonth.compareTo(fromMonth) >= 0;
  }).toList();
}

/// نسخة الطالب من خطة مرحلته.
///
/// الخصم يوزَّع على الأقساط، ورسم الحجز إما يُقتطع من أولها أو يبقى مطالبة مستقلة.
List<StudentPlanRow> buildStudentPlan(
  List<PlanItem> items,
  String studentId, {
  double seatFee = 0,
  bool deductSeat = true,
  PlanDiscount? discount,
  String enrollmentDate = '',
  EnrollmentPlanMode enrollmentMode = EnrollmentPlanMode.full,
  String? seatId,
  bool customIds = false,
}) {
  final source = enrollmentMode == EnrollmentPlanMode.fromEnrollment
      ? filterPlanFromEnrollment(items, enrollmentDate)
      : items;
  final makeId = customIds ? customInstallmentId : planInstallmentId;

  final discounted = applyPlanDiscount([
    for (final i in source)
      StudentPlanRow(
        id: makeId(i.id, studentId),
        title: i.title,
        amount: i.amount,
        dueDate: i.dueDate,
      ),
  ], discount);

  final fee = seatFee < 0 ? 0.0 : seatFee;
  if (fee <= 0) return discounted;

  final rows = deductSeat ? deductSeatFee(discounted, fee) : discounted;

  var total = 0.0;
  for (final i in discounted) {
    total += i.amount;
  }
  final seatAmount = deductSeat && discounted.isNotEmpty ? (fee < total ? fee : total) : fee;
  final dates = [if (enrollmentDate.isNotEmpty) enrollmentDate, if (rows.isNotEmpty) rows.first.dueDate]..sort();
  final seatDue = dates.isNotEmpty ? dates.first : enrollmentDate;

  return [
    StudentPlanRow(
      id: seatId ?? '${planIdPrefix}seat_$studentId',
      title: seatTitle,
      amount: seatAmount,
      dueDate: seatDue,
    ),
    ...rows,
  ];
}

/// أقساط جاهزة للحفظ من نسخة الطالب — مع `original_amount` و`plan_discount_share` كويب.
List<Installment> toInstallments(List<StudentPlanRow> rows, String studentId, String now, {String academicYearId = ''}) => [
  for (final row in rows)
    () {
      final isPlan = isStagePlanInstallmentId(row.id);
      final seat = row.seatDeduction;
      final original = row.originalAmount ?? (isPlan ? _round2(row.amount + seat) : null);
      final share = isPlan && original != null
          ? (() {
              final s = _round2(original - row.amount - seat);
              return s < 0 ? 0.0 : s;
            })()
          : 0.0;
      return Installment(
        id: row.id,
        studentId: studentId,
        title: row.title,
        amount: row.amount,
        originalAmount: original,
        seatDeduction: seat,
        planDiscountShare: share,
        academicYearId: academicYearId,
        dueDate: parseIsoDate(row.dueDate) ?? DateTime.now(),
        status: row.amount <= 0 ? 'paid' : 'unpaid',
        syncStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
    }(),
];
