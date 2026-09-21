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

/// تهيئة الجهاز الجديد — المقابل لـ `NewDeviceSetupModal` في النسخة المكتبية.
///
/// تسبق أي شاشة عمل: تسحب بيانات المنشأة من السحابة، ثم تُلزم بتحديد
/// المستخدم المثبَّت على الجهاز — وهو ما يحدد الصلاحيات واسم المستلم على
/// سندات القبض. بدونها كان أي جهاز يعمل بصلاحية مدير كاملة بلا هوية.
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

  String? selectedUserId;
  final password = TextEditingController();
  final _notifier = defaultDownloadNotifier();
  static const _noticeTitle = 'تهيئة الجهاز';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _performInitialSync());
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
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
        selectedUserId = store.setupCandidates.first.id;
      });
      unawaited(_refreshInBackground(store));
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
        pulled > 0
            ? 'اكتمل التنزيل — $pulled سجلاً. افتح التطبيق لاختيار الهوية.'
            : 'اكتمل التنزيل. افتح التطبيق لاختيار الهوية.',
        title: _noticeTitle,
      );
      if (!mounted) return;
      final candidates = store.setupCandidates;
      setState(() {
        pulledCount = pulled;
        progressPercent = 100;
        offline = false;
        selectedUserId = candidates.first.id;
        loading = false;
      });
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
          selectedUserId = store.setupCandidates.first.id;
          loading = false;
        });
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

  Future<void> _finish(AppStore store, AppUser user) async {
    setState(() => passwordError = null);

    // كلمة مرور المدير مطلوبة لكل الأدوار — تمنع تعيين جهاز بلا تصريح.
    // مطابق لـ `handleFinishSetup` في NewDeviceSetupModal.tsx
    setState(() => submitting = true);
    if (!await store.verifyAdminSetupPassword(password.text)) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        passwordError = 'كلمة مرور المدير غير صحيحة';
      });
      return;
    }

    try {
      await store.completeInitialSetup(user);
    } catch (e) {
      // بلا هذا يبقى الزر «جاري التثبيت…» إلى الأبد ولا يدخل المستخدم أبداً
      if (mounted) {
        setState(() => passwordError = e is StoreException ? e.message : 'تعذّر تثبيت هوية الجهاز.');
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

  /// التنزيل الأول: نسبة حقيقية وجدول جارٍ — ويمكن تصغير التطبيق والإشعار يتابع.
  Widget _loading() {
    final pct = progressPercent.clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // النسبة تصل من المزامنة دفعةً عند اكتمال كل جدول، فتقفز 5 نقاط مرة
          // واحدة. تُعرض منزلقةً إلى قيمتها الجديدة: ما يراه المستخدم تقدّمٌ
          // متصل لا قفزات، والرقم نفسه هو الرقم الحقيقي.
          SizedBox(
            width: 72,
            height: 72,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct / 100),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOut,
              builder: (context, value, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: pct <= 0 ? null : value,
                      strokeWidth: 3.5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.hover,
                      color: AppColors.amber,
                    ),
                  ),
                  Text(
                    '${(value * 100).round()}%',
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: AppColors.heading,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'جاري تنزيل بيانات المنشأة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppText.family,
              color: AppColors.heading,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progressLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.55),
          ),
          if (pulledCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'وُحّد $pulledCount سجلاً حتى الآن',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.faint, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct <= 0 ? null : pct / 100,
              minHeight: 6,
              backgroundColor: AppColors.hover,
              color: AppColors.amber,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(Corner.box),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _step(
                  icon: Icons.check_circle_rounded,
                  label: 'تسجيل الدخول',
                  state: _StepState.done,
                ),
                const SizedBox(height: 10),
                _step(
                  icon: Icons.downloading_rounded,
                  label: pct >= 100 ? 'اكتمل التنزيل' : 'تنزيل الطلاب والصفوف والمالية ($pct%)',
                  state: pct >= 100 ? _StepState.done : _StepState.active,
                ),
                const SizedBox(height: 10),
                _step(
                  icon: Icons.badge_outlined,
                  label: 'اختيار هوية الجهاز',
                  state: _StepState.pending,
                ),
              ],
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

  Widget _step({required IconData icon, required String label, required _StepState state}) {
    final Color color;
    final Color bg;
    switch (state) {
      case _StepState.done:
        color = AppColors.success;
        bg = AppColors.successSoft;
      case _StepState.active:
        color = AppColors.amberDark;
        bg = AppColors.amberSoft;
      case _StepState.pending:
        color = AppColors.faint;
        bg = Colors.white;
    }
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: state == _StepState.pending ? AppColors.line : color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppText.family,
              color: state == _StepState.pending ? AppColors.muted : AppColors.heading,
              fontSize: 12.5,
              fontWeight: state == _StepState.pending ? FontWeight.w600 : FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ],
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
              fontWeight: FontWeight.w800,
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

  Widget _form(AppStore store) {
    final candidates = store.setupCandidates;
    final selected = candidates.where((u) => u.id == selectedUserId).firstOrNull ?? candidates.first;
    final isAdmin = selected.role == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _status(),
        const SizedBox(height: 16),
        authLabel('المستخدم على هذا الجهاز:'),
        const SizedBox(height: 6),
        // بطاقة لكل مستخدم بدل قائمة منسدلة: الاختيار هنا يحدد صلاحية الجهاز
        // واسم المستلم على السندات، فيستحق أن يُرى كاملاً قبل اللمس
        for (final u in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _UserOption(
              user: u,
              selected: u.id == selected.id,
              onTap: () => setState(() {
                selectedUserId = u.id;
                passwordError = null;
                password.clear();
              }),
            ),
          ),
        const SizedBox(height: 14),
        authLabel('كلمة مرور المدير الرئيسية:'),
        const SizedBox(height: 6),
        TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          onChanged: (_) {
            if (passwordError != null) setState(() => passwordError = null);
          },
          onSubmitted: (_) => _finish(store, selected),
          style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontFamily: 'monospace'),
          decoration: authFieldDecoration('أدخل كلمة مرور المدير...', Icons.vpn_key_outlined),
        ),
        AuthErrorBox(message: passwordError),
        const SizedBox(height: 8),
        Text(
          'يتطلب تثبيت دور هذا الجهاز (${isAdmin ? 'مدير' : 'سكرتير'}) إدخال كلمة مرور المدير لمنع التعيين غير المصرح به.',
          style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 16),
        AuthSubmitButton(
          label: submitting ? 'جاري التثبيت...' : 'تأكيد وبدء العمل على الجهاز',
          icon: Icons.check_circle_outline,
          busy: submitting,
          onTap: submitting ? null : () => _finish(store, selected),
        ),
      ],
    );
  }

  /// نتيجة السحب في سطر هادئ فوق النموذج.
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

enum _StepState { done, active, pending }

/// خيار مستخدم في التهيئة: الاسم ودوره، وعلامة على المختار.
class _UserOption extends StatelessWidget {
  const _UserOption({required this.user, required this.selected, required this.onTap});

  final AppUser user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final admin = user.role == 'admin';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.box),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.amberSoft : Colors.white,
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: selected ? AppColors.amber : AppColors.line),
        ),
        child: Row(
          children: [
            Icon(
              admin ? Icons.shield_outlined : Icons.badge_outlined,
              size: 17,
              color: selected ? AppColors.amberDark : AppColors.muted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.heading),
                  ),
                  Text(
                    admin ? 'مدير — صلاحية كاملة' : 'سكرتير — صلاحية محدودة',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: AppColors.amberDark),
          ],
        ),
      ),
    );
  }
}
