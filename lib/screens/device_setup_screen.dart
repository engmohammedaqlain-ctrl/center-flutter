import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/auth_frame.dart';
import '../widgets/widgets.dart';

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

  /// أُكملت التهيئة ببيانات محلية لأن السحابة تعذّرت.
  bool offline = false;

  String? selectedUserId;
  final password = TextEditingController();

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

  Future<void> _performInitialSync() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      syncError = null;
    });

    final store = StoreScope.of(context);
    try {
      final pulled = await store.initialPull();
      if (!mounted) return;
      final candidates = store.setupCandidates;
      setState(() {
        pulledCount = pulled;
        offline = false;
        selectedUserId = candidates.first.id;
        loading = false;
      });
    } catch (e) {
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

  Future<void> _finish(AppStore store, AppUser user) async {
    setState(() => passwordError = null);

    // كلمة مرور المدير مطلوبة لكل الأدوار — تمنع تعيين جهاز بلا تصريح.
    // مطابق لـ `handleFinishSetup` في NewDeviceSetupModal.tsx
    if (!store.isAdminSetupPasswordValid(password.text)) {
      setState(() => passwordError = 'كلمة مرور المدير غير صحيحة');
      return;
    }

    setState(() => submitting = true);
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
    final name = store.institutionName.trim().isNotEmpty ? store.institutionName : (store.currentTenant?.name ?? '');

    return AuthFrame(
      title: name,
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

  Widget _loading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'جاري تنزيل بيانات المركز من السحابة...',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.heading, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'يتم جلب الطلاب والصفوف والسجلات وحسابات المستخدمين للبدء.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _error() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.danger, size: 30),
        const SizedBox(height: 12),
        Text(
          'تعذر تنزيل البيانات من السحابة',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.heading, fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          syncError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 16),
        AuthSubmitButton(label: 'إعادة المحاولة', icon: Icons.refresh, onTap: _performInitialSync),
      ],
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
        AppDropdown<String>(
          value: selected.id,
          items: [
            for (final u in candidates)
              DropdownMenuItem(
                value: u.id,
                child: Text('${u.name}  (${u.role == 'admin' ? 'مدير' : 'سكرتير'})'),
              ),
          ],
          onChanged: (v) => setState(() {
            selectedUserId = v;
            passwordError = null;
            password.clear();
          }),
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
    return Center(
      child: PressableScale(
        onTap: () => store.logout(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 15, color: AppColors.muted),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'العودة لتسجيل الدخول',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
