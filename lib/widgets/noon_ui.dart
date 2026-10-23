import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// لبنات هوية نون «رسمية حديثة» للبوابات (الطالب وولي الأمر والمعلم) والمودل —
// المقابل لـ `components/noon/noonUi.tsx` و`noonPortal.tsx` في الويب، بقيمها نفسها.
// الألوان من `Noon` (مشتقة من ثيم المدرسة)، والزوايا والأبعاد والظل والخط من
// `NoonRadius` و`NoonSize` و`nShadow` و`nText` في app_theme.dart.

// ── اللوح ────────────────────────────────────────────────────────────────────

/// زخرفة اللوح الأبيض: زوايا 10، وحد 1px بلون `line`، وظل ناعم جداً.
BoxDecoration nPanelDecoration({Color? color, Color? border, double radius = NoonRadius.panel}) => BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? Noon.line),
      boxShadow: nShadow,
    );

/// لوح أبيض (`nPanel`). بـ [onTap] يصير زراً يُظلَّل بـ `mist` عند اللمس.
class NPanel extends StatelessWidget {
  const NPanel({super.key, required this.child, this.padding = EdgeInsets.zero, this.onTap, this.margin});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(NoonRadius.panel);
    return Container(
      margin: margin,
      decoration: nPanelDecoration(),
      child: ClipRRect(
        borderRadius: radius,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  highlightColor: Noon.mist,
                  child: Padding(padding: padding, child: child),
                ),
              ),
      ),
    );
  }
}

/// أعمدة متباعدة بمسافة ثابتة (`space-y-*`).
class NColumn extends StatelessWidget {
  const NColumn({super.key, required this.children, this.gap = NoonSize.gap});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final shown = children.where((w) => w is! SizedBox || w.width != 0 || w.height != 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[if (i > 0) SizedBox(height: gap), shown[i]],
      ],
    );
  }
}

// ── العناوين ─────────────────────────────────────────────────────────────────

/// عنوان قسم كعناوين التقارير: شريط تمييز 4px، والاسم عريضاً، وعدّه خافتاً بين قوسين،
/// وتحته خط رفيع بلون `rule`. في طرفه إجراء أو وسم.
class NSectionTitle extends StatelessWidget {
  const NSectionTitle({super.key, required this.title, this.count, this.end, this.hint});

  final String title;
  final int? count;
  final Widget? end;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    Widget head = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 4, height: 16, color: Noon.teal),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nText(14, weight: FontWeight.w700),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text('($count)', style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
        ],
      ],
    );
    if (hint != null) head = Tooltip(message: hint!, child: head);
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Noon.rule))),
      child: Row(
        children: [
          Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: head)),
          if (end != null) ...[const SizedBox(width: 8), end!],
        ],
      ),
    );
  }
}

/// عنوان فرعي صغير خافت فوق جدول داخل قسم: «الأقساط (3)».
class NSubTitle extends StatelessWidget {
  const NSubTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: nText(12, weight: FontWeight.w700, color: Noon.muted));
}

// ── بطاقة الملخص ─────────────────────────────────────────────────────────────

/// بطاقة الملخص العميقة: تدرج غامق بثلاث وقفات وزوايا غير متناظرة، ولمعة داخلية في الأعلى
/// وظل ملوّن، ودائرتان باهتتان، والرقم الرئيسي أبيض 30 بوحدته بجانبه، وتحته شرائح التفاصيل.
/// واحدة في الشاشة فقط.
class NHeroCard extends StatefulWidget {
  const NHeroCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.tone = NoonHeroTone.theme,
    this.end,
    this.chips = const [],
    this.child,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final NoonHeroTone tone;
  final String? end;
  final List<String> chips;
  final Widget? child;

  @override
  State<NHeroCard> createState() => _NHeroCardState();
}

class _NHeroCardState extends State<NHeroCard> with SingleTickerProviderStateMixin {
  // دخول بظهور وارتفاع 250ms، ويُعطَّل لمن يفضّل حركة أقل
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _in.value = 1;
      } else {
        _in.forward();
      }
    });
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stops = Noon.hero(widget.tone);
    final white = Colors.white;
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: NoonRadius.hero,
        gradient: LinearGradient(
          // `to bottom left`
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          stops: const [0, 0.58, 1],
          colors: stops,
        ),
        boxShadow: [BoxShadow(color: stops.first.withValues(alpha: 0.28), blurRadius: 14.7, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -60,
            child: _circle(170, 0.07),
          ),
          Positioned(
            left: 70,
            bottom: -70,
            child: _circle(120, 0.05),
          ),
          // لمعة داخلية رفيعة في الأعلى
          Positioned(left: 0, right: 0, top: 0, child: Container(height: 1, color: white.withValues(alpha: 0.12))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (widget.icon != null) ...[
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(NoonRadius.tile),
                        ),
                        child: Icon(widget.icon, size: 16, color: white),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(12.5, weight: FontWeight.w500, color: white.withValues(alpha: 0.8)),
                      ),
                    ),
                    if (widget.end != null)
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(NoonRadius.tile),
                        ),
                        child: Text(widget.end!, style: nText(11, weight: FontWeight.w700, color: white)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        widget.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(30, weight: FontWeight.w700, color: white, height: 1.15),
                      ),
                    ),
                    if (widget.unit != null) ...[
                      const SizedBox(width: 6),
                      Text(widget.unit!, style: nText(13, weight: FontWeight.w500, color: white.withValues(alpha: 0.7), height: 1.15)),
                    ],
                  ],
                ),
                if (widget.chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final chip in widget.chips)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(NoonRadius.tile),
                            border: Border.all(color: white.withValues(alpha: 0.10)),
                          ),
                          child: Text(chip, style: nText(11, weight: FontWeight.w500, color: white.withValues(alpha: 0.9))),
                        ),
                    ],
                  ),
                ],
                if (widget.child != null) ...[const SizedBox(height: 12), widget.child!],
              ],
            ),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _in,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_in.value);
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child));
      },
      child: card,
    );
  }

  Widget _circle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
      );
}

/// شريط نسبة داخل بطاقة الملخص (الحضور): أبيض 90% على أبيض 20%.
class NHeroBar extends StatelessWidget {
  const NHeroBar({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.2))),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: (percent.clamp(0, 100)) / 100,
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── خانات الأرقام ────────────────────────────────────────────────────────────

enum NTone { green, red, sun, mist, neutral }

({Color num, Color bg}) _statTone(NTone t) => switch (t) {
      NTone.green => (num: Noon.green700, bg: Noon.green50),
      NTone.red => (num: Noon.red700, bg: Noon.red50),
      NTone.sun => (num: Noon.warn, bg: Noon.sunL),
      NTone.mist => (num: Noon.tealD, bg: Noon.mist),
      NTone.neutral => (num: Noon.text, bg: Noon.band),
    };

class NStat {
  const NStat({required this.label, required this.value, this.tone = NTone.neutral, this.unit});

  final String label;
  final String value;
  final NTone tone;
  final String? unit;
}

/// خانات أرقام مفصولة بخطوط كخانات الملخص في الكشف: تظليل فاتح بلون حالتها ورقم ملوّن.
class NStatTiles extends StatelessWidget {
  const NStatTiles({super.key, required this.items});

  final List<NStat> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Noon.line,
        borderRadius: BorderRadius.circular(NoonRadius.tile),
        border: Border.all(color: Noon.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 1),
              Expanded(
                child: Container(
                  color: _statTone(items[i].tone).bg,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: items[i].value,
                          children: [
                            if (items[i].unit != null)
                              TextSpan(text: ' ${items[i].unit}', style: nText(10, weight: FontWeight.w500, color: _statTone(items[i].tone).num)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(18, weight: FontWeight.w700, color: _statTone(items[i].tone).num, height: 1),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(11, weight: FontWeight.w500, color: Noon.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── الوسوم ───────────────────────────────────────────────────────────────────

({Color bg, Color fg, Color border}) nBadgeColors(NTone t) => switch (t) {
      NTone.neutral => (bg: Noon.band, fg: Noon.muted, border: Noon.line),
      NTone.mist => (bg: Noon.mist, fg: Noon.tealD, border: Noon.headLine),
      NTone.sun => (bg: Noon.sunL, fg: Noon.warn, border: Noon.warnLine),
      NTone.green => (bg: Noon.green50, fg: Noon.green700, border: Noon.green200),
      NTone.red => (bg: Noon.red50, fg: Noon.red700, border: Noon.red200),
    };

/// وسم حالة: مستطيل صغير بزاوية 4، تظليل فاتح ونص أغمق وحد رفيع. للحالة وحدها.
class NBadge extends StatelessWidget {
  const NBadge(this.text, {super.key, this.tone = NTone.neutral, this.icon, this.height = 20, this.fontSize = 11});

  final String text;
  final NTone tone;
  final IconData? icon;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = nBadgeColors(tone);
    return Container(
      height: height,
      padding: EdgeInsetsDirectional.only(start: icon != null ? 6 : 8, end: 8),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(NoonRadius.tag),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c.fg), const SizedBox(width: 4)],
          Text(text, maxLines: 1, style: nText(fontSize, weight: FontWeight.w700, color: c.fg, height: 1.2)),
        ],
      ),
    );
  }
}

/// سطر حقائق هادئ بدل عنقود وسوم: «الفصل الأول | الدروس 5». المفتاح خافت والقيمة بحبر النص.
class NMetaLine extends StatelessWidget {
  const NMetaLine({super.key, required this.items});

  /// (المفتاح، القيمة، لون القيمة إن خالف الحبر). القيمة الفارغة تُحذف.
  final List<(String, String, Color?)> items;

  @override
  Widget build(BuildContext context) {
    final rows = items.where((r) => r.$2.trim().isNotEmpty).toList();
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
                ? BoxDecoration(border: BorderDirectional(start: BorderSide(color: Noon.line)))
                : null,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: rows[i].$1, style: nText(11, weight: FontWeight.w500, color: Noon.muted, height: 20 / 11)),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: rows[i].$2,
                    style: nText(11, weight: FontWeight.w700, color: rows[i].$3 ?? Noon.text, height: 20 / 11),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── الأزرار ──────────────────────────────────────────────────────────────────

/// ألوان الأزرار: `sun` للإجراء الرئيسي الوحيد في الشاشة، و`ink` لما سواه، و`line` الثانوي،
/// و`ghost` الشفاف، و`danger` الحذف، و`onDark` على شريط الترويسة الداكن.
enum NBtnTone { ink, sun, line, ghost, danger, onDark }

/// زر نون: مستطيل بزوايا 8 ونص عريض. `md` للإجراء الرئيسي في الصفحة (40)، و`sm` لما داخل
/// البطاقات (32). بلا [label] يصير زر أيقونة مربعاً، و[tooltip] تلميحه.
class NBtn extends StatelessWidget {
  const NBtn({
    super.key,
    this.label,
    this.icon,
    this.tone = NBtnTone.line,
    this.small = false,
    this.onTap,
    this.busy = false,
    this.tooltip,
    this.expand = false,
    this.fg,
  });

  final String? label;
  final IconData? icon;
  final NBtnTone tone;
  final bool small;
  final VoidCallback? onTap;
  final bool busy;
  final String? tooltip;

  /// بعرض حاويته (`w-full`).
  final bool expand;

  /// لون نص مخصص (أيقونة الملاحظة المكتوبة بلون العنصر النشط).
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color color, Color? border) = switch (tone) {
      NBtnTone.ink => (Noon.ink, Noon.onInk, null),
      NBtnTone.sun => (Noon.action, Noon.onAction, null),
      NBtnTone.line => (Colors.white, Noon.text, Noon.line),
      NBtnTone.ghost => (Colors.transparent, Noon.muted, null),
      NBtnTone.danger => (Colors.transparent, Noon.red600, null),
      NBtnTone.onDark => (Colors.transparent, Noon.onInk, Noon.onInkSoft),
    };
    final ink = fg ?? color;
    final enabled = onTap != null && !busy;
    final h = small ? NoonSize.btnSm : NoonSize.btn;
    final iconOnly = label == null;
    final radius = BorderRadius.circular(NoonRadius.btn);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
        else if (icon != null)
          Icon(icon, size: small ? 16 : 18, color: ink),
        if (label != null) ...[
          if (busy || icon != null) const SizedBox(width: 6),
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nText(small ? 12 : 14, weight: FontWeight.w700, color: ink),
            ),
          ),
        ],
      ],
    );
    Widget button = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          highlightColor: tone == NBtnTone.ink || tone == NBtnTone.sun ? null : Noon.mist2,
          child: SizedBox(
            height: h,
            width: iconOnly ? h : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : (small ? 14 : 20)),
              child: content,
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// مفتاح خيارات بخانات متجاورة بحد واحد: المختار بتظليل `mist` وخط سفلي بلون العنصر النشط.
class NSegment<T> extends StatelessWidget {
  const NSegment({super.key, required this.value, required this.options, required this.onChanged, this.height = NoonSize.segment});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(NoonRadius.btn),
        border: Border.all(color: Noon.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(options[i].$1),
                child: Container(
                  decoration: BoxDecoration(
                    color: options[i].$1 == value ? Noon.mist : Colors.transparent,
                    border: i > 0 ? BorderDirectional(start: BorderSide(color: Noon.line)) : null,
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            options[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nText(
                              12,
                              weight: FontWeight.w700,
                              color: options[i].$1 == value ? Noon.text : Noon.muted,
                            ),
                          ),
                        ),
                      ),
                      if (options[i].$1 == value)
                        Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 2, color: Noon.teal)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── الحالات ──────────────────────────────────────────────────────────────────

/// تحميل: دائرة تدور بلون العنصر النشط، وتحتها النص.
class NLoading extends StatelessWidget {
  const NLoading({super.key, this.text = 'جارٍ التحميل'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Noon.teal)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: nText(14, weight: FontWeight.w500, color: Noon.muted)),
        ],
      ),
    );
  }
}

/// حالة فارغة: لوح أبيض (بحد متقطع افتراضياً) بأيقونة بلون العنصر النشط، والنص عريضاً خافتاً،
/// وزر إجراء بالحبر إن وُجد.
class NEmpty extends StatelessWidget {
  const NEmpty({
    super.key,
    required this.text,
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
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: Noon.teal),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: nText(14, weight: FontWeight.w700, color: Noon.muted)),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 12),
            NBtn(tone: NBtnTone.ink, icon: actionIcon, label: action, onTap: onAction),
          ],
        ],
      ),
    );
    if (!dashed) return Container(decoration: nPanelDecoration(), child: body);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(NoonRadius.panel), boxShadow: nShadow),
      child: CustomPaint(painter: NDashedBorder(color: Noon.line, radius: NoonRadius.panel), child: body),
    );
  }
}

/// حد متقطع بزوايا مدوّرة.
class NDashedBorder extends CustomPainter {
  const NDashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant NDashedBorder old) => old.color != color || old.radius != radius;
}

/// شريط تنبيه: نجاح عابر (`mist`) أو تنبيه يحتاج انتباهاً (`sun`، مثل إقفال العلامات).
class NNotice extends StatelessWidget {
  const NNotice({super.key, required this.text, this.sun = false, this.icon, this.trailing, this.tooltip});

  final String text;
  final bool sun;
  final IconData? icon;
  final Widget? trailing;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = sun ? Noon.warnD : Noon.text;
    Widget box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: sun ? Noon.sunL : Noon.mist,
        borderRadius: BorderRadius.circular(NoonRadius.tile),
        border: Border.all(color: sun ? Noon.warnLine : Noon.headLine),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 10)],
          Expanded(child: Text(text, style: nText(14, weight: FontWeight.w700, color: fg))),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    if (tooltip != null) box = Tooltip(message: tooltip!, child: box);
    return box;
  }
}

// ── الحقول ───────────────────────────────────────────────────────────────────

/// عنوان الحقل فوقه: 12 عريض بحبر النص.
class NField extends StatelessWidget {
  const NField({super.key, required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    Widget title = Text(label, style: nText(12, weight: FontWeight.w700));
    if (hint != null) title = Tooltip(message: hint!, child: title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [title, const SizedBox(height: 6), child],
    );
  }
}

/// زخرفة حقل نون (`nInput`): أبيض بحد `line` وزوايا 8، وعند التركيز حد بلون العنصر النشط.
InputDecoration nInputDecoration({String? hint, String? errorText, bool dense = false}) {
  OutlineInputBorder outline(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(NoonRadius.btn), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: nText(14, weight: FontWeight.w500, color: Noon.faint),
    filled: true,
    fillColor: Colors.white,
    errorText: errorText,
    errorStyle: nText(11, weight: FontWeight.w700, color: Noon.red700),
    contentPadding: EdgeInsets.symmetric(horizontal: dense ? 8 : 14, vertical: dense ? 8 : 10),
    border: outline(Noon.line),
    enabledBorder: outline(Noon.line),
    focusedBorder: outline(Noon.teal, 1.5),
    errorBorder: outline(Noon.red500),
    focusedErrorBorder: outline(Noon.red500, 1.5),
  );
}

/// صندوق بشكل الحقل (اختيار أو تاريخ): 40، أبيض بحد `line`، والنص 14 متوسط.
class NFieldBox extends StatelessWidget {
  const NFieldBox({super.key, required this.child, this.onTap, this.trailing});

  final Widget child;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(NoonRadius.btn);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: Noon.line)),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          height: NoonSize.input,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(child: DefaultTextStyle.merge(style: nText(14, weight: FontWeight.w700), child: child)),
                if (trailing != null) ...[const SizedBox(width: 6), Icon(trailing, size: 16, color: Noon.muted)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── الجداول ──────────────────────────────────────────────────────────────────

/// رأس جدول مظلّل بـ `head` وخطه `head-line`، ونص الأعمدة 11 عريض.
class NTableHead extends StatelessWidget {
  const NTableHead({super.key, required this.cells, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8)});

  /// كل خلية: (التسمية، المرونة أو العرض الثابت إن كانت سالبة).
  final List<(String, num)> cells;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: Noon.head, border: Border(bottom: BorderSide(color: Noon.headLine))),
      child: Row(
        children: [
          for (final (label, size) in cells)
            size < 0
                ? SizedBox(width: -size.toDouble(), child: _th(label))
                : Expanded(flex: size.toInt(), child: _th(label)),
        ],
      ),
    );
  }

  Widget _th(String label) => Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(11, weight: FontWeight.w700));
}

/// صف تذييل بعنوان وقيمة: «عدد الأيام 12» — بتظليل `mist` وخط علوي أغمق.
class NFootRow extends StatelessWidget {
  const NFootRow({super.key, required this.label, required this.value, this.tone, this.horizontal = 12});

  final String label;
  final String value;
  final Color? tone;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 10),
      decoration: BoxDecoration(color: Noon.mist, border: Border(top: BorderSide(color: Noon.ruleSoft))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: nText(12, weight: FontWeight.w700, color: Noon.muted))),
          const SizedBox(width: 12),
          Text(value, textDirection: TextDirection.ltr, style: nText(14, weight: FontWeight.w700, color: tone ?? Noon.text)),
        ],
      ),
    );
  }
}

/// صفوف بفواصل `line` بينها (`divide-y`).
class NDivided extends StatelessWidget {
  const NDivided({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Container(height: 1, color: Noon.line),
          children[i],
        ],
      ],
    );
  }
}

/// زر «عرض الكل (N)» في أسفل لوح: خط علوي ونص عريض بلون العنصر النشط الأغمق.
class NShowAll extends StatelessWidget {
  const NShowAll({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: Noon.mist2,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Noon.line))),
          child: Text(label, style: nText(12, weight: FontWeight.w700, color: Noon.tealD)),
        ),
      ),
    );
  }
}

/// سهم طيّ يدور نصف دورة حين يُفتح.
class NFoldArrow extends StatelessWidget {
  const NFoldArrow({super.key, required this.open, this.size = 16});

  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: const Duration(milliseconds: 150),
      child: Icon(Icons.keyboard_arrow_down_rounded, size: size + 2, color: Noon.muted),
    );
  }
}

/// قسم مطوي برأس يلخّص حاله: العنوان وعدده وجملة قصيرة وسهم. يُفتح على آخر [limit] صفوف
/// و«عرض الكل».
class NFold extends StatefulWidget {
  const NFold({
    super.key,
    required this.title,
    required this.count,
    required this.rows,
    this.summary,
    this.defaultOpen = false,
    this.head,
    this.limit = 3,
  });

  final String title;
  final int count;
  final String? summary;
  final bool defaultOpen;
  final List<Widget> rows;
  final Widget? head;
  final int limit;

  @override
  State<NFold> createState() => _NFoldState();
}

class _NFoldState extends State<NFold> {
  late bool open = widget.defaultOpen;
  bool all = false;

  @override
  void didUpdateWidget(covariant NFold old) {
    super.didUpdateWidget(old);
    if (widget.defaultOpen && !old.defaultOpen) open = true;
  }

  @override
  Widget build(BuildContext context) {
    final shown = all ? widget.rows : widget.rows.take(widget.limit).toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: nPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => open = !open),
              highlightColor: Noon.mist2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: widget.title, style: nText(14, weight: FontWeight.w700)),
                            TextSpan(text: ' (${widget.count})', style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
                            if (widget.summary != null)
                              TextSpan(text: '  · ${widget.summary}', style: nText(11, color: Noon.muted)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    NFoldArrow(open: open),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Noon.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?widget.head,
                  NDivided(children: shown),
                  if (widget.rows.length > widget.limit && !all)
                    NShowAll(label: 'عرض الكل (${widget.rows.length})', onTap: () => setState(() => all = true)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── الصفحة الداخلية ──────────────────────────────────────────────────────────

/// ترويسة صفحة داخلية (`NPage`): شريط بالحبر 56 وتحته خط رفيع بلون الإجراء، ورجوع
/// والعنوان 16 عريض وسطره الفرعي 12 مخفف.
class NPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const NPageHeader({super.key, required this.title, this.subtitle = '', this.onBack, this.actions = const []});

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: Noon.ink,
        border: Border(bottom: BorderSide(color: Noon.action, width: 2)),
      ),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
          child: Row(
            children: [
              Tooltip(
                message: 'رجوع',
                child: InkWell(
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(NoonRadius.btn),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    // سهم «رجوع» يشير لليمين في العربية (ArrowRight)
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: Noon.onInk),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(16, weight: FontWeight.w700, color: Noon.onInk)),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(12, weight: FontWeight.w500, color: Noon.onInkSoft),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// صفحة تغطي الشاشة بزر رجوع وتذييل ثابت (`NPage`): المحتوى بهامش 16 وفراغ 16 بين أقسامه.
class NPageScaffold extends StatelessWidget {
  const NPageScaffold({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.children,
    this.footer,
    this.onBack,
    this.actions = const [],
    this.body,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  /// بدل [children]: محتوى يدير تمريره بنفسه (المحادثة).
  final Widget? body;
  final Widget? footer;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Noon.paper,
      appBar: NPageHeader(title: title, subtitle: subtitle, onBack: onBack, actions: actions),
      body: DefaultTextStyle.merge(
        style: nText(14),
        child: Column(
          children: [
            Expanded(
              child: body ??
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [NColumn(children: children)],
                  ),
            ),
            if (footer != null)
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottom > 12 ? bottom : 12),
                decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Noon.line))),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

// ── شريط الحفظ ───────────────────────────────────────────────────────────────

/// أين استقر آخر حفظ: عند المدرسة، أو على الجهاز فقط.
enum NSavedWhere { school, device, failed }

/// شريط حفظ: عدد ما لم يُحفظ، وزر الحفظ بلون الإجراء معطّل ما دام لا تغيير، ثم حالة آخر حفظ بوقتها.
class NSaveBar extends StatelessWidget {
  const NSaveBar({
    super.key,
    required this.changes,
    required this.saveLabel,
    required this.onSave,
    this.saving = false,
    this.blocked,
    this.savedAt,
    this.savedWhere = NSavedWhere.school,
    this.offline = false,
    this.extra,
    this.flat = false,
  });

  final int changes;
  final String saveLabel;
  final VoidCallback onSave;
  final bool saving;
  final String? blocked;
  final DateTime? savedAt;
  final NSavedWhere savedWhere;
  final bool offline;
  final Widget? extra;

  /// في تذييل صفحة (حد `line`)، وإلا لاصق بحد الحبر.
  final bool flat;

  static String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    Widget main;
    String? sub;
    if (blocked != null) {
      main = Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: Noon.red700),
          const SizedBox(width: 6),
          Flexible(child: Text(blocked!, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(14, weight: FontWeight.w700, color: Noon.red700))),
        ],
      );
    } else if (changes > 0) {
      main = Text('$changes لم يُحفظ', maxLines: 1, style: nText(14, weight: FontWeight.w700));
      if (offline) sub = 'بلا اتصال: يُحفظ على الجهاز ويُرفع عند الاتصال';
    } else if (savedAt != null) {
      final device = savedWhere != NSavedWhere.school;
      final c = device ? Noon.warn : Noon.green700;
      main = Row(
        children: [
          Icon(Icons.check_rounded, size: 16, color: c),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${device ? 'محفوظ على الجهاز' : 'حُفظ'} ${_clock(savedAt!)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nText(14, weight: FontWeight.w700, color: c),
            ),
          ),
        ],
      );
      if (savedWhere == NSavedWhere.device) sub = 'يُرفع عند الاتصال';
      if (savedWhere == NSavedWhere.failed) sub = 'تعذّر الرفع للمدرسة، سيُعاد لاحقاً';
    } else {
      main = Text('لا تغييرات', style: nText(14, weight: FontWeight.w700, color: Noon.muted));
    }
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(NoonRadius.panel),
        border: Border.all(color: flat ? Noon.line : Noon.ink),
        boxShadow: nShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                main,
                if (sub != null)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(11, weight: FontWeight.w500, color: Noon.muted)),
              ],
            ),
          ),
          if (extra != null) ...[const SizedBox(width: 8), extra!],
          const SizedBox(width: 8),
          NBtn(
            tone: NBtnTone.sun,
            icon: Icons.check_rounded,
            label: saveLabel,
            busy: saving,
            onTap: changes == 0 || blocked != null ? null : onSave,
          ),
        ],
      ),
    );
  }
}

// ── الصور الشخصية ────────────────────────────────────────────────────────────

/// حرف الاسم الأول في دائرة بتظليل `mist` ونص `teal-d` (أو بالحبر إن كان [on]).
class NInitial extends StatelessWidget {
  const NInitial({super.key, required this.name, this.size = 24, this.fontSize = 11, this.on = false, this.icon = Icons.person_outline_rounded});

  final String name;
  final double size;
  final double fontSize;
  final bool on;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final fg = on ? Noon.onInk : Noon.tealD;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: on ? Noon.ink : Noon.mist, shape: BoxShape.circle),
      child: t.isEmpty
          ? Icon(icon, size: size * 0.55, color: fg)
          : Text(t.characters.first, style: nText(fontSize, weight: FontWeight.w700, color: fg, height: 1)),
    );
  }
}
