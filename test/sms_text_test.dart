import 'package:center_mobile/data/sms_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `smsText.test.ts` في الويب: نفس الحالات ونفس النتائج.
void main() {
  group('أجزاء رسالة SMS (حساب جوال وأوريدو)', () {
    test('العربي 70 حرف بالرسالة، والأطول 67 للجزء', () {
      final a = smsParts('م' * 70);
      expect([a.chars, a.parts, a.perPart, a.capacity, a.remaining, a.unicode], [70, 1, 70, 70, 0, true]);
      final b = smsParts('م' * 71);
      expect([b.chars, b.parts, b.perPart, b.capacity, b.remaining], [71, 2, 67, 134, 63]);
      expect(smsParts('م' * 134).parts, 2);
      expect(smsParts('م' * 135).parts, 3);
    });

    test('الإنجليزي 160، والأطول 153 للجزء', () {
      final a = smsParts('a' * 160);
      expect([a.parts, a.remaining, a.unicode], [1, 0, false]);
      final b = smsParts('a' * 161);
      expect([b.chars, b.parts, b.perPart, b.capacity], [161, 2, 153, 306]);
    });

    test('المسافات والأسطر أحرف', () {
      expect(smsParts('مرحبا يا\nأحمد').chars, 13);
    });

    test('حرف عربي واحد يقلب الرسالة كلها لـ 70', () {
      final c = smsParts('${'a' * 100}م');
      expect([c.chars, c.parts, c.perPart], [101, 2, 67]);
    });

    test('الإيموجي بحرفين، وبيقلب الإنجليزي لـ 70', () {
      final a = smsParts('مرحبا 😀');
      expect([a.chars, a.emoji], [8, true]);
      final b = smsParts('Hi 😀');
      expect([b.chars, b.unicode, b.emoji], [5, true, true]);
    });

    test('رموز GSM الموسّعة بحرفين بالإنجليزي', () {
      expect(smsParts('a{b}').chars, 6);
      expect(smsParts(r'\^[]~|€').chars, 14);
    });

    test('كم حرف تحذف حتى تنقص رسالة', () {
      expect(smsParts('م' * 75).toFewer, 5); // 2 ← 1: لازم ≤ 70
      expect(smsParts('م' * 140).toFewer, 6); // 3 ← 2: لازم ≤ 134
      expect(smsParts('م' * 60).toFewer, 0);
    });

    test('الفاضي صفر', () {
      final c = smsParts('');
      expect([c.chars, c.parts], [0, 0]);
    });
  });

  group('متغيرات الرسالة', () {
    const s = SmsStudent(
      id: '1',
      firstName: 'أحمد',
      fullName: 'أحمد محمد علي',
      parentName: 'محمد',
      gradeLevel: 'الخامس',
      section: 'أ',
    );

    test('كل متغير بقيمته', () {
      const text = '{ولي الأمر}: {الاسم} ({الاسم الكامل}) {الصف} عليه {المستحق} - {المدرسة}';
      expect(fillSmsVars(text, s, school: 'نون', dueOf: (_) => 150.4), 'محمد: أحمد (أحمد محمد علي) الخامس أ عليه 150 شيكل - نون');
    });

    test('المستحق بفواصل الآلاف', () {
      expect(fillSmsVars('{المستحق}', s, dueOf: (_) => 1234.6), '1,235 شيكل');
      expect(smsAmount(1000000), '1,000,000');
      expect(smsAmount(0), '0');
    });

    test('اسم المدرسة وحده ما بيخلّي الرسالة لكل طالب', () {
      expect(hasPerStudentVars('أهلاً من {المدرسة}'), isFalse);
      expect(hasPerStudentVars('غاب $smsNameTag'), isTrue);
    });
  });

  group('مستلمو رسالة SMS', () {
    const kids = [
      SmsStudent(id: '1', firstName: 'أحمد', parentPhone: '0599111111', phone: '0566000001'),
      SmsStudent(id: '2', firstName: 'سارة', parentPhone: '0599 111 111'), // أخت أحمد: نفس الرقم
      SmsStudent(id: '3', firstName: 'علي', phone: '0566000003'),
      SmsStudent(id: '4', firstName: 'منى', parentPhone: '+970599222222'),
    ];

    test('بلا متغيرات: رسالة وحدة لكل رقم، واللي بلا رقم ينعدّ', () {
      final r = buildSmsMessages(kids, ' بكرة عطلة ');
      expect(r.messages.map((m) => m.to).toList(), ['0599111111', '+970599222222']);
      expect(r.messages.first.message, 'بكرة عطلة');
      expect(r.missing, 1);
    });

    test('مع الاسم: رسالة لكل طالب باسمه حتى لو نفس الرقم', () {
      final r = buildSmsMessages(kids, 'غاب $smsNameTag اليوم');
      expect(r.messages.map((m) => m.message).toList(), ['غاب أحمد اليوم', 'غاب سارة اليوم', 'غاب منى اليوم']);
      expect(r.messages.map((m) => m.ref).toList(), ['1', '2', '4']);
    });

    test('للطلاب: رقم الطالب نفسه', () {
      final r = buildSmsMessages(kids, 'مرحبا', audience: SmsAudience.students);
      expect(r.messages.map((m) => m.to).toList(), ['0566000001', '0566000003']);
      expect(r.missing, 2);
    });

    test('أطول رسالة فعلية للعدّاد', () {
      final r = buildSmsMessages(kids, 'مرحبا $smsNameTag');
      expect(longestSmsMessage(r.messages, 'x'), 'مرحبا أحمد');
      expect(longestSmsMessage(const [], 'x'), 'x');
    });

    test('الرصيد = مجموع أجزاء كل رسالة فعلية بعد المتغيرات', () {
      // نفس النص: الاسم الطويل بيطلّع رسالته جزئين، والقصير جزء واحد
      final long = [
        SmsStudent(id: 'a', firstName: 'م' * 10, parentPhone: '0599000001'),
        const SmsStudent(id: 'b', firstName: 'م', parentPhone: '0599000002'),
      ];
      final r = buildSmsMessages(long, '${'ر' * 62} $smsNameTag');
      expect(r.messages.map((m) => smsParts(m.message).parts).toList(), [2, 1]);
      expect(totalSmsParts(r.messages), 3);
    });

    test('تمييز العدد', () {
      expect(smsLetters(3), 'أحرف');
      expect(smsLetters(11), 'حرف');
      expect(smsLetters(1), 'حرف');
    });
  });
}
