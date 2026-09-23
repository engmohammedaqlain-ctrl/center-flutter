import 'package:center_mobile/data/arabic_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// بحث الطلاب كما في الويب — البحث الحرفي كان يردّ «لا نتائج» على اسم موجود.

bool find(String name, String query, {String parentName = '', String phone = '', String nationalId = ''}) =>
    matchStudentSearch(
      fullName: name,
      query: query,
      parentName: parentName,
      phone: phone,
      nationalId: nationalId,
    );

void main() {
  const fullName = 'محمد خليل إبراهيم السويركي';

  test('الاسم الأول والعائلة معاً مع تخطّي الأب والجد', () {
    expect(find(fullName, 'محمد السويركي'), isTrue);
    expect(find(fullName, 'محمد خليل السويركي'), isTrue);
    expect(find(fullName, fullName), isTrue);
  });

  test('الهمزات والتاء المربوطة والألف المقصورة لا تُسقط النتيجة', () {
    expect(find('إبراهيم', 'ابراهيم'), isTrue);
    expect(find('ابراهيم', 'إبراهيم'), isTrue);
    expect(find('فاطمة الزهراء', 'فاطمه الزهراء'), isTrue);
    expect(find('يحيى', 'يحيي'), isTrue);
    expect(find('وائل', 'وايل'), isTrue);
  });

  test('الأسماء المركّبة متصلة ومنفصلة', () {
    expect(find('عبد الرحمن الشنطي', 'عبدالرحمن'), isTrue);
    expect(find('أبو بكر الصديق', 'ابوبكر'), isTrue);
  });

  test('أل التعريف الزائدة في البحث', () {
    expect(find('محمد عوض', 'العوض'), isTrue);
  });

  test('التشكيل والتطويل يُتجاهلان', () {
    expect(find('مُحَمَّد', 'محمد'), isTrue);
    expect(find('محـــمد', 'محمد'), isTrue);
  });

  test('الأرقام المشرقية تطابق اللاتينية في الهاتف والهوية', () {
    expect(find('طالب', '٠٥٩٩', phone: '0599123456'), isTrue);
    expect(find('طالب', '0599', phone: '٠٥٩٩١٢٣٤٥٦'), isTrue);
    expect(find('طالب', '431309616', nationalId: '431309616'), isTrue);
    expect(find('طالب', '059-912', phone: '0599123456'), isTrue, reason: 'الفواصل تُسقط');
  });

  test('اسم وليّ الأمر يُبحث فيه أيضاً', () {
    expect(find('سارة محمود', 'ابو عطايا', parentName: 'محمود أبو عطايا'), isTrue);
    // الكلمات تُطابَق بأي ترتيب، كالويب
    expect(find('سارة محمود', 'عطايا محمود', parentName: 'محمود أبو عطايا'), isTrue);
    expect(find('سارة محمود', 'أبو شعبان', parentName: 'محمود أبو عطايا'), isFalse);
  });

  test('اسم لا يطابق يبقى خارج النتائج', () {
    expect(find(fullName, 'أحمد'), isFalse);
    expect(find(fullName, 'محمد الدلو'), isFalse, reason: 'كلمة غير موجودة تُسقط المطابقة');
  });

  test('بحث فارغ يُبقي الكل', () {
    expect(find(fullName, ''), isTrue);
    expect(find(fullName, '   '), isTrue);
  });
}
