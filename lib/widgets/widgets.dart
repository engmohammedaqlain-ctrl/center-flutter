import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/permissions.dart';
import '../data/phone.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

final _r = BorderRadius.circular(Corner.field);

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(Corner.card);
    final body = Container(
      width: double.infinity,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: shape,
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: shape,
      child: InkWell(onTap: onTap, borderRadius: shape, child: body),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.fg, required this.bg, this.border});

  final String label;
  final Color fg;
  final Color bg;
  final Color? border;

  factory StatusChip.success(String label) => StatusChip(
        label: label,
        fg: const Color(0xFF166534),
        bg: AppColors.successSoft,
        border: AppColors.successBorder,
      );

  factory StatusChip.danger(String label) => StatusChip(
        label: label,
        fg: const Color(0xFF991B1B),
        bg: AppColors.dangerSoft,
        border: AppColors.dangerBorder,
      );

  factory StatusChip.muted(String label) => StatusChip(
        label: label,
        fg: const Color(0xFF475569),
        bg: const Color(0xFFF1F5F9),
        border: AppColors.line,
      );

  factory StatusChip.amber(String label) => StatusChip(
        label: label,
        fg: AppColors.amber, // `text-[#9A4F05]` يُحال إلى لون العمليات
        bg: AppColors.amberSoft,
        border: AppColors.amberBorder,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Corner.chip),
        border: Border.all(color: border ?? bg),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.3),
      ),
    );
  }
}

class MoneyChip extends StatelessWidget {
  const MoneyChip({super.key, required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context) {
    if (balance == 0) return StatusChip.success('خالص 0 $currency');
    if (balance < 0) return StatusChip.danger('عليه ${money(balance)}');
    return StatusChip(
      label: 'له ${money(balance)}',
      fg: const Color(0xFF1E40AF),
      bg: AppColors.infoSoft,
      border: const Color(0xFFBFDBFE),
    );
  }
}

/// ارتفاع موحّد لأدوات السطر الواحد (بحث، تصفية) كي تتساوى متجاورة.
const controlHeight = 42.0;

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint, this.onChanged, this.trailing});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  /// ما يُعرض في طرف الحقل — كعدد النتائج — بدل سطر مستقل تحته.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final clear = controller.text.isEmpty
        ? null
        : IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: const Icon(Icons.close, size: 16, color: AppColors.faint),
            onPressed: () {
              controller.clear();
              onChanged?.call('');
            },
          );

    return SizedBox(
      height: controlHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12.5),
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        // الحقل يملأ ارتفاعه كاملاً فيُرسم إطاره بالارتفاع نفسه لزر التصفية.
        // بدونها يلتفّ الإطار حول سطر النص فيقصر عن جاره أو يطول بحسب الخط.
        expands: true,
        maxLines: null,
        minLines: null,
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.faint),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIcon: trailing == null
              ? clear
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: trailing),
                    ?clear,
                  ],
                ),
        ),
      ),
    );
  }
}

/// زر تصفية مدمج: أيقونة واسم الاختيار الحالي، ويفتح قائمة الخيارات.
///
/// بديل القائمة المنسدلة بعرض الشاشة حين تشارك البحثَ سطراً واحداً. يتلوّن
/// حين تكون التصفية مفعّلة حتى لا يُنسى أن القائمة مقصوصة.
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.options,
    required this.value,
    required this.onSelected,
    this.maxWidth = 132,
  });

  /// القيمة ← النص المعروض. القيمة الفارغة تعني «الكل».
  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onSelected;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final active = value.isNotEmpty;
    final label = options[value] ?? options[''] ?? '';
    final fg = active ? AppColors.amber : AppColors.text;

    return PopupMenuButton<String>(
      initialValue: value,
      tooltip: 'تصفية',
      position: PopupMenuPosition.under,
      color: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Corner.field))),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem<String>(
            value: e.key,
            height: 40,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: e.key == value ? Icon(Icons.check, size: 16, color: AppColors.amber) : null,
                ),
                Expanded(
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: e.key == value ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: controlHeight,
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: active ? AppColors.amberSoft : Colors.white,
          border: Border.all(color: active ? AppColors.amberBorder : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.filter_alt : Icons.filter_alt_outlined, size: 16, color: fg),
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

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.color,
    this.busy = false,
    this.height = 40,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final Color? color;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      height: height,
      child: ElevatedButton(
        // أثناء العمل يبقى الزر بلونه ويُمنع الضغط وحده
        onPressed: busy ? () {} : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.amber,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          disabledForegroundColor: AppColors.faint,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: _r),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        child: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            // النص لا يطفح حين يضيق الزر: يُقصَّ بنقاط في الزر الممتد، ويصغر قليلاً
            // في الزر الحر — الذي قد لا يعرف عرضاً أقصى داخل صفّ فلا يصلح له القصّ
            : expand
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
                        Text(label),
                      ],
                    ),
                  ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.heading,
          side: const BorderSide(color: AppColors.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: _r),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
        ),
        // يصغر النص قليلاً حين يضيق الزر بدل أن يطفح خارجه
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

/// شعار المنشأة، أو أيقونة افتراضية إن لم يُرفع شعار.
/// فكّ شعار المنشأة المخزّن كـ Base64 (مع بادئة data: أو بدونها).
Uint8List? decodeLogo(String logo) {
  if (logo.isEmpty) return null;
  try {
    final comma = logo.indexOf(',');
    return base64Decode(comma >= 0 ? logo.substring(comma + 1) : logo);
  } catch (_) {
    return null;
  }
}

/// شعار المنشأة داخل إطار أبيض — مطابق لصندوق الشعار في `MobileHeader`.
class InstitutionBadge extends StatelessWidget {
  const InstitutionBadge({
    super.key,
    required this.logo,
    this.size = 32,
    this.radius = 9,
    this.onDark = true,
  });

  final String logo;
  final double size;
  final double radius;

  /// على خلفية داكنة إطار أبيض شفاف؛ على فاتحة إطار رمادي خفيف جداً يُظهر حدود
  /// الشعار الأبيض فلا يذوب في الورقة البيضاء.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeLogo(logo);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: onDark ? Colors.white.withValues(alpha: 0.25) : AppColors.line,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius > 2 ? radius - 2 : 0),
        child: bytes == null
            ? Icon(Icons.school, color: AppColors.amber, size: size * 0.58)
            : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}

/// شاشة "لا تملك صلاحية" — أوضح من إخفاء صامت يُربك المستخدم.
/// مطابقة لمكوّن `NoAccess` في App.tsx.
class NoAccess extends StatelessWidget {
  const NoAccess({super.key, required this.section, required this.roleName});

  final String section;
  final String roleName;

  @override
  Widget build(BuildContext context) {
    final label = sectionLabels[section] ?? section;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corner.box),
                color: AppColors.amberSoft,
                border: Border.all(color: AppColors.amberBorder),
              ),
              child: const Text('🔒', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(height: 12),
            Text(
              'قسم $label غير متاح لصلاحيتك',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                text: 'حسابك على هذا الجهاز مسجَّل بصلاحية ',
                children: [
                  TextSpan(text: roleName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(
                    text: '. للوصول إلى هذا القسم، اطلب من مدير النظام تعديل صلاحيتك من '
                        '«الإعدادات ← المستخدمين والصلاحيات».',
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, color: AppColors.faint, size: 22),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.requiredField = false});
  final String text;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.heading),
          children: [
            if (requiredField) const TextSpan(text: ' *', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({super.key, required this.value, required this.items, required this.onChanged, this.hint});

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final selected = items.any((e) => e.value == value) ? value : null;
    return DropdownButtonFormField<T>(
      key: ValueKey(selected),
      initialValue: selected,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      dropdownColor: Colors.white,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      hint: hint == null ? null : Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.faint)),
      style: const TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w600),
    );
  }
}

class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.bg,
    this.border,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Color? bg;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: bg ?? const Color(0xFFF1F5F9),
          border: Border.all(color: border ?? AppColors.lineStrong),
        ),
        child: Icon(icon, size: 14, color: color ?? AppColors.navy),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

void showAppSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12.5)),
      backgroundColor: error ? AppColors.danger : AppColors.navy,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: _r),
    ),
  );
}

Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  Color confirmColor = AppColors.danger,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: _r),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: confirmLabel,
                    color: confirmColor,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result == true;
}

Future<void> launchTel(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

/// فتح محادثة واتساب برسالة جاهزة — المقابل لـ `wa.me/<n>?text=`.
Future<void> launchWaWithText(String phone, String text) async {
  final n = getWhatsAppPhone(phone);
  if (n.isEmpty) return;
  final uri = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> launchWa(String phone) async {
  final n = getWhatsAppPhone(phone);
  if (n.isEmpty) return;
  final uri = Uri.parse('https://wa.me/$n');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}


/// زر تواصل: الأيقونة وحدها بلا إطار ولا تعبئة، ومساحة لمس مريحة حولها
/// تُظهر تموّجاً دائرياً خفيفاً عند الضغط.
class ContactIconButton extends StatelessWidget {
  const ContactIconButton({super.key, required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 36, height: 36, child: Center(child: child)),
      ),
    );
  }
}

/// فقاعة محادثة دائرية بذيل — مطابقة لأيقونة `MessageCircle` من lucide التي
/// يستعملها Center لزر واتساب، ولا مقابل لها في مكتبة Material.
class MessageCircleIcon extends StatelessWidget {
  const MessageCircleIcon({super.key, required this.color, this.size = 18});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _MessageCirclePainter(color)));
  }
}

class _MessageCirclePainter extends CustomPainter {
  const _MessageCirclePainter(this.color);
  final Color color;

  static const _pi = 3.141592653589793;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // الذيل في أسفل اليسار كما في الأيقونة الأصلية، ولا ينعكس مع الاتجاه
    const tail = 3 * _pi / 4;
    const gap = 0.36;
    final rect = Rect.fromCircle(center: Offset(w * 0.54, h * 0.46), radius: w * 0.40);
    final path = Path()
      ..arcTo(rect, tail + gap, 2 * _pi - 2 * gap, true)
      ..lineTo(w * 0.08, h * 0.92)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MessageCirclePainter old) => old.color != color;
}
