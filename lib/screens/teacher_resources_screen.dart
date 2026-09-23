import 'dart:async';

import 'package:flutter/material.dart';

import '../data/download_notification.dart';
import '../data/portal.dart';
import '../data/portal_offline.dart';
import '../data/store.dart';
import '../data/teacher_resources.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_frame.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';
import 'portal_screens.dart';

/// صفحة تجهيز موارد المعلم — المقابل لـ [DeviceSetupScreen] عند الإدارة.
///
/// أول دخول بلا كاش: تنتظر اكتمال التنزيل بنسبة دقيقة ثم تفتح البوابة.
/// دخول لاحق بكاش: تفتح البوابة فوراً وتحدّث الموارد في الخلفية مع إشعار.
class TeacherResourcesScreen extends StatefulWidget {
  const TeacherResourcesScreen({
    super.key,
    required this.user,
    required this.onExit,
    this.service = const PortalService(),
    this.offline,
  });

  final PortalUser user;
  final Future<void> Function() onExit;
  final PortalService service;
  final PortalOffline? offline;

  @override
  State<TeacherResourcesScreen> createState() => _TeacherResourcesScreenState();
}

class _TeacherResourcesScreenState extends State<TeacherResourcesScreen> {
  bool loading = true;
  String? error;
  int progressPercent = 0;
  String progressLabel = 'جاري الاتصال بالسحابة…';
  String progressDetail = '';
  int records = 0;
  bool _cancelled = false;

  late final PortalOffline _offline = widget.offline ?? PortalOffline(AppStore.instance.db);
  final _notifier = defaultDownloadNotifier();
  static const _noticeTitle = 'موارد المعلم';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_notifier.hide());
    super.dispose();
  }

  void _onProgress(TeacherResourceProgress p) {
    if (!mounted || _cancelled) return;
    setState(() {
      progressPercent = p.percent;
      progressLabel = p.label;
      progressDetail = p.detail;
      records = p.records;
    });
    unawaited(_notifier.show(
      p.detail.isEmpty ? '${p.percent}% — ${p.label}' : '${p.percent}% — ${p.label} ${p.detail}',
      percent: p.percent,
      title: _noticeTitle,
    ));
  }

  Future<void> _openPortal() async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TeacherPortalScreen(
          user: widget.user,
          onExit: widget.onExit,
          service: widget.service,
          offline: _offline,
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (!mounted) return;

    // كاش جاهز: ادخل البوابة فوراً — التحديث الخلفي من داخل البوابة نفسها
    if (teacherResourcesReady(_offline)) {
      await _openPortal();
      return;
    }

    setState(() {
      loading = true;
      error = null;
      progressPercent = 0;
      progressLabel = 'جاري الاتصال بالسحابة…';
      progressDetail = '';
      records = 0;
    });
    unawaited(_notifier.show('بدء تنزيل مواردك…', percent: 0, title: _noticeTitle));

    try {
      await hydrateTeacherResources(
        service: widget.service,
        offline: _offline,
        user: widget.user,
        onProgress: _onProgress,
        isCancelled: () => _cancelled || !mounted,
      );
      if (_cancelled || !mounted) return;
      await _notifier.finish(
        records > 0 ? 'اكتمل التنزيل — $records عنصراً.' : 'اكتمل تجهيز مواردك.',
        title: _noticeTitle,
      );
      if (!mounted) return;
      setState(() {
        progressPercent = 100;
        loading = false;
      });
      await _openPortal();
    } catch (_) {
      await _notifier.hide();
      if (!mounted || _cancelled) return;
      setState(() {
        loading = false;
        error = 'تعذّر تنزيل مواردك من السحابة. يلزم اتصال في أول دخول.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return AuthFrame(
      title: store.institutionName.isEmpty ? 'بوابة المعلم' : store.institutionName,
      subtitle: 'تجهيز موارد صفوفك على هذا الجهاز',
      logo: store.institutionLogo,
      children: [
        AuthCard(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: error != null ? _error() : _loading(),
          ),
        ),
        const SizedBox(height: 14),
        _back(),
      ],
    );
  }

  Widget _loading() {
    final pct = progressPercent.clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct / 100),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              final shown = pct <= 0 ? '…' : '${(value * 100).round()}%';
              return Text(
                shown,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppText.family,
                  color: AppColors.navy,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'جاري تنزيل مواردك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppText.family,
              color: AppColors.heading,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            progressLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
          ),
          if (progressDetail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              progressDetail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.faint, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
          if (records > 0) ...[
            const SizedBox(height: 4),
            Text(
              'وُحّد $records عنصراً حتى الآن',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.faint, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct <= 0 ? null : pct / 100,
              minHeight: 6,
              backgroundColor: AppColors.navy.withValues(alpha: 0.08),
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'يمكنك تصغير التطبيق — يظهر إشعار بالنسبة، ويُنبَّهك عند الانتهاء.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _error() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.dangerBorder),
            ),
            child: const Icon(Icons.cloud_off_outlined, color: AppColors.danger, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            'تعذر تنزيل مواردك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppText.family,
              color: AppColors.heading,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.55),
          ),
          const SizedBox(height: 18),
          AuthSubmitButton(label: 'إعادة المحاولة', icon: Icons.refresh, onTap: _start),
        ],
      ),
    );
  }

  Widget _back() {
    return PressableScale(
      onTap: () async {
        _cancelled = true;
        await _notifier.hide();
        await widget.onExit();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'العودة لتسجيل الدخول',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppText.family,
                  color: AppColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
