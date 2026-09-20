import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/portal.dart';
import '../data/printing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';

/// ترويسة مضغوطة + شريط سفلي + وصل — هوية الجوال لبوابة الطالب/ولي الأمر.


/// عنصر تنقّل سفلي.
class PortalNavItem {
  const PortalNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.activeIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

/// ترويسة البوابة: شعار المدرسة، واسم صاحب الحساب (أو اسم المدرسة إن وُجدت
/// تفاصيل تحته)، والخروج — بدل ترويسة وبطاقة منفصلتين.
class PortalChromeHeader extends StatelessWidget {
  const PortalChromeHeader({
    super.key,
    required this.branding,
    required this.roleLabel,
    required this.displayName,
    required this.gradeLine,
    required this.onExit,
    this.nationalId = '',
    this.action,
  });

  final PortalBranding branding;
  final String roleLabel;
  final String displayName;
  final String gradeLine;
  final VoidCallback onExit;
  final String nationalId;

  /// زر يسبق زر الخروج — المزامنة في بوابة المعلم، كترويسة الإدارة.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final details = [
      if (gradeLine.trim().isNotEmpty) gradeLine.trim(),
      if (nationalId.trim().isNotEmpty) nationalId.trim(),
      if (roleLabel.trim().isNotEmpty) roleLabel.trim(),
    ].join('  ·  ');
    // بلا تفاصيل (بوابة المعلم): الاسم بجانب الشعار يستغل عرض الترويسة
    // بدل سطر فارغ تحتها. مع التفاصيل (طالب/ولي أمر): اسم المدرسة فوق والاسم تحته.
    final nameBesideLogo = details.isEmpty;
    final title = nameBesideLogo ? displayName : branding.name;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppColors.navy, AppColors.navyMid],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -30,
            top: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, top + 10, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    InstitutionBadge(logo: branding.logo, size: 32, radius: 10, onDark: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white.withValues(alpha: nameBesideLogo ? 1 : 0.92),
                          fontSize: nameBesideLogo ? 16 : 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ?action,
                    IconButton(
                      tooltip: 'خروج',
                      onPressed: onExit,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.logout_rounded, size: 19, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
                if (!nameBesideLogo) ...[
                  const SizedBox(height: 8),
                  // الاسم وتفاصيله في سطر واحد يمتدّ بعرض الترويسة، وينكسر إلى
                  // سطر ثانٍ عند الحاجة فقط — لا سطر شبه فارغ تحت كل سطر
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Text.rich(
                      TextSpan(
                        text: displayName,
                        style: const TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                        children: [
                          TextSpan(
                            text: '  ·  $details',
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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

/// سطر هوية: مرحلة · شعبة بلا تكرار كلمة «شعبة».
String portalGradeLine({
  required PortalUser user,
  Student? student,
}) {
  final grade = user.gradeLevel.trim().isNotEmpty
      ? user.gradeLevel.trim()
      : (student?.gradeLevel.trim().isNotEmpty ?? false)
          ? student!.gradeLevel.trim()
          : '';
  final rawSection = user.section.trim().isNotEmpty ? user.section.trim() : (student?.section.trim() ?? '');
  final section = rawSection.isEmpty
      ? ''
      : (rawSection.startsWith('شعبة') ? rawSection : 'شعبة $rawSection');
  if (grade.isEmpty && section.isEmpty) return '';
  if (grade.isEmpty) return section;
  if (section.isEmpty) return grade;
  return '$grade · $section';
}

/// شريط تنقّل سفلي بهوية الشل.
class PortalBottomNav extends StatelessWidget {
  const PortalBottomNav({
    super.key,
    required this.items,
    required this.activeId,
    required this.onSelect,
  });

  final List<PortalNavItem> items;
  final String activeId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(top: 4, bottom: bottom > 0 ? bottom : 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            // فاصل رفيع بين كل قسمين، كشريط الإدارة
            if (i > 0) Container(width: 1, height: 28, color: AppColors.line),
            Expanded(
              child: _PortalNavTile(
                item: items[i],
                active: items[i].id == activeId,
                onTap: () => onSelect(items[i].id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortalNavTile extends StatelessWidget {
  const _PortalNavTile({required this.item, required this.active, required this.onTap});

  final PortalNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = active ? (item.activeIcon ?? item.icon) : item.icon;
    return PressableScale(
      scale: 0.96,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: active ? AppColors.amber : AppColors.faint,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppText.family,
                color: active ? AppColors.amber : AppColors.faint,
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// فتح مادة دراسية عبر رابط موقَّع إن لزم.
Future<void> openPortalMaterial(
  BuildContext context,
  String url, {
  PortalService service = const PortalService(),
}) async {
  final target = await service.materialOpenUrl(url);
  if (!context.mounted) return;
  if (target == null || target.isEmpty) {
    showAppSnack(context, 'تعذّر فتح الملف', error: true);
    return;
  }
  var ok = false;
  final uri = Uri.tryParse(target.trim());
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) showAppSnack(context, 'تعذّر فتح الرابط', error: true);
}

/// سند القبض بهوية الجوال.
/// سند القبض كما يُطبع في الإدارة: ورقة مؤطّرة بترويسة المدرسة ورقم السند
/// وتاريخه، ثم بنوده، وتوقيع المستلم — لا مجرد بيانات في أسطر.
class PortalReceiptSheet extends StatelessWidget {
  const PortalReceiptSheet({
    super.key,
    required this.payment,
    required this.student,
    required this.branding,
  });

  final Payment payment;
  final Student student;
  final PortalBranding branding;

  @override
  Widget build(BuildContext context) {
    final p = payment;

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ),
              Expanded(
                child: Text(
                  v,
                  style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'سند قبض',
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: AppColors.heading,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.faint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            // الورقة المؤطّرة — نفس سند الإدارة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: AppColors.navy, width: 1.4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      InstitutionBadge(logo: branding.logo, size: 36, radius: Corner.box, onDark: false),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              branding.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppText.family,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.heading,
                              ),
                            ),
                            const Text('سند قبض مالي', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            p.receiptNumber,
                            style: TextStyle(
                              fontFamily: AppText.family,
                              fontWeight: FontWeight.w800,
                              color: AppColors.amber,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(formatDate(p.date), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.line),
                  const SizedBox(height: 8),
                  row('وصلنا من', student.fullName),
                  if (student.gradeLevel.trim().isNotEmpty) row('المرحلة', student.gradeLevel.trim()),
                  row('المبلغ المقبوض', money(p.amount)),
                  // «وقدره كتابةً» بند رسمي في السند لا يجوز إسقاطه
                  row('وقدره كتابةً', amountInArabicWords(p.amount)),
                  if (p.discountAmount.abs() > 0)
                    row(
                      'الخصم',
                      '-${money(p.discountAmount.abs())}'
                          '${p.discountReason.isEmpty ? '' : ' (${p.discountReason})'}',
                    ),
                  row('طريقة السداد', branding.methodLabel(p.method)),
                  row('وذلك عن', paymentPurposeNames[p.purpose] ?? p.purpose),
                  if (p.senderName.isNotEmpty) row('اسم المحول منه', p.senderName),
                  if (p.reference.isNotEmpty) row('الرقم المرجعي', p.reference),
                  if (p.notes.trim().isNotEmpty) row('البيان', p.notes.trim()),
                  const SizedBox(height: 6),
                  const Divider(color: AppColors.line),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'المستلم: ${p.receivedByName.trim().isEmpty ? branding.name : p.receivedByName.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'التوقيع: ............',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                  if (p.cancelled)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: StatusChip(
                        label: 'هذا السند ملغى',
                        fg: Color(0xFF991B1B),
                        bg: Color(0xFFFEE2E2),
                        border: Color(0xFFFECACA),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showPortalReceipt({
  required BuildContext context,
  required Payment payment,
  required Student student,
  required PortalBranding branding,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
    ),
    builder: (_) => PortalReceiptSheet(payment: payment, student: student, branding: branding),
  );
}
