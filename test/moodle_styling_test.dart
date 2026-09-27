import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/widgets/moodle_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// تنسيق المودل و«صفي» — مطابق لـ `moodleStyle.tsx` و`HomeroomClass.tsx` في الويب.
void main() {
  group('تنسيق المودل', () {
    test('لون الوحدة: المختار، وإلا بترتيبها في الصفحة', () {
      const plain = CourseSection(id: 's', groupId: 'g', term: 'term_1', title: 'الوحدة');
      expect(unitColor(plain, 0), const Color(0xFF2563EB));
      expect(unitColor(plain, 9), const Color(0xFF059669));
      expect(unitColor(plain.copyWith(color: '#E11D48'), 0), const Color(0xFFE11D48));
      // قيمة غير صالحة تعود للتلقائي
      expect(unitColor(plain.copyWith(color: 'red'), 2), const Color(0xFF7C3AED));
    });

    test('اللون والخط العريض يُقرآن من السحابة ويُكتبان حين يُختاران وحدهما', () {
      final section = CourseSection.fromCloud({'id': 's', 'group_id': 'g', 'title': 'و', 'color': '#059669'});
      expect(section.color, '#059669');
      expect(section.toCloud()['color'], '#059669');
      // منشأة لم تشغّل ترحيل التنسيق بعد تبقى تكتب وحداتها
      expect(CourseSection.fromCloud({'id': 's', 'group_id': 'g', 'title': 'و'}).toCloud().containsKey('color'), isFalse);

      final item = CourseItem.fromCloud({
        'id': 'i',
        'section_id': 's',
        'group_id': 'g',
        'title': 'درس',
        'type': 'note',
        'title_color': '#D97706',
        'title_bold': true,
      });
      expect(item.titleColor, '#D97706');
      expect(item.titleBold, isTrue);
      expect(item.toCloud()['title_bold'], isTrue);
      final bare = CourseItem.fromCloud({'id': 'i', 'section_id': 's', 'group_id': 'g', 'title': 'درس', 'type': 'note'}).toCloud();
      expect(bare.containsKey('title_color'), isFalse);
      expect(bare.containsKey('title_bold'), isFalse);
    });

    test('نسخ الوحدة للتعديل يحفظ ترتيبها ولونها', () {
      const s = CourseSection(id: 's', groupId: 'g', term: 'term_1', title: 'قديم', color: '#475569', sortOrder: 3);
      final moved = s.copyWith(sortOrder: 0);
      expect(moved.sortOrder, 0);
      expect(moved.color, '#475569');
      expect(s.copyWith(title: 'جديد').title, 'جديد');
    });

    test('لم يُحفظ: رسالة واضحة، ولا يُعامل كانقطاع', () {
      const e = MoodleNotSaved();
      expect(e, isA<PortalException>());
      expect(e.message, contains('لم يُحفظ التغيير'));
    });
  });

  group('«صفي»', () {
    test('ما تُرجعه homeroom_class يُقرأ كاملاً', () {
      final data = HomeroomClassData.fromJson({
        'rooms': [
          {'id': 'r1', 'name': 'أ', 'grade_level': 'عاشر'},
        ],
        'students': [
          {
            'id': 'st1',
            'room_id': 'r1',
            'first_name': 'أحمد',
            'last_name': 'علي',
            'full_name': null,
            'national_id': '123',
            'portal_code': 'S1',
            'parent_portal_code': 'P1',
            'birth_date': '2010-01-02T00:00:00',
          },
        ],
        'evaluations': [
          {'id': 'e1', 'student_id': 'st1', 'subject_id': 'm', 'score': 18, 'max_score': 20, 'term': 'term_1', 'component_id': 'c1'},
        ],
        'subjects': [
          {'id': 'm', 'name': 'رياضيات'},
        ],
      });
      expect(data.rooms.single.label, 'عاشر — أ');
      final s = data.students.single;
      expect(s.name, 'أحمد علي');
      expect(s.birthDate, '2010-01-02');
      expect(s.parentPortalCode, 'P1');
      expect(data.evaluations.single.score, 18);
      expect(data.subjects['m'], 'رياضيات');
    });

    test('المعلم غير المربي: قوائم فارغة', () {
      final data = HomeroomClassData.fromJson({'rooms': [], 'students': [], 'evaluations': [], 'subjects': []});
      expect(data.rooms, isEmpty);
      expect(data.students, isEmpty);
    });
  });
}
