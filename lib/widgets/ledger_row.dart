import 'package:flutter/material.dart';

import 'admin_tokens.dart';
import 'admin_ui.dart' show NoonText;

/// حالة السطر في كشف الحساب: تحدد لون الدائرة الأمامية وأيقونتها.
enum LedgerTone { paid, due, upcoming, partial, neutral, cancelled }

/// سطر كشف حساب موحّد للأقساط وسندات القبض في ملف الطالب وبوابتي الطالب وولي الأمر:
/// دائرة بحالته، وعنوانه وتحته تفصيله، وفي الطرف مبلغه وتحته شارة حالته، وشريط تقدّم للمسدد جزئياً.
/// [footer] لإجراءات السطر (خصم، حذف، معاينة...) تحت محتواه.
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.amount,
    this.subtitle,
    this.notes = const [],
    this.badge,
    this.progress,
    this.footer,
    this.onTap,
    this.chevron = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final IconData icon;
  final LedgerTone tone;
  final Widget title;
  final Widget amount;
  final Widget? subtitle;

  /// أسطر صغيرة تحت التفصيل (سبب الخصم، الإعفاء، المتبقي).
  final List<Widget> notes;
  final Widget? badge;

  /// نسبة المسدد من القسط (0..1) حين يكون جزئياً.
  final double? progress;
  final Widget? footer;
  final VoidCallback? onTap;

  /// سهم «فتح» في الطرف (يشير لليسار في العربية).
  final bool chevron;
  final EdgeInsetsGeometry padding;

  (Color fg, Color bg) get _colors => switch (tone) {
        LedgerTone.paid => (AdminNoon.green700, AdminNoon.green50),
        LedgerTone.due => (AdminNoon.red600, AdminNoon.red50),
        LedgerTone.partial => (AdminNoon.warn, AdminNoon.sunL),
        LedgerTone.cancelled => (AdminNoon.faint, AdminNoon.band),
        _ => (AdminNoon.muted, AdminNoon.band),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors;
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle.merge(
                      style: NoonText.style(14, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      DefaultTextStyle.merge(style: NoonText.style(11.5, color: AdminNoon.muted), child: subtitle!),
                    ],
                    for (final n in notes) ...[const SizedBox(height: 3), n],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(style: NoonText.style(14.5, weight: FontWeight.w700), child: amount),
                  if (badge != null) ...[const SizedBox(height: 5), badge!],
                ],
              ),
              if (chevron) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(Icons.chevron_right_rounded, size: 20, color: AdminNoon.faint),
                ),
              ],
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AdminNoon.line,
                  valueColor: AlwaysStoppedAnimation(AdminNoon.green700),
                ),
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsetsDirectional.only(start: 48), child: footer!),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, highlightColor: AdminNoon.mist, child: body),
    );
  }
}
