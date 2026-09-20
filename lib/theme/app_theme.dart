import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// مقياس النص — ثمانية سانس + أدوار ثابتة (قريب من سلم Jira).
abstract final class AppText {
  static const family = 'ThmanyahSans';

  /// عنوان شاشة أو قسم.
  static TextStyle get title => TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.heading,
        height: 1.3,
        letterSpacing: -0.2,
      );

  /// عنوان بطاقة أو صف في قائمة.
  static TextStyle get cardTitle => TextStyle(
        fontFamily: family,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: AppColors.heading,
        height: 1.35,
      );

  /// نص أساسي.
  static TextStyle get body => TextStyle(
        fontFamily: family,
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: AppColors.text,
        height: 1.45,
      );

  /// نص ثانوي وشروح.
  static TextStyle get muted => TextStyle(
        fontFamily: family,
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        color: AppColors.muted,
        height: 1.4,
      );

  /// تسمية حقل أو شارة.
  static TextStyle get label => TextStyle(
        fontFamily: family,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: AppColors.muted,
        height: 1.3,
        letterSpacing: 0.15,
      );

  /// رقم بارز — أرقام جدولية حيث يدعمها الخط.
  static TextStyle get figure => TextStyle(
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: AppColors.heading,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// مقياس المسافات — تنفّس أوضح؛ العناصر لا تتكدّس.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;

  /// الهامش الأفقي الموحّد لمحتوى الشاشات.
  static const screen = EdgeInsets.symmetric(horizontal: 16);

  /// فراغ رأسي بين أقسام الصفحة.
  static const section = 20.0;
}

/// زوايا بهوية Atlassian/Jira: لوزنجات ناعمة وبطاقات 8.
abstract final class Corner {
  /// الشارات (lozenge).
  static const chip = 3.0;

  /// الأزرار.
  static const field = 8.0;

  /// الحقول النصية.
  static const input = 6.0;

  /// الصناديق الداخلية.
  static const box = 6.0;

  /// البطاقات.
  static const card = 8.0;

  /// النوافذ الحوارية.
  static const dialog = 12.0;

  /// الحافة العلوية للأوراق السفلية.
  static const sheet = 16.0;
}

/// ظل بطاقة خفيف جداً — عمق بلا حدود غامقة.
final cardShadow = <BoxShadow>[
  BoxShadow(
    color: const Color(0xFF091E42).withValues(alpha: 0.04),
    blurRadius: 10,
    offset: const Offset(0, 2),
  ),
];

abstract final class AppTheme {
  static final radius = BorderRadius.circular(Corner.input);

  static ThemeData build() {
    OutlineInputBorder border([Color c = AppColors.line, double w = 1]) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c, width: w),
        );

    final base = ThemeData(useMaterial3: true, fontFamily: AppText.family).textTheme.apply(
          fontFamily: AppText.family,
          bodyColor: AppColors.text,
          displayColor: AppColors.heading,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppText.family,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      colorScheme: ColorScheme.light(
        primary: AppColors.accent,
        onPrimary: Colors.white,
        secondary: AppColors.navy,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
      ),
      textTheme: base,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: AppText.family,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
        ),
      ),
      // رجوع بأسلوب أحدث (سهم iOS الرفيع) بدل سهم Material العريض — لكل AppBar تلقائياً
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: IconTheme.of(context).color ?? Colors.white,
        ),
      ),
      dividerColor: AppColors.line,
      splashFactory: NoSplash.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(fontFamily: AppText.family, color: AppColors.faint, fontSize: 12),
        labelStyle: AppText.muted,
        border: border(),
        enabledBorder: border(),
        focusedBorder: border(AppColors.accent, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.5),
        errorStyle: TextStyle(
          fontFamily: AppText.family,
          color: AppColors.danger,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        errorMaxLines: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
          textStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.dialog)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.card)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corner.card),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }
}
