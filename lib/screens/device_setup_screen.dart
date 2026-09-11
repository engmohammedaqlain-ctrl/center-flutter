import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// تهيئة الجهاز الجديد — المقابل لـ `NewDeviceSetupModal` في النسخة المكتبية.
///
/// تسبق أي شاشة عمل: تسحب بيانات المنشأة من السحابة، ثم تُلزم بتحديد
/// المستخدم المثبَّت على الجهاز — وهو ما يحدد الصلاحيات واسم المستلم على
/// سندات القبض. بدونها كان أي جهاز يعمل بصلاحية مدير كاملة بلا هوية.
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
      // هوية الجهاز، وإلا انحبس من يعيد الدخول بلا اتصال.
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
    final tenantName = store.currentTenant?.name ?? store.institutionName;

    return Scaffold(
      body: Container(
        // خلفية بهوية المنشأة: الحجاب الأسود المسطّح كان يبدو كخطأ في العرض
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.navy, AppColors.navyDark],
          ),
        ),
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Corner.box),
                  color: Colors.white,
                  border: Border.all(color: AppColors.lineStrong),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // شريط تمييز علوي
                    Container(height: 4, color: AppColors.amber),
                    _header(tenantName),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: loading
                          ? _loading()
                          : syncError != null
                              ? _error()
                              : _form(store),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _header(String tenantName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Corner.box),
              color: AppColors.amberSoft,
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: Icon(Icons.apartment, color: AppColors.amber, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                ),
                const Text(
                  'تهيئة النظام لأول مرة على هذا الجهاز',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Corner.box),
              color: AppColors.amberSoft,
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: const Text(
              'تهيئة أولية',
              style: TextStyle(color: Color(0xFFD97706), fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.box),
            color: AppColors.amberSoft,
            border: Border.all(color: AppColors.amberBorder),
          ),
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.amber),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'جاري تنزيل بيانات المركز من السحابة...',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
        ),
        const SizedBox(height: 6),
        const Text(
          'يتم جلب الطلاب والصفوف والسجلات وحسابات المستخدمين للبدء.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.6),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _error() {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.box),
            color: AppColors.dangerSoft,
            border: Border.all(color: AppColors.dangerBorder),
          ),
          child: const Icon(Icons.error_outline, color: AppColors.danger, size: 26),
        ),
        const SizedBox(height: 14),
        const Text(
          'تعذر تنزيل البيانات من السحابة',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF881337)),
        ),
        const SizedBox(height: 6),
        Text(
          syncError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.danger, fontSize: 11.5, height: 1.6),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          expand: true,
          height: 40,
          icon: Icons.refresh,
          label: 'إعادة المحاولة',
          onPressed: _performInitialSync,
        ),
        const SizedBox(height: 8),
        // مخرج من الشاشة: بلا اتصال تتعذّر التهيئة، وبلا هذا الزر يبقى
        // المستخدم محبوساً فيها بلا وسيلة للعودة إلى بوابة الدخول.
        SizedBox(
          width: double.infinity,
          child: GhostButton(
            label: 'العودة لتسجيل الدخول',
            icon: Icons.arrow_back,
            onPressed: () => StoreScope.of(context).logout(),
          ),
        ),
      ],
    );
  }

  Widget _form(AppStore store) {
    final candidates = store.setupCandidates;
    final selected = candidates.where((u) => u.id == selectedUserId).firstOrNull ?? candidates.first;
    final isAdmin = selected.role == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.box),
            color: offline ? AppColors.amberSoft : AppColors.successSoft,
            border: Border.all(color: offline ? AppColors.amberBorder : AppColors.successBorder),
          ),
          child: Row(
            children: [
              Icon(
                offline ? Icons.cloud_off : Icons.check_circle_outline,
                size: 16,
                color: offline ? AppColors.amber : AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  offline
                      ? 'تعذّر الاتصال بالسحابة — سيتم المتابعة بالبيانات المحفوظة على الجهاز.'
                      : 'تم تنزيل البيانات بنجاح ($pulledCount سجل).',
                  style: TextStyle(
                    color: offline ? const Color(0xFF9A4F05) : const Color(0xFF166534),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const FieldLabel('المستخدم على هذا الجهاز:'),
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
        const SizedBox(height: 12),
        const FieldLabel('كلمة مرور المدير الرئيسية:'),
        TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          onChanged: (_) {
            if (passwordError != null) setState(() => passwordError = null);
          },
          onSubmitted: (_) => _finish(store, selected),
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'أدخل كلمة مرور المدير لتأكيد تعيين الجهاز',
            prefixIcon: Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.amber),
          ),
        ),
        if (passwordError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              passwordError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '* يتطلب تثبيت دور هذا الجهاز (${isAdmin ? 'مدير' : 'سكرتير'}) إدخال كلمة مرور المدير لمنع التعيين غير المصرح به.',
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          expand: true,
          height: 42,
          busy: submitting,
          color: AppColors.navy,
          icon: Icons.arrow_forward,
          label: submitting ? 'جاري التثبيت...' : 'تأكيد وبدء العمل على الجهاز',
          onPressed: submitting ? null : () => _finish(store, selected),
        ),
      ],
    );
  }
}
