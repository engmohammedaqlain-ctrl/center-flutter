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
///
/// تُكتب في العمود القديم `grade_level` حين لا تُحدَّد للمادة مرحلة، فيفهمها
/// نظام الويب كما كان قبل أن تصير المادة تحمل أكثر من مرحلة.
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
/// نتائج التطبيع محفوظة: القيم المميزة قليلة — أسماء مراحل وشعب لا تتجاوز
/// العشرات — بينما النداء يتكرر عشرات الآلاف من المرات في الإطار الواحد.
///
/// شاشة الصفوف تطابق كل طالب بكل شعبة، وكل مطابقة كانت تُجري ثماني عمليات
/// استبدال على النصّ نفسه من جديد.
final _normCache = <String, String>{};

String normalizeAcademicText(String? value) {
  if (value == null || value.isEmpty) return '';
  final cached = _normCache[value];
  if (cached != null) return cached;
  final result = _normalize(value);
  // حدٌّ أعلى يمنع نموّ الذاكرة إن وصلت قيم كثيرة غير متوقعة
  if (_normCache.length < 4096) _normCache[value] = result;
  return result;
}

String _normalize(String value) {
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

/// مراحل المادة كما تُخزَّن: بلا فراغٍ ولا تكرار، والقيمة العامة تُحذف.
///
/// «كل المراحل» هو ألا تُذكر مرحلة، لا أن تُعدّ المراحل الموجودة اليوم: مرحلةٌ
/// تُضاف بعد شهر تنطبق عليها المادة العامة بلا أن يفتحها أحد ويعلّمها.
List<String> normalizeSubjectGrades(Iterable<String> grades) {
  final general = normalizeAcademicText(generalGradeLabel);
  final seen = <String>{};
  final kept = <String>[];
  for (final grade in grades) {
    final key = normalizeAcademicText(grade);
    if (key.isEmpty || key == general) continue;
    if (seen.add(key)) kept.add(grade.trim());
  }
  return kept;
}

/// مادة عامة: بلا مرحلة محددة، أو موسومة صراحةً بأنها لكل المراحل.
bool isGeneralSubject(Iterable<String> subjectGrades) => normalizeSubjectGrades(subjectGrades).isEmpty;

/// هل تُدرَّس هذه المادة في هذه المرحلة؟ شعبة بلا مرحلة تقبل كل المواد.
///
/// المادة تحمل مراحلها كلها — الفيزياء للعاشر والحادي عشر والثاني عشر — فتكفي
/// مطابقة واحدةٍ منها.
bool subjectAppliesToGrade(Iterable<String> subjectGrades, String? gradeLevel) {
  if (normalizeAcademicText(gradeLevel).isEmpty) return true;
  if (isGeneralSubject(subjectGrades)) return true;
  return subjectGrades.any((g) => isSameGrade(g, gradeLevel));
}

/// مراحل المادة كما يراها المستخدم؛ القائمة الفارغة تعني «كل المراحل».
List<String> subjectGrades(SubjectItem subject) {
  final fromList = normalizeSubjectGrades(subject.gradeLevels);
  if (fromList.isNotEmpty) return fromList;
  return normalizeSubjectGrades([subject.gradeLevel]);
}

/// مراحل المادة كما تُعرض في سطرٍ واحد — `subjectGradesLabel` في الويب.
String subjectGradesLabel(SubjectItem subject) {
  final grades = subjectGrades(subject);
  return grades.isEmpty ? 'كل المراحل' : grades.join(' · ');
}

/// هل تُدرَّس المادة في المرحلة؟ — `subjectCoversGrade`.
bool subjectCoversGrade(SubjectItem subject, String? gradeLevel) =>
    subjectAppliesToGrade(subjectGrades(subject), gradeLevel);

/// تصفية المواد على مرحلة واحدة — `filterSubjectsForGrade`.
List<T> filterSubjectsForGrade<T extends SubjectItem>(
  Iterable<T> subjects,
  String? gradeLevel,
) =>
    subjects.where((s) => subjectCoversGrade(s, gradeLevel)).toList();

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
