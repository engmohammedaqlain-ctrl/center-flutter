import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'admin_tokens.dart';
import 'animated_count.dart';

/// لبنات شاشات الإدارة بهوية نون «رسمية حديثة» — مطابقة لـ `components/noon/noonUi.tsx`
/// و`noonPortal.tsx` في الويب على عرض الجوال. الألوان من [AdminNoon] (ثيم المدرسة).

/// نغمة البطاقة العميقة: ثيم المدرسة أو أخضر (مسدد/حاضر) أو نبيذي (مستحق).
enum HeroTone { theme, paid, due }

TextStyle _t(double size, FontWeight w, Color c, {double? height}) =>
    TextStyle(fontFamily: AppText.family, fontSize: size, fontWeight: w, color: c, height: height);

/// بطاقة الملخص العميقة — `NHeroCard`: تدرج بثلاث وقفات وزوايا غير متناظرة
/// ودائرتان باهتتان وخانة أيقونة، والرقم أبيض 30. واحدة في الشاشة فقط.
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

  List<Color> get _colors {
    final ink = AdminNoon.ink;
    final teal = AdminNoon.teal;
    return switch (tone) {
      HeroTone.paid => const [Color(0xFF0F4A34), Color(0xFF1E7651), Color(0xFF08301F)],
      HeroTone.due => const [Color(0xFF62202B), Color(0xFF8C3441), Color(0xFF431018)],
      HeroTone.theme => [
          AdminNoon.mix(ink, 0.66, Colors.black),
          AdminNoon.mix(AdminNoon.mix(teal, 0.55, ink), 0.74, Colors.black),
          AdminNoon.mix(ink, 0.38, Colors.black),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final tile = Colors.white.withValues(alpha: 0.14);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 20px 12px 20px 12px كما في الويب (زوايا فعلية لا تنقلب مع الاتجاه)
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(12),
        ),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          stops: const [0, 0.58, 1],
          colors: colors,
        ),
        boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          // لمعة داخلية رفيعة في الأعلى
          Positioned(left: 0, right: 0, top: 0, child: Container(height: 1, color: Colors.white.withValues(alpha: 0.12))),
          Positioned(
            left: -40,
            top: -60,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          Positioned(
            left: 70,
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
                Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(AdminNoon.rTile)),
                        child: Icon(icon, size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(12.5, FontWeight.w500, Colors.white.withValues(alpha: 0.8))),
                    ),
                    if (end.isNotEmpty)
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(AdminNoon.rTile)),
                        child: Text(end, style: _t(11, FontWeight.w700, Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(30, FontWeight.w700, Colors.white, height: 1.15)
                              .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(unit, style: _t(13, FontWeight.w500, Colors.white.withValues(alpha: 0.7))),
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
                            borderRadius: BorderRadius.circular(AdminNoon.rTile),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                          ),
                          child: Text(c, style: _t(11, FontWeight.w500, Colors.white.withValues(alpha: 0.9))),
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
      decoration: noonPanel(),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          iconColor: AdminNoon.muted,
          collapsedIconColor: AdminNoon.muted,
          title: Text(title, style: _t(14, FontWeight.w700, AdminNoon.text)),
          subtitle: summary.isEmpty
              ? null
              : Text(summary,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(11, FontWeight.w400, AdminNoon.muted)),
          children: [child],
        ),
      ),
    );
  }
}

/// قسم قابل للطي — `CollapsibleSection` في ملف الطالب: لوح نون، رأسه العنوان
/// ووسمه وإضافته وسهم، وتحته خط حين يُفتح، والمحتوى بحشوة 16×12.
class NoonFoldCard extends StatefulWidget {
  const NoonFoldCard({
    super.key,
    required this.title,
    required this.children,
    this.badge,
    this.headerExtra,
    this.initiallyOpen = false,
    this.gap = 10,
  });

  final String title;
  final Widget? badge;
  final Widget? headerExtra;
  final bool initiallyOpen;
  final List<Widget> children;
  final double gap;

  @override
  State<NoonFoldCard> createState() => _NoonFoldCardState();
}

class _NoonFoldCardState extends State<NoonFoldCard> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: noonPanel(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsetsDirectional.only(start: 16, end: 12),
              decoration: open
                  ? BoxDecoration(border: Border(bottom: BorderSide(color: AdminNoon.line)))
                  : null,
              child: Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(widget.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w700, AdminNoon.text)),
                    ),
                  ),
                  if (widget.badge != null) ...[const SizedBox(width: 8), Flexible(child: widget.badge!)],
                  const Spacer(),
                  if (widget.headerExtra != null) ...[widget.headerExtra!, const SizedBox(width: 8)],
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AdminNoon.muted),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.children.length; i++) ...[
                    if (i > 0) SizedBox(height: widget.gap),
                    widget.children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── اللوح ───────────────────────────────────────────────────────────────────

/// `nPanel`: لوح أبيض بزاوية 10 وحدّ `line` وظل ناعم جداً.
BoxDecoration noonPanel({Color? border, Color color = Colors.white, double radius = AdminNoon.rPanel}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? AdminNoon.line),
      boxShadow: AdminNoon.shadow,
    );

/// لوح يُلمس كله (بطاقة صف أو طالب) بزاوية 10 وتظليل `mist-2` عند اللمس.
class NoonTapPanel extends StatelessWidget {
  const NoonTapPanel({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(AdminNoon.rPanel);
    return Material(
      color: Colors.transparent,
      borderRadius: r,
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        highlightColor: AdminNoon.mist2,
        child: Ink(
          decoration: noonPanel(border: selected ? AdminNoon.ink : null),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ── الأزرار ─────────────────────────────────────────────────────────────────

/// نغمات `NBtn`: الشمس (`sun`) للإجراء الرئيسي الوحيد في الشاشة، والحبر لما سواه.
enum NoonTone { ink, sun, line, ghost, danger, dangerFill }

/// زر نون — `NBtn`: مستطيل بزاوية 8 ونص عريض. `small` 32px لما داخل البطاقات،
/// وإلا 40px. بلا [label] يصير زر أيقونة مربعاً ويحمل [tooltip].
class NoonButton extends StatelessWidget {
  const NoonButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.tone = NoonTone.line,
    this.small = false,
    this.expand = false,
    this.busy = false,
    this.tooltip,
    this.size,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final NoonTone tone;
  final bool small;
  final bool expand;
  final bool busy;
  final String? tooltip;

  /// ارتفاع (وعرض زر الأيقونة) مخصص — كأزرار البحث 44.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (tone) {
      NoonTone.ink => (AdminNoon.ink, AdminNoon.onInk, null),
      NoonTone.sun => (AdminNoon.action, AdminNoon.onAction, null),
      NoonTone.line => (Colors.white, AdminNoon.text, AdminNoon.line),
      NoonTone.ghost => (Colors.transparent, AdminNoon.muted, null),
      NoonTone.danger => (Colors.transparent, AdminNoon.red600, null),
      NoonTone.dangerFill => (AdminNoon.red600, Colors.white, null),
    };
    final h = size ?? (small ? 32.0 : 40.0);
    final iconOnly = label == null || label!.isEmpty;
    final enabled = onPressed != null && !busy;
    final r = BorderRadius.circular(AdminNoon.rTile);
    final iconSize = small ? 16.0 : 18.0;

    final content = busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: iconSize, color: fg),
              if (icon != null && !iconOnly) const SizedBox(width: 6),
              if (!iconOnly)
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(small ? 12 : 14, FontWeight.w700, fg),
                  ),
                ),
            ],
          );

    Widget btn = Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Material(
        color: bg,
        borderRadius: r,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: r,
          child: Container(
            height: h,
            width: iconOnly ? h : (expand ? double.infinity : null),
            padding: iconOnly ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: small ? 14 : 20),
            alignment: Alignment.center,
            decoration: border == null
                ? null
                : BoxDecoration(borderRadius: r, border: Border.all(color: border)),
            child: content,
          ),
        ),
      ),
    );
    final tip = tooltip ?? (iconOnly ? label : null);
    if (tip != null && tip.isNotEmpty) btn = Tooltip(message: tip, child: btn);
    return btn;
  }
}

// ── الوسوم وسطر الحقائق ──────────────────────────────────────────────────────

enum NoonBadgeTone { neutral, mist, sun, green, red }

/// وسم حالة — `NBadge`: مستطيل 20px بزاوية 4، تظليل فاتح ونص أغمق وحد رفيع.
class NoonBadge extends StatelessWidget {
  const NoonBadge(this.label, {super.key, this.tone = NoonBadgeTone.neutral, this.height = 20, this.fontSize = 11});

  final String label;
  final NoonBadgeTone tone;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color border) = switch (tone) {
      NoonBadgeTone.neutral => (AdminNoon.band, AdminNoon.muted, AdminNoon.line),
      NoonBadgeTone.mist => (AdminNoon.mist, AdminNoon.tealD, AdminNoon.headLine),
      NoonBadgeTone.sun => (Colors.transparent, AdminNoon.warn, AdminNoon.warnLine),
      NoonBadgeTone.green => (AdminNoon.green50, AdminNoon.green700, AdminNoon.green200),
      NoonBadgeTone.red => (AdminNoon.red50, AdminNoon.red700, AdminNoon.red200),
    };
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AdminNoon.rTag),
        border: Border.all(color: border),
      ),
      child: Text(label, maxLines: 1, style: _t(fontSize, FontWeight.w700, fg, height: 1)),
    );
  }
}

/// سطر حقائق هادئ — `NMetaLine`: «المرحلة الأول | الطلاب 20»، المفتاح خافت والقيمة بحبر النص.
class NoonMetaLine extends StatelessWidget {
  const NoonMetaLine(this.items, {super.key});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final rows = items.where((e) => e.$2.trim().isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 2,
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            margin: EdgeInsetsDirectional.only(start: i > 0 ? 8 : 0),
            padding: EdgeInsetsDirectional.only(start: i > 0 ? 8 : 0),
            decoration: i > 0
                ? BoxDecoration(border: BorderDirectional(start: BorderSide(color: AdminNoon.line)))
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(rows[i].$1, style: _t(11, FontWeight.w500, AdminNoon.muted, height: 20 / 11)),
                const SizedBox(width: 4),
                Text(rows[i].$2, style: _t(11, FontWeight.w700, AdminNoon.text, height: 20 / 11)),
              ],
            ),
          ),
      ],
    );
  }
}

/// عنوان قسم — `NSectionTitle`: شريط تمييز 4px وعنوان عريض وعدّ خافت، وتحته خط رفيع.
class NoonSectionTitle extends StatelessWidget {
  const NoonSectionTitle(this.title, {super.key, this.count, this.end});

  final String title;
  final int? count;
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AdminNoon.rule))),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: AdminNoon.teal),
          const SizedBox(width: 8),
          Flexible(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(14, FontWeight.w700, AdminNoon.text)),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text('($count)', style: _t(12, FontWeight.w500, AdminNoon.muted)),
          ],
          const Spacer(),
          ?end,
        ],
      ),
    );
  }
}

// ── الحالات ─────────────────────────────────────────────────────────────────

/// حالة فارغة — `NEmpty`: لوح بحد متقطع وأيقونة بلون العنصر النشط ونص عريض خافت.
class NoonEmpty extends StatelessWidget {
  const NoonEmpty(
    this.text, {
    super.key,
    this.icon = Icons.inbox_outlined,
    this.dashed = true,
    this.action,
    this.actionIcon,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final bool dashed;
  final String? action;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: AdminNoon.teal),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: _t(14, FontWeight.w700, AdminNoon.muted)),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 12),
            NoonButton(label: action, icon: actionIcon, tone: NoonTone.ink, onPressed: onAction),
          ],
        ],
      ),
    );
    if (!dashed) {
      return Container(width: double.infinity, decoration: noonPanel(), child: body);
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AdminNoon.rPanel),
        boxShadow: AdminNoon.shadow,
      ),
      child: CustomPaint(painter: _DashedBorder(AdminNoon.line, AdminNoon.rPanel), child: body),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

/// شريط تنبيه — `NNotice`: نجاح عابر (`mist`) أو تنبيه يحتاج انتباهاً (`sun`).
class NoonNotice extends StatelessWidget {
  const NoonNotice(this.text, {super.key, this.sun = false, this.icon, this.trailing});

  final String text;
  final bool sun;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = sun ? AdminNoon.warnD : AdminNoon.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: sun ? Colors.transparent : AdminNoon.mist,
        borderRadius: BorderRadius.circular(AdminNoon.rTile),
        border: Border.all(color: sun ? AdminNoon.warnLine : AdminNoon.headLine),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 10)],
          Expanded(child: Text(text, style: _t(14, FontWeight.w700, fg))),
          ?trailing,
        ],
      ),
    );
  }
}

/// تحميل — `NLoading`: حلقة بلون العنصر النشط ونص خافت.
class NoonLoading extends StatelessWidget {
  const NoonLoading({super.key, this.text = 'جارٍ التحميل'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: AdminNoon.teal)),
          const SizedBox(height: 10),
          Text(text, style: _t(14, FontWeight.w500, AdminNoon.muted)),
        ],
      ),
    );
  }
}

// ── البحث والتصفية ──────────────────────────────────────────────────────────

/// حقل البحث على الجوال: 44px بزاوية 8، أيقونة البحث في طرفه والعدد بجانبها،
/// وزر المسح في أوله — كحقل `nInput` في قائمة الطلاب على الويب.
class NoonSearchField extends StatefulWidget {
  const NoonSearchField({super.key, required this.controller, required this.hint, this.onChanged, this.count});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final String? count;

  @override
  State<NoonSearchField> createState() => _NoonSearchFieldState();
}

class _NoonSearchFieldState extends State<NoonSearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AdminNoon.rTile),
        border: Border.all(color: focused ? AdminNoon.teal : AdminNoon.line),
        boxShadow: focused
            ? [BoxShadow(color: AdminNoon.teal.withValues(alpha: 0.22), spreadRadius: 3)]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: hasText
                ? InkWell(
                    onTap: () {
                      widget.controller.clear();
                      widget.onChanged?.call('');
                      setState(() {});
                    },
                    child: Tooltip(message: 'مسح', child: Icon(Icons.close_rounded, size: 16, color: AdminNoon.muted)),
                  )
                : null,
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: (v) {
                widget.onChanged?.call(v);
                setState(() {});
              },
              textInputAction: TextInputAction.search,
              style: _t(14, FontWeight.w500, AdminNoon.text),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                hintText: widget.hint,
                hintStyle: _t(14, FontWeight.w500, AdminNoon.faint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (widget.count != null) ...[
            const SizedBox(width: 6),
            Text(widget.count!, style: _t(11, FontWeight.w700, AdminNoon.muted)),
          ],
          const SizedBox(width: 6),
          Icon(Icons.search_rounded, size: 16, color: AdminNoon.muted),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// خيار في ورقة التصفية — `SheetChip`: 36px بزاوية 6، والمختار بالحبر.
class NoonSheetChip extends StatelessWidget {
  const NoonSheetChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AdminNoon.ink : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? AdminNoon.ink : AdminNoon.line),
        ),
        child: Text(label, style: _t(12, FontWeight.w700, selected ? AdminNoon.onInk : AdminNoon.text)),
      ),
    );
  }
}

/// فلتر مفعّل تحت البحث يُلغى بلمسه — `ActiveChip`.
class NoonActiveChip extends StatelessWidget {
  const NoonActiveChip({super.key, required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClear,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 28,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
        decoration: BoxDecoration(
          color: AdminNoon.mist,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AdminNoon.headLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _t(12, FontWeight.w700, AdminNoon.tealD)),
            const SizedBox(width: 4),
            Icon(Icons.close_rounded, size: 14, color: AdminNoon.tealD),
          ],
        ),
      ),
    );
  }
}

/// مفتاح خيارات — `NSegment`: خانات متجاورة بحد واحد، والمختار بتظليل `mist` وخط سفلي.
class NoonSegment<T> extends StatelessWidget {
  const NoonSegment({super.key, required this.value, required this.options, required this.onChanged, this.scroll = false});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// خانات بعرض نصها تتمرر أفقياً (`min-w-max`) بدل تقسيم العرض.
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    Widget cell(int i) {
      final (id, label) = options[i];
      final on = id == value;
      final c = InkWell(
        onTap: () => onChanged(id),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AdminNoon.mist : null,
            border: Border(
              right: i > 0 ? BorderSide(color: AdminNoon.line) : BorderSide.none,
              bottom: on ? BorderSide(color: AdminNoon.teal, width: 2) : BorderSide.none,
            ),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(12, FontWeight.w700, on ? AdminNoon.text : AdminNoon.muted)),
        ),
      );
      return scroll ? c : Expanded(child: c);
    }

    final row = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AdminNoon.rTile),
        border: Border.all(color: AdminNoon.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
          children: [for (var i = 0; i < options.length; i++) cell(i)],
        ),
      ),
    );
    return scroll ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row) : row;
  }
}

// ── النافذة ─────────────────────────────────────────────────────────────────

/// ورقة سفلية بشكل `NModal` على الجوال: رأس بالعنوان وزر إغلاق وتحته خط،
/// والمحتوى يتمرر، وتذييل بحد علوي والأزرار في طرفه.
Future<T?> showNoonSheet<T>(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext ctx, StateSetter setSheet) body,
  List<Widget> Function(BuildContext ctx, StateSetter setSheet)? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AdminNoon.rPanel)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => NoonSheetFrame(
        title: title,
        footer: footer?.call(ctx, setSheet),
        children: body(ctx, setSheet),
      ),
    ),
  );
}

class NoonSheetFrame extends StatelessWidget {
  const NoonSheetFrame({super.key, required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final List<Widget>? footer;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 14, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AdminNoon.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _t(16, FontWeight.w700, AdminNoon.text)),
                  ),
                  NoonButton(
                    icon: Icons.close_rounded,
                    tone: NoonTone.ghost,
                    small: true,
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 12, 20, footer == null ? 8 + (bottom < 16 ? 16 : bottom) : 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
            if (footer != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: EdgeInsets.fromLTRB(20, 12, 20, bottom < 16 ? 16 : bottom),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AdminNoon.line))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < footer!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      footer![i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// تسمية مجموعة في ورقة — `text-xs font-bold text-noon-muted mb-2`.
class NoonSheetLabel extends StatelessWidget {
  const NoonSheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: _t(12, FontWeight.w700, AdminNoon.muted)),
      );
}

/// نصوص نون الشائعة للشاشات.
abstract final class NoonText {
  static TextStyle get title => _t(15, FontWeight.w700, AdminNoon.text);
  static TextStyle get body => _t(12, FontWeight.w400, AdminNoon.text);
  static TextStyle get muted => _t(12, FontWeight.w400, AdminNoon.muted);
  static TextStyle style(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
      _t(size, weight, color ?? AdminNoon.text, height: height);
}

/// تاريخ بصيغة الويب (`formatDate`): «12 أكتوبر 2026».
String noonDate(DateTime d) => '${d.day} ${gregorianMonths[d.month - 1]} ${d.year}';
