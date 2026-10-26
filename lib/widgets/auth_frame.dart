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
    final logoSize = keyboard ? 72.0 : 120.0;
    final top = MediaQuery.paddingOf(context).top;
    // كصفحة دخول الويب: شريط بلون الهوية يعبره الشعار نصفه
    final bandHeight = top + (keyboard ? 96.0 : 184.0);
    final logoTop = keyboard ? 40.0 : 112.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            height: bandHeight,
            child: ColoredBox(color: AppColors.navy),
          ),
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, top + logoTop, 16, 40),
                // ارتفاع أدنى بقدر الشاشة: المحتوى يُمرَّر حين تأخذ لوحة المفاتيح
                // نصفه — بدل أن يُعصر ويقفز مع كل فتح لها
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: (box.maxHeight - top - logoTop - 40).clamp(0.0, double.infinity)),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      // عدد الأبناء ثابت مهما فُتحت لوحة المفاتيح: حذف العنوان
                      // الفرعي والتذييل عند فتحها كان يزيح ما بعدهما، فتُبنى الحقول
                      // من جديد وتفقد التركيز — فتنغلق لوحة المفاتيح فور فتحها.
                      // المفاتيح تضمن بقاء عناصر النموذج نفسها عبر كل إعادة بناء.
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            key: const ValueKey('auth-logo'),
                            duration: const Duration(milliseconds: 200),
                            width: logoSize,
                            height: logoSize,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: const Color(0x140F172A)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Corner.box),
                              // شعار المنشأة إن وصل، وإلا شعار النظام نفسه الذي
                              // يحمله تطبيق سطح المكتب
                              child: image == null
                                  ? Image.asset('assets/logo.png', fit: BoxFit.contain)
                                  : Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
                            ),
                          ),
                          SizedBox(key: const ValueKey('auth-gap-title'), height: keyboard ? 10 : 20),
                          Text(
                            title,
                            key: const ValueKey('auth-title'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: AppColors.heading,
                              fontSize: keyboard ? 18 : 24,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                          AnimatedSize(
                            key: const ValueKey('auth-subtitle'),
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: keyboard || subtitle == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      subtitle!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: AppText.family,
                                        color: Color(0xFF64748B),
                                        fontSize: 14,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                          ),
                          SizedBox(key: const ValueKey('auth-gap-body'), height: keyboard ? 14 : 24),
                          KeyedSubtree(
                            key: const ValueKey('auth-body'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: children,
                            ),
                          ),
                          AnimatedSize(
                            key: const ValueKey('auth-footer'),
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: keyboard || footer == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(padding: const EdgeInsets.only(top: 16), child: footer!),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x140F172A)),
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
InputDecoration authFieldDecoration(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, letterSpacing: 0),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.navy),
      ),
    );

/// زر إظهار/إخفاء كلمة المرور داخل الحقل — بلا كتابة عمياء عند الخطأ.
class AuthRevealButton extends StatelessWidget {
  const AuthRevealButton({super.key, required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      tooltip: visible ? 'إخفاء' : 'إظهار',
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
        color: AppColors.faint,
      ),
    );
  }
}

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
        height: 66,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          // بلون الهوية كزر الويب؛ معطّلاً يبهت ولا يصير رمادياً
          color: onTap == null && !busy ? AppColors.navy.withValues(alpha: 0.55) : AppColors.navy,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
