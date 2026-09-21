import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// حجم الصفحة الافتراضي للقوائم الطويلة — يمنع بناء آلاف الصفوف دفعة واحدة.
const kListPageSize = 30;

/// شريحة ظاهرة من القائمة: أول [visible] عنصراً.
List<T> listPage<T>(List<T> items, int visible) {
  if (items.isEmpty || visible <= 0) return const [];
  if (visible >= items.length) return items;
  return items.sublist(0, visible);
}

/// زر «عرض المزيد» تحت قائمة مقطوعة.
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({
    super.key,
    required this.shown,
    required this.total,
    required this.onMore,
    this.pageSize = kListPageSize,
  });

  final int shown;
  final int total;
  final VoidCallback onMore;
  final int pageSize;

  @override
  Widget build(BuildContext context) {
    if (shown >= total) return const SizedBox.shrink();
    final left = total - shown;
    final next = left < pageSize ? left : pageSize;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextButton(
        onPressed: onMore,
        child: Text(
          'عرض $next من $left المتبقية',
          style: TextStyle(
            fontFamily: AppText.family,
            color: AppColors.amber,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
