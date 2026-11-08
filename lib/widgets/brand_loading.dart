import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../data/school_brand.dart';
import '../data/store.dart';
import 'widgets.dart' show decodeLogo;

/// شاشة انتقال بهوية المدرسة: عند الدخول بحساب محفوظ، واستعادة الجلسة، وتسجيل الخروج.
/// خلفية بلون الثيم الداكن، وشعار المدرسة في صندوق أبيض تدور حوله حلقة، والرسالة تحته.
class BrandLoadingScreen extends StatelessWidget {
  const BrandLoadingScreen({super.key, required this.message, this.logo = '', this.name = ''});

  /// شاشة الانتقال بشعار المدرسة واسمها المعروفين على الجهاز.
  factory BrandLoadingScreen.auto(String message) {
    final brand = SchoolBrand.instance;
    final store = AppStore.instance;
    final useBrand = brand.linked && brand.name.isNotEmpty;
    return BrandLoadingScreen(
      message: message,
      logo: store.institutionLogo.isNotEmpty && !useBrand ? store.institutionLogo : brand.logo,
      name: store.institutionName.isNotEmpty && !useBrand ? store.institutionName : brand.name,
    );
  }

  final String message;

  /// شعار المدرسة المحفوظ؛ فارغ = شعار النظام.
  final String logo;
  final String name;

  /// شعار تعذّر تحميله: أيقونة مدرسة بدل مربع الخطأ الأحمر.
  static Widget get _fallback => Icon(Icons.school_outlined, size: 30, color: Noon.ink);

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
                width: 104,
                height: 104,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 104,
                      height: 104,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        strokeCap: StrokeCap.round,
                        color: Noon.onInk,
                        backgroundColor: Noon.onInk.withValues(alpha: 0.14),
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Corner.box),
                        child: image == null
                            ? Image.asset('assets/logo.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallback)
                            : Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, __, ___) => _fallback),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (name.trim().isNotEmpty) ...[
                Text(
                  name.trim(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: AppText.family, fontSize: 17, fontWeight: FontWeight.w700, color: Noon.onInk, height: 1.3),
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
