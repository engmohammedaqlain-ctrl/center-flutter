import 'dart:async';

import 'package:flutter/material.dart';

import '../data/download_notification.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/auth_frame.dart';
import '../widgets/widgets.dart';

/// تهيئة الجهاز الجديد — المقابل لـ `NewDeviceSetupModal` في النسخة المكتبية.
///
/// تسبق أي شاشة عمل وتنزّل بيانات المنشأة وحدها: لا اختيار مستخدم ولا كلمة مدير.
/// لكل موظف حسابه يدخل به، وحساب المنشأة يعمل باسم مديرها تلقائياً
/// (`adoptOwnerIdentity`)؛ تعيين «سكرتير» على جهاز المالك كان حماية زائفة.
///
/// بإطار شاشة الدخول نفسه: هي خطوتها الثانية لا نافذة منفصلة.
class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  bool loading = true;
  bool submitting = false;
  String? syncError;
  String? passwordError;
  int pulledCount = 0;

  /// نسبة حقيقية 0–100 من تقدّم السحب.
  int progressPercent = 0;
  String progressLabel = 'جاري الاتصال بالسحابة…';

  /// أُكملت التهيئة ببيانات محلية لأن السحابة تعذّرت.
  bool offline = false;

  /// بيانات المدرسة نفسها كانت على الجهاز، فلم يُنتظر تنزيل جديد.
  bool reusedLocal = false;

  final _notifier = defaultDownloadNotifier();
  static const _noticeTitle = 'تهيئة الجهاز';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _performInitialSync());
  }


  void _onPullProgress(PullProgress p) {
    if (mounted) {
      setState(() {
        progressPercent = p.percent;
        pulledCount = p.recordsPulled;
        progressLabel = switch (p.phase) {
          PullProgressPhase.fetching => 'تنزيل ${p.tableLabel}…',
          PullProgressPhase.applying => 'حفظ ${p.tableLabel}…',
          PullProgressPhase.finishing => 'إنهاء الحسابات…',
        };
      });
    }
    unawaited(_notifier.show(
      '${p.percent}% — ${p.tableLabel}',
      percent: p.percent,
      title: _noticeTitle,
    ));
  }

  Future<void> _performInitialSync() async {
    if (!mounted) return;
    final store = StoreScope.of(context);

    // تبديل المستخدم داخل المدرسة نفسها: البيانات على الجهاز، فتُفتح قائمة
    // المستخدمين فوراً ويُحدَّث ما تغيّر في الخلفية بلا شاشة انتظار
    if (store.hasLocalTenantData) {
      setState(() {
        reusedLocal = true;
        loading = false;
        syncError = null;
      });
      unawaited(_refreshInBackground(store));
      await _complete(store);
      return;
    }

    setState(() {
      loading = true;
      syncError = null;
      progressPercent = 0;
      progressLabel = 'جاري الاتصال بالسحابة…';
      pulledCount = 0;
    });
    unawaited(_notifier.show('بدء تنزيل بيانات المنشأة…', percent: 0, title: _noticeTitle));

    try {
      final pulled = await store.initialPull(onProgress: _onPullProgress);
      await _notifier.finish(
        pulled > 0 ? 'اكتمل التنزيل — $pulled سجلاً.' : 'اكتمل التنزيل.',
        title: _noticeTitle,
      );
      if (!mounted) return;
      setState(() {
        pulledCount = pulled;
        progressPercent = 100;
        offline = false;
        loading = false;
      });
      await _complete(store);
    } catch (e) {
      await _notifier.hide();
      if (!mounted) return;
      final message = e is StoreException ? e.message : 'تعذر الاتصال بالسحابة لجلب البيانات.';
      // جهاز يحمل بيانات محلية أصلاً يكمل بها: تعذّر السحب لا يمنع تحديد
      // هوية الجهاز، وإلا انحبس من يعيد الدخول بلا اتصال. كلمة مرور المدير
      // تبقى مطلوبة في الحالتين.
      if (store.users.isNotEmpty || store.students.isNotEmpty) {
        setState(() {
          offline = true;
          pulledCount = 0;
          loading = false;
        });
        await _complete(store);
        return;
      }
      setState(() {
        loading = false;
        syncError = message;
      });
    }
  }

  /// تحديثٌ صامت لما تغيّر: فشله لا يمنع المستخدم من المتابعة ببياناته.
  Future<void> _refreshInBackground(AppStore store) async {
    try {
      final pulled = await store.initialPull(onProgress: _onPullProgress);
      if (mounted && pulled > 0) setState(() => pulledCount = pulled);
      await _notifier.hide();
    } catch (_) {
      await _notifier.hide();
      // دون اتصال: البيانات المحفوظة تكفي لاختيار الهوية
    }
  }

  /// بعد التنزيل: هوية الجهاز من الحساب نفسه — موظف دخل بحسابه، أو المالك باسم مديره.
  Future<void> _complete(AppStore store) async {
    if (!mounted) return;
    setState(() {
      passwordError = null;
      submitting = true;
    });
    try {
      await store.adoptOwnerIdentity();
      await store.completeInitialSetup();
    } catch (e) {
      if (mounted) {
        setState(() => passwordError = e is StoreException ? e.message : 'تعذّر إكمال تهيئة الجهاز.');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    return AuthFrame(
      // بلا اسم مدرسة: هويتها لم تصل بعد — هي ما يُنزَّل الآن — وعرض اسمٍ محفوظ
      // على الجهاز كان يُظهر اسم مدرسة أخرى عملت عليه من قبل
      title: 'تهيئة الجهاز',
      subtitle: 'تهيئة النظام لأول مرة على هذا الجهاز',
      logo: store.institutionLogo,
      children: [
        AuthCard(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: loading
                ? _loading()
                : syncError != null
                    ? _error()
                    : _form(store),
          ),
        ),
        if (!submitting) ...[
          const SizedBox(height: 14),
          _backToLogin(store),
        ],
      ],
    );
  }

  /// التنزيل الأول: نسبة واضحة + شريط واحد (بلا دويرة مكرّرة).
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
            'جاري تنزيل بيانات المنشأة',
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
          if (pulledCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'وُحّد $pulledCount سجلاً حتى الآن',
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
          Text(
            'يمكنك تصغير التطبيق — يظهر إشعار بالنسبة، ويُنبَّهك عند الانتهاء.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45),
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
            'تعذر تنزيل البيانات من السحابة',
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
            syncError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.55),
          ),
          const SizedBox(height: 18),
          AuthSubmitButton(label: 'إعادة المحاولة', icon: Icons.refresh, onTap: _performInitialSync),
        ],
      ),
    );
  }

  /// بعد التنزيل: حالة ما نُزّل، والإكمال تلقائي. زر لإعادة المحاولة إن تعذّر.
  Widget _form(AppStore store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _status(),
        AuthErrorBox(message: passwordError),
        const SizedBox(height: 16),
        AuthSubmitButton(
          label: submitting ? 'جاري الإكمال...' : 'بدء العمل على الجهاز',
          icon: Icons.check_circle_outline,
          busy: submitting,
          onTap: submitting ? null : () => _complete(store),
        ),
      ],
    );
  }

  Widget _status() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: offline ? AppColors.amberSoft : AppColors.successSoft,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: offline ? AppColors.amberBorder : AppColors.successBorder),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_outlined : Icons.check_circle_outline,
            size: 16,
            color: offline ? AppColors.amber : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offline
                  ? 'تعذّر الاتصال بالسحابة — المتابعة بالبيانات المحفوظة على الجهاز.'
                  : 'تم تنزيل البيانات بنجاح ($pulledCount سجل).',
              style: TextStyle(color: AppColors.heading, fontSize: 12, fontWeight: FontWeight.w700, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// مخرج من الشاشة في كل حالاتها: من لا يملك كلمة مرور المدير أو لا اتصال
  /// عنده يعود إلى بوابة الدخول بدل أن يُحبس هنا.
  Widget _backToLogin(AppStore store) {
    return PressableScale(
      onTap: () async {
        if (!await confirmLogout(context)) return;
        await _notifier.hide();
        await store.logout();
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
