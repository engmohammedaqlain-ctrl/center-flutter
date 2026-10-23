import 'package:center_mobile/data/school_brand.dart';
import 'package:center_mobile/data/school_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('كود المدرسة من رابط صفحتها', () {
    expect(parseSchoolLink('https://noonschool.app/d/abc'), 'ABC');
    expect(parseSchoolLink('https://noon-school.pages.dev/d/ABC/'), 'ABC');
    expect(parseSchoolLink('https://noonschool.app/d/ABC/play'), 'ABC');
    expect(parseSchoolLink('https://NoonSchool.app/d/x_1?utm=qr'), 'X_1');
    expect(parseSchoolLink('https://example.com/d/ABC'), isNull);
    expect(parseSchoolLink('http://noonschool.app/d/ABC'), isNull);
    expect(parseSchoolLink('https://noonschool.app/app/?school=ABC'), isNull);
    expect(parseSchoolLink('https://noonschool.app/d/'), isNull);
    expect(parseSchoolLink('https://noonschool.app/d/a%2Fb'), isNull);
    expect(parseSchoolLink(''), isNull);
    expect(parseSchoolLink(null), isNull);
  });

  group('رابط المدرسة يفتح التطبيق عليها', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('يحل محل مدرسة رابط التنزيل، ويبقى في الفتح التالي', () async {
      SchoolBrand brand() => SchoolBrand(
            readAsset: () async => '{}',
            readReferrer: () async => 'school=OLD',
            fetch: (code) async => (name: 'مدرسة $code', logo: '', colors: null),
          );

      final first = brand();
      await first.load();
      await Future<void>.delayed(Duration.zero);
      expect((first.code, first.name), ('OLD', 'مدرسة OLD'));

      await first.openLink('NEW');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect((first.code, first.name, first.linked), ('NEW', 'مدرسة NEW', true));

      final next = brand();
      await next.readBundled();
      expect((next.code, next.linked), ('NEW', false));
    });

    test('قبل التحميل: الرابط أولاً، والمتجر لا يُسأل', () async {
      var asked = 0;
      final brand = SchoolBrand(
        readAsset: () async => '{}',
        readReferrer: () async {
          asked++;
          return 'school=OLD';
        },
        fetch: (code) async => (name: 'مدرسة $code', logo: '', colors: null),
      );
      await brand.readBundled();
      await brand.openLink('ABC');
      await brand.load();
      await Future<void>.delayed(Duration.zero);
      expect((brand.code, brand.name, asked), ('ABC', 'مدرسة ABC', 0));
    });

    test('نسخة المدرسة الخاصة لا تتبدّل', () async {
      final brand = SchoolBrand(
        readAsset: () async => '{"code":"MINE","name":"مدرستي"}',
        fetch: (_) async => null,
      );
      await brand.openLink('OTHER');
      expect((brand.code, brand.name, brand.linked), ('MINE', 'مدرستي', false));
    });
  });
}
