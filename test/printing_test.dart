import 'package:center_mobile/data/printing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('amount in Arabic words', () {
    test('handles zero and the single units', () {
      expect(amountInArabicWords(0), 'صفر شيكل فقط لا غير');
      expect(amountInArabicWords(1), 'واحد شيكل فقط لا غير');
      expect(amountInArabicWords(9), 'تسعة شيكل فقط لا غير');
    });

    test('handles the teens and tens', () {
      expect(amountInArabicWords(11), 'أحد عشر شيكل فقط لا غير');
      expect(amountInArabicWords(20), 'عشرون شيكل فقط لا غير');
      expect(amountInArabicWords(45), 'خمسة وأربعون شيكل فقط لا غير');
    });

    test('handles hundreds', () {
      expect(amountInArabicWords(100), 'مئة شيكل فقط لا غير');
      expect(amountInArabicWords(250), 'مئتان وخمسون شيكل فقط لا غير');
      expect(amountInArabicWords(999), 'تسعمئة وتسعة وتسعون شيكل فقط لا غير');
    });

    test('handles thousands with correct duals and plurals', () {
      expect(amountInArabicWords(1000), 'ألف شيكل فقط لا غير');
      expect(amountInArabicWords(2000), 'ألفان شيكل فقط لا غير');
      expect(amountInArabicWords(3000), contains('آلاف'));
      expect(amountInArabicWords(1500), 'ألف وخمسمئة شيكل فقط لا غير');
    });

    test('handles millions', () {
      expect(amountInArabicWords(1000000), 'مليون شيكل فقط لا غير');
      expect(amountInArabicWords(2000000), 'مليونان شيكل فقط لا غير');
    });

    test('spells out the fractional agora part', () {
      expect(amountInArabicWords(10.5), contains('أغورة'));
      expect(amountInArabicWords(10.5), startsWith('عشرة شيكل و'));
      expect(amountInArabicWords(200), isNot(contains('أغورة')));
    });

    test('ignores the sign', () {
      expect(amountInArabicWords(-75), amountInArabicWords(75));
    });
  });
}
