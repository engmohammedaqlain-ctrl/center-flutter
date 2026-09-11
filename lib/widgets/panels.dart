import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

// عناصر العرض المشتركة بين ملف الطالب والمالية: بطاقة رقم، وشريط ملخص، وبلاطة
// سجل، وزر صغير داخلها. مصدر واحد كي تبدو الصفحتان من نظام واحد.

/// بلاطة عنصر متكرر: خلفية فاتحة وإطار رفيع.
BoxDecoration tileDecoration({bool white = false}) => BoxDecoration(
      borderRadius: BorderRadius.circular(Corner.box),
      color: white ? Colors.white : AppColors.bg,
      border: Border.all(color: AppColors.line),
    );

/// رقم إحصائي في بطاقة مستقلة: عنوان صغير فوق قيمة بارزة بلونها، في المنتصف.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.color, this.caption});

  final String label;
  final String value;
  final Color color;

  /// سطر صغير تحت القيمة — كعدد السندات.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
          ],
        ],
      ),
    );
  }
}

/// بطاقات أرقام متجاورة بارتفاع واحد.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// شريط رمادي فاتح بإطار رفيع — للملخصات والملاحظات، كما في Center.
class InfoStrip extends StatelessWidget {
  const InfoStrip({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: tileDecoration(),
      child: child,
    );
  }
}

/// «حضور: 12» بلون الحالة — ملخص في سطر واحد.
class TallyText extends StatelessWidget {
  const TallyText(this.label, this.value, this.color, {super.key});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        children: [TextSpan(text: '$value', style: const TextStyle(fontWeight: FontWeight.w900))],
      ),
      style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700),
    );
  }
}

/// زر صغير داخل البلاطة: أيقونة ونص بإطار.
class TileButton extends StatelessWidget {
  const TileButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final Color color;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.box),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: background, border: Border.all(color: border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(data: IconThemeData(color: color), child: icon),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// معيار تصفية واحد داخل [GroupedFilterButton].
class FilterGroup {
  const FilterGroup({required this.title, required this.options, required this.value, required this.onSelected});

  final String title;

  /// القيمة ← النص المعروض. القيمة الفارغة تعني «الكل».
  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onSelected;
}

/// زر تصفية واحد لأكثر من معيار — كطريقة الدفع والحالة معاً — كي يبقى البحث
/// والتصفية في سطر واحد. بشكل [FilterButton] نفسه، ويتلوّن حين تُفعَّل تصفية.
class GroupedFilterButton extends StatelessWidget {
  const GroupedFilterButton({super.key, required this.groups, this.maxWidth = 132});

  final List<FilterGroup> groups;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final active = groups.where((g) => g.value.isNotEmpty).toList();
    final label = switch (active.length) {
      0 => 'تصفية',
      1 => active.first.options[active.first.value] ?? 'تصفية',
      _ => 'تصفية (${active.length})',
    };
    final on = active.isNotEmpty;
    final fg = on ? AppColors.amber : AppColors.text;

    return PopupMenuButton<(int, String)>(
      tooltip: 'تصفية',
      position: PopupMenuPosition.under,
      color: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Corner.field))),
      onSelected: (choice) => groups[choice.$1].onSelected(choice.$2),
      itemBuilder: (_) => [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const PopupMenuDivider(height: 8),
          PopupMenuItem<(int, String)>(
            enabled: false,
            height: 28,
            child: Text(
              groups[g].title,
              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          for (final e in groups[g].options.entries)
            PopupMenuItem<(int, String)>(
              value: (g, e.key),
              height: 40,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: e.key == groups[g].value ? Icon(Icons.check, size: 16, color: AppColors.amber) : null,
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: e.key == groups[g].value ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
      child: Container(
        height: controlHeight,
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: on ? AppColors.amberSoft : Colors.white,
          border: Border.all(color: on ? AppColors.amberBorder : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.filter_alt : Icons.filter_alt_outlined, size: 16, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}
