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

/// معرّف حتمي: إعادة تطبيق الخطة لا تكرر القسط على الطالب نفسه.
String planInstallmentId(String itemId, String studentId) => '$planIdPrefix${itemId}_$studentId';

bool isPlanInstallmentId(String id) => id.startsWith(planIdPrefix);

double planTotal(Iterable<PlanItem> items) {
  var sum = 0.0;
  for (final i in items) {
    sum += i.amount;
  }
  return sum;
}

double _round2(double n) => (n * 100).round() / 100;

/// بداية الفصل الأول، أو تاريخ اليوم حين لم تُضبط تواريخ المرحلة بعد.
String planStartDate(GradeFee? grade, String today) =>
    grade == null || grade.term1Start.isEmpty ? today : grade.term1Start;

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
    for (var i = 0; i < total; i++)
      PlanItem(
        id: newId(),
        title: '$titlePrefix ${i + 1}',
        amount: _round2(amount),
        dueDate: addMonths(firstDueDate, i * step),
      ),
  ];
}

/// خصمٌ على خطة الطالب: نسبة أو مبلغ ثابت.
class PlanDiscount {
  const PlanDiscount({required this.percentage, required this.value, this.reason = ''});

  const PlanDiscount.percent(double value, {String reason = ''})
      : this(percentage: true, value: value, reason: reason);

  const PlanDiscount.fixed(double value, {String reason = ''})
      : this(percentage: false, value: value, reason: reason);

  final bool percentage;
  final double value;
  final String reason;
}

/// صفٌّ في نسخة الطالب من الخطة، قبل أن يصير قسطاً محفوظاً.
class StudentPlanRow {
  const StudentPlanRow({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    this.originalAmount,
  });

  final String id;
  final String title;
  final double amount;
  final String dueDate;
  final double? originalAmount;

  StudentPlanRow copyWith({double? amount, double? originalAmount}) => StudentPlanRow(
        id: id,
        title: title,
        amount: amount ?? this.amount,
        dueDate: dueDate,
        originalAmount: originalAmount ?? this.originalAmount,
      );
}

/// توزيع خصم على الأقساط بنسبة قيمة كل قسط، والكسر المتبقي يُصحَّح على آخر قسط
/// حتى يساوي مجموعُ المخصوم قيمةَ الخصم بالضبط.
List<StudentPlanRow> applyPlanDiscount(List<StudentPlanRow> items, PlanDiscount? discount) {
  if (discount == null || discount.value <= 0 || items.isEmpty) return items;

  var total = 0.0;
  for (final i in items) {
    total += i.amount;
  }
  if (total <= 0) return items;

  final cut = discount.percentage
      ? (total * (discount.value < 100 ? discount.value : 100)) / 100
      : (discount.value < total ? discount.value : total);
  if (cut <= 0) return items;

  var taken = 0.0;
  return [
    for (var index = 0; index < items.length; index++)
      () {
        final item = items[index];
        final share = index == items.length - 1 ? _round2(cut - taken) : _round2((item.amount / total) * cut);
        taken = _round2(taken + share);
        return item.copyWith(amount: _round2(item.amount - share), originalAmount: item.amount);
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
        final cut = inst.amount < remaining ? inst.amount : remaining;
        remaining -= cut;
        return inst.copyWith(amount: _round2(inst.amount - cut));
      }(),
  ];
}

/// نسخة الطالب من خطة مرحلته.
///
/// الخصم يوزَّع على الأقساط، ورسم الحجز إما يُقتطع من أولها (فلا يدفع الطالب أكثر
/// من المجموع) أو يبقى مطالبة مستقلة فوقها.
List<StudentPlanRow> buildStudentPlan(
  List<PlanItem> items,
  String studentId, {
  double seatFee = 0,
  bool deductSeat = true,
  PlanDiscount? discount,
  String enrollmentDate = '',
}) {
  final discounted = applyPlanDiscount(
    [
      for (final i in items)
        StudentPlanRow(
          id: planInstallmentId(i.id, studentId),
          title: i.title,
          amount: i.amount,
          dueDate: i.dueDate,
        ),
    ],
    discount,
  );

  final fee = seatFee < 0 ? 0.0 : seatFee;
  if (fee <= 0) return discounted;

  final rows = deductSeat ? deductSeatFee(discounted, fee) : discounted;

  // سلفة على الخطة: لا يُطالَب من رسم الحجز بأكثر مما خُصم منها
  var total = 0.0;
  for (final i in discounted) {
    total += i.amount;
  }
  final seatAmount = deductSeat && discounted.isNotEmpty ? (fee < total ? fee : total) : fee;
  final dates = [
    if (enrollmentDate.isNotEmpty) enrollmentDate,
    if (rows.isNotEmpty) rows.first.dueDate,
  ]..sort();
  final seatDue = dates.isNotEmpty ? dates.first : enrollmentDate;

  return [
    StudentPlanRow(id: '${planIdPrefix}seat_$studentId', title: seatTitle, amount: seatAmount, dueDate: seatDue),
    ...rows,
  ];
}

/// أقساط جاهزة للحفظ من نسخة الطالب.
List<Installment> toInstallments(List<StudentPlanRow> rows, String studentId, String now) => [
      for (final row in rows)
        Installment(
          id: row.id,
          studentId: studentId,
          title: row.title,
          amount: row.amount,
          originalAmount: row.originalAmount,
          dueDate: parseIsoDate(row.dueDate) ?? DateTime.now(),
          status: row.amount <= 0 ? 'paid' : 'unpaid',
          syncStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        ),
    ];
