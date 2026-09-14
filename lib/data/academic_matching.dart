/// مطابقة المراحل والشعب — المرجع الوحيد، مطابق لـ `lib/academicMatching.ts`.
///
/// كانت المطابقة مكرّرة في مواضع بقواعد متباينة، أكثرها يعتمد `contains`:
/// فـ«علمي 1» يطابق «علمي 10»، و«الثاني عشر» يبتلع «الثاني عشر علمي» و«الثاني
/// عشر أدبي» معاً. النتيجة لم تكن عرضاً خاطئاً فقط، بل تسجيل طلاب شعبة في مواد
/// شعبة أخرى. المطابقة هنا تامة بعد تطبيع الكتابة العربية، وغياب القيمة لا
/// يطابق شيئاً — إلا حيث يكون الغياب معناه «عام» صراحةً.
library;

import '../models/models.dart';

/// قيمة المرحلة التي تعني «تصلح لكل المراحل» في نموذج المادة الدراسية.
const generalGradeLabel = 'عام / كل المراحل';

final _diacriticsAndTatweel = RegExp('[ً-ْٰـ]');
final _alef = RegExp('[إأآٱ]');
final _yeh = RegExp('[ىئ]');
final _arabicDigits = RegExp('[٠-٩]');
final _persianDigits = RegExp('[۰-۹]');
final _spaces = RegExp(r'\s+');

/// تطبيع نص أكاديمي (مرحلة أو اسم شعبة) قبل المقارنة.
///
/// يوحّد صور الألف والياء والهاء والأرقام العربية والمسافات، فـ«الثانى عشر  علمى»
/// و«الثاني عشر علمي» نص واحد. لا يحذف كلمة ولا يختزل الاسم، حتى لا تتطابق
/// مرحلتان مختلفتان بعد التطبيع.
String normalizeAcademicText(String? value) {
  if (value == null || value.isEmpty) return '';
  return value
      .replaceAll(_diacriticsAndTatweel, '')
      .replaceAll(_alef, 'ا')
      .replaceAll(_yeh, 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ة', 'ه')
      .replaceAllMapped(_arabicDigits, (m) => '${m[0]!.codeUnitAt(0) - 0x0660}')
      .replaceAllMapped(_persianDigits, (m) => '${m[0]!.codeUnitAt(0) - 0x06F0}')
      .replaceAll(_spaces, ' ')
      .trim()
      .toLowerCase();
}

/// هل المرحلتان واحدة؟ غياب أي طرف لا يطابق — لا يجوز أن يطابق الفراغ كل شيء.
bool isSameGrade(String? a, String? b) {
  final na = normalizeAcademicText(a);
  return na.isNotEmpty && na == normalizeAcademicText(b);
}

/// هل اسم الشعبة واحد؟
bool isSameSectionName(String? a, String? b) {
  final na = normalizeAcademicText(a);
  return na.isNotEmpty && na == normalizeAcademicText(b);
}

/// مادة عامة: بلا مرحلة محددة، أو موسومة صراحةً بأنها لكل المراحل.
bool isGeneralSubject(String? subjectGrade) {
  final g = normalizeAcademicText(subjectGrade);
  return g.isEmpty || g == normalizeAcademicText(generalGradeLabel);
}

/// هل تُدرَّس هذه المادة في هذه المرحلة؟ شعبة بلا مرحلة تقبل كل المواد.
bool subjectAppliesToGrade(String? subjectGrade, String? gradeLevel) {
  if (normalizeAcademicText(gradeLevel).isEmpty) return true;
  if (isGeneralSubject(subjectGrade)) return true;
  return isSameGrade(subjectGrade, gradeLevel);
}

/// هل ينتمي الطالب لهذه الشعبة بحسب اسم شعبته ومرحلته؟
///
/// للاستدلال فقط (بيانات بلا ربط صريح، واقتراح الشعبة). الربط المعتمد هو
/// `room_id` في التسجيل.
bool belongsToSection({
  required String? section,
  required String? grade,
  required String? roomName,
  required String? roomGrade,
}) {
  if (!isSameSectionName(section, roomName)) return false;
  if (normalizeAcademicText(roomGrade).isEmpty) return true;
  return isSameGrade(grade, roomGrade);
}

bool studentBelongsToRoom(Student student, Classroom room) => belongsToSection(
      section: student.section,
      grade: student.gradeLevel,
      roomName: room.name,
      roomGrade: room.gradeLevel,
    );

/// مجموعة مادة مدرسية: بلا جدول أسبوعي ولا رسوم شهرية.
///
/// مجموعات المركز المجدولة تُدار يدوياً بأسعارها وتسجيلاتها، فلا يجوز لمنطق
/// الشعب المدرسية أن يعدّل تسجيلاتها.
bool isSchoolGroup({
  required List<int> days,
  required String startTime,
  required String endTime,
  required double pricePerMonth,
}) =>
    days.isEmpty && startTime.trim().isEmpty && endTime.trim().isEmpty && pricePerMonth == 0;
