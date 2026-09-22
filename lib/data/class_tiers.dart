import '../models/models.dart';
import 'academic_matching.dart';
import 'store.dart';

/// تخمين أوّلي من اسم المرحلة — مطابق لـ `guessStageTier` في الويب.
/// الكلمة الصريحة (ابتدائي، إعدادي…) تسبق رقم الصف.
String? guessStageTier(String name) {
  final g = name.trim().toLowerCase();
  if (g.isEmpty) return null;

  if (RegExp(r'روضة|رياض|تمهيدي|بستان|kg').hasMatch(g)) return 'kindergarten';
  if (RegExp(r'ثانوي|توجيهي').hasMatch(g)) return 'secondary';
  if (RegExp(r'إعدادي|اعدادي|متوسط').hasMatch(g)) return 'middle';
  if (RegExp(r'ابتدائي').hasMatch(g)) return 'primary';

  if (RegExp(r'عاشر|حادي عشر|ثاني عشر|\b(10|11|12)\b|١[٠-٢]').hasMatch(g)) {
    return 'secondary';
  }
  if (RegExp(r'خامس|سادس|سابع|ثامن|تاسع|\b[5-9]\b|[٥-٩]').hasMatch(g)) {
    return 'middle';
  }
  if (RegExp(r'أول|اول|ثاني|ثالث|رابع|\b[1-4]\b|[١-٤]').hasMatch(g)) {
    return 'primary';
  }
  return null;
}

/// المرحلة الكبرى لاسم مرحلة دراسية — مطابق لـ `getGradeTier` في SchoolClasses.tsx:
/// جدول الرسوم أولاً، ثم التخمين من الاسم. ما لا يُعرف يعود `other`.
String gradeTier(AppStore store, String grade) {
  final name = grade.trim();
  if (name.isEmpty) return 'other';

  final fee = store.gradeFeesInViewedYear
      .where((f) => isSameGrade(f.gradeName, name))
      .firstOrNull;
  if (fee != null && educationalStageTiers.containsKey(fee.tier)) return fee.tier;

  return guessStageTier(name) ?? 'other';
}

/// مرحلة الصف: كـ الويب — من الرسوم/اسم المرحلة، لا من `rooms.stage_tier`
/// الافتراضي (`secondary`) الذي كان يجمع كل الصفوف تحت الثانوية.
String classTier(AppStore store, Classroom room) {
  final fromGrade = gradeTier(store, room.gradeLevel);
  final stored = room.tier.trim();
  if (stored.isEmpty) return fromGrade;
  // secondary كان الافتراض القديم: لا نثق به إن كان اسم المرحلة يقول غير ذلك
  if (stored == 'secondary' && fromGrade != 'secondary' && fromGrade != 'other') {
    return fromGrade;
  }
  if (educationalStageTiers.containsKey(stored)) return stored;
  return fromGrade;
}
