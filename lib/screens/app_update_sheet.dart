import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_update.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_frame.dart';
import '../widgets/widgets.dart';

/// ورقة التحديث — تُفتح من القائمة السريعة، أو وحدها حين يصل إصدار جديد.
///
/// [checkNow] يفحص الاستضافة فور الفتح: من يفتحها بيده يريد جواباً الآن، لا
/// آخر ما عُرف قبل ساعات.
Future<void> showUpdateSheet(BuildContext context, {bool checkNow = true, AppUpdater? updater}) async {
  final u = updater ?? AppUpdater.instance;
  if (checkNow) unawaited(u.check(force: true));
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: UpdatePanel(updater: u, onLater: () => Navigator.pop(ctx)),
      ),
    ),
  );
  // أُغلقت بلا تثبيت: لا تُعرض وحدها لهذا الإصدار مجدداً، وتبقى في القائمة
  if (u.action == UpdateAction.optional) await u.dismiss();
}

/// شاشة تحجب التطبيق حين لا يعود إصداره صالحاً للعمل مع الخادم.
///
/// بلا «لاحقاً»: إصدارٌ لم تعد السحابة تفهم صيغته يرفع تعديلات تُرفض أو تُفسد،
/// والبيانات المحلية باقية كما هي بعد التثبيت.
class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return AuthFrame(
      title: store.institutionName.isEmpty ? appName : store.institutionName,
      subtitle: 'يلزم تحديث التطبيق للمتابعة',
      logo: store.institutionLogo,
      children: [AuthCard(child: UpdatePanel(updater: AppUpdater.instance))],
    );
  }
}

/// محتوى التحديث المشترك بين الورقة والشاشة الإلزامية.
class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, required this.updater, this.onLater});

  final AppUpdater updater;

  /// `null` في التحديث الإلزامي: لا إغلاق ولا «لاحقاً».
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final u = updater;
        final release = u.release;
        final action = u.action;
        final available = action != UpdateAction.none && release != null;
        final checking = u.phase == UpdatePhase.checking;
        final downloading = u.phase == UpdatePhase.downloading;

        final title = action == UpdateAction.mandatory
            ? 'تحديث مطلوب'
            : available
                ? 'تحديث متاح'
                : checking
                    ? 'جارِ البحث عن تحديث...'
                    : 'التطبيق محدَّث';
        final tone = action == UpdateAction.mandatory
            ? AppColors.danger
            : available
                ? AppColors.success
                : AppColors.info;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Corner.box),
                  ),
                  child: Icon(available ? Icons.system_update : Icons.verified_outlined, size: 20, color: tone),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: TextStyle(color: AppColors.heading, fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        _versionLine(u, available),
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (onLater != null) SquareIconButton(icon: Icons.close, onTap: onLater!),
              ],
            ),

            if (action == UpdateAction.mandatory) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(Corner.box),
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                child: const Text(
                  'هذا الإصدار لم يعد يعمل مع الخادم. ثبّت التحديث لمتابعة العمل — '
                  'بياناتك المحفوظة على الجهاز تبقى كما هي.',
                  style: TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.6),
                ),
              ),
            ],

            if (available && release.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('ما الجديد', style: TextStyle(color: AppColors.heading, fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(Corner.box),
                  border: Border.all(color: AppColors.line),
                ),
                child: SingleChildScrollView(
                  child: Text(release.notes, style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.7)),
                ),
              ),
            ],

            if (downloading) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: u.progress,
                  minHeight: 6,
                  color: AppColors.success,
                  backgroundColor: AppColors.line,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                release?.sizeBytes == null || release!.sizeBytes <= 0
                    ? 'تم تنزيل ${megabytes(u.received)}'
                    : 'تم تنزيل ${megabytes(u.received)} من ${release.sizeLabel}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],

            AuthErrorBox(message: u.error),
            const SizedBox(height: 16),

            Row(
              children: [
                if (onLater != null) ...[
                  Expanded(child: GhostButton(label: available ? 'لاحقاً' : 'إغلاق', onPressed: onLater)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: available
                      ? PrimaryButton(
                          label: downloading
                              ? u.progress == null
                                  ? 'جارِ التنزيل...'
                                  : 'جارِ التنزيل ${(u.progress! * 100).floor()}%'
                              : u.phase == UpdatePhase.ready
                                  ? 'تثبيت الآن'
                                  : release.sizeLabel.isEmpty
                                      ? 'تنزيل وتثبيت'
                                      : 'تنزيل وتثبيت (${release.sizeLabel})',
                          icon: u.phase == UpdatePhase.ready ? Icons.install_mobile : Icons.download,
                          color: AppColors.success,
                          busy: downloading,
                          onPressed: downloading ? null : () => unawaited(u.install()),
                        )
                      : PrimaryButton(
                          label: checking ? 'جارِ الفحص...' : 'فحص التحديثات',
                          icon: Icons.refresh,
                          busy: checking,
                          onPressed: checking ? null : () => unawaited(u.check(force: true)),
                        ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _versionLine(AppUpdater u, bool available) {
    final installed = u.installedName.isEmpty ? '' : 'المثبَّت ${u.installedName}';
    final release = u.release;
    if (!available || release == null) return installed.isEmpty ? 'تطبيق الجوال' : installed;
    final next = 'الجديد ${release.versionName}';
    return installed.isEmpty ? next : '$installed ← $next';
  }
}
