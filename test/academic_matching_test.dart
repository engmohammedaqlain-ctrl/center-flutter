import 'package:center_mobile/data/academic_matching.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `academicMatching.test.ts`: المطابقة الضبابية (`contains`) كانت تجعل
/// «علمي 1» يطابق «علمي 10»، و«الثاني عشر» يبتلع فرعيه، وغياب المرحلة يطابق كل
/// شيء. هذه الاختبارات تثبّت الحدود.
void main() {
  group('مطابقة المراحل والشعب', () {
    test('التطبيع يوحّد صور الألف والياء والهاء والأرقام والمسافات', () {
      expect(normalizeAcademicText('الثانى عشر  علمى'), normalizeAcademicText('الثاني عشر علمي'));
      expect(normalizeAcademicText(' شعبة (أ) '), normalizeAcademicText('شعبه (ا)'));
      expect(normalizeAcademicText('شعبة ١'), normalizeAcademicText('شعبة 1'));
      expect(normalizeAcademicText(null), '');
    });

    test('مرحلة لا تطابق مرحلة اسمها جزء منها', () {
      expect(isSameGrade('الثاني عشر', 'الثاني عشر علمي'), isFalse);
      expect(isSameGrade('الثاني عشر علمي', 'الثاني عشر أدبي'), isFalse);
      expect(isSameGrade('الثاني عشر علمي', 'الثانى عشر علمى'), isTrue);
    });

    test('غياب المرحلة لا يطابق شيئاً', () {
      expect(isSameGrade('', 'الثاني عشر علمي'), isFalse);
      expect(isSameGrade(null, null), isFalse);
    });

    test('اسم شعبة لا يطابق اسماً يبدأ بنفس الحروف', () {
      expect(isSameSectionName('علمي 1', 'علمي 10'), isFalse);
      expect(isSameSectionName('شعبة علمي 1', 'علمي 1'), isFalse);
      expect(isSameSectionName('شعبة (أ)', 'شعبة (ا)'), isTrue);
    });

    test('مادة المرحلة ومادة عامة فقط تصلحان للشعبة', () {
      expect(subjectAppliesToGrade('حادي عشر', 'ثاني عشر علمي'), isFalse);
      expect(subjectAppliesToGrade('ثاني عشر علمي', 'ثاني عشر علمي'), isTrue);
      expect(subjectAppliesToGrade('عام / كل المراحل', 'ثاني عشر علمي'), isTrue);
      expect(subjectAppliesToGrade(null, 'ثاني عشر علمي'), isTrue);
      // شعبة بلا مرحلة تقبل كل المواد
      expect(subjectAppliesToGrade('حادي عشر', ''), isTrue);
    });

    test('عضوية الطالب في الشعبة تتطلب تطابق الاسم والمرحلة معاً', () {
      bool belongs(String section, String grade) =>
          belongsToSection(section: section, grade: grade, roomName: 'شعبة علمي 1', roomGrade: 'ثاني عشر علمي');

      expect(belongs('شعبة علمي 1', 'ثاني عشر علمي'), isTrue);
      expect(belongs('شعبة علمي 10', 'ثاني عشر علمي'), isFalse);
      expect(belongs('شعبة علمي 1', 'ثاني عشر أدبي'), isFalse);
      // طالب بلا مرحلة كان يُعدّ عضواً في كل شعبة
      expect(belongs('شعبة علمي 1', ''), isFalse);
      expect(belongs('', 'ثاني عشر علمي'), isFalse);
    });

    test('مجموعة المدرسة بلا جدول ولا رسوم؛ المجدولة ليست منها', () {
      expect(isSchoolGroup(days: const [], startTime: '', endTime: '', pricePerMonth: 0), isTrue);
      expect(isSchoolGroup(days: const [1, 3], startTime: '16:00', endTime: '17:30', pricePerMonth: 120), isFalse);
      expect(isSchoolGroup(days: const [], startTime: '', endTime: '', pricePerMonth: 120), isFalse);
    });
  });
}
