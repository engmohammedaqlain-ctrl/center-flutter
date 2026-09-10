import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// مقياس النص — قيمة واحدة لكل دور، لا أرقام متناثرة في الشاشات.
///
/// المقاسات مأخوذة من واجهة الهاتف في Center: العناوين 13، والنص 12،
/// والثانوي 11.5، والتسميات 10.5. اختلافها من شاشة لأخرى كان يجعل
/// البطاقات تبدو غير منتمية لبعضها.
abstract final class AppText {
  /// عنوان شاشة أو قسم.
  static TextStyle get title => TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.heading, height: 1.35);

  /// عنوان بطاقة أو صف في قائمة.
  static TextStyle get cardTitle => TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.heading, height: 1.3);

  /// نص أساسي.
  static const body = TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.5);

  /// نص ثانوي وشروح.
  static const muted = TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5);

  /// تسمية حقل أو شارة.
  static const label = TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.35, fontWeight: FontWeight.w600);

  /// رقم بارز.
  static TextStyle get figure => TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.heading, height: 1.2);
}

/// مقياس المسافات — مضاعفات ثابتة بدل قيم عشوائية.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 7.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const xl = 18.0;

  /// الهامش الأفقي الموحّد لمحتوى الشاشات.
  static const screen = EdgeInsets.symmetric(horizontal: 14);
}

/// نصف قطر الزوايا — صفر في كل مكان، تماماً كنظام التصميم في Center
/// (`borderRadius: 0` لكل المقاسات في tailwind.config.ts).
///
/// الحداثة هنا من المسافة والتباين والظل الخفيف، لا من تدوير الحواف:
/// الحافة المستقيمة هوية النظام الإداري وتُبقي الجداول والبطاقات متراصّة.
abstract final class Corner {
  static const card = 0.0;
  static const field = 0.0;
  static const chip = 0.0;
  static const sheet = 0.0;
}

/// ظل خفيف يفصل البطاقة عن الخلفية بلا ثقل — بديل التدوير في إعطاء العمق.
const cardShadow = [
  BoxShadow(color: Color(0x0D0B2545), blurRadius: 10, offset: Offset(0, 2)),
];

abstract final class AppTheme {
  static final radius = BorderRadius.circular(Corner.field);

  static ThemeData build() {
    final base = GoogleFonts.ibmPlexSansArabicTextTheme();
    OutlineInputBorder border([Color c = AppColors.line, double w = 1]) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: Colors.white,
      colorScheme: ColorScheme.light(
        primary: AppColors.amber,
        onPrimary: Colors.white,
        secondary: AppColors.navy,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.text,
      ),
      textTheme: base.apply(bodyColor: AppColors.text, displayColor: AppColors.heading),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      dividerColor: AppColors.line,
      splashFactory: NoSplash.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        hintStyle: const TextStyle(color: AppColors.faint, fontSize: 12),
        labelStyle: AppText.muted,
        border: border(),
        enabledBorder: border(),
        focusedBorder: border(AppColors.amber, 1.4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.card)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
        ),
      ),
    );
  }
}
