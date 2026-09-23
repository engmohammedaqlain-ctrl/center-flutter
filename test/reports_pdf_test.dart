import 'package:center_mobile/data/printing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// التقارير تُبنى بالعربية.
///
/// خط الواجهة ملفه OpenType/CFF رغم امتداد `.ttf`، ومكتبة المستندات تقرأ
/// مجسّمات TrueType وحدها — فكانت تعدّه خطاً لاتينياً وترمي عند أول حرف عربي.
/// كل تقارير التطبيق كانت تفشل قبل أن تُبنى، بلا رسالة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// كل خط يُحمَّل فعلاً في [PdfKit] — لا خطاً مهجوراً في الأصول.
  const shipped = [
    'assets/fonts/pdf/NotoNaskhArabic-Regular.ttf',
    'assets/fonts/pdf/NotoNaskhArabic-Bold.ttf',
    'assets/fonts/pdf/NotoSans-Regular.ttf',
    'assets/fonts/pdf/NotoSans-Bold.ttf',
    'assets/fonts/pdf/NotoSansSymbols2-Regular.ttf',
  ];

  test('خطوط المستندات كلها TrueType وموجودة في الحزمة', () async {
    for (final path in shipped) {
      final bytes = (await rootBundle.load(path)).buffer.asUint8List();
      // توقيع TrueType: 0x00010000 — لا 'OTTO'
      expect(bytes.sublist(0, 4), [0, 1, 0, 0], reason: '$path: OTTO لا تقرأه مكتبة المستندات');
    }
  });

  test('مستند بعناوين وجدول عربيين يُبنى صالحاً', () async {
    final bytes = await PdfKit.build(
      title: 'كشف تفقد وحضور الطلاب',
      institutionName: 'مدرسة أبو عقلين الخاصة',
      subtitle: 'المرحلة: ثاني عشر أدبي   ·   الشعبة: شعبة (1)',
      body: (_) => [
        PdfKit.table(
          headers: const ['#', 'اسم الطالب', 'الأحد', 'الاثنين', 'الغياب'],
          rows: const [
            ['1', 'علي أبو حسنين', 'حاضر', 'غائب', '1'],
            ['2', 'سارة محمود', 'حاضر', 'مأذون', '0'],
          ],
        ),
      ],
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  test('مستند أفقي بعملة وأرقام — كشف مالي', () async {
    final bytes = await PdfKit.build(
      title: 'كشف الدفعات',
      institutionName: 'مدرسة أبو عقلين الخاصة',
      landscape: true,
      body: (_) => [
        PdfKit.table(
          headers: const ['رقم السند', 'الطالب', 'المبلغ', 'الطريقة'],
          rows: const [
            ['١٢٣', 'ريم قاسم', '250.00', 'نقداً'],
            ['124', 'علي محمد', '1,300.50', 'تحويل بنكي'],
          ],
        ),
      ],
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('buildSafe تُرجع null ولا ترمي عند فشل البناء', () async {
    final bytes = await PdfKit.buildSafe(
      title: 'كشف',
      institutionName: 'مدرسة',
      body: (_) => throw StateError('محتوى تالف'),
    );
    expect(bytes, isNull, reason: 'المستدعي يعرض رسالة بدل أن يمرّ الفشل صامتاً');
  });
}
