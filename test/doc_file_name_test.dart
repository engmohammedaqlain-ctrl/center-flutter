import 'package:center_mobile/data/printing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('رقم السند بشرطته المائلة لا يصير مجلداً في اسم الملف', () {
    // «سند قبض 2026/1097» كان يُكتب في مجلد «2026» غير موجود فيفشل واتساب والحفظ
    expect(PdfKit.fileName('سند قبض 2026/1097.png'), 'سند_قبض_2026-1097.png');
    expect(PdfKit.fileName('سند صرف 2026/12'), 'سند_صرف_2026-12.pdf');
    expect(PdfKit.fileName(r'a\b:c*d?e"f<g>h|i'), 'a-b-c-d-e-f-g-h-i.pdf');
    expect(PdfKit.fileName('كشف'), 'كشف.pdf');
  });
}
