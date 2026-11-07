import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'widgets.dart' show decodeLogo;

/// شاشة انتقال بهوية المدرسة: عند الدخول بحساب محفوظ، واستعادة الجلسة، وتسجيل الخروج.
/// خلفية بلون الثيم الداكن، وشعار المدرسة في صندوق أبيض تدور حوله حلقة، والرسالة تحته.
class BrandLoadingScreen extends StatelessWidget {
  const BrandLoadingScreen({super.key, required this.message, this.logo = '', this.name = ''});

  final String message;

  /// شعار المدرسة المحفوظ؛ فارغ = شعار النظام.
  final String logo;
  final String name;

  @override
  Widget build(BuildContext context) {
    final image = decodeLogo(logo);
    return Material(
      color: Noon.ink,
      child: SizedBox.expand(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 148,
                height: 148,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 148,
                      height: 148,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        color: Noon.onInk,
                        backgroundColor: Noon.onInk.withValues(alpha: 0.14),
                      ),
                    ),
                    Container(
                      width: 108,
                      height: 108,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Corner.box),
                        child: image == null
                            ? Image.asset('assets/logo.png', fit: BoxFit.contain)
                            : Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (name.trim().isNotEmpty) ...[
                Text(
                  name.trim(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: AppText.family, fontSize: 20, fontWeight: FontWeight.w700, color: Noon.onInk, height: 1.3),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AppText.family, fontSize: 14.5, fontWeight: FontWeight.w500, color: Noon.onInkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
