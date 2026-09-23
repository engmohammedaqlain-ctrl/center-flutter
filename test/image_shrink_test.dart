import 'dart:typed_data';

import 'package:center_mobile/data/image_shrink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// ورقة عمل مصوّرة بالهاتف: خلفية بيضاء بتدرّج إضاءة، وسطور سوداء كالنص.
///
/// ليست ضجيجاً عشوائياً عمداً — الضجيج النقي يُفشل JPEG ويُنجح PNG، فيقيس
/// الاختبار عكس ما يقع في يد المعلم.
Uint8List _photo({int width = 4000, int height = 3000, bool alpha = false}) {
  final im = img.Image(width: width, height: height, numChannels: alpha ? 4 : 3);
  final lineHeight = height ~/ 40;
  var seed = 7;
  for (var y = 0; y < height; y++) {
    // تدرّج إضاءة ناعم كضوء الغرفة على الورقة
    final paper = 235 + (y * 20 ~/ height);
    final isText = (y ~/ lineHeight).isEven && y % lineHeight < lineHeight ~/ 3;
    for (var x = 0; x < width; x++) {
      final inMargin = x < width ~/ 10 || x > width - width ~/ 10;
      final ink = isText && !inMargin && (x ~/ (width ~/ 60)).isEven;
      // حبيبات المستشعر: بلاها يضغط PNG الصورة إلى لا شيء ولا يقيس الاختبار شيئاً
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final grain = (seed >> 16) % 13 - 6;
      final v = ((ink ? 30 : paper) + grain).clamp(0, 255);
      // شفافية حقيقية عند الطلب: الهوامش تُفرَّغ كرسمٍ بخلفية شفافة
      final a = alpha && inMargin ? 0 : 255;
      im.setPixelRgba(x, y, v, v, (v - 2).clamp(0, 255), a);
    }
  }
  return Uint8List.fromList(alpha ? img.encodePng(im) : img.encodeJpg(im, quality: 100));
}

void main() {
  test('صورة هاتف ضخمة تُصغَّر كثيراً ويصير أطول ضلع 1600', () async {
    final original = _photo();
    final out = await ImageShrink.forUpload(original, 'ورقة عمل.jpg');

    expect(out.bytes.length, lessThan(original.length));
    final decoded = img.decodeImage(out.bytes)!;
    expect([decoded.width, decoded.height].reduce((a, b) => a > b ? a : b), ImageShrink.maxDimension);
    expect(decoded.width / decoded.height, closeTo(4 / 3, 0.01), reason: 'النسبة محفوظة');
    // ورقة بسبعة ميجابايت تنزل إلى أقلّ من مئتي كيلوبايت
    expect(ImageShrink.savedPercent(original.length, out.bytes.length), greaterThan(90));
  });

  test('PDF يمرّ كما هو بلا مساس', () async {
    final pdf = Uint8List.fromList(List<int>.filled(600 * 1024, 7));
    final out = await ImageShrink.forUpload(pdf, 'امتحان.pdf');
    expect(out.bytes, same(pdf));
    expect(out.fileName, 'امتحان.pdf');
  });

  test('صورة صغيرة أصلاً لا تُفكّ ولا تُعاد', () async {
    final small = Uint8List.fromList(List<int>.filled(20 * 1024, 3));
    final out = await ImageShrink.forUpload(small, 'صورة.jpg');
    expect(out.bytes, same(small));
  });

  test('الشفافية تبقى PNG ولا تنقلب خلفية سوداء', () async {
    final png = _photo(width: 2400, height: 2400, alpha: true);
    final out = await ImageShrink.forUpload(png, 'رسم.png');

    expect(out.fileName, 'رسم.png');
    expect(img.decodeImage(out.bytes)!.hasAlpha, isTrue);
  });

  test('PNG معتم يصير jpg ويبقى الاسم مقروءاً', () async {
    final png = Uint8List.fromList(img.encodePng(img.decodeImage(_photo(width: 3000, height: 2200))!));
    expect(png.length, greaterThan(ImageShrink.minBytesToTry), reason: 'العيّنة فوق عتبة التصغير');

    final out = await ImageShrink.forUpload(png, 'لوح الصف.png');
    expect(out.fileName, 'لوح الصف.jpg');
    expect(out.bytes.length, lessThan(png.length));
  });

  test('بايتات تالفة تعود كما هي بدل أن تمنع الإرفاق', () async {
    final junk = Uint8List.fromList(List<int>.filled(700 * 1024, 200));
    final out = await ImageShrink.forUpload(junk, 'مكسورة.jpg');
    expect(out.bytes, same(junk));
    expect(out.fileName, 'مكسورة.jpg');
  });
}
