import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/institution.dart';

/// ألوان الواجهة.
///
/// الخمسة التي يخصّصها المدير من «إعدادات المطور» متغيّرة، لأنها تُحفظ في
/// `institution_settings` وتصل كل جهاز عبر المزامنة: تثبيتها في الكود كان
/// يُبقي الجوال على الكهرماني الافتراضي بينما سطح المكتب يعرض ألوان المنشأة.
/// أما ألوان الدلالة — النجاح والخطر والنص — فثابتة لأن معناها لا يتغيّر.
abstract final class AppColors {
  // ── ألوان الهوية (تتبع إعدادات المنشأة) ──────────────────────────────────
  /// خلفية الترويسة والقوائم — `sidebarBg` (افتراضي الويب `#0F172A`).
  static Color navy = const Color(0xFF0F172A);
  static Color navyDark = const Color(0xFF0B1220);
  static Color navyMid = const Color(0xFF1E293B);

  /// لون الإجراء وسندات القبض — `actionButton` (افتراضي الويب `#0EA5E9`).
  static Color amber = const Color(0xFF0EA5E9);
  static Color amberDark = const Color(0xFF0284C7);

  /// لون التمييز على الهاتف: القسم المفتوح — `activeItem`.
  static Color accent = const Color(0xFF0284C7);

  /// خلفية وحدّ فاتحان مشتقّان من لون العمليات — مطابق لـ
  /// `color-mix(in srgb, var(--theme-action-btn) 10%/25%, white)` في index.css.
  static Color amberSoft = _mix(const Color(0xFF0EA5E9), 0.10);
  static Color amberBorder = _mix(const Color(0xFF0EA5E9), 0.25);

  /// خلفية مساحة العمل — `appBg`.
  static Color bg = const Color(0xFFF8FAFC);

  /// لون العناوين والأزرار الأساسية — `primaryButton`.
  static Color heading = const Color(0xFF0F172A);

  // ── ألوان ثابتة المعنى (سلم Atlassian/Jira — الدلالة لا تتبع المنشأة) ───
  static const surface = Color(0xFFFFFFFF);
  /// خلفية sunk افتراضية حين لا تضبط المنشأة لوناً.
  static const sunken = Color(0xFFF7F8F9);
  static const line = Color(0x1F091E42); // ≈12% حبر — أخف من سليت صلب
  static const lineStrong = Color(0xFFDCDFE4);
  static const hover = Color(0xFFF1F2F4);

  /// حبر Atlassian — ليس أسوداً صرفاً.
  static const text = Color(0xFF172B4D);
  static const muted = Color(0xFF44546F);
  static const faint = Color(0xFF626F86);

  /// اسم المنشأة على الشريط العلوي الداكن.
  static const headerMuted = Color(0xFF9FADBC);

  static const success = Color(0xFF1F845A);
  static const successSoft = Color(0xFFDCFFF1);
  static const successBorder = Color(0xFFBAF3DB);
  static const danger = Color(0xFFC9372C);
  static const dangerSoft = Color(0xFFFFECEB);
  static const dangerBorder = Color(0xFFFFD2CC);
  static const info = Color(0xFF0055CC);
  static const infoSoft = Color(0xFFE9F2FF);
  static const warn = Color(0xFF7F5F01);
  static const warnSoft = Color(0xFFFFF7D6);

  /// طبع ألوان المنشأة على الواجهة. الدرجات المشتقة تُحسب من اللون الأساس
  /// فيبقى التدرّج متناسقاً مهما اختار المدير.
  static void apply(InstitutionColors c) {
    final side = parseHexColor(c.sidebarBg) ?? const Color(0xFF0F172A);
    // لون ناقص أو تالف يعود إلى أقرب لون من هوية المنشأة نفسها — لا إلى لون
    // النظام الافتراضي، فمنشأة ضبطت لونين فقط لا تظهر بنصف هويتها
    final action = parseHexColor(c.actionButton) ?? const Color(0xFF0EA5E9);
    final highlight = parseHexColor(c.activeItem) ?? action;
    final primary = parseHexColor(c.primaryButton) ?? side;
    final surfaceBg = parseHexColor(c.appBg) ?? const Color(0xFFF8FAFC);

    navy = side;
    navyDark = _shade(side, 0.72);
    navyMid = _shade(side, 1.45);

    amber = action;
    amberDark = _shade(action, 0.86);
    // تمييز القسم المفتوح على الهاتف يتبع activeItem (هوية المنشأة)، كما في
    // القائمة الجانبية على سطح المكتب. لون العمليات يبقى للأزرار والشارات.
    accent = highlight;
    amberSoft = _mix(action, 0.10);
    amberBorder = _mix(action, 0.25);

    heading = primary;
    bg = surfaceBg;

    Noon.derive(sidebar: side, active: highlight, action: action, appBg: surfaceBg);
  }

  /// إعادة الألوان إلى هوية النظام الافتراضية.
  static void reset() => apply(InstitutionColors.defaults);

  /// تفتيح أو تغميق بضرب المركّبات — `factor` أقل من 1 يُغمّق.
  /// مزج اللون بالأبيض بنسبة — مطابق لـ `color-mix(in srgb, <لون> N%, white)`.
  static Color _mix(Color c, double ratio) {
    int ch(double v) => (v * 255 * ratio + 255 * (1 - ratio)).round().clamp(0, 255);
    return Color.fromARGB(255, ch(c.r), ch(c.g), ch(c.b));
  }

  static Color _shade(Color c, double factor) {
    int ch(double v) => (v * 255 * factor).round().clamp(0, 255);
    return Color.fromARGB(255, ch(c.r), ch(c.g), ch(c.b));
  }

}

/// مزج `pct` (0..1) من [color] مع [base] — مطابق لـ `color-mix(in srgb, <لون> N%, <أساس>)`.
Color noonMix(Color color, double pct, [Color base = const Color(0xFFFFFFFF)]) {
  int ch(double a, double b) => ((a * pct + b * (1 - pct)) * 255).round().clamp(0, 255);
  return Color.fromARGB(255, ch(color.r, base.r), ch(color.g, base.g), ch(color.b, base.b));
}

double _luminanceY(Color c) {
  double ch(double v) => math.pow(v, 2.4).toDouble();
  return 0.2126729 * ch(c.r) + 0.7151522 * ch(c.g) + 0.0721750 * ch(c.b);
}

/// التباين الإدراكي APCA — مطابق لـ `apcaContrast` في `lib/institution.ts`.
double _apca(double txtY, double bgY) {
  const icr = 0.1;
  const deltaY2 = 0.027;
  final normBg = bgY > deltaY2 ? bgY : bgY + math.pow(deltaY2 - bgY, 1.414);
  final normTxt = txtY > deltaY2 ? txtY : txtY + math.pow(deltaY2 - txtY, 1.414);
  if (normBg > normTxt) {
    final sapc = (math.pow(normBg, 0.56) - math.pow(normTxt, 0.57)) * 1.14;
    return sapc < icr ? 0 : (sapc - 0.027) * 100;
  }
  final sapc = (math.pow(normBg, 0.65) - math.pow(normTxt, 0.62)) * 1.14;
  return sapc.abs() < icr ? 0 : (sapc + 0.027) * 100;
}

/// النص المقروء فوق خلفية: الأبيض أو الداكن `#191D15` — مطابق لـ `readableOn` في الويب.
Color noonReadableOn(Color background) {
  const dark = Color(0xFF191D15);
  final bgY = _luminanceY(background);
  final white = _apca(_luminanceY(const Color(0xFFFFFFFF)), bgY).abs();
  final onDark = _apca(_luminanceY(dark), bgY).abs();
  return white >= onDark ? const Color(0xFFFFFFFF) : dark;
}

/// لون بطاقة الملخص العميقة: `theme` من ثيم المدرسة، و`due` نبيذي للمستحق، و`paid` أخضر عميق للمسدد.
enum NoonHeroTone { theme, due, paid }

/// لوحة نون للبوابات (الطالب وولي الأمر والمعلم) والمودل — مطابقة لـ `NOON_PALETTE`
/// في `lib/noonTheme.ts` بالويب. أسماؤها ثابتة وقيمها تُشتق من ألوان المدرسة الخمسة
/// عند كل `AppColors.apply`: الحبر من لون القائمة، والأزرق المخضر من العنصر النشط،
/// والإجراء من لون العمليات، والورق من خلفية النظام. لا شفافية على ألوانها: لكل درجة اسم.
abstract final class Noon {
  static const _white = Color(0xFFFFFFFF);
  static const _black = Color(0xFF000000);

  // ── من ثيم المدرسة ───────────────────────────────────────────────────────
  /// شريط الترويسة والإطارات الداكنة.
  static Color ink = const Color(0xFF0F172A);
  static Color onInk = _white;

  /// سطر فرعي على شريط الحبر.
  static Color onInkSoft = noonMix(_white, 0.72, const Color(0xFF0F172A));

  /// التبويب النشط وأشرطة التمييز.
  static Color teal = const Color(0xFF0284C7);
  static Color onTeal = _white;
  static Color tealD = noonMix(const Color(0xFF0284C7), 0.78, _black);

  /// الإجراء الرئيسي الوحيد في الشاشة.
  static Color action = const Color(0xFF0EA5E9);
  static Color onAction = _white;
  static Color actionH = noonMix(const Color(0xFF0EA5E9), 0.88);

  /// تدرجات فاتحة من العنصر النشط.
  static Color mist = noonMix(const Color(0xFF0284C7), 0.14);
  static Color mist2 = noonMix(const Color(0xFF0284C7), 0.07);
  static Color band = noonMix(const Color(0xFF0284C7), 0.05);

  /// رأس الجدول وحدّه.
  static Color head = noonMix(const Color(0xFF0284C7), 0.24);
  static Color headLine = noonMix(const Color(0xFF0284C7), 0.38);

  /// خلفية الصفحة.
  static Color paper = const Color(0xFFF8FAFC);

  /// محايدات بميل خفيف نحو الحبر.
  static Color line = noonMix(const Color(0xFF0F172A), 0.14);
  static Color rule = noonMix(const Color(0xFF0F172A), 0.62);
  static Color ruleSoft = noonMix(const Color(0xFF0F172A), 0.42);
  static Color muted = noonMix(const Color(0xFF0F172A), 0.25, const Color(0xFF64757A));
  static Color faint = noonMix(const Color(0xFF0F172A), 0.40);

  /// نص الجسم والعناوين: داكن دائماً.
  static Color text = noonMix(const Color(0xFF0F172A), 0.55, _black);

  // ── ثابتة الدلالة ────────────────────────────────────────────────────────
  /// التنبيه الكهرماني (معلّق، مأذون، مقفل).
  static const sunL = Color(0xFFFEF1D2);
  static const warn = Color(0xFF8A5B00);
  static const warnD = Color(0xFF6B4A00);
  static const warnLine = Color(0xFFEDD39A);

  /// أخضر المسدد والحاضر (emerald في Tailwind).
  static const green50 = Color(0xFFECFDF5);
  static const green200 = Color(0xFFA7F3D0);
  static const green600 = Color(0xFF059669);
  static const green700 = Color(0xFF047857);
  static const green800 = Color(0xFF065F46);

  /// أحمر الغياب والمتأخر (rose في Tailwind).
  static const red50 = Color(0xFFFFF1F2);
  static const red200 = Color(0xFFFECDD3);
  static const red500 = Color(0xFFF43F5E);
  static const red600 = Color(0xFFE11D48);
  static const red700 = Color(0xFFBE123C);
  static const red800 = Color(0xFF9F1239);

  static List<Color> _heroTheme = _themeStops(const Color(0xFF0F172A), const Color(0xFF0284C7));

  static List<Color> _themeStops(Color ink, Color teal) => [
        noonMix(ink, 0.66, _black),
        noonMix(noonMix(teal, 0.55, ink), 0.74, _black),
        noonMix(ink, 0.38, _black),
      ];

  /// وقفات التدرج الثلاث لبطاقة الملخص: بداية، ووسط أفتح، وركن سفلي أغمق.
  static List<Color> hero(NoonHeroTone tone) => switch (tone) {
        NoonHeroTone.theme => _heroTheme,
        NoonHeroTone.due => const [Color(0xFF62202B), Color(0xFF8C3441), Color(0xFF431018)],
        NoonHeroTone.paid => const [Color(0xFF0F4A34), Color(0xFF1E7651), Color(0xFF08301F)],
      };

  /// اشتقاق اللوحة من ألوان المدرسة — يُستدعى من `AppColors.apply`.
  static void derive({required Color sidebar, required Color active, required Color action, required Color appBg}) {
    ink = sidebar;
    onInk = noonReadableOn(sidebar);
    onInkSoft = noonMix(onInk, 0.72, sidebar);
    teal = active;
    onTeal = noonReadableOn(active);
    tealD = noonMix(active, 0.78, _black);
    Noon.action = action;
    onAction = noonReadableOn(action);
    actionH = noonMix(action, 0.88);
    mist = noonMix(active, 0.14);
    mist2 = noonMix(active, 0.07);
    band = noonMix(active, 0.05);
    head = noonMix(active, 0.24);
    headLine = noonMix(active, 0.38);
    paper = appBg;
    line = noonMix(sidebar, 0.14);
    rule = noonMix(sidebar, 0.62);
    ruleSoft = noonMix(sidebar, 0.42);
    muted = noonMix(sidebar, 0.25, const Color(0xFF64757A));
    faint = noonMix(sidebar, 0.40);
    text = noonMix(sidebar, 0.55, _black);
    _heroTheme = _themeStops(sidebar, active);
  }
}
