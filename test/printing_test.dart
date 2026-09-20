import 'package:center_mobile/data/printing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('amount in Arabic words (tafqeet)', () {
    test('handles zero like web ReceiptModal', () {
      expect(amountInArabicWords(0), 'صفر شيكل');
      expect(amountInArabicWords(0), isNot(contains('فقط')));
      expect(amountInArabicWords(1), 'فقط واحد شيكلاً لا غير');
      expect(amountInArabicWords(9), 'فقط تسعة شيكلاً لا غير');
    });

    test('handles the teens and tens', () {
      expect(amountInArabicWords(11), 'فقط أحد عشر شيكلاً لا غير');
      expect(amountInArabicWords(20), 'فقط عشرون شيكلاً لا غير');
      expect(amountInArabicWords(45), 'فقط خمسة وأربعون شيكلاً لا غير');
    });

    test('handles hundreds with مئتان spelling like web', () {
      expect(amountInArabicWords(100), 'فقط مائة شيكلاً لا غير');
      expect(amountInArabicWords(250), 'فقط مئتان وخمسون شيكلاً لا غير');
      expect(amountInArabicWords(250), isNot(contains('مائتان')));
      expect(amountInArabicWords(350), 'فقط ثلاثمائة وخمسون شيكلاً لا غير');
      expect(amountInArabicWords(999), 'فقط تسعمائة وتسعة وتسعون شيكلاً لا غير');
    });

    test('handles thousands with correct duals and plurals', () {
      expect(amountInArabicWords(1000), 'فقط ألف شيكلاً لا غير');
      expect(amountInArabicWords(2000), 'فقط ألفان شيكلاً لا غير');
      expect(amountInArabicWords(3000), contains('آلاف'));
      expect(amountInArabicWords(15000), contains('ألفاً'));
      expect(amountInArabicWords(1500), 'فقط ألف وخمسمائة شيكلاً لا غير');
    });

    test('handles millions', () {
      expect(amountInArabicWords(1000000), 'فقط مليون شيكلاً لا غير');
      expect(amountInArabicWords(2000000), 'فقط مليونان شيكلاً لا غير');
    });

    test('drops agora fractions like the web tafqeet', () {
      expect(amountInArabicWords(10.5), 'فقط عشرة شيكلاً لا غير');
      expect(amountInArabicWords(10.5), isNot(contains('أغورة')));
    });

    test('ignores the sign', () {
      expect(amountInArabicWords(-75), amountInArabicWords(75));
    });
  });
}
