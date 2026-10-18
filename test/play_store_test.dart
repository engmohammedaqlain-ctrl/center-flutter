import 'package:center_mobile/data/play_store.dart';
import 'package:center_mobile/data/school_brand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('كود المدرسة من نص الإحالة', () {
    expect(parseReferrerSchool('school=abc'), 'ABC');
    expect(parseReferrerSchool('school%3DABC'), 'ABC');
    expect(parseReferrerSchool('school=ABC&utm_source=site'), 'ABC');
    expect(parseReferrerSchool('utm_source=google-play&utm_medium=organic'), isNull);
    expect(parseReferrerSchool('school=a/b'), isNull);
    expect(parseReferrerSchool(''), isNull);
    expect(parseReferrerSchool(null), isNull);
  });

  group('نسخة المتجر: الهوية من رابط التنزيل', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('يُقرأ الكود مرة ويُحفظ، وتُجلب الهوية', () async {
      var asked = 0;
      SchoolBrand brand() => SchoolBrand(
            readAsset: () async => '{}',
            readReferrer: () async {
              asked++;
              return 'school=abc';
            },
            fetch: (code) async => (name: 'مدرسة $code', logo: '', colors: null),
          );

      final first = brand();
      await first.load();
      await Future<void>.delayed(Duration.zero);
      expect((first.code, first.name), ('ABC', 'مدرسة ABC'));

      // الفتح التالي: الكود من الجهاز قبل أول إطار، والمتجر لا يُسأل ثانية
      final next = brand();
      await next.readBundled();
      expect(next.code, 'ABC');
      await next.load();
      expect(asked, 1);
    });

    test('بلا مدرسة في الرابط: الشاشة العامة، ولا يُعاد السؤال', () async {
      var asked = 0;
      Future<String?> referrer() async {
        asked++;
        return 'utm_source=google-play&utm_medium=organic';
      }

      final a = SchoolBrand(readAsset: () async => '{}', readReferrer: referrer, fetch: (_) async => null);
      await a.load();
      expect((a.code, a.name), (null, ''));
      await SchoolBrand(readAsset: () async => '{}', readReferrer: referrer, fetch: (_) async => null).load();
      expect(asked, 1);
    });

    test('تعذّر الاتصال بالمتجر: يُسأل في الفتح التالي', () async {
      var asked = 0;
      Future<String?> referrer() async => ++asked == 1 ? null : 'school=XYZ';
      await SchoolBrand(readAsset: () async => '{}', readReferrer: referrer, fetch: (_) async => null).load();
      final b = SchoolBrand(readAsset: () async => '{}', readReferrer: referrer, fetch: (_) async => null);
      await b.load();
      expect((b.code, asked), ('XYZ', 2));
    });
  });
}
