import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// أقرب ما يمكن لواجهة الجوال في البرنامج الأصلي: حواف حادة، بلا ظل، كثافة إدارية.
abstract final class AppTheme {
  static const radius = BorderRadius.zero;

  static ThemeData build() {
    final base = GoogleFonts.ibmPlexSansArabicTextTheme();
    OutlineInputBorder border([Color c = AppColors.line]) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: AppColors.amber,
        onPrimary: Colors.white,
        secondary: AppColors.navy,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.text,
      ),
      textTheme: base.apply(bodyColor: AppColors.text, displayColor: AppColors.heading),
      appBarTheme: const AppBarTheme(
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: const TextStyle(color: AppColors.faint, fontSize: 12),
        border: border(),
        enabledBorder: border(),
        focusedBorder: border(AppColors.amber),
      ),
    );
  }
}
