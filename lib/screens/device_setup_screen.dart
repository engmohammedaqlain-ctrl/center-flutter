import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
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
        selectedUserId = candidates.first.id;
        loading = false;
      });
    } on StoreException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        syncError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        syncError = 'تعذر الاتصال بالسحابة لجلب البيانات.';
      });
    }
  }

  Future<void> _finish(AppStore store, AppUser user) async {
    setState(() => passwordError = null);

    if (user.role == 'admin' && !store.isAdminSetupPasswordValid(password.text)) {
      setState(() => passwordError = 'كلمة المرور غير صحيحة');
      return;
    }

    setState(() => submitting = true);
    await store.completeInitialSetup(user);
    if (!mounted) return;
    setState(() => submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tenantName = store.currentTenant?.name ?? store.institutionName;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
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
              color: AppColors.amberSoft,
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: const Icon(Icons.apartment, color: AppColors.amber, size: 20),
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
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
            color: AppColors.amberSoft,
            border: Border.all(color: AppColors.amberBorder),
          ),
          child: const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.amber),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
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
            color: AppColors.successSoft,
            border: Border.all(color: AppColors.successBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم تنزيل البيانات بنجاح ($pulledCount سجل).',
                  style: const TextStyle(color: Color(0xFF166534), fontSize: 12, fontWeight: FontWeight.w700),
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
        if (isAdmin) ...[
          const SizedBox(height: 12),
          const FieldLabel('كلمة مرور الإدارة:'),
          TextField(
            controller: password,
            obscureText: true,
            autofocus: true,
            onChanged: (_) {
              if (passwordError != null) setState(() => passwordError = null);
            },
            onSubmitted: (_) => _finish(store, selected),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'أدخل كلمة مرور',
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
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '* يتطلب تثبيت صلاحيات المدير على هذا الجهاز إدخال كلمة المرور.',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.6),
                children: [
                  const TextSpan(text: 'سيتم تثبيت الجهاز باسم '),
                  TextSpan(
                    text: selected.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading),
                  ),
                  const TextSpan(text: ' كـ '),
                  const TextSpan(text: 'سكرتير', style: TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' وتصدر سندات القبض باسمه دون الحاجة لكلمة مرور.'),
                ],
              ),
            ),
          ),
        ],
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
