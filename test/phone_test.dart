import 'package:center_mobile/data/phone.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// خانات الجوال — مطابق لـ `phoneUtils.test.ts` في الويب.

void main() {
  group('combinePhoneAndPrefix', () {
    test('رقم محلي يبدأ بـ 20 أو 97 يبقى بمقدمته المختارة، لا يُعدّ دولياً', () {
      expect(combinePhoneAndPrefix('2020766', '056'), '0562020766');
      expect(combinePhoneAndPrefix('9701234', '059'), '0599701234');
      expect(isValidStudentPhone(combinePhoneAndPrefix('2020766', '056'), '056'), isTrue);
    });

    test('رقم محلي يبدأ بـ 59 أو 56 لا يُضاف له صفر', () {
      expect(combinePhoneAndPrefix('5912345', '059'), '0595912345');
      expect(combinePhoneAndPrefix('5612345', '056'), '0565612345');
    });

    test('الأرقام الكاملة تبقى كما هي', () {
      expect(combinePhoneAndPrefix('0591234567', '056'), '0591234567');
      expect(combinePhoneAndPrefix('591234567', '059'), '0591234567');
      expect(combinePhoneAndPrefix('+970591234567', '059'), '+970591234567');
      expect(combinePhoneAndPrefix('970591234567', '059'), '+970591234567');
    });

    test('المقدمات الدولية', () {
      expect(combinePhoneAndPrefix('591234567', '+970'), '+970591234567');
      expect(combinePhoneAndPrefix('1001234567', '+20'), '+201001234567');
    });

    test('ذهاب وإياب مع التحليل', () {
      final parsed = parsePhoneAndPrefix(combinePhoneAndPrefix('2020766', '056'));
      expect((parsed.prefix, parsed.number), ('056', '2020766'));
    });
  });

  group('normalizePhoneInput', () {
    test('رقم كامل بأي صيغة يضبط مقدمته', () {
      for (final v in ['0562020766', '562020766', '+970562020766', '00970562020766', '972562020766', '٠٥٦٢٠٢٠٧٦٦', '056-202-0766']) {
        final next = normalizePhoneInput(v, '059');
        expect((next.prefix, next.number), ('056', '2020766'), reason: v);
      }
    });

    test('الرقم بعد المقدمة يبقى كما هو ولو بدأ بـ 59 أو 20 أو 97', () {
      expect(normalizePhoneInput('2020766', '056').number, '2020766');
      expect(normalizePhoneInput('5912345', '059').number, '5912345');
      expect(normalizePhoneInput('9701234', '059').number, '9701234');
    });

    test('الكتابة رقماً رقماً لا تُقص قبل اكتمال الرقم الكامل', () {
      expect(normalizePhoneInput('05620', '059').number, '05620');
      expect(normalizePhoneInput('056202076', '059').number, '056202076');
    });

    test('يُقص الزائد عن طول المقدمة', () {
      expect(normalizePhoneInput('12345678', '059').number, '1234567');
      expect(normalizePhoneInput('5212345678', '+972').number, '521234567');
    });

    test('مصر خارج القائمة، والرقم المحفوظ بها تظهر مقدمته', () {
      expect(phonePrefixes, isNot(contains('+20')));
      expect(phonePrefixOptions('+20'), contains('+20'));
      expect(phonePrefixOptions('059'), phonePrefixes);
    });
  });
}
