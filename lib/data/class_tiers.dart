import '../models/models.dart';
import 'store.dart';

/// المرحلة الكبرى لاسم مرحلة دراسية — مطابق لـ `getGradeTier` في SchoolClasses.tsx:
/// جدول الرسوم أولاً، ثم الأسماء والأرقام الشائعة. ما لا يُعرف يعود `other`.
String gradeTier(AppStore store, String grade) {
  final name = grade.trim();
  if (name.isEmpty) return 'other';

  final fee = store.gradeFees.where((f) => f.gradeName.trim().toLowerCase() == name.toLowerCase()).firstOrNull;
  if (fee != null && educationalStageTiers.containsKey(fee.tier)) return fee.tier;

  final g = name.toLowerCase();
  bool any(List<String> words) => words.any(g.contains);

  if (any(['ثانوي', 'توجيهي', 'ثاني عشر', 'حادي عشر', 'عاشر']) ||
      RegExp(r'\b(10|11|12)\b').hasMatch(g) ||
      RegExp('[١][٠-٢]').hasMatch(g)) {
    return 'secondary';
  }
  if (any(['إعدادي', 'متوسط', 'تاسع', 'ثامن', 'سابع', 'سادس', 'خامس']) ||
      RegExp(r'\b[5-9]\b').hasMatch(g) ||
      RegExp('[٥-٩]').hasMatch(g)) {
    return 'middle';
  }
  if (any(['ابتدائي', 'رابع', 'ثالث', 'ثاني', 'أول']) || RegExp(r'\b[1-4]\b').hasMatch(g) || RegExp('[١-٤]').hasMatch(g)) {
    return 'primary';
  }
  if (any(['روضة', 'رياض', 'تمهيدي', 'بستان', 'kg'])) return 'kindergarten';
  return 'other';
}

/// مرحلة الصف: المحفوظة معه إن وُجدت، وإلا المشتقة من مرحلته الدراسية.
String classTier(AppStore store, Classroom room) {
  if (room.tier.isNotEmpty && educationalStageTiers.containsKey(room.tier)) return room.tier;
  return gradeTier(store, room.gradeLevel);
}
