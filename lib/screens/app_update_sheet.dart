import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_update.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_frame.dart';
import '../widgets/widgets.dart';

/// لون الانقطاع والتوقف — ثابت المعنى كالنجاح والخطر، لا يتبع ألوان المنشأة.
const _warning = Color(0xFFB45309);
const _warningSoft = Color(0xFFFEF3C7);

/// ورقة التحديث — تُفتح من القائمة السريعة، أو وحدها حين يصل إصدار جديد.
///
/// [checkNow] يفحص الاستضافة فور الفتح: من يفتحها بيده يريد جواباً الآن، لا
/// آخر ما عُرف قبل ساعات.
Future<void> showUpdateSheet(BuildContext context, {bool checkNow = true, AppUpdater? updater}) async {
  final u = updater ?? AppUpdater.instance;
  if (checkNow) {
    unawaited(u.check(force: true));
    unawaited(u.checkPatch(force: true));
  }
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

        final title = action == UpdateAction.mandatory
            ? 'تحديث مطلوب'
            : available
                ? switch (u.phase) {
                    UpdatePhase.downloading || UpdatePhase.verifying => 'جارِ تنزيل التحديث',
                    UpdatePhase.retrying || UpdatePhase.paused => 'تنزيل التحديث متوقف',
                    UpdatePhase.ready => 'التحديث جاهز للتثبيت',
                    _ => 'تحديث متاح',
                  }
                : u.patchPhase != PatchPhase.none
                    ? 'تحديث في الخلفية'
                    : checking
                        ? 'جارِ البحث عن تحديث...'
                        : u.checkedWithNoUpdate
                            ? 'لا يوجد تحديث'
                            : 'التطبيق محدَّث';
        final tone = action == UpdateAction.mandatory
            ? AppColors.danger
            : available || u.patchPhase != PatchPhase.none
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

            if (available && u.transferring) ...[
              const SizedBox(height: 12),
              DownloadProgressCard(updater: u),
            ] else if (available && release.notes.isNotEmpty) ...[
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

            if (u.patchPhase != PatchPhase.none) ...[
              const SizedBox(height: 12),
              _PatchLine(phase: u.patchPhase),
            ],

            // التوقف يشرح نفسه في بطاقة التنزيل؛ الخطأ هنا لما لا يُستكمل
            AuthErrorBox(message: u.phase == UpdatePhase.paused ? null : u.error),
            const SizedBox(height: 16),

            Row(
              children: [
                if (onLater != null) ...[
                  Expanded(
                    child: GhostButton(
                      // التنزيل يستمر بعد الإغلاق، والشريط أعلى التطبيق يتابعه
                      label: !available ? 'إغلاق' : (u.busy ? 'إخفاء' : 'لاحقاً'),
                      onPressed: onLater,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(flex: 2, child: available ? _actionButton(u, release) : _checkButton(u, checking)),
              ],
            ),
          ],
        );
      },
    );
  }

  static Widget _actionButton(AppUpdater u, AppRelease release) {
    final percent = u.progress == null ? null : (u.progress! * 100).floor();
    return switch (u.phase) {
      UpdatePhase.downloading => PrimaryButton(
          label: percent == null ? 'جارِ التنزيل...' : 'جارِ التنزيل $percent%',
          icon: Icons.download,
          color: AppColors.success,
          busy: true,
          onPressed: null,
        ),
      UpdatePhase.verifying => PrimaryButton(
          label: 'جارِ التحقق...',
          icon: Icons.verified_user_outlined,
          color: AppColors.success,
          busy: true,
          onPressed: null,
        ),
      UpdatePhase.retrying => PrimaryButton(
          label: 'المحاولة الآن',
          icon: Icons.refresh,
          color: _warning,
          onPressed: u.retryNow,
        ),
      UpdatePhase.paused => PrimaryButton(
          label: 'استكمال التنزيل',
          icon: Icons.play_arrow_rounded,
          color: AppColors.success,
          onPressed: () => unawaited(u.install()),
        ),
      UpdatePhase.failed => PrimaryButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh,
          color: AppColors.success,
          onPressed: () => unawaited(u.install()),
        ),
      UpdatePhase.ready => PrimaryButton(
          label: 'تثبيت الآن',
          icon: Icons.install_mobile,
          color: AppColors.success,
          onPressed: () => unawaited(u.install()),
        ),
      _ => PrimaryButton(
          label: release.sizeLabel.isEmpty ? 'تنزيل وتثبيت' : 'تنزيل وتثبيت (${release.sizeLabel})',
          icon: Icons.download,
          color: AppColors.success,
          onPressed: () => unawaited(u.install()),
        ),
    };
  }

  static Widget _checkButton(AppUpdater u, bool checking) => PrimaryButton(
        label: checking ? 'جارِ الفحص...' : 'فحص التحديثات',
        icon: Icons.refresh,
        busy: checking,
        onPressed: checking
            ? null
            : () {
                unawaited(u.check(force: true));
                unawaited(u.checkPatch(force: true));
              },
      );

  static String _versionLine(AppUpdater u, bool available) {
    final installed = u.installedName.isEmpty ? '' : 'المثبَّت ${u.installedName}';
    final release = u.release;
    if (!available || release == null) {
      if (u.checkedWithNoUpdate) {
        return installed.isEmpty ? 'فحصتَ الآن — لا جديد' : '$installed — لا جديد بعد الفحص';
      }
      return installed.isEmpty ? 'تطبيق الجوال' : installed;
    }
    final next = 'الجديد ${release.versionName}';
    return installed.isEmpty ? next : '$installed ← $next';
  }
}

/// بطاقة تنزيل البناء: النسبة والحجم والسرعة والوقت الباقي، وحالة الانقطاع.
class DownloadProgressCard extends StatelessWidget {
  const DownloadProgressCard({super.key, required this.updater});

  final AppUpdater updater;

  @override
  Widget build(BuildContext context) {
    final u = updater;
    final phase = u.phase;
    final interrupted = phase == UpdatePhase.retrying || phase == UpdatePhase.paused;
    final percent = u.progress == null ? null : (u.progress! * 100).floor();
    final tone = interrupted
        ? _warning
        : phase == UpdatePhase.verifying
            ? AppColors.info
            : AppColors.success;
    final (icon, label) = switch (phase) {
      UpdatePhase.retrying => (Icons.wifi_off_rounded, 'انقطع الاتصال — محاولة جديدة خلال ${u.retryIn} ث'),
      UpdatePhase.paused => (Icons.pause_circle_outline, 'التنزيل متوقف'),
      UpdatePhase.verifying => (Icons.verified_user_outlined, 'جارِ التحقق من سلامة الملف...'),
      _ => (Icons.downloading_rounded, 'جارِ التنزيل'),
    };

    final total = u.totalBytes;
    final size = total == null ? megabytes(u.received) : '${megabytes(u.received)} من ${megabytes(total)}';
    final remaining = u.remaining;
    final pace = phase == UpdatePhase.downloading && u.speed > 0
        ? '${megabytes(u.speed.round())}/ث${remaining == null ? '' : ' · باقٍ ${_duration(remaining)}'}'
        : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: interrupted ? _warningSoft.withValues(alpha: 0.5) : AppColors.bg,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: interrupted ? _warning.withValues(alpha: 0.3) : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: tone),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: AppColors.heading, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              if (percent != null)
                Text(
                  '$percent%',
                  style: TextStyle(color: tone, fontSize: 18, fontWeight: FontWeight.w900),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              // التحقق بلا نسبة تُعرف: شريطٌ متحرك بدل ١٠٠٪ ثابتة توحي بالتوقف
              value: phase == UpdatePhase.verifying ? null : u.progress,
              minHeight: 8,
              color: tone,
              backgroundColor: AppColors.line,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(size, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (pace.isNotEmpty) Text(pace, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
          if (interrupted) ...[
            const SizedBox(height: 8),
            const Text(
              'ما نزل محفوظ، ويُستكمل من مكانه.',
              style: TextStyle(color: _warning, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  static String _duration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s ث';
    return '${(s / 60).ceil()} د';
  }
}

class _PatchLine extends StatelessWidget {
  const _PatchLine({required this.phase});

  final PatchPhase phase;

  @override
  Widget build(BuildContext context) {
    final downloading = phase == PatchPhase.downloading;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.successSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: Row(
        children: [
          if (downloading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success),
            )
          else
            const Icon(Icons.check_circle, size: 15, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              patchMessage(phase),
              style: const TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// نص حالة التحديث الصامت.
String patchMessage(PatchPhase phase) => phase == PatchPhase.downloading
    ? 'جارِ تحميل التحديث في الخلفية...'
    : 'التحديث جاهز — يُطبَّق عند فتح التطبيق مرة ثانية';

/// شريطٌ رفيع فوق شريط الأقسام يقول ما يجري للتحديث في الخلفية.
///
/// يظهر حين تُخفى ورقة التحديث والتنزيل مستمر أو متوقف، وحين يُنزَّل تحديثٌ
/// صامت: فلا يبدو التطبيق ساكناً وهو يعمل، ولا يُفاجأ المستخدم بتغيّره بعد
/// إعادة الفتح. لمسُه يفتح الورقة (إلا التحديث الصامت: لا يطلب فعلاً من المستخدم).
class UpdateStatusStrip extends StatelessWidget {
  const UpdateStatusStrip({super.key, this.updater});

  final AppUpdater? updater;

  @override
  Widget build(BuildContext context) {
    final u = updater ?? AppUpdater.instance;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final content = _content(u);
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: content == null
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: content.tone.withValues(alpha: 0.10),
                  child: InkWell(
                    onTap: content.opensSheet ? () => showUpdateSheet(context, checkNow: false, updater: u) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Row(
                        children: [
                          if (content.spinning)
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: content.progress,
                                color: content.tone,
                                backgroundColor: content.progress == null ? null : content.tone.withValues(alpha: 0.2),
                              ),
                            )
                          else
                            Icon(content.icon, size: 15, color: content.tone),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              content.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: content.tone, fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (content.opensSheet) Icon(Icons.chevron_left, size: 16, color: content.tone),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  static _StripContent? _content(AppUpdater u) {
    final percent = u.progress == null ? null : (u.progress! * 100).floor();
    final available = u.action != UpdateAction.none && u.release != null;
    if (available) {
      switch (u.phase) {
        case UpdatePhase.downloading:
          return _StripContent(
            text: percent == null ? 'جارِ تنزيل التحديث...' : 'جارِ تنزيل التحديث $percent%',
            tone: AppColors.success,
            spinning: true,
            progress: u.progress,
          );
        case UpdatePhase.verifying:
          return const _StripContent(text: 'جارِ التحقق من التحديث...', tone: AppColors.info, spinning: true);
        case UpdatePhase.retrying:
          return _StripContent(
            text: 'انقطع الاتصال — محاولة جديدة خلال ${u.retryIn} ث',
            tone: _warning,
            icon: Icons.wifi_off_rounded,
          );
        case UpdatePhase.paused:
          return _StripContent(
            text: percent == null
                ? 'تنزيل التحديث متوقف — اضغط للاستكمال'
                : 'تنزيل التحديث متوقف عند $percent% — اضغط للاستكمال',
            tone: _warning,
            icon: Icons.pause_circle_outline,
          );
        case UpdatePhase.ready:
          return const _StripContent(
            text: 'التحديث جاهز للتثبيت — اضغط للتثبيت',
            tone: AppColors.success,
            icon: Icons.install_mobile,
          );
        default:
          break;
      }
    }
    return switch (u.patchPhase) {
      PatchPhase.downloading => _StripContent(
          text: patchMessage(PatchPhase.downloading),
          tone: AppColors.info,
          spinning: true,
          opensSheet: false,
        ),
      PatchPhase.ready => _StripContent(
          text: patchMessage(PatchPhase.ready),
          tone: AppColors.success,
          icon: Icons.check_circle,
          opensSheet: false,
        ),
      PatchPhase.none => null,
    };
  }
}

class _StripContent {
  const _StripContent({
    required this.text,
    required this.tone,
    this.icon = Icons.info_outline,
    this.spinning = false,
    this.progress,
    this.opensSheet = true,
  });

  final String text;
  final Color tone;
  final IconData icon;
  final bool spinning;
  final double? progress;

  /// التحديث الصامت لا يطلب من المستخدم شيئاً: لا ورقة تُفتح له.
  final bool opensSheet;
}
