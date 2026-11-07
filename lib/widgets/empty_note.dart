import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// رسالة «لا يوجد شيء هنا» داخل قسم أو بطاقة: في منتصف مكانها، بخط أوضح من نص الجسم،
/// بدل سطر صغير ملتصق بطرف الشاشة.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.icon, this.good = false});

  final String text;
  final IconData? icon;

  /// خبر طيب (لا غياب، لا متأخرات): بلون النجاح بدل الرمادي.
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.success : Noon.muted;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 26, color: color), const SizedBox(height: 8)],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppText.family, fontSize: 14, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
