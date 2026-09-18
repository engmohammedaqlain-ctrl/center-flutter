/// أجور المعلمين — المقابل لـ `features/finance/teacherSalary.ts`.
///
/// صرفٌ حرّ لا مستحقات: كان النظام يحسب «راتباً مستحقاً» و«متبقياً» لكل معلم عن
/// كل شهر، ويلاحق المدير بها بلا طريقة لإيقافها. المدرسة عمل خاص لا وظيفة
/// حكومية: شهر بلا راتب، وشهر بأكثر من الراتب، وشهر إجازة. فلم يبقَ إلا ما صُرف
/// فعلاً، والراتب المسجّل للمعلم رقمٌ يُقترح في السند ويُعدَّل أو يُتجاهل.
library;

import '../models/models.dart';

/// أنواع سند صرف المعلم كما تُعرض — `PAYOUT_TYPE_NAMES`.
const payoutTypeNames = <String, String>{
  'salary': 'راتب',
  'advance': 'سلفة',
  'bonus': 'مكافأة',
};

String monthLabel(String month) =>
    month.length < 7 ? month : '${month.substring(5, 7)}/${month.substring(0, 4)}';

String monthKeyOf(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// بيان سند الراتب كما في الويب: «راتب/سلفة/مكافأة + الاسم + MM/YYYY».
String payoutDescription(TeacherPayout p, {String fallbackName = ''}) {
  final type = payoutTypeNames[p.payoutType] ?? 'راتب';
  final name = p.teacherName.trim().isNotEmpty
      ? p.teacherName.trim()
      : fallbackName.trim();
  final month = monthLabel(salaryMonthOf(p));
  if (name.isEmpty) return '$type $month';
  return '$type $name $month';
}

/// تصنيف سندات أجور المعلمين في السجل والوصل — مطابق لـ Finance.tsx.
const payoutExpenseCategory = 'رواتب';

/// آخر يوم في شهر بصيغة `YYYY-MM` — نهاية المدة التي يُنسب لها السند.
String monthEnd(String month) {
  final parts = month.split('-');
  final y = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
  final last = DateTime(y, m + 1, 0).day;
  return '$month-${last.toString().padLeft(2, '0')}';
}

/// شهر الصرف الذي يُنسب له السند، لا يوم صرفه: راتب أيلول المصروف في تشرين لأيلول.
String salaryMonthOf(TeacherPayout p) {
  final raw = p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate;
  return raw.length < 7 ? raw : raw.substring(0, 7);
}

/// ما صُرف لمعلم عن شهر، مفصولاً بنوعه — `paidInMonth`.
///
/// [teacherIds] يشمل نسخ المعلم في الأعوام السابقة ([linkedTeacherIds]) فلا
/// يُقترح صرف راتب صُرف قبل إغلاق العام لنسخة أخرى.
({double salary, double advance, double bonus, double total}) paidInMonth(
  Iterable<TeacherPayout> payouts,
  Set<String> teacherIds,
  String month,
) {
  var salary = 0.0;
  var advance = 0.0;
  var bonus = 0.0;
  for (final p in payouts) {
    if (!teacherIds.contains(p.teacherId) || salaryMonthOf(p) != month) continue;
    switch (p.payoutType) {
      case 'advance':
        advance += p.amount;
      case 'bonus':
        bonus += p.amount;
      default:
        salary += p.amount;
    }
  }
  return (salary: salary, advance: advance, bonus: bonus, total: salary + advance + bonus);
}
