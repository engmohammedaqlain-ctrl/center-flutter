import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// تصغير الصور قبل رفعها إلى المودل.
///
/// المعلم يصوّر ورقة بهاتفه فتخرج بعشرة ميجابايت وأبعاد 4000 بكسل، بينما
/// الطالب يفتحها على شاشة صغيرة. الرفع كان يستهلك باقته ويفشل عند الحد،
/// والتنزيل يستهلك باقة الطالب — بلا فرق يُرى في الوضوح.
///
/// العقد نفسه في الويب (`MATERIAL_IMAGE_COMPRESSION` في `materialLimits.ts`):
/// أطول ضلع 1920، JPEG بجودة 0.82، والحجم يُفحص بعد الضغط لا قبله.
class ImageShrink {
  /// أطول ضلع بعد التصغير — أوضح من أي شاشة جوال.
  static const maxDimension = 1920;

  /// جودة JPEG: أقل من ذلك يُظهر أثراً على خط اليد والنص المصوَّر.
  static const jpegQuality = 82;

  /// ما دون هذا الحجم لا يستحق فكّ الترميز وإعادته — صورة بمئتي كيلوبايت
  /// لا ترهق رفعاً ولا تنزيلاً.
  static const minBytesToTry = 200 * 1024;

  /// صيغ تقبلها حاوية المواد كما هي، فالصغيرة منها لا تُعاد.
  static const _uploadable = {'jpg', 'jpeg', 'png', 'webp'};

  /// هل الاسم لصورة يمكن تصغيرها؟ PDF وملفات أوفيس تمرّ كما هي.
  static bool isImage(String fileName) => const {
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic',
        'heif',
      }.contains(_ext(fileName));

  static String _ext(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  /// يُعيد ما يجب رفعه فعلاً: الصورة JPEG باسم `.jpg`. إن تعذّر التصغير أو لم
  /// يُجدِ نفعاً عاد الأصل كما هو — فشلُ ضغطٍ لا يجوز أن يمنع معلماً من إرفاق
  /// ورقته، وصيغةٌ لا تقبلها الحاوية يرفضها فحص النوع بعده برسالة مفهومة.
  static Future<({Uint8List bytes, String fileName})> forUpload(
    Uint8List bytes,
    String fileName,
  ) async {
    if (!isImage(fileName)) return (bytes: bytes, fileName: fileName);
    final uploadable = _uploadable.contains(_ext(fileName));
    if (uploadable && bytes.length < minBytesToTry) {
      return (bytes: bytes, fileName: fileName);
    }
    try {
      // خارج خيط الواجهة: فكّ ترميز صورة بأربعة آلاف بكسل يُجمّد الشاشة
      final out = await Isolate.run(() => _toJpeg(bytes, maxDimension, jpegQuality));
      if (out == null || (uploadable && out.length >= bytes.length)) {
        return (bytes: bytes, fileName: fileName);
      }
      return (bytes: out, fileName: _rename(fileName, 'jpg'));
    } catch (_) {
      return (bytes: bytes, fileName: fileName);
    }
  }

  /// صورة إشعار التحويل لطلب الدفع: JPEG صغير يمرّ تحت حد حاوية الطلبات
  /// (2 ميجا). `null` إن لم تكن صورة تُقرأ.
  static Future<Uint8List?> forReceipt(Uint8List bytes) async {
    try {
      return await Isolate.run(() => _toJpeg(bytes, 1400, 70));
    } catch (_) {
      return null;
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

/// فكّ الصورة وتصغيرها إلى [maxDimension] ثم JPEG. فكّ JPEG وتصغيره يطبّقان
/// اتجاه الكاميرا (EXIF)، فلا تنقلب الورقة المصوّرة.
Uint8List? _toJpeg(Uint8List bytes, int maxDimension, int quality) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longest <= maxDimension
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
          interpolation: img.Interpolation.average,
        );

  // JPEG بلا شفافية: الشفاف يُسطَّح على أبيض بدل أن يصير خلفية سوداء
  final flat = _usesTransparency(resized) ? _onWhite(resized) : resized;
  return img.encodeJpg(flat, quality: quality);
}

/// هل في الصورة بكسل شفاف فعلاً؟ يتوقف عند أول واحد.
bool _usesTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}

img.Image _onWhite(img.Image image) {
  final bg = img.Image(width: image.width, height: image.height, numChannels: 3);
  img.fill(bg, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(bg, image);
}
