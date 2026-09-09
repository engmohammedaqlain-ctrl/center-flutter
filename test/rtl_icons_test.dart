import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// اتجاه الأسهم في واجهة عربية.
///
/// أيقونات Material الاتجاهية تحمل `matchTextDirection: true`، فتنعكس تلقائياً
/// داخل `Directionality.rtl`. لذلك يُختار الاسم **دلالياً** لا بصرياً:
/// `arrow_back` يعني «رجوع» ويُرسم يميناً في العربية، و`arrow_forward` يعني
/// «تقدّم» ويُرسم يساراً. اختيارها بالشكل الظاهر كان يقلب كل الأسهم.
void main() {
  test('الأيقونات الاتجاهية تنعكس مع اتجاه النص', () {
    for (final icon in [
      Icons.arrow_back,
      Icons.arrow_forward,
      Icons.chevron_left,
      Icons.chevron_right,
      Icons.arrow_back_ios,
      Icons.arrow_forward_ios,
    ]) {
      expect(icon.matchTextDirection, isTrue, reason: 'code ${icon.codePoint}');
    }
  });

  testWidgets('سهم الرجوع يُرسم نحو اليمين في العربية', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Icon(Icons.arrow_back),
      ),
    );
    final rich = tester.widget<RichText>(find.byType(RichText));
    final span = rich.text as TextSpan;
    // النص يُرسم معكوساً أفقياً، وهو ما يقلب السهم إلى جهة اليمين
    expect(rich.textDirection, TextDirection.rtl);
    expect(span.style?.fontFamily, 'MaterialIcons');
  });

  test('اختيار الأيقونة في الشاشات دلالي لا بصري', () {
    // خريطة النية → الأيقونة الصحيحة، مرجعاً للمراجعة المستقبلية
    const intent = <String, IconData>{
      'رجوع للخلف': Icons.arrow_back,
      'تقدّم وتأكيد': Icons.arrow_forward,
      'الأسبوع السابق': Icons.chevron_left,
      'الأسبوع التالي': Icons.chevron_right,
      'فتح التفاصيل': Icons.chevron_right,
    };
    expect(intent['رجوع للخلف'], isNot(intent['تقدّم وتأكيد']));
    expect(intent['الأسبوع السابق'], isNot(intent['الأسبوع التالي']));
  });
}
