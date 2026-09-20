import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// صف قائمة بريميوم — بطاقة بيضاء بحدّ خفيف من ثيم التطبيق، بلا حدود غامقة.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 12, 14),
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(Corner.card);
    final body = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: shape,
        border: Border.all(
          color: selected ? AppColors.accent.withValues(alpha: 0.35) : AppColors.line,
        ),
        boxShadow: cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: AppColors.muted,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: shape,
      child: InkWell(onTap: onTap, borderRadius: shape, child: body),
    );
  }
}

/// فاصل قائمة — يُستخدم فقط حين تبقى الصفوف مسطّحة بلا بطاقات.
Widget appListDivider() => Divider(
      height: 1,
      thickness: 1,
      color: AppColors.line,
      indent: 16,
      endIndent: 16,
    );
