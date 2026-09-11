import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('الجنس بالإنجليزية يُقرأ بالعربية كما يحفظه Center', () {
    expect(genderLabel('male'), 'ذكر');
    expect(genderLabel('Male'), 'ذكر');
    expect(genderLabel(' female '), 'أنثى');
    expect(genderLabel('F'), 'أنثى');
  });

  test('القيم العربية تبقى كما هي', () {
    expect(genderLabel('ذكر'), 'ذكر');
    expect(genderLabel('أنثى'), 'أنثى');
    expect(genderLabel('انثى'), 'أنثى', reason: 'بلا همزة');
  });

  test('الفارغ يعود للافتراضي، والمجهول لا يُمسح', () {
    expect(genderLabel(null), 'ذكر');
    expect(genderLabel(''), 'ذكر');
    expect(genderLabel('غير محدد'), 'غير محدد');
  });
}
