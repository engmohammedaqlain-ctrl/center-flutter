import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'animated_count.dart';
import 'widgets.dart';

/// إطار الشاشات التي تسبق العمل — تسجيل الدخول وتهيئة الجهاز.
///
/// هوية واحدة للشاشتين: خلفية بيضاء، وشعار المنشأة في صندوق بحدّ رفيع، والاسم
/// تحته، ثم المحتوى. مع فتح لوحة المفاتيح يصغر الشعار وتختفي الحواشي، والمحتوى
/// يُمرَّر ولا يُعصر.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.logo = '',
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// شعار المنشأة المحفوظ. فارغ = أيقونة المدرسة بلون الهوية.
  final String logo;
  final List<Widget> children;

  /// سطر هادئ أسفل المحتوى، يختفي مع لوحة المفاتيح.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final image = decodeLogo(logo);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final logoSize = keyboard ? 60.0 : 88.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            // ارتفاع أدنى بقدر الشاشة: المحتوى في المنتصف حين يتسع المكان، ويُمرَّر
            // حين تأخذ لوحة المفاتيح نصفه — بدل أن يُعصر ويقفز مع كل فتح لها
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: (box.maxHeight - 40).clamp(0.0, double.infinity)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: logoSize,
                        height: logoSize,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(Corner.card),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Corner.box),
                          child: image == null
                              ? Icon(Icons.school_outlined, color: AppColors.navy, size: logoSize * 0.5)
                              : Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                      ),
                      SizedBox(height: keyboard ? 10 : 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.heading,
                          fontSize: keyboard ? 17 : 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!keyboard && subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                      SizedBox(height: keyboard ? 14 : 24),
                      ...children,
                      if (!keyboard && footer != null) ...[
                        const SizedBox(height: 16),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// الصندوق الأبيض الذي يحمل النموذج بعرض الإطار كله.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

/// تسمية حقل بنقطتيها: «اسم المستخدم:».
Widget authLabel(String text) => Text(
      text,
      style: TextStyle(color: AppColors.heading, fontSize: 12, fontWeight: FontWeight.w700),
    );

/// الحقل بشكل التطبيق الافتراضي (خلفية بيضاء، حدّ رفيع، تمييز عند التركيز)
/// مع أيقونة بادئة هادئة.
InputDecoration authFieldDecoration(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 17, color: AppColors.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );

/// صندوق الخطأ تحت الحقول — يظهر وينطوي بحركة قصيرة، ولا يشغل مكاناً بلا خطأ.
class AuthErrorBox extends StatelessWidget {
  const AuthErrorBox({super.key, required this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(Corner.box),
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message!,
                        style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// الزر الرئيسي بلون الهوية بعرض النموذج.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.icon,
    this.busy = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(Corner.field),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            else
              Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
