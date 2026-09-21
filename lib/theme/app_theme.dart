import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// مقياس النص — أخف وأهدأ لبرنامج إدارة (أقل «عرض» وأكثر قراءة يومية).
abstract final class AppText {
  static const family = 'ThmanyahSans';

  /// عنوان شاشة أو قسم.
  static TextStyle get title => TextStyle(
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.heading,
        height: 1.35,
      );

  /// عنوان بطاقة أو صف في قائمة.
  static TextStyle get cardTitle => TextStyle(
        fontFamily: family,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.heading,
        height: 1.4,
      );

  /// نص أساسي.
  static TextStyle get body => TextStyle(
        fontFamily: family,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.text,
        height: 1.5,
      );

  /// نص ثانوي وشروح.
  static TextStyle get muted => TextStyle(
        fontFamily: family,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.muted,
        height: 1.45,
      );

  /// تسمية حقل أو شارة.
  static TextStyle get label => TextStyle(
        fontFamily: family,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.muted,
        height: 1.35,
      );

  /// رقم بارز — بلا Black الثقيل.
  static TextStyle get figure => TextStyle(
        fontFamily: family,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.heading,
        height: 1.25,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// مقياس المسافات — تنفّس أوضح؛ العناصر لا تتكدّس.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;

  /// الهامش الأفقي الموحّد لمحتوى الشاشات.
  static const screen = EdgeInsets.symmetric(horizontal: 16);

  /// فراغ رأسي بين أقسام الصفحة.
  static const section = 16.0;
}

/// زوايا بهوية Atlassian/Jira: لوزنجات ناعمة وبطاقات 8.
abstract final class Corner {
  /// الشارات (lozenge).
  static const chip = 3.0;

  /// الأزرار.
  static const field = 6.0;

  /// الحقول النصية.
  static const input = 6.0;

  /// الصناديق الداخلية.
  static const box = 6.0;

  /// البطاقات.
  static const card = 8.0;

  /// النوافذ الحوارية.
  static const dialog = 10.0;

  /// الحافة العلوية للأوراق السفلية.
  static const sheet = 14.0;
}

/// ظل بطاقة خفيف جداً — عمق بلا حدود غامقة.
final cardShadow = <BoxShadow>[
  BoxShadow(
    color: const Color(0xFF091E42).withValues(alpha: 0.035),
    blurRadius: 8,
    offset: const Offset(0, 1),
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
      textTheme: base.copyWith(
        bodyLarge: AppText.body.copyWith(fontSize: 13),
        bodyMedium: AppText.body,
        bodySmall: AppText.muted,
        titleLarge: AppText.title,
        titleMedium: AppText.cardTitle,
        titleSmall: AppText.cardTitle.copyWith(fontSize: 12),
        labelLarge: AppText.label.copyWith(fontWeight: FontWeight.w600),
        labelMedium: AppText.label,
        labelSmall: AppText.label.copyWith(fontSize: 9.5),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 20),
        titleTextStyle: TextStyle(
          fontFamily: AppText.family,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        toolbarHeight: 48,
      ),
      // رجوع بأسلوب أحدث (سهم iOS الرفيع) بدل سهم Material العريض — لكل AppBar تلقائياً
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 17,
          color: IconTheme.of(context).color ?? Colors.white,
        ),
      ),
      dividerColor: AppColors.line,
      splashFactory: NoSplash.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(fontFamily: AppText.family, color: AppColors.faint, fontSize: 11.5),
        labelStyle: AppText.muted,
        border: border(),
        enabledBorder: border(),
        focusedBorder: border(AppColors.accent, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.5),
        errorStyle: TextStyle(
          fontFamily: AppText.family,
          color: AppColors.danger,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        errorMaxLines: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
          textStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40),
          textStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.dialog)),
        titleTextStyle: AppText.title,
        contentTextStyle: AppText.body,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.card)),
        textStyle: AppText.body,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: AppText.label,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.chip)),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        titleTextStyle: AppText.cardTitle,
        subtitleTextStyle: AppText.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
    );
  }
}
