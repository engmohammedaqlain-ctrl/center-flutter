import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'animated_count.dart';

/// المسافة التي تتركها القوائم أسفلها كي لا يغطي زر الإبهام آخر بطاقة.
const thumbActionClearance = 84.0;

/// الإجراء الأكثر استعمالاً في الشاشة.
class ThumbAction {
  const ThumbAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String label;
  final IconData icon;

  /// `null` يعطّل الزر ويُبقيه ظاهراً — كزر «الكل حاضر» بلا طلاب.
  final VoidCallback? onPressed;
  final Color? color;
}

/// يضع إجراء الشاشة الأساسي في منطقة الإبهام: أسفل الشاشة فوق شريط التنقّل،
/// في الجهة اليمنى حيث تصل إبهام اليد اليمنى بلا مدّ.
///
/// الأزرار المتكررة يومياً — طالب جديد، دفعة، الكل حاضر — كانت في أعلى الشاشة
/// فتحتاج اليدين أو إعادة إمساك الهاتف. الزر يصغر إلى أيقونة أثناء التمرير
/// للأسفل كي لا يحجب المحتوى، ويعود بنصه عند الصعود أو في أعلى القائمة.
class ThumbActionLayer extends StatefulWidget {
  const ThumbActionLayer({super.key, required this.child, this.action});

  final Widget child;
  final ThumbAction? action;

  @override
  State<ThumbActionLayer> createState() => _ThumbActionLayerState();
}

class _ThumbActionLayerState extends State<ThumbActionLayer> {
  bool _extended = true;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n is! ScrollUpdateNotification) {
      return false;
    }
    final delta = n.scrollDelta ?? 0;
    final atTop = n.metrics.pixels <= n.metrics.minScrollExtent + 8;
    // عتبة صغيرة تمنع الارتجاف مع كل بكسل
    if (!atTop && delta.abs() < 3) return false;
    final next = atTop || delta < 0;
    if (next != _extended) setState(() => _extended = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        if (action != null)
          PositionedDirectional(
            start: 14,
            bottom: 14,
            child: _ThumbButton(action: action, extended: _extended),
          ),
      ],
    );
  }
}

class _ThumbButton extends StatelessWidget {
  const _ThumbButton({required this.action, required this.extended});

  final ThumbAction action;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final color = enabled
        ? (action.color ?? AppColors.amber)
        : const Color(0xFFCBD5E1);

    return Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      child: PressableScale(
        onTap: action.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 50,
          constraints: const BoxConstraints(minWidth: 50),
          padding: EdgeInsets.symmetric(horizontal: extended ? 18 : 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.zero,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.38),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 21, color: Colors.white),
                if (extended) ...[
                  const SizedBox(width: 8),
                  Text(
                    action.label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
