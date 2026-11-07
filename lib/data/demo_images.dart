/// صور البيانات التجريبية — المقابل لـ `demoImages.ts` ونموذجي الوثيقة وإشعار التحويل في `demoData.ts`.
/// الويب يرسمها SVG ثم يحوّلها PNG؛ هنا تُرسم PNG مباشرة بالرسّام نفسه والأشكال نفسها.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// عدد المتغيّرات لكل جنس، للدوران عليها بحسب رقم الطالب — `AVATAR_VARIANTS`.
const avatarVariants = 6;

const _backgrounds = [0xFFDBEAFE, 0xFFDCFCE7, 0xFFFEF3C7, 0xFFFCE7F3, 0xFFE0E7FF, 0xFFCCFBF1];
const _shirts = [0xFF0F766E, 0xFF1D4ED8, 0xFFB45309, 0xFF9D174D, 0xFF475569, 0xFF047857];
const _skins = [0xFFF1C9A5, 0xFFE0AC83, 0xFFC68E63, 0xFFF5D5B8];
const _hairs = [0xFF292524, 0xFF451A03, 0xFF78350F, 0xFF1C1917];

Future<Uint8List> _render(int w, int h, void Function(Canvas c) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Paint _fill(int color) => Paint()..color = Color(color);

/// صورة شخصية 200×260: المتغيّر يحدّد الألوان، والجنس يحدّد الشعر — `avatarSvg`.
Future<Uint8List> avatarPng(int variant, String gender) => _render(200, 260, (c) {
      final skin = _fill(_skins[(variant * 3) % _skins.length]);
      final hair = _fill(_hairs[(variant * 7 + 2) % _hairs.length]);
      c.drawRect(const Rect.fromLTWH(0, 0, 200, 260), _fill(_backgrounds[variant % _backgrounds.length]));
      c.drawPath(
        Path()
          ..moveTo(20, 260)
          ..cubicTo(20, 214, 54, 190, 100, 190)
          ..cubicTo(146, 190, 180, 214, 180, 260)
          ..close(),
        _fill(_shirts[(variant * 5 + 1) % _shirts.length]),
      );
      c.drawPath(
        Path()
          ..moveTo(84, 186)
          ..lineTo(116, 186)
          ..lineTo(116, 208)
          ..cubicTo(116, 216, 109, 222, 100, 222)
          ..cubicTo(91, 222, 84, 216, 84, 208)
          ..close(),
        skin,
      );
      final face = Rect.fromCenter(center: const Offset(100, 112), width: 68, height: 80);
      if (gender == 'أنثى') {
        c.drawPath(
          Path()
            ..moveTo(52, 118)
            ..cubicTo(52, 72, 74, 48, 100, 48)
            ..cubicTo(126, 48, 148, 72, 148, 118)
            ..lineTo(148, 164)
            ..cubicTo(148, 176, 138, 184, 128, 184)
            ..lineTo(72, 184)
            ..cubicTo(62, 184, 52, 176, 52, 164)
            ..close(),
          hair,
        );
        c.drawOval(face, skin);
        c.drawPath(
          Path()
            ..moveTo(66, 100)
            ..cubicTo(74, 74, 90, 66, 100, 66)
            ..cubicTo(110, 66, 130, 74, 136, 98)
            ..cubicTo(120, 90, 90, 90, 66, 100)
            ..close(),
          hair,
        );
      } else {
        c.drawOval(face, skin);
        c.drawPath(
          Path()
            ..moveTo(64, 106)
            ..cubicTo(60, 70, 82, 50, 102, 50)
            ..cubicTo(122, 50, 144, 70, 136, 106)
            ..cubicTo(132, 90, 122, 80, 100, 80)
            ..cubicTo(78, 80, 70, 90, 64, 106)
            ..close(),
          hair,
        );
      }
      final eye = _fill(0xFF1C1917);
      c.drawCircle(const Offset(88, 114), 3.2, eye);
      c.drawCircle(const Offset(112, 114), 3.2, eye);
      c.drawPath(
        Path()
          ..moveTo(90, 130)
          ..quadraticBezierTo(100, 138, 110, 130),
        Paint()
          ..color = const Color(0xFF881337)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    });

void _text(Canvas c, String text, Offset center, {double size = 12, int color = 0xFF1E293B, bool bold = false, bool alignStart = false}) {
  final p = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, color: Color(color), fontWeight: bold ? FontWeight.bold : FontWeight.normal),
    ),
    textDirection: TextDirection.rtl,
  )..layout(maxWidth: 380);
  final dx = alignStart ? center.dx - p.width : center.dx - p.width / 2;
  p.paint(c, Offset(dx, center.dy - p.height / 2));
  p.dispose();
}

Paint _stroke(int color, double w) => Paint()
  ..color = Color(color)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

/// نموذج وثيقة مدرسية 400×260 — `SAMPLE_DOC_SVG`.
Future<Uint8List> sampleDocPng() => _render(400, 260, (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 260), _fill(0xFFF8FAFC));
      c.drawRect(const Rect.fromLTWH(1, 1, 398, 258), _stroke(0xFFCBD5E1, 2));
      c.drawRRect(RRect.fromLTRBR(20, 20, 380, 60, const Radius.circular(4)), _fill(0xFF0B2545));
      _text(c, 'وثيقة مدرسية رسمية - نموذج تجريبي', const Offset(200, 40), size: 14, color: 0xFFFFFFFF, bold: true);
      c.drawRect(const Rect.fromLTWH(270, 80, 100, 120), _fill(0xFFE2E8F0));
      c.drawRect(const Rect.fromLTWH(270, 80, 100, 120), _stroke(0xFF94A3B8, 1));
      _text(c, 'صورة شخصية', const Offset(320, 140), color: 0xFF64748B);
      final line = _stroke(0xFFCBD5E1, 3);
      c.drawLine(const Offset(40, 95), const Offset(250, 95), line);
      c.drawLine(const Offset(60, 125), const Offset(250, 125), line);
      c.drawLine(const Offset(100, 155), const Offset(250, 155), line);
      _text(c, 'معتمد وموثق لدى الإدارة المدرسية', const Offset(200, 235), color: 0xFF059669, bold: true);
    });

/// إشعار تحويل مالي 400×300 — `SAMPLE_TRANSFER_SVG`.
Future<Uint8List> sampleTransferPng() => _render(400, 300, (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), _fill(0xFFFFFFFF));
      c.drawRect(const Rect.fromLTWH(1, 1, 398, 298), _stroke(0xFF059669, 2));
      c.drawRect(const Rect.fromLTWH(0, 0, 400, 45), _fill(0xFF059669));
      _text(c, 'إشعار تحويل مالي معتمد', const Offset(200, 24), size: 15, color: 0xFFFFFFFF, bold: true);
      _text(c, 'الجهة: بنك فلسطين / جوال باي', const Offset(360, 80), size: 13, bold: true, alignStart: true);
      _text(c, 'المبلغ: مسدد بالكامل', const Offset(360, 115), color: 0xFF475569, alignStart: true);
      _text(c, 'حالة العملية: ناجحة ومقبوضة', const Offset(360, 150), color: 0xFF475569, alignStart: true);
      c.drawRect(const Rect.fromLTWH(40, 180, 320, 40), _fill(0xFFF0FDF4));
      c.drawRect(const Rect.fromLTWH(40, 180, 320, 40), _stroke(0xFFBBF7D0, 1));
      _text(c, 'TRX-PAL-VERIFIED-SUCCESS', const Offset(200, 200), size: 13, color: 0xFF16A34A, bold: true);
      _text(c, 'إشعار دفع إلكتروني رسمي', const Offset(200, 265), size: 11, color: 0xFF64748B);
    });

/// صور الديمو كلها مرة واحدة: الصورة الشخصية لكل جنس بمتغيّراتها، والوثيقة، والإشعار.
class DemoImages {
  const DemoImages({required this.avatars, required this.doc, required this.transfer});

  final Map<String, List<Uint8List>> avatars;
  final Uint8List doc;
  final Uint8List transfer;

  static Future<DemoImages> render() async => DemoImages(
        avatars: {
          for (final g in const ['ذكر', 'أنثى']) g: [for (var i = 0; i < avatarVariants; i++) await avatarPng(i, g)],
        },
        doc: await sampleDocPng(),
        transfer: await sampleTransferPng(),
      );
}
