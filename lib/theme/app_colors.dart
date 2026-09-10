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
  /// خلفية الترويسة والقوائم — `sidebarBg`.
  static Color navy = const Color(0xFF0B2545);
  static Color navyDark = const Color(0xFF071D36);
  static Color navyMid = const Color(0xFF123963);

  /// لون الإجراء وسندات القبض — `actionButton`.
  static Color amber = const Color(0xFFE88C15);
  static Color amberDark = const Color(0xFFD97E0D);

  /// خلفية الشارات وحدّها. ثابتتان كما في Center: `bg-[#FFF7ED]` و`#FED7AA`
  /// مكتوبتان صراحةً في المكوّنات، والهوية تتحكّم بخمسة ألوان لا غير.
  /// اشتقاقهما من لون الإجراء كان يجعلهما زهريتين باهتتين مع هوية حمراء.
  static const amberSoft = Color(0xFFFFF7ED);
  static const amberBorder = Color(0xFFFED7AA);

  /// خلفية مساحة العمل — `appBg`.
  static Color bg = const Color(0xFFF8FAFC);

  /// لون العناوين والأزرار الأساسية — `primaryButton`.
  static Color heading = const Color(0xFF0B2545);

  // ── ألوان ثابتة المعنى ───────────────────────────────────────────────────
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2E8F0);
  static const lineStrong = Color(0xFFCBD5E1);

  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);

  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFDCFCE7);
  static const successBorder = Color(0xFFBBF7D0);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const dangerBorder = Color(0xFFFECACA);
  static const info = Color(0xFF2563EB);
  static const infoSoft = Color(0xFFDBEAFE);

  /// طبع ألوان المنشأة على الواجهة. الدرجات المشتقة تُحسب من اللون الأساس
  /// فيبقى التدرّج متناسقاً مهما اختار المدير.
  static void apply(InstitutionColors c) {
    final side = parseHexColor(c.sidebarBg) ?? const Color(0xFF0B2545);
    final action = parseHexColor(c.actionButton) ?? const Color(0xFFE88C15);
    final primary = parseHexColor(c.primaryButton) ?? side;
    final surfaceBg = parseHexColor(c.appBg) ?? const Color(0xFFF8FAFC);

    navy = side;
    navyDark = _shade(side, 0.72);
    navyMid = _shade(side, 1.45);

    amber = action;
    amberDark = _shade(action, 0.86);

    heading = primary;
    bg = surfaceBg;
  }

  /// إعادة الألوان إلى هوية النظام الافتراضية.
  static void reset() => apply(InstitutionColors.defaults);

  /// تفتيح أو تغميق بضرب المركّبات — `factor` أقل من 1 يُغمّق.
  static Color _shade(Color c, double factor) {
    int ch(double v) => (v * 255 * factor).round().clamp(0, 255);
    return Color.fromARGB(255, ch(c.r), ch(c.g), ch(c.b));
  }

}
