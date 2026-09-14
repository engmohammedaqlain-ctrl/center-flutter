import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../data/institution.dart';
import '../data/portal.dart';
import '../data/printing.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

// بوابتا المعلم والطالب — المقابل لـ `pages/TeacherPortal.tsx` و`pages/StudentPortal.tsx`.
//
// التصميم منقول عن النسخة المكتبية عنصراً عنصراً: ترويسة بيضاء بالشعار واسم
// المنشأة وزر خروج وردي، ثم شريط تبويبات بخط سفلي بلون التمييز، ثم بطاقات
// بيضاء بزوايا مستديرة على خلفية رمادية فاتحة. الألوان الثابتة هي درجات
// Tailwind نفسها المكتوبة في الصفحتين.

// ═══ ألوان البوابة (درجات Tailwind في الصفحتين) ═════════════════════════════

abstract final class _C {
  static const bg = Color(0xFFF8FAFC);
  static const line = Color(0xFFE2E8F0);
  static const lineStrong = Color(0xFFCBD5E1);
  static const soft = Color(0xFFF1F5F9);
  static const text = Color(0xFF0F172A);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const navy = Color(0xFF0B2545);

  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);

  static const rose50 = Color(0xFFFFF1F2);
  static const rose200 = Color(0xFFFECDD3);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);
  static const rose800 = Color(0xFF9F1239);

  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);

  static const green = Color(0xFF16A34A);
  static const greenDark = Color(0xFF15803D);
  static const greenSoft = Color(0xFFF0FDF4);
  static const greenBorder = Color(0xFFBBF7D0);
  static const greenText = Color(0xFF166534);

  static const red = Color(0xFFDC2626);
  static const redDark = Color(0xFFB91C1C);
  static const redSoft = Color(0xFFFEF2F2);
  static const redBorder = Color(0xFFFECACA);

  static const orangeDark = Color(0xFFB45309);

  static const blue50 = Color(0xFFEFF6FF);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple700 = Color(0xFF7E22CE);
}

const _mono = 'monospace';

/// ألوان الهوية بعد قراءتها من إعدادات المنشأة، بافتراضي Center.
class _Brand {
  _Brand(PortalBranding b)
      : primary = parseHexColor(b.colors.primaryButton) ?? const Color(0xFF0B2545),
        active = parseHexColor(b.colors.activeItem) ?? const Color(0xFFE88C15),
        action = parseHexColor(b.colors.actionButton) ?? const Color(0xFFE88C15),
        side = parseHexColor(b.colors.sidebarBg) ?? const Color(0xFF0B2545);

  final Color primary;
  final Color active;
  final Color action;
  final Color side;
}

TextStyle _base(BuildContext context) => Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

// ═══ عناصر مشتركة ═══════════════════════════════════════════════════════════

/// الترويسة: الشعار واسم المنشأة و«المعلم: …» مقابل زر خروج وردي.
class _PortalHeader extends StatelessWidget {
  const _PortalHeader({
    required this.branding,
    required this.role,
    required this.userName,
    required this.onExit,
  });

  final PortalBranding branding;
  final String role;
  final String userName;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final brand = _Brand(branding);
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _C.line)),
      ),
      child: Row(
        children: [
          InstitutionBadge(logo: branding.logo, size: 40, radius: Corner.card, onDark: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  branding.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: brand.primary, fontSize: 12.5, fontWeight: FontWeight.w900, height: 1.25),
                ),
                const SizedBox(height: 2),
                Text(
                  '$role: $userName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _C.muted, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _C.rose50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Corner.field),
              side: const BorderSide(color: _C.rose200),
            ),
            child: InkWell(
              onTap: onExit,
              borderRadius: BorderRadius.circular(Corner.field),
              child: const SizedBox(
                height: 32,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, size: 14, color: _C.rose700),
                      SizedBox(width: 6),
                      Text('خروج', style: TextStyle(color: _C.rose700, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
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

class _TabSpec {
  const _TabSpec(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

/// شريط التبويبات: أعمدة متساوية، والنشط نصه وخطه السفلي بلون التمييز.
class _PortalTabs extends StatelessWidget {
  const _PortalTabs({
    required this.tabs,
    required this.active,
    required this.color,
    required this.onSelect,
    this.compact = false,
  });

  final List<_TabSpec> tabs;
  final String active;
  final Color color;
  final ValueChanged<String> onSelect;

  /// خمسة تبويبات للطالب: خط أصغر كي تتسع في عرض الهاتف.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 16, compact ? 4 : 8, compact ? 8 : 16, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _C.line)),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.id == active ? color : Colors.transparent, width: 2),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: compact ? 14 : 16, color: t.id == active ? color : _C.muted),
                        SizedBox(width: compact ? 4 : 6),
                        Text(
                          t.label,
                          style: TextStyle(
                            color: t.id == active ? color : _C.muted,
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
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

/// بطاقة البوابة: بيضاء بإطار رفيع وزوايا 16.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: _C.line),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

/// «الصف / المجموعة:» — عنوان الحقل.
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text, style: const TextStyle(color: _C.slate600, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _Select<T> extends StatelessWidget {
  const _Select({required this.value, required this.items, required this.onChanged, this.height = 40});

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(Corner.input),
        border: Border.all(color: _C.lineStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(Corner.input),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: _C.muted),
          style: _base(context).copyWith(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    this.hint,
    this.keyboardType,
    this.errorText,
    this.onChanged,
    this.maxLines = 1,
    this.ltr = false,
    this.center = false,
    this.dense = false,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool ltr;
  final bool center;

  /// حقل صغير داخل صف طالب (الدرجة والملاحظة).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder outline(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Corner.input), borderSide: BorderSide(color: c, width: w));

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      textAlign: center ? TextAlign.center : TextAlign.start,
      textDirection: ltr ? TextDirection.ltr : null,
      style: _base(context).copyWith(color: _C.text, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: ltr ? _mono : null),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: _C.bg,
        errorText: errorText,
        errorStyle: const TextStyle(color: _C.rose700, fontSize: 10.5, fontWeight: FontWeight.w700),
        contentPadding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 9 : 12),
        border: outline(_C.lineStrong),
        enabledBorder: outline(_C.lineStrong),
        focusedBorder: outline(_C.navy, 1.4),
        errorBorder: outline(_C.rose200),
        focusedErrorBorder: outline(_C.rose700, 1.4),
      ),
    );
  }
}

/// حقل تاريخ بشكل الحقول: التاريخ مقابل أيقونة التقويم.
class _DateBox extends StatelessWidget {
  const _DateBox({required this.date, required this.onPicked});

  /// `yyyy-mm-dd`
  final String date;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final current = parseIsoDate(date) ?? DateTime.now();
    return InkWell(
      borderRadius: BorderRadius.circular(Corner.input),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(current.year - 3),
          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
          cancelText: 'إلغاء',
          confirmText: 'اختيار',
        );
        if (picked != null) onPicked(isoDate(picked));
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(Corner.input),
          border: Border.all(color: _C.lineStrong),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                formatDate(current),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _C.text, fontSize: 12, fontFamily: _mono),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_outlined, size: 15, color: _C.text),
          ],
        ),
      ),
    );
  }
}

/// زر ممتلئ بلون الهوية.
class _Solid extends StatelessWidget {
  const _Solid({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.height = 44,
    this.busy = false,
    this.radius = Corner.field,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool busy;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else if (icon != null)
                    Icon(icon, size: 16, color: Colors.white),
                  if (busy || icon != null) const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر فاتح بإطار — «الكل حاضر» و«إلغاء».
class _Soft extends StatelessWidget {
  const _Soft({
    required this.label,
    required this.onTap,
    this.icon,
    this.fg = _C.muted,
    this.bg = Colors.white,
    this.border = _C.lineStrong,
    this.height = 40,
    this.radius = Corner.field,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color fg;
  final Color bg;
  final Color border;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// مربع إحصاء ملوّن: العنوان فوق الرقم.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.bg,
    required this.border,
    required this.labelColor,
    required this.valueColor,
    this.radius = Corner.card,
  });

  final String label;
  final String value;
  final Color bg;
  final Color border;
  final Color labelColor;
  final Color valueColor;
  final double radius;

  factory _Stat.plain(String label, String value, {Color valueColor = _C.navy, double radius = Corner.card}) => _Stat(
        label: label,
        value: value,
        bg: Colors.white,
        border: _C.line,
        labelColor: _C.muted,
        valueColor: valueColor,
        radius: radius,
      );

  factory _Stat.green(String label, String value, {double radius = Corner.card}) => _Stat(
        label: label,
        value: value,
        bg: _C.emerald50,
        border: _C.emerald200,
        labelColor: _C.emerald800,
        valueColor: _C.emerald700,
        radius: radius,
      );

  factory _Stat.red(String label, String value, {double radius = Corner.card}) => _Stat(
        label: label,
        value: value,
        bg: _C.rose50,
        border: _C.rose200,
        labelColor: _C.rose800,
        valueColor: _C.rose700,
        radius: radius,
      );

  factory _Stat.amber(String label, String value, {double radius = Corner.card}) => _Stat(
        label: label,
        value: value,
        bg: _C.amber50,
        border: _C.amber200,
        labelColor: _C.amber800,
        valueColor: _C.amber700,
        radius: radius,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: labelColor, fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.w900, fontFamily: _mono),
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة حالة بإطار.
class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.fg, required this.bg, this.border, this.icon, this.radius = Corner.chip, this.maxLines = 1});

  final String text;
  final Color fg;
  final Color bg;
  final Color? border;
  final IconData? icon;
  final double radius;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة فارغة: رسالة في المنتصف، بإطار متقطع حين تدعو لإضافة شيء.
class _Empty extends StatelessWidget {
  const _Empty(this.message, {this.icon, this.dashed = false, this.action, this.onAction, this.height = 110});

  final String message;
  final IconData? icon;
  final bool dashed;
  final String? action;
  final VoidCallback? onAction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 32, color: _C.lineStrong), const SizedBox(height: 8)],
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w800, height: 1.6),
          ),
          if (action != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  color: _C.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!dashed) return _Card(padding: EdgeInsets.zero, child: body);
    return CustomPaint(
      painter: const _DashedBorder(color: _C.lineStrong, radius: Corner.card),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Corner.card)),
        child: body,
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color || old.radius != radius;
}

/// شريط نجاح أخضر مقتضب.
class _Success extends StatelessWidget {
  const _Success(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _C.emerald50,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: _C.emerald200),
      ),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: _C.emerald600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: _C.emerald800, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// «الفصل الأول / الفصل الثاني / أخرى» — أزرار مجزّأة على خلفية رمادية.
class _TermSwitch extends StatelessWidget {
  const _TermSwitch({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _terms = ['term_1', 'term_2', 'other'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _C.soft, borderRadius: BorderRadius.circular(Corner.box)),
      child: Row(
        children: [
          for (final t in _terms)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == t ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(Corner.chip),
                    boxShadow: value == t
                        ? const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 2, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Text(
                    academicTermLabels[t]!,
                    style: TextStyle(
                      color: value == t ? _C.navy : _C.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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

/// ألوان شارة نوع المادة التعليمية.
({Color fg, Color bg}) _itemTypeColors(String type) => switch (type) {
      'file' => (fg: _C.blue700, bg: _C.blue50),
      'link' => (fg: _C.purple700, bg: _C.purple50),
      'assignment' => (fg: _C.emerald700, bg: _C.emerald50),
      _ => (fg: _C.slate700, bg: _C.soft),
    };

Future<void> _openUrl(BuildContext context, String url) async {
  var ok = false;
  final uri = Uri.tryParse(url.trim());
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) showAppSnack(context, 'تعذّر فتح الرابط', error: true);
}

/// حالة تحميل أو خطأ بشكل Center.
Widget _loadingView() => const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Text('جارِ تحميل البيانات...', style: TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );

Widget _errorView(String message, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 34, color: _C.faint),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            _Soft(label: 'إعادة المحاولة', icon: Icons.refresh, onTap: retry, fg: _C.navy),
          ],
        ),
      ),
    );

/// شريط حفظ ثابت أسفل الشاشة — «حفظ كشف الحضور الآن».
Widget _saveBar(BuildContext context, {required String label, required Color color, required bool busy, required VoidCallback onTap}) {
  return Container(
    padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
    decoration: const BoxDecoration(
      color: _C.bg,
      border: Border(top: BorderSide(color: _C.line)),
    ),
    child: _Solid(label: busy ? 'جارِ الحفظ...' : label, icon: Icons.check, color: color, busy: busy, onTap: onTap),
  );
}

// ══════════════════════════════════════════════════════════════════════════
// بوابة المعلم
// ══════════════════════════════════════════════════════════════════════════

class TeacherPortalScreen extends StatefulWidget {
  const TeacherPortalScreen({
    super.key,
    required this.user,
    required this.onExit,
    this.service = const PortalService(),
  });

  final PortalUser user;
  final VoidCallback onExit;

  /// قابلة للاستبدال في الاختبارات كي لا تمسّ السحابة.
  final PortalService service;

  @override
  State<TeacherPortalScreen> createState() => _TeacherPortalScreenState();
}

class _TeacherPortalScreenState extends State<TeacherPortalScreen> {
  static const _uuid = Uuid();

  TeacherPortalData? data;
  String? error;
  bool loading = true;

  String tab = 'attendance';
  String groupId = '';

  // رصد الحضور
  String sessionDate = isoDate(DateTime.now());
  Map<String, String> marks = {};
  bool savingAttendance = false;
  bool attendanceSaved = false;
  int _marksToken = 0;

  // رصد الدرجات
  final evalTitle = TextEditingController();
  final evalMax = TextEditingController(text: '100');
  String evalType = 'quiz';
  String evalDate = isoDate(DateTime.now());
  String? titleError;
  final _scores = <String, TextEditingController>{};
  final _notes = <String, TextEditingController>{};
  bool savingEvaluations = false;
  bool evaluationsSaved = false;
  List<StudentEvaluation> recent = const [];

  // المودل
  String term = 'term_1';
  List<CourseSection> sections = const [];
  bool loadingMoodle = false;
  String? moodleMessage;
  int _moodleToken = 0;

  PortalService get _service => widget.service;

  TeacherClass? get _current => data?.classes.where((c) => c.group.id == groupId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    evalTitle.dispose();
    evalMax.dispose();
    for (final c in [..._scores.values, ..._notes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await _service.teacherData(widget.user);
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
        if (result.classes.every((c) => c.group.id != groupId)) {
          groupId = result.classes.isEmpty ? '' : result.classes.first.group.id;
        }
      });
      _refreshTab();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذّر الاتصال بالسحابة.';
      });
    }
  }

  /// بيانات التبويب المفتوح للشعبة المختارة.
  void _refreshTab() {
    switch (tab) {
      case 'attendance':
        _loadMarks();
      case 'evaluations':
        _loadEvaluations();
      case 'moodle':
        _loadMoodle();
    }
  }

  void _selectGroup(String? id) {
    if (id == null || id == groupId) return;
    setState(() {
      groupId = id;
      marks = {};
      recent = const [];
      sections = const [];
    });
    _refreshTab();
  }

  void _selectTab(String id) {
    if (id == tab) return;
    setState(() => tab = id);
    _refreshTab();
  }

  // ── الحضور ────────────────────────────────────────────────────────────────

  Future<void> _loadMarks() async {
    final c = _current;
    if (c == null) return;
    final token = ++_marksToken;
    setState(() {
      marks = {};
      attendanceSaved = false;
    });
    try {
      final saved = await _service.sessionAttendance(c.group.id, sessionDate);
      if (!mounted || token != _marksToken) return;
      setState(() {
        marks = {
          for (final e in saved.entries)
            e.key: const {'present', 'absent', 'excused'}.contains(e.value.status) ? e.value.status : 'absent',
        };
      });
    } catch (_) {
      // بلا اتصال: يبقى الكشف على افتراضه «حاضر»
    }
  }

  String _statusOf(String studentId) => marks[studentId] ?? 'present';

  Future<void> _saveAttendance() async {
    final c = _current;
    if (c == null || savingAttendance) return;
    setState(() => savingAttendance = true);
    try {
      // يُحفظ ما يراه المعلم: من لم يُلمس يُرصد «حاضراً» كما يظهر
      await _service.saveAttendance(
        group: c.group,
        date: sessionDate,
        statuses: {for (final s in c.students) s.id: _statusOf(s.id)},
        teacher: widget.user,
      );
      if (!mounted) return;
      setState(() {
        savingAttendance = false;
        attendanceSaved = true;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => attendanceSaved = false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => savingAttendance = false);
      showAppSnack(context, 'تعذّر حفظ كشف الحضور', error: true);
    }
  }

  // ── الدرجات ───────────────────────────────────────────────────────────────

  Future<void> _loadEvaluations() async {
    final c = _current;
    if (c == null) return;
    try {
      final list = await _service.groupEvaluations(c.group.id);
      if (mounted && _current?.group.id == c.group.id) setState(() => recent = list);
    } catch (_) {
      // السجل السابق عرض إضافي؛ غيابه لا يمنع الرصد
    }
  }

  TextEditingController _ctl(Map<String, TextEditingController> map, String id) =>
      map.putIfAbsent(id, () => TextEditingController());

  double get _maxScore {
    final v = double.tryParse(evalMax.text.trim());
    return v == null || v <= 0 ? 100 : v;
  }

  void _fullScoreForAll() {
    final full = trimNum(_maxScore);
    setState(() {
      for (final s in _current?.students ?? const <Student>[]) {
        _ctl(_scores, s.id).text = full;
      }
    });
  }

  Future<void> _saveEvaluations() async {
    final c = _current;
    if (c == null || savingEvaluations) return;

    final title = evalTitle.text.trim();
    setState(() => titleError = title.isEmpty ? 'يرجى إدخال عنوان الاختبار أو التقييم' : null);
    if (title.isEmpty) {
      showAppSnack(context, 'يرجى تحديد عنوان التقييم واختيار الشعبة', error: true);
      return;
    }

    final max = _maxScore;
    final batch = <StudentEvaluation>[];
    for (final s in c.students) {
      final raw = _ctl(_scores, s.id).text.trim();
      if (raw.isEmpty) continue;
      final score = double.tryParse(raw);
      if (score == null || score < 0 || score > max) {
        showAppSnack(context, 'درجة غير صالحة للطالب ${s.fullName} (من 0 إلى ${trimNum(max)})', error: true);
        return;
      }
      batch.add(StudentEvaluation(
        id: _uuid.v4(),
        studentId: s.id,
        groupId: c.group.id,
        subjectId: c.group.subjectId,
        teacherId: widget.user.id,
        title: title,
        score: score,
        maxScore: max,
        evaluationDate: evalDate,
        type: evalType,
        notes: _ctl(_notes, s.id).text.trim(),
      ));
    }
    if (batch.isEmpty) {
      showAppSnack(context, 'يرجى إدخال درجة واحدة على الأقل', error: true);
      return;
    }

    setState(() => savingEvaluations = true);
    try {
      await _service.saveEvaluations(batch, widget.user.tenantId);
      if (!mounted) return;
      setState(() {
        savingEvaluations = false;
        evaluationsSaved = true;
        evalTitle.clear();
        // الدرجات تُمسح مع العنوان: بقاؤها يُعيد حفظها تحت عنوان الاختبار التالي
        for (final ctl in [..._scores.values, ..._notes.values]) {
          ctl.clear();
        }
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => evaluationsSaved = false);
      });
      _loadEvaluations();
    } catch (_) {
      if (!mounted) return;
      setState(() => savingEvaluations = false);
      showAppSnack(context, 'حدث خطأ أثناء حفظ الدرجات', error: true);
    }
  }

  Future<void> _deleteEvaluation(StudentEvaluation e) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف التقييم',
      message: 'هل أنت متأكد من حذف هذا التقييم؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      await _service.deleteEvaluation(e.id);
      _loadEvaluations();
    } catch (_) {
      if (mounted) showAppSnack(context, 'فشل حذف التقييم', error: true);
    }
  }

  // ── المودل ────────────────────────────────────────────────────────────────

  Future<void> _loadMoodle() async {
    final c = _current;
    if (c == null) return;
    final token = ++_moodleToken;
    setState(() => loadingMoodle = true);
    try {
      final list = await _service.groupSections(
        tenantId: widget.user.tenantId,
        groupId: c.group.id,
        term: term,
        includeHidden: true,
      );
      if (!mounted || token != _moodleToken) return;
      setState(() {
        sections = list;
        loadingMoodle = false;
      });
    } catch (_) {
      if (mounted && token == _moodleToken) setState(() => loadingMoodle = false);
    }
  }

  void _flash(String message) {
    setState(() => moodleMessage = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && moodleMessage == message) setState(() => moodleMessage = null);
    });
  }

  Future<void> _newSection() async {
    final c = _current;
    if (c == null) return;
    final created = await showModalBottomSheet<CourseSection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _NewSectionSheet(
        service: _service,
        tenantId: widget.user.tenantId,
        groupId: c.group.id,
        initialTerm: term,
        sortOrder: sections.length,
        color: _Brand(data!.branding).primary,
      ),
    );
    if (created == null || !mounted) return;
    if (created.term == term || (term == 'other' && created.term == 'general')) {
      setState(() => sections = [...sections, created]);
    }
    _flash('تم إنشاء القسم بنجاح');
  }

  Future<void> _toggleVisibility(CourseSection sec) async {
    try {
      await _service.setSectionVisible(sec.id, !sec.isVisible);
      if (!mounted) return;
      setState(() => sections = [for (final s in sections) s.id == sec.id ? s.copyWith(isVisible: !s.isVisible) : s]);
    } catch (_) {
      if (mounted) showAppSnack(context, 'فشل تعديل حالة ظهور القسم', error: true);
    }
  }

  Future<void> _deleteSection(CourseSection sec) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف القسم',
      message: 'تأكيد حذف قسم "${sec.title}" وجميع مواده؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      await _service.deleteSection(sec, widget.user.tenantId);
      if (mounted) setState(() => sections = sections.where((s) => s.id != sec.id).toList());
    } catch (_) {
      if (mounted) showAppSnack(context, 'فشل حذف القسم', error: true);
    }
  }

  Future<void> _newItem(CourseSection sec) async {
    final created = await showModalBottomSheet<CourseItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _NewItemSheet(
        service: _service,
        tenantId: widget.user.tenantId,
        section: sec,
        color: _Brand(data!.branding).primary,
      ),
    );
    if (created == null || !mounted) return;
    setState(() => sections = [
          for (final s in sections) s.id == sec.id ? s.copyWith(items: [...s.items, created]) : s,
        ]);
    _flash('تمت إضافة المادة بنجاح');
  }

  Future<void> _deleteItem(CourseSection sec, CourseItem item) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف المادة',
      message: 'تأكيد حذف "${item.title}"؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      await _service.deleteItem(item, widget.user.tenantId);
      if (!mounted) return;
      setState(() => sections = [
            for (final s in sections)
              s.id == sec.id ? s.copyWith(items: s.items.where((i) => i.id != item.id).toList()) : s,
          ]);
    } catch (_) {
      if (mounted) showAppSnack(context, 'فشل حذف العنصر', error: true);
    }
  }

  Future<void> _copySection(CourseSection sec) async {
    final others = data!.classes.where((c) => c.group.id != groupId).toList();
    if (others.isEmpty) {
      showAppSnack(context, 'لا توجد شعب أخرى مسندة لك', error: true);
      return;
    }
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _CopySectionSheet(
        service: _service,
        tenantId: widget.user.tenantId,
        section: sec,
        targets: others,
        color: _Brand(data!.branding).primary,
      ),
    );
    if (count != null && mounted) _flash('تم نسخ القسم بنجاح إلى $count شعبة');
  }

  // ── البناء ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final branding = data?.branding ?? const PortalBranding();
    final brand = _Brand(branding);
    final c = _current;

    Widget? bottom;
    if (!loading && error == null && c != null && c.students.isNotEmpty) {
      if (tab == 'attendance') {
        bottom = _saveBar(context,
            label: 'حفظ كشف الحضور الآن', color: brand.action, busy: savingAttendance, onTap: _saveAttendance);
      } else if (tab == 'evaluations') {
        bottom = _saveBar(context,
            label: 'حفظ كشف الدرجات', color: brand.action, busy: savingEvaluations, onTap: _saveEvaluations);
      }
    }

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _PortalHeader(branding: branding, role: 'المعلم', userName: widget.user.name, onExit: widget.onExit),
          _PortalTabs(
            tabs: const [
              _TabSpec('attendance', 'رصد الحضور', Icons.how_to_reg_outlined),
              _TabSpec('evaluations', 'رصد الدرجات', Icons.workspace_premium_outlined),
              _TabSpec('moodle', 'المودل', Icons.menu_book_outlined),
            ],
            active: tab,
            color: brand.active,
            onSelect: _selectTab,
          ),
          Expanded(
            child: loading
                ? _loadingView()
                : error != null
                    ? _errorView(error!, _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: brand.active,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: switch (tab) {
                            'evaluations' => _evaluationsTab(brand),
                            'moodle' => _moodleTab(brand),
                            _ => _attendanceTab(brand),
                          },
                        ),
                      ),
          ),
          ?bottom,
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _groupItems({required bool detailed}) {
    final classes = data?.classes ?? const <TeacherClass>[];
    if (classes.isEmpty) {
      return const [DropdownMenuItem(value: '', child: Text('لا توجد مجموعات مسندة لك'))];
    }
    return [
      for (final k in classes)
        DropdownMenuItem(
          value: k.group.id,
          child: Text(
            detailed
                ? [
                    k.group.name,
                    if (k.subjectName.isNotEmpty) '(${k.subjectName})',
                    if (k.roomName.isNotEmpty) '- ${k.roomName}',
                  ].join(' ')
                : k.group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }

  // ── تبويب رصد الحضور ─────────────────────────────────────────────────────

  List<Widget> _attendanceTab(_Brand brand) {
    final c = _current;
    final students = c?.students ?? const <Student>[];
    var present = 0, absent = 0, excused = 0;
    for (final s in students) {
      switch (_statusOf(s.id)) {
        case 'absent':
          absent++;
        case 'excused':
          excused++;
        default:
          present++;
      }
    }

    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Label('الصف / المجموعة:'),
            _Select<String>(
              value: groupId,
              items: _groupItems(detailed: true),
              onChanged: (data?.classes.isEmpty ?? true) ? null : _selectGroup,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('تاريخ الحصة:'),
                      _DateBox(
                        date: sessionDate,
                        onPicked: (d) {
                          setState(() => sessionDate = d);
                          _loadMarks();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Soft(
                    label: 'الكل حاضر',
                    icon: Icons.check_circle_outline,
                    fg: _C.greenText,
                    bg: _C.greenSoft,
                    border: _C.greenBorder,
                    onTap: students.isEmpty
                        ? null
                        : () => setState(() => marks = {for (final s in students) s.id: 'present'}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (attendanceSaved) ...[
        const SizedBox(height: 12),
        const _Success('تم حفظ كشف الحضور وتحديث بوابة الطالب بنجاح'),
      ],
      const SizedBox(height: 16),
      if (students.isNotEmpty) ...[
        Row(
          children: [
            Expanded(child: _Stat.plain('الطلاب', '${students.length}')),
            const SizedBox(width: 8),
            Expanded(child: _Stat.green('حضور', '$present')),
            const SizedBox(width: 8),
            Expanded(child: _Stat.red('غياب', '$absent')),
            const SizedBox(width: 8),
            Expanded(child: _Stat.amber('مأذون', '$excused')),
          ],
        ),
        const SizedBox(height: 8),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'كشف الطلاب (${students.length}):',
                style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            Text.rich(
              TextSpan(
                text: 'الصف: ',
                children: [
                  TextSpan(
                    text: (c?.roomName ?? '').isEmpty ? '—' : c!.roomName,
                    style: const TextStyle(color: _C.text, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      if (students.isEmpty)
        const _Empty('لا يوجد طلاب مسجلين في هذه المجموعة', height: 150)
      else
        for (var i = 0; i < students.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AttendanceRow(
              index: i + 1,
              student: students[i],
              status: _statusOf(students[i].id),
              onSet: (status) => setState(() => marks = {...marks, students[i].id: status}),
            ),
          ),
    ];
  }

  // ── تبويب رصد الدرجات ────────────────────────────────────────────────────

  List<Widget> _evaluationsTab(_Brand brand) {
    final c = _current;
    final students = c?.students ?? const <Student>[];
    final names = {for (final s in students) s.id: s.fullName};

    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)],
        );

    Widget field(String label, Widget input) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [_Label(label), input],
        );

    return [
      _Card(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined, size: 16, color: brand.active),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'رصد درجات اختبار أو تقييم',
                    style: TextStyle(color: brand.primary, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                if (evaluationsSaved)
                  const _Badge('تم حفظ الدرجات', fg: _C.emerald600, bg: _C.emerald50, icon: Icons.check_circle_outline),
              ],
            ),
            const SizedBox(height: 12),
            field(
              'الصف / المجموعة:',
              _Select<String>(
                value: groupId,
                height: 36,
                items: _groupItems(detailed: false),
                onChanged: (data?.classes.isEmpty ?? true) ? null : _selectGroup,
              ),
            ),
            const SizedBox(height: 12),
            pair(
              field(
                'عنوان الاختبار / التقييم:',
                _Input(
                  controller: evalTitle,
                  hint: 'مثلاً: اختبار الشهر الأول',
                  errorText: titleError,
                  onChanged: (_) {
                    if (titleError != null) setState(() => titleError = null);
                  },
                ),
              ),
              field(
                'نوع التقييم:',
                _Select<String>(
                  value: evalType,
                  items: [
                    for (final e in evaluationTypeNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => evalType = v ?? evalType),
                ),
              ),
            ),
            const SizedBox(height: 12),
            pair(
              field(
                'الدرجة القصوى:',
                _Input(controller: evalMax, keyboardType: TextInputType.number, ltr: true),
              ),
              field('تاريخ التقييم:', _DateBox(date: evalDate, onPicked: (d) => setState(() => evalDate = d))),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              'قائمة الطلاب (${students.length})',
              style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w900),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (students.isNotEmpty)
                  InkWell(
                    onTap: _fullScoreForAll,
                    child: const Text(
                      'رصد الدرجة الكاملة للجميع',
                      style: TextStyle(color: _C.blue600, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                const Text('اترك الدرجة فارغة لمن لم يختبر', style: TextStyle(color: _C.muted, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (students.isEmpty)
        const _Empty('لا يوجد طلاب مسجلون في هذه الشعبة', height: 110)
      else
        for (final s in students)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Card(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: _Input(
                      controller: _ctl(_scores, s.id),
                      hint: 'من ${trimNum(_maxScore)}',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ltr: true,
                      center: true,
                      dense: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 88,
                    child: _Input(controller: _ctl(_notes, s.id), hint: 'ملاحظة', dense: true),
                  ),
                ],
              ),
            ),
          ),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Card(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'سجل التقييمات السابقة لهذه الشعبة (${recent.length})',
                style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const Padding(padding: EdgeInsets.only(top: 8, bottom: 10), child: Divider(height: 1, color: _C.soft)),
              for (final e in recent)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _C.bg,
                    borderRadius: BorderRadius.circular(Corner.box),
                    border: Border.all(color: _C.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              names[e.studentId] ?? 'طالب',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              [e.title, e.typeLabel, if (e.evaluationDate.isNotEmpty) e.evaluationDate].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _C.muted, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Badge(
                        '${e.score == null ? '—' : trimNum(e.score!)} / ${trimNum(e.maxScore)}',
                        fg: _C.emerald700,
                        bg: _C.emerald50,
                        border: _C.emerald200,
                        radius: Corner.chip,
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 17, color: _C.rose600),
                        onPressed: () => _deleteEvaluation(e),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  // ── تبويب المودل ─────────────────────────────────────────────────────────

  List<Widget> _moodleTab(_Brand brand) {
    final classes = data?.classes ?? const <TeacherClass>[];
    final hasGroup = _current != null;

    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('الشعبة الحالية:', style: TextStyle(color: _C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            _Select<String>(
              value: groupId,
              height: 36,
              items: classes.isEmpty
                  ? const [DropdownMenuItem(value: '', child: Text('لا توجد مجموعات مسندة لك'))]
                  : [
                      for (final k in classes)
                        DropdownMenuItem(
                          value: k.group.id,
                          child: Text(
                            '${cleanGroupName(k.group.name, k.group.gradeLevel)} — '
                            '${k.group.gradeLevel.trim().isEmpty ? 'عام' : k.group.gradeLevel.trim()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
              onChanged: classes.isEmpty ? null : _selectGroup,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _Solid(
                label: 'إضافة وحدة / قسم',
                icon: Icons.add,
                color: brand.primary,
                height: 34,
                radius: Corner.field,
                onTap: hasGroup ? _newSection : null,
              ),
            ),
            const SizedBox(height: 10),
            _TermSwitch(
              value: term,
              onChanged: (t) {
                setState(() => term = t);
                _loadMoodle();
              },
            ),
          ],
        ),
      ),
      if (moodleMessage != null) ...[const SizedBox(height: 12), _Success(moodleMessage!)],
      const SizedBox(height: 16),
      if (loadingMoodle)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _C.navy)),
              SizedBox(height: 8),
              Text('جارٍ تحميل الوحدات الدراسية...', style: TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        )
      else if (sections.isEmpty)
        _Empty(
          'لا توجد وحدات أو أقسام مضافة لهذه الشعبة في هذا الفصل',
          icon: Icons.layers_outlined,
          dashed: true,
          height: 200,
          action: hasGroup ? 'انقر هنا لإضافة أول وحدة' : null,
          onAction: hasGroup ? _newSection : null,
        )
      else
        for (final sec in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TeacherSectionCard(
              section: sec,
              onAddItem: () => _newItem(sec),
              onCopy: () => _copySection(sec),
              onToggle: () => _toggleVisibility(sec),
              onDelete: () => _deleteSection(sec),
              onOpenItem: (it) => _openUrl(context, it.contentUrl),
              onDeleteItem: (it) => _deleteItem(sec, it),
            ),
          ),
    ];
  }
}

/// صف طالب في كشف الحضور: الرقم والاسم والهوية، وثلاثة أزرار رصد.
class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.index, required this.student, required this.status, required this.onSet});

  final int index;
  final Student student;
  final String status;
  final ValueChanged<String> onSet;

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: _C.soft, shape: BoxShape.circle),
              child: Text(
                '$index',
                style: const TextStyle(color: _C.slate600, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: _mono),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                student.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (student.nationalId.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 32, top: 2),
            child: Text(
              'هوية: ${student.nationalId.trim()}',
              style: const TextStyle(color: _C.faint, fontSize: 10, fontFamily: _mono),
            ),
          ),
      ],
    );

    final buttons = [
      _markButton('حاضر', Icons.check_circle_outline, 'present', _C.green, _C.greenDark, _C.greenSoft, _C.greenBorder),
      _markButton('غائب', Icons.cancel_outlined, 'absent', _C.red, _C.redDark, _C.redSoft, _C.redBorder),
      _markButton('مأذون', null, 'excused', _C.amber600, _C.orangeDark, _C.amber50, _C.amber200),
    ];

    return _Card(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, box) {
          // ثلاثة أزرار بأيقوناتها بجوار الاسم تحتاج نحو 380 بكسل؛ دونها تنزل
          // تحته بعرض كامل فلا يُسحق الاسم ولا تصغر أهداف اللمس
          if (box.maxWidth < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                info,
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: buttons[i]),
                    ],
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 8),
              for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 6), buttons[i]],
            ],
          );
        },
      ),
    );
  }

  Widget _markButton(String label, IconData? icon, String value, Color on, Color onBorder, Color off, Color offBorder) {
    final selected = status == value;
    return GestureDetector(
      onTap: () => onSet(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? on : off,
          borderRadius: BorderRadius.circular(Corner.field),
          border: Border.all(color: selected ? onBorder : offBorder),
          boxShadow: selected ? [BoxShadow(color: on.withValues(alpha: 0.22), blurRadius: 0, spreadRadius: 2)] : null,
        ),
        // ثلث عرض 320 بكسل لا يسع الأيقونة والكلمة بحجمهما: يُصغَّر المحتوى ولا يطفح
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: selected ? Colors.white : on), const SizedBox(width: 4)],
              Text(label, style: TextStyle(color: selected ? Colors.white : on, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// وحدة في مودل المعلم: ترويستها بإجراءاتها، ثم موادها.
class _TeacherSectionCard extends StatelessWidget {
  const _TeacherSectionCard({
    required this.section,
    required this.onAddItem,
    required this.onCopy,
    required this.onToggle,
    required this.onDelete,
    required this.onOpenItem,
    required this.onDeleteItem,
  });

  final CourseSection section;
  final VoidCallback onAddItem;
  final VoidCallback onCopy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<CourseItem> onOpenItem;
  final ValueChanged<CourseItem> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    final sec = section;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: sec.isVisible ? Colors.white : const Color(0x33FFFBEB),
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: sec.isVisible ? _C.line : _C.amber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
            decoration: const BoxDecoration(
              color: _C.bg,
              border: Border(bottom: BorderSide(color: _C.line)),
            ),
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, size: 16, color: _C.navy),
                const SizedBox(width: 6),
                // أربعة إجراءات في الطرف لا تتسع مع عنوان وشارتين في سطر واحد عند
                // 320 بكسل: العنوان وشاراته ينكسران تحت بعضها والإجراءات ثابتة
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        sec.title,
                        style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                      _Badge(sec.termLabel, fg: _C.muted, bg: _C.line, radius: Corner.chip),
                      if (!sec.isVisible) const _Badge('مخفي', fg: _C.amber700, bg: _C.amber100, radius: Corner.chip),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onAddItem,
                  borderRadius: BorderRadius.circular(Corner.field),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: const Color(0x0D0B2545), borderRadius: BorderRadius.circular(Corner.field)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 13, color: _C.navy),
                        SizedBox(width: 3),
                        Text('مادة', style: TextStyle(color: _C.navy, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
                _iconAction(Icons.copy_outlined, 'نسخ القسم لشعب أخرى', _C.muted, onCopy),
                _iconAction(
                  sec.isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  sec.isVisible ? 'إخفاء القسم عن الطلاب' : 'إظهار القسم للطلاب',
                  sec.isVisible ? _C.muted : _C.amber600,
                  onToggle,
                ),
                _iconAction(Icons.delete_outline, 'حذف القسم', _C.rose600, onDelete),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: sec.items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'لا توجد مواد أو واجبات مضافة في هذه الوحدة',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _C.faint, fontSize: 11),
                    ),
                  )
                : Column(
                    children: [
                      for (final it in sec.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ItemTile(
                            item: it,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (it.contentUrl.isNotEmpty)
                                  _Soft(
                                    label: 'فتح',
                                    icon: it.type == 'file' ? Icons.description_outlined : Icons.open_in_new,
                                    fg: _C.navy,
                                    height: 28,
                                    radius: Corner.field,
                                    onTap: () => onOpenItem(it),
                                  ),
                                _iconAction(Icons.delete_outline, 'حذف المادة', _C.rose600, () => onDeleteItem(it)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, Color color, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 16, color: color),
        onPressed: onTap,
      );
}

/// مادة تعليمية: نوعها وعنوانها ووصفها وموعد تسليمها، مقابل إجراءاتها.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.trailing, this.showNew = false});

  final CourseItem item;
  final Widget trailing;
  final bool showNew;

  @override
  Widget build(BuildContext context) {
    final colors = _itemTypeColors(item.type);
    final overdue = item.isOverdue();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: _C.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Badge(item.typeLabel, fg: colors.fg, bg: colors.bg, radius: Corner.chip),
                    if (showNew && item.isNew()) const _Badge('جديد', fg: _C.amber800, bg: _C.amber100, radius: Corner.chip),
                    Text(
                      item.title,
                      style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    item.description.trim(),
                    maxLines: showNew ? null : 2,
                    overflow: showNew ? null : TextOverflow.ellipsis,
                    style: const TextStyle(color: _C.slate600, fontSize: 11, height: 1.6),
                  ),
                ],
                if (item.type == 'assignment' && item.dueDate.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: _C.faint),
                      const SizedBox(width: 4),
                      // بجوار زر «فتح» يضيق العمود: الموعد ينكسر سطراً ولا يطفح
                      Flexible(
                        child: Text(
                          'تاريخ التسليم: ${item.dueDate}${overdue ? ' (منتهٍ)' : ''}',
                          style: TextStyle(
                            color: overdue ? _C.faint : _C.emerald700,
                            fontSize: 10.5,
                            fontWeight: overdue ? FontWeight.w500 : FontWeight.w800,
                            fontFamily: _mono,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

// ── نوافذ المودل ───────────────────────────────────────────────────────────

Widget _sheetFrame(BuildContext context, {required String title, required List<Widget> children}) {
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(color: _C.navy, fontSize: 13, fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18, color: _C.faint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 1, color: _C.line),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _sheetActions(BuildContext context, {required String label, required Color color, required bool busy, required VoidCallback? onSave}) {
  return Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      children: [
        Expanded(child: _Soft(label: 'إلغاء', onTap: () => Navigator.pop(context), height: 40, radius: Corner.field)),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _Solid(label: busy ? 'جارٍ الحفظ...' : label, color: color, busy: busy, onTap: onSave, height: 40, radius: Corner.field),
        ),
      ],
    ),
  );
}

class _NewSectionSheet extends StatefulWidget {
  const _NewSectionSheet({
    required this.service,
    required this.tenantId,
    required this.groupId,
    required this.initialTerm,
    required this.sortOrder,
    required this.color,
  });

  final PortalService service;
  final String tenantId;
  final String groupId;
  final String initialTerm;
  final int sortOrder;
  final Color color;

  @override
  State<_NewSectionSheet> createState() => _NewSectionSheetState();
}

class _NewSectionSheetState extends State<_NewSectionSheet> {
  final title = TextEditingController();
  late String term = widget.initialTerm == 'general' ? 'other' : widget.initialTerm;
  String? titleError;
  bool busy = false;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      setState(() => titleError = 'يرجى إدخال عنوان الوحدة');
      return;
    }
    setState(() => busy = true);
    try {
      final section = await widget.service.createSection(
        tenantId: widget.tenantId,
        groupId: widget.groupId,
        term: term,
        title: title.text,
        sortOrder: widget.sortOrder,
      );
      if (mounted) Navigator.pop(context, section);
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      showAppSnack(context, 'فشل إنشاء القسم', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(
      context,
      title: 'إضافة قسم أو وحدة دراسية',
      children: [
        const _Label('عنوان الوحدة / القسم:'),
        _Input(
          controller: title,
          hint: 'مثال: الوحدة الأولى - الجبر والمصفوفات',
          errorText: titleError,
          onChanged: (_) {
            if (titleError != null) setState(() => titleError = null);
          },
        ),
        const SizedBox(height: 12),
        const _Label('الفصل الدراسي:'),
        _Select<String>(
          value: term,
          items: const [
            DropdownMenuItem(value: 'term_1', child: Text('الفصل الأول')),
            DropdownMenuItem(value: 'term_2', child: Text('الفصل الثاني')),
            DropdownMenuItem(value: 'other', child: Text('أخرى')),
          ],
          onChanged: (v) => setState(() => term = v ?? term),
        ),
        _sheetActions(context, label: 'حفظ القسم', color: widget.color, busy: busy, onSave: _save),
      ],
    );
  }
}

class _NewItemSheet extends StatefulWidget {
  const _NewItemSheet({required this.service, required this.tenantId, required this.section, required this.color});

  final PortalService service;
  final String tenantId;
  final CourseSection section;
  final Color color;

  @override
  State<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends State<_NewItemSheet> {
  final title = TextEditingController();
  final url = TextEditingController();
  final description = TextEditingController();
  String type = 'file';
  String dueDate = '';
  XFile? file;
  int fileSize = 0;
  List<int>? fileBytes;
  String? titleError;
  String? error;
  bool busy = false;

  @override
  void dispose() {
    title.dispose();
    url.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF أو صورة',
          extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'],
          uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png', 'org.webmproject.webp'],
        ),
      ],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (bytes.length > PortalService.maxMaterialBytes) {
        error = 'حجم الملف يتجاوز 10 ميجابايت';
        file = null;
        fileBytes = null;
      } else if (PortalService.materialMime(picked.name) == null) {
        error = 'نوع الملف غير مدعوم؛ يُسمح بملفات PDF والصور فقط';
        file = null;
        fileBytes = null;
      } else {
        error = null;
        file = picked;
        fileBytes = bytes;
        fileSize = bytes.length;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      titleError = title.text.trim().isEmpty ? 'يرجى إدخال العنوان' : null;
      error = null;
    });
    if (titleError != null) return;
    if (type == 'file' && fileBytes == null) {
      setState(() => error = 'يرجى اختيار ملف (PDF أو صورة)');
      return;
    }
    final link = url.text.trim();
    if (type == 'link') {
      final uri = Uri.tryParse(link);
      if (link.isEmpty || uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        setState(() => error = 'يرجى إدخال رابط صحيح يبدأ بـ https://');
        return;
      }
    }

    setState(() => busy = true);
    try {
      var contentUrl = type == 'link' ? link : '';
      var fileName = '';
      int? size;
      if (type == 'file') {
        contentUrl = await widget.service.uploadMaterial(
          bytes: fileBytes!,
          fileName: file!.name,
          tenantId: widget.tenantId,
        );
        fileName = file!.name;
        size = fileSize;
      }
      final item = await widget.service.createItem(CourseItem(
        id: '',
        tenantId: widget.tenantId,
        sectionId: widget.section.id,
        groupId: widget.section.groupId,
        title: title.text,
        type: type,
        contentUrl: contentUrl,
        fileName: fileName,
        fileSize: size,
        description: description.text,
        dueDate: dueDate,
        sortOrder: widget.section.items.length,
      ));
      if (mounted) Navigator.pop(context, item);
    } on PortalException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'فشل إضافة العنصر';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(
      context,
      title: 'إضافة مادة تعليمية / واجب',
      children: [
        const _Label('نوع العنصر:'),
        _Select<String>(
          value: type,
          items: const [
            DropdownMenuItem(value: 'file', child: Text('ورقة عمل / ملخص (PDF أو صورة)')),
            DropdownMenuItem(value: 'link', child: Text('رابط فيديو / شرح (YouTube / Drive)')),
            DropdownMenuItem(value: 'assignment', child: Text('واجب منزلي')),
            DropdownMenuItem(value: 'note', child: Text('ملاحظة / توجيه تعليمي')),
          ],
          onChanged: (v) => setState(() {
            type = v ?? type;
            error = null;
          }),
        ),
        const SizedBox(height: 12),
        const _Label('العنوان:'),
        _Input(
          controller: title,
          hint: 'عنوان الدرس أو ورقة العمل أو الواجب...',
          errorText: titleError,
          onChanged: (_) {
            if (titleError != null) setState(() => titleError = null);
          },
        ),
        if (type == 'file') ...[
          const SizedBox(height: 12),
          const _Label('الملف المرفق (PDF أو صورة - أقصى حد 10MB):'),
          Row(
            children: [
              _Soft(label: 'اختيار ملف', icon: Icons.attach_file, fg: _C.navy, bg: _C.soft, border: _C.soft, height: 36, radius: Corner.field, onTap: _pick),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file?.name ?? 'لم يُختر ملف',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _C.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        if (type == 'link') ...[
          const SizedBox(height: 12),
          const _Label('رابط الشرح أو المادة:'),
          _Input(controller: url, hint: 'https://...', keyboardType: TextInputType.url, ltr: true),
          const SizedBox(height: 4),
          const Text(
            'تنبيه: إذا كان الرابط من Google Drive تأكد من ضبطه على "متاح لأي شخص لديه الرابط".',
            style: TextStyle(color: _C.muted, fontSize: 10.5, height: 1.5),
          ),
        ],
        if (type == 'assignment') ...[
          const SizedBox(height: 12),
          const _Label('تاريخ التسليم في الحصة:'),
          _DateBox(
            date: dueDate.isEmpty ? isoDate(DateTime.now()) : dueDate,
            onPicked: (d) => setState(() => dueDate = d),
          ),
        ],
        const SizedBox(height: 12),
        const _Label('وصف أو تعليمات إضافية (اختياري):'),
        _Input(controller: description, hint: 'اكتب أرقام الصفحات أو ملاحظات الدراسة...', maxLines: 2),
        if (error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _C.rose50,
              borderRadius: BorderRadius.circular(Corner.box),
              border: Border.all(color: _C.rose200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 15, color: _C.rose700),
                const SizedBox(width: 6),
                Expanded(child: Text(error!, style: const TextStyle(color: _C.rose700, fontSize: 12, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
        ],
        _sheetActions(context, label: 'حفظ المادة', color: widget.color, busy: busy, onSave: _save),
      ],
    );
  }
}

class _CopySectionSheet extends StatefulWidget {
  const _CopySectionSheet({
    required this.service,
    required this.tenantId,
    required this.section,
    required this.targets,
    required this.color,
  });

  final PortalService service;
  final String tenantId;
  final CourseSection section;
  final List<TeacherClass> targets;
  final Color color;

  @override
  State<_CopySectionSheet> createState() => _CopySectionSheetState();
}

class _CopySectionSheetState extends State<_CopySectionSheet> {
  final selected = <String>{};
  bool busy = false;

  Future<void> _copy() async {
    setState(() => busy = true);
    try {
      final count = await widget.service.copySectionToGroups(widget.section, selected.toList(), widget.tenantId);
      if (mounted) Navigator.pop(context, count);
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      showAppSnack(context, 'فشل نسخ القسم', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(
      context,
      title: 'نسخ القسم لشعب أخرى',
      children: [
        Text.rich(
          TextSpan(
            text: 'سيتم نسخ وحدة ',
            children: [
              TextSpan(
                text: '"${widget.section.title}"',
                style: const TextStyle(color: _C.text, fontWeight: FontWeight.w800),
              ),
              const TextSpan(text: ' وجميع موادها للشعب المختارة:'),
            ],
          ),
          style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.circular(Corner.box),
            border: Border.all(color: _C.line),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(6),
            children: [
              for (final t in widget.targets)
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: _C.navy,
                  value: selected.contains(t.group.id),
                  onChanged: (v) => setState(() => v == true ? selected.add(t.group.id) : selected.remove(t.group.id)),
                  title: Text(
                    '${t.group.name} (${t.group.gradeLevel.trim().isEmpty ? 'عام' : t.group.gradeLevel.trim()})',
                    style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
        _sheetActions(
          context,
          label: busy ? 'جارٍ النسخ...' : 'نسخ إلى (${selected.length}) شعب',
          color: widget.color,
          busy: busy,
          onSave: selected.isEmpty ? null : _copy,
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// بوابة الطالب
// ══════════════════════════════════════════════════════════════════════════

class StudentPortalScreen extends StatefulWidget {
  const StudentPortalScreen({
    super.key,
    required this.user,
    required this.onExit,
    this.service = const PortalService(),
  });

  final PortalUser user;
  final VoidCallback onExit;

  /// قابلة للاستبدال في الاختبارات كي لا تمسّ السحابة.
  final PortalService service;

  @override
  State<StudentPortalScreen> createState() => _StudentPortalScreenState();
}

class _StudentPortalScreenState extends State<StudentPortalScreen> {
  StudentPortalData? data;
  String? error;
  bool loading = true;

  /// ولي الأمر يتابع ملف ابنه: الجدول والحضور والدرجات والرسوم، بلا المودل —
  /// المحتوى الدراسي ليس من شأنه، ولا تمنحه القاعدة إياه أصلاً.
  bool get isParent => widget.user.isParent;

  late String tab = isParent ? 'attendance' : 'moodle';

  // المودل
  String? moodleGroupId;
  String term = 'term_1';
  List<CourseSection> sections = const [];
  bool loadingMoodle = false;
  final closed = <String>{};
  int _moodleToken = 0;

  PortalService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await _service.studentData(widget.user);
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
        if (result == null) {
          error = 'تعذّر جلب بيانات الطالب.';
        } else if (moodleGroupId == null && result.subjects.isNotEmpty) {
          moodleGroupId = result.subjects.first.groupId;
        }
      });
      if (tab == 'moodle' && !isParent) _loadMoodle();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذّر الاتصال بالسحابة.';
      });
    }
  }

  Future<void> _loadMoodle() async {
    final gid = moodleGroupId;
    if (gid == null || gid.isEmpty) return;
    final token = ++_moodleToken;
    setState(() => loadingMoodle = true);
    try {
      final list = await _service.groupSections(
        tenantId: widget.user.tenantId,
        groupId: gid,
        term: term,
        // الطالب يرى المنشور وحده
        includeHidden: false,
      );
      if (!mounted || token != _moodleToken) return;
      setState(() {
        sections = list;
        closed.clear();
        loadingMoodle = false;
      });
    } catch (_) {
      if (mounted && token == _moodleToken) setState(() => loadingMoodle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = data?.branding ?? const PortalBranding();
    final brand = _Brand(branding);

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _PortalHeader(
            branding: branding,
            role: isParent ? 'ولي الأمر' : 'الطالب',
            userName: widget.user.name,
            onExit: widget.onExit,
          ),
          _ProfileBand(user: widget.user, student: data?.student, color: brand.side),
          _PortalTabs(
            compact: true,
            tabs: [
              if (!isParent) const _TabSpec('moodle', 'المودل', Icons.menu_book_outlined),
              // المدرسة لا جداول أوقات فيها: المادة ومعلمها هما المحتوى
              const _TabSpec('subjects', 'المواد والمعلمون', Icons.menu_book_outlined),
              const _TabSpec('attendance', 'الحضور', Icons.event_available_outlined),
              const _TabSpec('evaluations', 'الدرجات', Icons.workspace_premium_outlined),
              const _TabSpec('financial', 'الرسوم', Icons.credit_card_outlined),
            ],
            active: tab,
            color: brand.active,
            onSelect: (id) {
              setState(() => tab = id);
              if (id == 'moodle' && !isParent && sections.isEmpty) _loadMoodle();
            },
          ),
          Expanded(
            child: loading
                ? _loadingView()
                : error != null
                    ? _errorView(error!, _load)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _load();
                        },
                        color: brand.active,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: switch (tab) {
                            'subjects' => _subjectsTab(brand),
                            'attendance' => _attendanceTab(),
                            'evaluations' => _evaluationsTab(brand),
                            'financial' => _financialTab(brand),
                            _ => _moodleTab(),
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── المودل ────────────────────────────────────────────────────────────────

  List<Widget> _moodleTab() {
    final subjects = data!.subjects;
    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('المادة الدراسية:', style: TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                Text(
                  '${subjects.length} مواد مسجلة',
                  style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w800, fontFamily: _mono),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (subjects.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'لا توجد مواد مسجلة حالياً',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in subjects)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => moodleGroupId = s.groupId);
                            _loadMoodle();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: moodleGroupId == s.groupId ? _C.navy : _C.soft,
                              borderRadius: BorderRadius.circular(Corner.chip),
                            ),
                            child: Text(
                              s.subjectName,
                              style: TextStyle(
                                color: moodleGroupId == s.groupId ? Colors.white : _C.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            _TermSwitch(
              value: term,
              onChanged: (t) {
                setState(() => term = t);
                _loadMoodle();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (loadingMoodle)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _C.navy)),
              SizedBox(height: 8),
              Text('جارٍ تحميل المحتوى الدراسي...', style: TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        )
      else if (sections.isEmpty)
        const _Empty(
          'لا توجد وحدات أو دروس منشورة لهذه المادة في هذا الفصل',
          icon: Icons.layers_outlined,
          dashed: true,
          height: 200,
        )
      else
        for (final sec in sections) Padding(padding: const EdgeInsets.only(bottom: 12), child: _studentSection(sec)),
    ];
  }

  Widget _studentSection(CourseSection sec) {
    final open = !closed.contains(sec.id);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: _C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open ? closed.add(sec.id) : closed.remove(sec.id)),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.bg,
                border: open ? const Border(bottom: BorderSide(color: _C.line)) : null,
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined, size: 16, color: _C.navy),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          sec.title,
                          style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                        _Badge(sec.termLabel, fg: _C.muted, bg: _C.line, radius: Corner.chip),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${sec.items.length} عنصر',
                    style: const TextStyle(color: _C.muted, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: _mono),
                  ),
                  const SizedBox(width: 4),
                  Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: _C.muted),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.all(12),
              child: sec.items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'لا توجد مواد أو واجبات مضافة في هذه الوحدة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _C.faint, fontSize: 11),
                      ),
                    )
                  : Column(
                      children: [
                        for (final it in sec.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ItemTile(
                              item: it,
                              showNew: true,
                              trailing: it.contentUrl.isEmpty
                                  ? const SizedBox.shrink()
                                  : _Soft(
                                      label: it.type == 'file' ? 'عرض الملف' : 'فتح الرابط',
                                      icon: it.type == 'file' ? Icons.description_outlined : Icons.open_in_new,
                                      fg: _C.navy,
                                      height: 32,
                                      radius: Corner.field,
                                      onTap: () => _openUrl(context, it.contentUrl),
                                    ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  // ── الجدول ────────────────────────────────────────────────────────────────

  List<Widget> _subjectsTab(_Brand brand) {
    final subjects = data!.subjects;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'المواد والمعلمون (${subjects.length}):',
          style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 10),
      if (subjects.isEmpty)
        const _Empty('لا توجد مواد مسجلة حالياً', height: 130)
      else
        for (final s in subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Card(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.subjectName, style: TextStyle(color: brand.primary, fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 13, color: brand.active),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  text: 'المعلم: ',
                                  children: [
                                    TextSpan(
                                      text: s.teacherName,
                                      style: const TextStyle(color: _C.slate700, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _C.muted, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        if (s.roomName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text('القاعة: ${s.roomName}', style: const TextStyle(color: _C.faint, fontSize: 10.5)),
                        ],
                      ],
                    ),
                  ),
                  if (s.days.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    // خمسة أيام بأسمائها أعرض من نصف الهاتف: الشارة تنكسر سطرين
                    // داخل نصف البطاقة بدل أن تدفع اسم المادة خارجها
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _Badge(daysNames(s.days), fg: _C.amber600, bg: _C.amber100, radius: Corner.chip, maxLines: 2),
                          if (s.startTime.length >= 5 && s.endTime.length >= 5) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule, size: 11, color: _C.muted),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    '${s.startTime.substring(0, 5)} - ${s.endTime.substring(0, 5)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(color: _C.muted, fontSize: 10.5, fontFamily: _mono),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
    ];
  }

  // ── الحضور ────────────────────────────────────────────────────────────────

  List<Widget> _attendanceTab() {
    final a = data!.attendance;
    return [
      Row(
        children: [
          Expanded(child: _Stat.green('حضور', '${a.present}')),
          const SizedBox(width: 8),
          Expanded(child: _Stat.red('غياب', '${a.absent}')),
          const SizedBox(width: 8),
          Expanded(child: _Stat.amber('مأذون', '${a.excused}')),
        ],
      ),
      const SizedBox(height: 16),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('سجل الحضور:', style: TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      if (a.records.isEmpty)
        const _Empty('لا توجد سجلات حضور مسجلة بعد', height: 130)
      else
        for (final r in a.records)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: _C.line),
              ),
              // التاريخ وسببه في عمود، والحالة في الطرف: الملاحظة الطويلة كانت
              // تزاحم التاريخ في سطر واحد فيُقصّ أحدهما
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r.date,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(color: _C.slate700, fontSize: 12, fontWeight: FontWeight.w800, fontFamily: _mono),
                        ),
                        if (r.notes.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              r.notes.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _C.faint, fontSize: 10.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  switch (r.status) {
                    'present' => const _Badge('حاضر', fg: _C.emerald700, bg: _C.emerald50, border: _C.emerald200, icon: Icons.check_circle_outline),
                    'excused' => const _Badge('مأذون', fg: _C.amber700, bg: _C.amber50, border: _C.amber200),
                    _ => const _Badge('غائب', fg: _C.rose700, bg: _C.rose50, border: _C.rose200, icon: Icons.cancel_outlined),
                  },
                ],
              ),
            ),
          ),
    ];
  }

  // ── الدرجات ───────────────────────────────────────────────────────────────

  List<Widget> _evaluationsTab(_Brand brand) {
    final list = data!.evaluations;
    final pcts = [for (final e in list) e.maxScore > 0 && e.score != null ? e.score! / e.maxScore * 100 : 0.0];
    final average = pcts.isEmpty ? 0 : (pcts.reduce((a, b) => a + b) / pcts.length).round();
    final best = pcts.isEmpty ? 0 : pcts.reduce((a, b) => a > b ? a : b).round();

    Widget summary(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(label, style: const TextStyle(color: _C.muted, fontSize: 10.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900, fontFamily: _mono)),
            ],
          ),
        );

    return [
      if (list.isNotEmpty) ...[
        _Card(
          child: Row(
            children: [
              summary('الاختبارات', '${list.length}', _C.navy),
              summary('المعدل', '$average%', _C.emerald600),
              summary('أعلى علامة', '$best%', _C.amber600),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'كشف الدرجات والتقييمات (${list.length}):',
          style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 10),
      if (list.isEmpty)
        const _Empty('لم يتم رصد أي درجات أو تقييمات لك بعد', icon: Icons.workspace_premium_outlined, height: 160)
      else
        for (final e in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: _evaluationCard(e, brand)),
    ];
  }

  Widget _evaluationCard(StudentEvaluation e, _Brand brand) {
    final pct = e.percent ?? 0;
    final tone = pct >= 85
        ? (fg: _C.emerald700, bg: _C.emerald50, bar: const Color(0xFF10B981))
        : pct >= 50
            ? (fg: _C.amber700, bg: _C.amber50, bar: const Color(0xFFF59E0B))
            : (fg: _C.rose700, bg: _C.rose50, bar: const Color(0xFFF43F5E));

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(e.subjectName, style: TextStyle(color: brand.primary, fontSize: 12, fontWeight: FontWeight.w900)),
                        _Badge(e.typeLabel, fg: _C.slate700, bg: _C.soft, radius: Corner.chip),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.title.isEmpty ? 'تقييم دراسي' : e.title,
                      style: const TextStyle(color: _C.slate700, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text.rich(
                    TextSpan(
                      text: e.score == null ? '—' : trimNum(e.score!),
                      style: TextStyle(
                        color: e.passed ? _C.emerald600 : _C.rose600,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      children: [
                        TextSpan(
                          text: ' / ${trimNum(e.maxScore)}',
                          style: const TextStyle(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: _mono),
                  ),
                  const SizedBox(height: 2),
                  _Badge('$pct%', fg: tone.fg, bg: tone.bg, radius: Corner.chip),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: _C.soft,
              color: tone.bar,
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 8, bottom: 6), child: Divider(height: 1, color: _C.bg)),
          Row(
            children: [
              Expanded(
                child: Text(
                  'المعلم: ${e.teacherName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _C.muted, fontSize: 11),
                ),
              ),
              Text(e.evaluationDate, style: const TextStyle(color: _C.muted, fontSize: 11, fontFamily: _mono)),
            ],
          ),
          if (e.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _C.bg,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: _C.soft),
              ),
              child: Text.rich(
                TextSpan(
                  text: 'ملاحظة: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  children: [TextSpan(text: e.notes.trim(), style: const TextStyle(fontWeight: FontWeight.w500))],
                ),
                style: const TextStyle(color: _C.slate600, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── الرسوم ────────────────────────────────────────────────────────────────

  List<Widget> _financialTab(_Brand brand) {
    final f = data!.finance;
    final owes = f.currentDue > 0;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: owes
                ? _Stat.red('المستحق حالياً', money(f.currentDue), radius: Corner.card)
                : _Stat.green('حالة الحساب', 'مسدد بالكامل', radius: Corner.card),
          ),
          const SizedBox(width: 8),
          Expanded(child: _Stat.plain('إجمالي المسدد', money(f.totalPaid), valueColor: _C.emerald600, radius: Corner.card)),
          const SizedBox(width: 8),
          Expanded(child: _Stat.plain('إجمالي الرسوم', money(f.totalDue), valueColor: brand.primary, radius: Corner.card)),
        ],
      ),
      if (f.remainingBalance > f.currentDue) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.circular(Corner.box),
            border: Border.all(color: _C.line),
          ),
          child: Text.rich(
            TextSpan(
              text: 'المتبقي لكامل العام: ',
              children: [
                TextSpan(
                  text: money(f.remainingBalance),
                  style: const TextStyle(color: _C.navy, fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: ' (أقساط مجدولة قادمة)'),
              ],
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _C.muted, fontSize: 11),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'جدول الأقساط والمطالبات (${f.installments.length}):',
          style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 8),
      if (f.installments.isEmpty)
        const _Empty('لا توجد أقساط مسجلة حالياً', height: 90)
      else
        for (final i in f.installments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Card(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.title, style: TextStyle(color: brand.primary, fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 11, color: _C.muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'استحقاق: ${i.dueDate}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _C.muted, fontSize: 10.5, fontFamily: _mono),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money(i.amount),
                        style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w900, fontFamily: _mono),
                      ),
                      const SizedBox(height: 4),
                      _installmentBadge(i),
                    ],
                  ),
                ],
              ),
            ),
          ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'سجل الدفعات وسندات القبض (${f.payments.length}):',
          style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 8),
      if (f.payments.isEmpty)
        const _Empty('لا توجد سندات قبض مسجلة بعد', height: 90)
      else
        for (final p in f.payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Card(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'سند #${p.receiptNumber}',
                              style: TextStyle(color: brand.primary, fontSize: 12, fontWeight: FontWeight.w900, fontFamily: _mono),
                            ),
                            _Badge(data!.branding.methodLabel(p.method), fg: _C.muted, bg: _C.soft, radius: Corner.chip),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(isoDate(p.date), style: const TextStyle(color: _C.faint, fontSize: 10.5, fontFamily: _mono)),
                        if (p.purpose.isNotEmpty)
                          Text(
                            paymentPurposeNames[p.purpose] ?? p.purpose,
                            style: const TextStyle(color: _C.slate600, fontSize: 10.5),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Badge('+ ${money(p.amount)}', fg: _C.emerald600, bg: _C.emerald50, border: _C.emerald200, radius: Corner.chip),
                      const SizedBox(height: 6),
                      _Soft(
                        label: 'عرض الوصل',
                        icon: Icons.description_outlined,
                        fg: _C.navy,
                        bg: _C.bg,
                        border: _C.line,
                        height: 32,
                        onTap: () => _showReceipt(p),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  Widget _installmentBadge(PortalInstallment i) {
    if (i.status == 'unpaid') {
      return i.isDueNow
          ? const _Badge('مستحق الآن', fg: _C.rose700, bg: _C.rose50, border: _C.rose200)
          : const _Badge('قسط قادم', fg: _C.slate600, bg: _C.soft, border: _C.line);
    }
    if (i.status == 'partially_paid') {
      return i.isDueNow
          ? _Badge('مستحق جزئياً (باقي ${money(i.remaining)})', fg: _C.amber700, bg: _C.amber50, border: _C.amber200)
          : _Badge('قادم (باقي ${money(i.remaining)})', fg: _C.slate600, bg: _C.soft, border: _C.line);
    }
    return const _Badge('مسدد', fg: _C.emerald700, bg: _C.emerald50, border: _C.emerald200);
  }

  Future<void> _showReceipt(Payment p) {
    final d = data!;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => _PortalReceipt(payment: p, student: d.student, branding: d.branding),
    );
  }
}

/// شريط هوية الطالب بلون القائمة الجانبية: الاسم والمرحلة ورقم الهوية.
class _ProfileBand extends StatelessWidget {
  const _ProfileBand({required this.user, required this.student, required this.color});

  final PortalUser user;
  final Student? student;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final grade = user.gradeLevel.trim().isNotEmpty
        ? user.gradeLevel.trim()
        : (student?.gradeLevel.trim().isNotEmpty ?? false)
            ? student!.gradeLevel.trim()
            : 'طالب';
    final rawSection = user.section.trim().isNotEmpty ? user.section.trim() : (student?.section.trim() ?? '');
    // الشعبة المحفوظة قد تحمل كلمة «شعبة»: لا تتكرر «شعبة شعبة (1)»
    final section = rawSection.isEmpty ? '' : (rawSection.startsWith('شعبة') ? ' - $rawSection' : ' - شعبة $rawSection');
    final nationalId = user.nationalId.trim();

    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.person_outline, size: 15, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.isParent
                      ? (user.studentName.isNotEmpty ? user.studentName : (student?.fullName ?? user.name))
                      : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                ),
                Text(
                  '$grade$section',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (nationalId.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Corner.chip),
              ),
              child: Text(
                nationalId,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontFamily: _mono),
              ),
            ),
        ],
      ),
    );
  }
}

/// سند القبض كما يراه الطالب — المقابل لـ `ReceiptModal`.
class _PortalReceipt extends StatelessWidget {
  const _PortalReceipt({required this.payment, required this.student, required this.branding});

  final Payment payment;
  final Student student;
  final PortalBranding branding;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final brand = _Brand(branding);

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 100, child: Text(k, style: const TextStyle(color: _C.muted, fontSize: 11.5))),
              Expanded(child: Text(v, style: const TextStyle(color: _C.text, fontSize: 12.5, fontWeight: FontWeight.w800))),
            ],
          ),
        );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                InstitutionBadge(logo: branding.logo, size: 40, radius: Corner.card, onDark: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(branding.name, style: TextStyle(color: brand.primary, fontSize: 13, fontWeight: FontWeight.w900)),
                      const Text('سند قبض', style: TextStyle(color: _C.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: _C.faint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: _C.line)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'رقم الوصل: ${p.receiptNumber}',
                    style: TextStyle(color: brand.primary, fontSize: 12.5, fontWeight: FontWeight.w900, fontFamily: _mono),
                  ),
                ),
                Text(formatDate(p.date), style: const TextStyle(color: _C.muted, fontSize: 11.5, fontFamily: _mono)),
              ],
            ),
            const SizedBox(height: 12),
            row('وصلنا من', student.fullName),
            if (student.gradeLevel.trim().isNotEmpty) row('المرحلة الدراسية', student.gradeLevel.trim()),
            row('المبلغ المقبوض', money(p.amount)),
            row('وقدره كتابةً', amountInArabicWords(p.amount)),
            row('طريقة السداد', branding.methodLabel(p.method)),
            row('وذلك عن', paymentPurposeNames[p.purpose] ?? p.purpose),
            if (p.senderName.isNotEmpty) row('اسم المحول منه', p.senderName),
            if (p.reference.isNotEmpty) row('الرقم المرجعي', p.reference),
            if (p.notes.trim().isNotEmpty) row('البيان', p.notes.trim()),
          ],
        ),
      ),
    );
  }
}
