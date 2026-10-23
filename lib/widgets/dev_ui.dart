import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// لبنات بوابة المطور بنمط نون الجديد: بطاقة رقم واحدة عميقة، وعنوان قسم بشريط
// تمييز، ولوح صفوف بفواصل بدل بطاقة لكل صف. المقابل لـ NHeroCard وNSectionTitle
// وNTable في لوحة الويب.

/// بطاقة الرقم الأهم: تدرج بلون الترويسة بزوايا غير متناظرة ودائرتين باهتتين.
/// واحدة في الشاشة فقط.
class DevHero extends StatelessWidget {
  const DevHero({super.key, required this.label, required this.value, this.unit, this.chips = const []});

  final String label;
  final String value;

  /// وحدة أصغر وأخف بجوار الرقم.
  final String? unit;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          colors: [AppColors.navyMid, AppColors.navy, AppColors.navyDark],
        ),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -40,
            top: -60,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          PositionedDirectional(
            end: 70,
            bottom: -70,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        unit!,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
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
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Corner.box),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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

/// عنوان قسم: شريط تمييز قصير وعنوان عريض وعدّه خافت، وتحته خط رفيع.
class DevSectionTitle extends StatelessWidget {
  const DevSectionTitle(this.title, {super.key, this.count, this.trailing});

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.lineStrong))),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('($count)', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// لوح أبيض بحدّ رفيع وظل ناعم، صفوفه تفصلها خطوط.
class DevPanel extends StatelessWidget {
  const DevPanel({super.key, required this.rows, this.tint});

  final List<Widget> rows;

  /// لون خلفية الصفوف المحيطة، اختياري.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tint ?? AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: AppColors.line),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// سطر مفتاح وقيمة هادئ: المفتاح خافت والقيمة بحبر النص.
class DevKV extends StatelessWidget {
  const DevKV(this.k, this.v, {super.key, this.color, this.mono = false});

  final String k;
  final String v;
  final Color? color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 62, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11))),
        Expanded(
          child: Text(
            v,
            textDirection: mono ? TextDirection.ltr : null,
            textAlign: mono ? TextAlign.start : null,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.text,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}
