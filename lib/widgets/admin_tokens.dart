import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// لوحة نون لشاشات الإدارة — مؤقتة حتى تصل رموز التصميم المشتركة في `theme/`.
///
/// منقولة من `lib/noonTheme.ts` في الويب (`NOON_PALETTE`): كل درجة مشتقة من
/// ألوان المدرسة الخمسة بالمزج مع الأبيض (`color-mix(in srgb, …)`)، فتتبع
/// هوية المدرسة كما في الويب: الحبر من لون القائمة، والأزرق المخضر من العنصر
/// النشط، والإجراء من أزرار العمليات، والورق من خلفية النظام.
abstract final class AdminNoon {
  static Color get ink => AppColors.navy;
  static Color get onInk => readableOn(ink);
  static Color get onInkSoft => mix(onInk, 0.72, ink);

  static Color get teal => AppColors.accent;
  static Color get onTeal => readableOn(teal);
  static Color get tealD => mix(teal, 0.78, Colors.black);

  static Color get action => AppColors.amber;
  static Color get onAction => readableOn(action);

  static Color get mist => mix(teal, 0.14);
  static Color get mist2 => mix(teal, 0.07);
  static Color get band => mix(teal, 0.05);

  /// رأس الجدول — أوضح من `mist`.
  static Color get head => mix(teal, 0.24);
  static Color get headLine => mix(teal, 0.38);

  static Color get paper => AppColors.bg;

  static Color get line => mix(ink, 0.14);
  static Color get rule => mix(ink, 0.62);
  static Color get ruleSoft => mix(ink, 0.42);
  static Color get muted => mix(ink, 0.25, const Color(0xFF64757A));
  static Color get faint => mix(ink, 0.40);

  /// نص الجسم والعناوين: داكن دائماً مهما كان لون القائمة.
  static Color get text => mix(ink, 0.55, Colors.black);

  // حالات التنبيه الكهرمانية: ثابتة لأن دلالتها لا تتبع لون المدرسة
  static const sunL = Color(0xFFFEF1D2);
  static const warn = Color(0xFF8A5B00);
  static const warnD = Color(0xFF6B4A00);
  static const warnLine = Color(0xFFEDD39A);

  // أخضر المسدد وأحمر المستحق (emerald / rose في Tailwind)
  static const green50 = Color(0xFFECFDF5);
  static const green200 = Color(0xFFA7F3D0);
  static const green700 = Color(0xFF047857);
  static const red50 = Color(0xFFFFF1F2);
  static const red200 = Color(0xFFFECDD3);
  static const red600 = Color(0xFFE11D48);
  static const red700 = Color(0xFFBE123C);

  /// `nShadow`: ظل ناعم جداً فوق حدّ اللوح.
  static const shadow = <BoxShadow>[
    BoxShadow(color: Color(0x0F0A3336), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D0A3336), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// سلّم الزوايا: لوح 10، بلاطة وزر وحقل 8، وسم 4.
  static const rPanel = 10.0;
  static const rTile = 8.0;
  static const rTag = 4.0;

  /// مزج `ratio` من اللون مع `base` — `color-mix(in srgb, c ratio%, base)`.
  static Color mix(Color c, double ratio, [Color base = Colors.white]) {
    int ch(double a, double b) => ((a * ratio + b * (1 - ratio)) * 255).round().clamp(0, 255);
    return Color.fromARGB(255, ch(c.r, base.r), ch(c.g, base.g), ch(c.b, base.b));
  }

  /// الأبيض أو الداكن فوق خلفية — `readableOn` في institution.ts (تباين APCA).
  static Color readableOn(Color bg) {
    double y(Color c) {
      double ch(double v) => math.pow(v, 2.4).toDouble();
      return 0.2126729 * ch(c.r) + 0.7151522 * ch(c.g) + 0.0721750 * ch(c.b);
    }

    double apca(double txt, double back) {
      const icr = 0.1;
      const d = 0.027;
      final nb = back > d ? back : back + math.pow(d - back, 1.414);
      final nt = txt > d ? txt : txt + math.pow(d - txt, 1.414);
      if (nb > nt) {
        final s = (math.pow(nb, 0.56) - math.pow(nt, 0.57)) * 1.14;
        return s < icr ? 0 : (s - 0.027) * 100;
      }
      final s = (math.pow(nb, 0.65) - math.pow(nt, 0.62)) * 1.14;
      return s.abs() < icr ? 0 : (s + 0.027) * 100;
    }

    const dark = Color(0xFF191D15);
    final b = y(bg);
    return apca(1, b).abs() >= apca(y(dark), b).abs() ? Colors.white : dark;
  }
}
