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
