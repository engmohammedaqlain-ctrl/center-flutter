import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/phone.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';

const _r = BorderRadius.zero;

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: body),
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
        fg: const Color(0xFF9A4F05),
        bg: AppColors.amberSoft,
        border: AppColors.amberBorder,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border ?? bg),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
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

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint, this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12.5),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.faint),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, size: 16, color: AppColors.faint),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
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
    this.height = 36,
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
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.amber,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          disabledForegroundColor: AppColors.faint,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const RoundedRectangleBorder(borderRadius: _r),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        child: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
                  Text(label),
                ],
              ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.heading,
          side: const BorderSide(color: AppColors.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: const RoundedRectangleBorder(borderRadius: _r),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
            Text(label),
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
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.heading),
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
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
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
      shape: const RoundedRectangleBorder(borderRadius: _r),
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
    shape: const RoundedRectangleBorder(borderRadius: _r),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
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

Future<void> launchWa(String phone) async {
  final n = getWhatsAppPhone(phone);
  if (n.isEmpty) return;
  final uri = Uri.parse('https://wa.me/$n');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
