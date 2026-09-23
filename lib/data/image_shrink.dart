import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// تصغير الصور قبل رفعها إلى المودل.
///
/// المعلم يصوّر ورقة بهاتفه فتخرج بعشرة ميجابايت وأبعاد 4000 بكسل، بينما
/// الطالب يفتحها على شاشة صغيرة. الرفع كان يستهلك باقته ويفشل عند الحد،
/// والتنزيل يستهلك باقة الطالب — بلا فرق يُرى في الوضوح.
class ImageShrink {
  /// أطول ضلع بعد التصغير — يكفي لقراءة ورقة مصوّرة على أي شاشة.
  static const maxDimension = 1600;

  /// جودة JPEG: أقل من ذلك يُظهر أثراً على خط اليد والنص المصوَّر.
  static const jpegQuality = 80;

  /// ما دون هذا الحجم لا يستحق فكّ الترميز وإعادته — صورة بمئتي كيلوبايت
  /// لا ترهق رفعاً ولا تنزيلاً.
  static const minBytesToTry = 200 * 1024;

  /// هل الاسم لصورة يمكن تصغيرها؟ PDF يمرّ كما هو.
  static bool isImage(String fileName) => const {
        'jpg',
        'jpeg',
        'png',
        'webp',
      }.contains(fileName.split('.').last.toLowerCase());

  /// يُعيد ما يجب رفعه فعلاً. إن تعذّر التصغير أو لم يُجدِ نفعاً عاد الأصل
  /// كما هو — فشلُ ضغطٍ لا يجوز أن يمنع معلماً من إرفاق ورقته.
  static Future<({Uint8List bytes, String fileName})> forUpload(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!isImage(fileName) || bytes.length < minBytesToTry) {
      return (bytes: bytes, fileName: fileName);
    }
    try {
      // خارج خيط الواجهة: فكّ ترميز صورة بأربعة آلاف بكسل يُجمّد الشاشة
      final out = await Isolate.run(() => _shrink(bytes));
      if (out == null || out.bytes.length >= bytes.length) {
        return (bytes: bytes, fileName: fileName);
      }
      return (bytes: out.bytes, fileName: _rename(fileName, out.extension));
    } catch (_) {
      return (bytes: bytes, fileName: fileName);
    }
  }

  static String _rename(String fileName, String extension) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    return '$stem.$extension';
  }

  /// نسبة التصغير المئوية بين حجمين — لإظهارها للمعلم.
  static int savedPercent(int before, int after) =>
      before <= 0 || after >= before ? 0 : (100 - (after * 100 / before)).round();
}

({Uint8List bytes, String extension})? _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longest <= ImageShrink.maxDimension
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? ImageShrink.maxDimension : null,
          height: decoded.height > decoded.width ? ImageShrink.maxDimension : null,
          interpolation: img.Interpolation.average,
        );

  // الشفافية تُفقد في JPEG فتصير خلفيةً سوداء. لكن أغلب ملفات PNG تحمل قناة
  // ألفا معتمة بالكامل — الحكم بوجودها وحده كان يُبقيها PNG ضخماً بلا سبب.
  if (_usesTransparency(resized)) {
    return (bytes: img.encodePng(resized, level: 6), extension: 'png');
  }
  return (bytes: img.encodeJpg(resized, quality: ImageShrink.jpegQuality), extension: 'jpg');
}

/// هل في الصورة بكسل شفاف فعلاً؟ يتوقف عند أول واحد.
bool _usesTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}
