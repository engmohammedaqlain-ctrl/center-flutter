import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// نغمة البطاقة العميقة: ثيم المدرسة أو أخضر (مسدد/حاضر) أو نبيذي (مستحق).
enum HeroTone { theme, paid, due }

/// بطاقة واحدة بتدرّج لون المدرسة للرقم الأهم في الشاشة، كـ NHeroCard في الويب.
class AdminHero extends StatelessWidget {
  const AdminHero({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.end = '',
    this.chips = const [],
    this.icon,
    this.tone = HeroTone.theme,
  });

  final String label;
  final String value;
  final String unit;
  final String end;
  final List<String> chips;
  final IconData? icon;
  final HeroTone tone;

  List<Color> get _colors => switch (tone) {
        HeroTone.paid => const [Color(0xFF0F4A34), Color(0xFF1E7651)],
        HeroTone.due => const [Color(0xFF5B1A24), Color(0xFF8C3441)],
        HeroTone.theme => [AppColors.navyDark, AppColors.navyMid],
      };

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final dim = Colors.white.withValues(alpha: 0.78);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(20),
          topEnd: Radius.circular(12),
          bottomStart: Radius.circular(12),
          bottomEnd: Radius.circular(20),
        ),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: colors,
        ),
        boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -40,
            top: -60,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[Icon(icon, size: 16, color: dim), const SizedBox(width: 6)],
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppText.family, fontSize: 12.5, fontWeight: FontWeight.w600, color: dim)),
                    ),
                    if (end.isNotEmpty)
                      Text(end,
                          style: TextStyle(fontFamily: AppText.family, fontSize: 11.5, fontWeight: FontWeight.w600, color: dim)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontFamily: AppText.family, fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(unit,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: AppText.family, fontSize: 13, fontWeight: FontWeight.w600, color: dim)),
                      ),
                    ],
                  ],
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(Corner.chip + 2),
                          ),
                          child: Text(c,
                              style: const TextStyle(
                                  fontFamily: AppText.family, fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// قسم مطوي بملخص: العنوان وسطر موجز، والمحتوى عند الفتح.
class AdminFold extends StatelessWidget {
  const AdminFold({
    super.key,
    required this.title,
    required this.child,
    this.summary = '',
    this.initiallyExpanded = false,
  });

  final String title;
  final String summary;
  final bool initiallyExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          iconColor: AppColors.muted,
          collapsedIconColor: AppColors.muted,
          title: Text(title, style: AppText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: summary.isEmpty
              ? null
              : Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppText.family, fontSize: 12, color: AppColors.muted)),
          children: [child],
        ),
      ),
    );
  }
}
