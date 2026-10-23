import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/portal.dart';
import '../data/printing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/home_shortcut.dart';
import '../widgets/noon_ui.dart';
import '../widgets/widgets.dart';
import 'app_update_sheet.dart';

/// ترويسة نون + شريط سفلي + وصل — هيكل بوابات الطالب وولي الأمر والمعلم.


/// عنصر تنقّل سفلي.
class PortalNavItem {
  const PortalNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.activeIcon,
    this.dot = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData? activeIcon;

  /// نقطة تنبيه: جديد لم يُقرأ (ردود الأهل على «الملاحظات»).
  final bool dot;
}

/// ترويسة البوابة كترويسة كشف رسمي (`NPortalHeader` في الويب): شريط بالحبر عليه شعار
/// المدرسة واسمها وسطر صغير (الدور والاسم) مخففاً، و«تثبيت» و«خروج»، وتحته خط رفيع بلون
/// الإجراء. رقم الهوية لا يُعرض: الشاشة قد تكون مفتوحة أمام الآخرين.
class PortalChromeHeader extends StatelessWidget {
  const PortalChromeHeader({
    super.key,
    required this.branding,
    required this.sub,
    required this.onExit,
    this.action,
  });

  final PortalBranding branding;

  /// السطر الصغير تحت اسم المدرسة: «المعلم: …»، «ولي الأمر: …»، أو اسم الطالب وصفه.
  final String sub;
  final VoidCallback onExit;

  /// إجراء يسبق «تثبيت» و«خروج» — حالة الرفع في بوابة المعلم.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final logo = decodeLogo(branding.logo);
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 12),
      decoration: BoxDecoration(
        color: Noon.ink,
        border: Border(bottom: BorderSide(color: Noon.action, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(NoonRadius.tile),
              border: Border.all(color: Noon.line),
            ),
            child: logo == null
                ? Icon(Icons.school_outlined, size: 20, color: Noon.teal)
                : Image.memory(
                    logo,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    cacheWidth: (36 * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  branding.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nText(14, weight: FontWeight.w700, color: Noon.onInk, height: 1.25),
                ),
                if (sub.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nText(12, weight: FontWeight.w500, color: Noon.onInkSoft),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (action != null) ...[action!, const SizedBox(width: 6)],
          HomeShortcutButton(
            name: branding.name,
            logo: branding.logo,
            builder: (pin) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: NBtn(
                tone: NBtnTone.onDark,
                small: true,
                icon: Icons.download_rounded,
                label: 'تثبيت',
                tooltip: 'أضف للشاشة الرئيسية',
                onTap: pin,
              ),
            ),
          ),
          NBtn(
            tone: NBtnTone.onDark,
            small: true,
            icon: Icons.logout_rounded,
            label: 'خروج',
            onTap: () async {
              if (await confirmLogout(context)) onExit();
            },
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

/// الشريط السفلي (`NBottomNav` في الويب): حد علوي وظل صاعد خفيف وفاصل رفيع بين الخانات،
/// أيقونة 24 وتسمية 11، والنشط بمستطيل مظلّل بـ `mist` خلف الأيقونة وتسمية عريضة بلون
/// العنصر النشط، والباقي خافت، وتبديل فوري. هامش الآيفون في حشوته.
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // يظهر وأنت داخل البوابة — بلا انتظار الخروج لشاشة الدخول
        const UpdateStatusStrip(),
        if (items.length > 1)
          Container(
            padding: EdgeInsets.only(top: 4, bottom: bottom > 4 ? bottom : 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Noon.line)),
              boxShadow: const [BoxShadow(color: Color(0x140A3336), blurRadius: 14.7, offset: Offset(0, -6))],
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Container(width: 1, height: 28, color: Noon.line),
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
          ),
      ],
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
    final color = active ? Noon.teal : Noon.muted;
    return PressableScale(
      scale: 0.95,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active ? Noon.mist : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(active ? (item.activeIcon ?? item.icon) : item.icon, size: 24, color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nText(11, weight: active ? FontWeight.w700 : FontWeight.w500, color: color, height: 1),
                    ),
                  ],
                ),
              ),
              if (item.dot)
                PositionedDirectional(
                  top: 6,
                  end: box.maxWidth * 0.28,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Noon.action,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool portalLooksLikeImage(String url, {String fileName = ''}) {
  final name = fileName.toLowerCase();
  if (RegExp(r'\.(jpe?g|png|webp|gif)$').hasMatch(name)) return true;
  final path = url.toLowerCase().split('?').first;
  return RegExp(r'\.(jpe?g|png|webp|gif)$').hasMatch(path);
}

bool _looksLikeImage(String url, {String fileName = ''}) =>
    portalLooksLikeImage(url, fileName: fileName);

/// أيقونة نوع الملف — بدل معاينة الصورة: تنزيلها لكل طالب عند فتح الوحدة كان
/// يستهلك نقل ملفات المدرسة. يُفتح الملف باللمس فقط.
IconData portalMaterialIcon(CourseItem item) {
  if (item.type == 'link') return Icons.open_in_new_rounded;
  final name = (item.fileName.isNotEmpty ? item.fileName : item.contentUrl.split('?').first).toLowerCase();
  if (portalLooksLikeImage(item.contentUrl, fileName: item.fileName)) return Icons.image_outlined;
  if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (RegExp(r'\.docx?$').hasMatch(name)) return Icons.description_outlined;
  if (RegExp(r'\.pptx?$').hasMatch(name)) return Icons.slideshow_outlined;
  if (RegExp(r'\.xlsx?$').hasMatch(name)) return Icons.table_chart_outlined;
  return Icons.insert_drive_file_outlined;
}

/// فتح مادة دراسية داخل التطبيق قدر الإمكان (صورة / تبويب داخلي)، لا المتصفح الخارجي.
Future<void> openPortalMaterial(
  BuildContext context,
  String url, {
  PortalService service = const PortalService(),
  String fileName = '',
}) async {
  final target = await service.materialOpenUrl(url);
  if (!context.mounted) return;
  if (target == null || target.isEmpty) {
    showAppSnack(context, 'تعذّر فتح الملف', error: true);
    return;
  }

  final polished = polishExternalLink(target);
  final isStorage = PortalService.materialPath(url) != null;

  if (_looksLikeImage(polished, fileName: fileName) ||
      (isStorage && _looksLikeImage(url, fileName: fileName))) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => _InAppImageViewer(url: polished),
    );
    return;
  }

  final uri = Uri.tryParse(polished);
  if (uri == null) {
    showAppSnack(context, 'تعذّر فتح الرابط', error: true);
    return;
  }

  // PDF الموقَّع وروابط يوتيوب/درايف: تبويب داخل التطبيق (Custom Tabs / SFSafari)
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.inAppWebView);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) showAppSnack(context, 'تعذّر فتح الرابط', error: true);
}

/// معاينة صورة داخل التطبيق مع تكبير/تصغير — بلا متصفح خارجي.
class _InAppImageViewer extends StatelessWidget {
  const _InAppImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    );
                  },
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'تعذّر عرض الصورة',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
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
                      fontWeight: FontWeight.w600,
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
                                fontWeight: FontWeight.w600,
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
                              fontWeight: FontWeight.w600,
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
