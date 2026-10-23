import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/push.dart';
import '../data/store.dart';
import '../data/supabase.dart';
import '../data/tenant_service.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/dev_ui.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';
import 'app_installs_screen.dart';
import 'developer_health_screen.dart';

/// مطابق لـ USERNAME_RULE في دالة السيرفر `admin-tenants`.
const _usernameRule = 'اسم المستخدم: 3 إلى 32 من الأحرف الإنجليزية الصغيرة والأرقام و . _ -';

/// تأكيد حذف منشأة: معرّفها أو كلمة «حذف» — مطابق لنافذة الحذف في
/// DeveloperDashboardPage.
bool tenantDeleteConfirmed(String typed, Tenant t) {
  final value = typed.trim();
  return value.isNotEmpty && (value == t.code.trim() || value == 'حذف');
}

/// بوابة المطور والاشتراكات — المقابل لـ `pages/DeveloperDashboardPage.tsx`.
///
/// المنشآت تُقرأ وتُكتب في Supabase؛ القائمة المحلية احتياط عند انقطاع الاتصال.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  final search = TextEditingController();
  bool loading = false;
  String? notice;

  StreamSubscription<PushNotice>? _alerts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // جهاز المطور تصله إنذارات الأعطال؛ والتطبيق مفتوح لا يعرضها أندرويد فتظهر هنا
    _alerts = ParentPush.instance.received.listen(_showAlert);
    unawaited(ParentPush.instance.register());
  }

  @override
  void dispose() {
    unawaited(_alerts?.cancel());
    search.dispose();
    super.dispose();
  }

  void _showAlert(PushNotice n) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text([n.title, n.body].where((s) => s.isNotEmpty).join('\n'))),
    );
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final ok = await AppStore.instance.refreshTenantsFromCloud();
    if (!mounted) return;
    setState(() {
      loading = false;
      notice = ok ? null : 'تعذّر الاتصال بالسحابة — تُعرض النسخة المحفوظة محلياً.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = search.text.trim();
        final list = store.tenants.where((t) {
          if (q.isEmpty) return true;
          return t.name.contains(q) ||
              t.code.toLowerCase().contains(q.toLowerCase()) ||
              t.username.toLowerCase().contains(q.toLowerCase()) ||
              t.ownerName.contains(q) ||
              t.ownerPhone.contains(q);
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        final live = store.tenants.where((t) => t.active && !t.isDemo).length;
        final now = DateTime.now();
        final soon = store.tenants
            .where((t) => t.active && !t.isDemo && !t.isLifetime && t.expiresAt.difference(now).inDays <= 30)
            .length;

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            children: [
              _header(context, store),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      if (notice != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Corner.box),
                            color: AppColors.warnSoft,
                            border: Border.all(color: const Color(0xFFF5CD47)),
                          ),
                          child: Text(notice!, style: const TextStyle(fontSize: 11.5, color: AppColors.warn)),
                        ),
                      DevHero(
                        label: 'منشآت نشطة',
                        value: '$live',
                        unit: 'من ${store.tenants.length}',
                        chips: [if (soon > 0) '$soon تنتهي خلال شهر'],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SearchField(
                              controller: search,
                              hint: 'بحث',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'تحديث',
                            icon: const Icon(Icons.refresh, color: AppColors.muted, size: 20),
                            onPressed: loading ? null : _refresh,
                          ),
                          const SizedBox(width: 8),
                          PrimaryButton(
                            label: 'منشأة',
                            icon: Icons.add,
                            onPressed: () => _edit(context, null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DevSectionTitle('المنشآت', count: list.length),
                      const SizedBox(height: 8),
                      if (loading && store.tenants.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator(color: AppColors.amber)),
                        )
                      else if (list.isEmpty)
                        const EmptyState(message: 'لا نتائج')
                      else
                        DevPanel(
                          rows: [
                            for (final t in list)
                              _TenantRow(
                                tenant: t,
                                onEdit: () => _edit(context, t),
                                onExtend: () => _extend(context, t),
                                onToggle: () => _toggleStatus(context, t),
                                onEnter: () => _enterTenant(context, t),
                                onDelete: () => _delete(context, t),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, AppStore store) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(14, top + 10, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.navy,
        border: Border(bottom: BorderSide(color: AppColors.amber, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Corner.box),
              color: Colors.white.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.tune, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('بوابة المطور',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          IconButton(
            tooltip: 'المتابعة',
            icon: const Icon(Icons.monitor_heart_outlined, color: Colors.white, size: 20),
            onPressed: () => openDeveloperHealth(context),
          ),
          IconButton(
            tooltip: 'الأجهزة',
            icon: const Icon(Icons.devices_outlined, color: Colors.white, size: 20),
            onPressed: () => openAppInstalls(context),
          ),
          IconButton(
            tooltip: 'خروج',
            icon: Icon(Icons.logout_rounded, color: Colors.white.withValues(alpha: 0.85), size: 19),
            onPressed: () async {
              final ok = await confirmSheet(
                context,
                title: 'تسجيل الخروج',
                message: 'هل ترغب في الخروج من بوابة المطور؟',
                confirmLabel: 'خروج',
              );
              if (ok) await store.logout();
            },
          ),
        ],
      ),
    );
  }

  /// «دخول للمنشأة» — تقمّص المنشأة لمعاينة بياناتها كما يراها موظفوها.
  /// اشتراك منتهٍ لا يمنع — كالويب؛ يظهر شريط التنبيه داخل الشاشة.
  Future<void> _enterTenant(BuildContext context, Tenant t) async {
    final store = StoreScope.of(context);
    final ok = await confirmSheet(
      context,
      title: 'دخول للمنشأة',
      message: 'فتح «${t.name}» بصلاحية المدير.',
      confirmLabel: 'دخول',
    );
    if (!ok || !context.mounted) return;
    final error = await store.enterTenantAsDeveloper(t);
    if (error != null && context.mounted) showAppSnack(context, error, error: true);
  }

  Future<void> _toggleStatus(BuildContext context, Tenant t) async {
    final store = StoreScope.of(context);
    final suspending = t.active;
    final ok = await confirmSheet(
      context,
      title: suspending ? 'إيقاف الاشتراك' : 'تفعيل الاشتراك',
      message: suspending
          ? 'سيُمنع موظفو «${t.name}» من الدخول إلى النظام. هل تريد المتابعة؟'
          : 'سيُعاد تفعيل اشتراك «${t.name}» ويستطيع موظفوها الدخول.',
      confirmLabel: suspending ? 'إيقاف' : 'تفعيل',
    );
    if (!ok || !context.mounted) return;
    final next = !t.active;
    await _update(
      context,
      store,
      t,
      {'status': next ? 'active' : 'suspended'},
      suspending ? 'تم إيقاف الاشتراك' : 'تم تفعيل الاشتراك',
      () => t.active = next,
    );
  }

  Future<void> _extend(BuildContext context, Tenant t) async {
    final store = StoreScope.of(context);
    final months = TextEditingController(text: '12');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final n = int.tryParse(months.text.trim()) ?? 0;
          final base = t.expiresAt.isAfter(DateTime.now()) ? t.expiresAt : DateTime.now();
          final preview = DateTime(base.year, base.month + n, base.day);
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تمديد اشتراك «${t.name}»',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.heading)),
                const SizedBox(height: 4),
                Text('الانتهاء الحالي: ${formatDate(t.expiresAt)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                const SizedBox(height: 10),
                const FieldLabel('عدد الأشهر'),
                TextField(
                  controller: months,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setSt(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in [1, 3, 6, 12, 24])
                      GhostButton(label: '$m شهر', onPressed: () => setSt(() => months.text = '$m')),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: AppColors.bg, border: Border.all(color: AppColors.line)),
                  child: Text(
                    n <= 0 ? 'أدخل عدد أشهر صحيحاً' : 'تاريخ الانتهاء الجديد: ${formatDate(preview)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: n <= 0 ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ActionButtons(
                  primaryFlex: 1,
                  gap: 8,
                  primary: PrimaryButton(
                    label: 'تمديد',
                    onPressed: n <= 0
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            if (!context.mounted) return;
                            // التمديد يعيد تفعيل الاشتراك، كما في `handleConfirmExtend`
                            await _update(
                              context,
                              store,
                              t,
                              {
                                'expires_at': preview.toUtc().toIso8601String(),
                                'plan_type': 'rental',
                                'status': 'active',
                              },
                              'تم تمديد الاشتراك حتى ${formatDate(preview)}',
                              () {
                                t.expiresAt = preview;
                                t.planType = 'rental';
                                t.active = true;
                              },
                            );
                          },
                  ),
                  secondary: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx)),
                ),
              ],
            ),
          );
        },
      ),
    );
    months.dispose();
  }

  Future<void> _delete(BuildContext context, Tenant t) async {
    final store = StoreScope.of(context);
    final typed = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('حذف منشأة نهائياً',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.danger)),
              const SizedBox(height: 6),
              // التأكيد بالمعرّف أو بكلمة «حذف» — كما في DeveloperDashboardPage
              Text(
                '«${t.name}» · المعرّف: ${t.code}\nللتأكيد اكتب المعرّف أو «حذف».',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: typed,
                onChanged: (_) => setSt(() {}),
                decoration: InputDecoration(hintText: t.code),
              ),
              const SizedBox(height: 12),
              ActionButtons(
                primaryFlex: 1,
                gap: 8,
                primary: PrimaryButton(
                  label: 'حذف نهائياً',
                  color: AppColors.danger,
                  onPressed: tenantDeleteConfirmed(typed.text, t) ? () => Navigator.pop(ctx, true) : null,
                ),
                secondary: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx, false)),
              ),
            ],
          ),
        ),
      ),
    );
    typed.dispose();
    if (confirmed != true || !context.mounted) return;

    // الحذف مع حساب الدخول عبر دالة السيرفر. كان يُحذف محلياً مهما حدث،
    // والقاعدة لا تسمح بالحذف المباشر، فتعود المنشأة عند أول تحديث
    final error = await store.tenantApi.remove(t.id);
    if (!context.mounted) return;
    if (error != null) {
      showAppSnack(context, error, error: true);
      return;
    }
    store.deleteTenant(t.id);
    showAppSnack(context, 'تم حذف المنشأة');
  }

  /// تعديل حقول منشأة في السحابة، ثم على الجهاز بعد قبولها — `updateTenant`.
  ///
  /// كان يُحفظ محلياً أولاً، فيبقى تعديلٌ رفضته السحابة ظاهراً كأنه نُفّذ.
  Future<void> _update(
    BuildContext context,
    AppStore store,
    Tenant t,
    Map<String, dynamic> fields,
    String okMessage,
    void Function() apply,
  ) async {
    final error = await store.tenantApi.update(t.id, fields);
    if (!context.mounted) return;
    if (error != null) {
      showAppSnack(context, error, error: true);
      return;
    }
    apply();
    t.updatedAt = DateTime.now().toUtc().toIso8601String();
    store.upsertTenant(t);
    showAppSnack(context, okMessage);
  }

  Future<void> _edit(BuildContext context, Tenant? existing) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    final code = TextEditingController(text: existing?.code ?? '');
    final username = TextEditingController(text: existing?.username ?? '');
    // كلمات المرور لا تُقرأ من السحابة ولا تُعرض: فارغة عند التعديل تعني «بلا تغيير»
    final password = TextEditingController();
    final adminPassword = TextEditingController();
    final ownerName = TextEditingController(text: existing?.ownerName ?? '');
    final ownerPhone = TextEditingController(text: existing?.ownerPhone ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final months = TextEditingController(text: '12');
    var planType = existing?.planType ?? 'rental';
    var codeTouched = existing != null;
    // شعار المدرسة: يُقرأ من سجل هويتها السحابي، ويُحفظ فقط إن تغيّر
    String? logo;
    var logoChanged = false;
    // الاسم تحت أيقونة نسخة المدرسة: يصل الأجهزة مع البناء التالي
    final iconName = TextEditingController();
    var savedIconName = '';
    if (existing != null) {
      try {
        logo = await fetchTenantLogo(existing.id);
      } catch (_) {}
      try {
        savedIconName = await fetchTenantIconName(existing.id);
        iconName.text = savedIconName;
      } catch (_) {}
      if (!context.mounted) return;
    }
    var saving = false;
    String? failure;
    final errors = FieldErrors();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'إضافة منشأة جديدة' : 'تعديل: ${existing.name}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.heading)),
                const SizedBox(height: 10),
                FieldLabel('اسم المنشأة', key: errors.key('name'), requiredField: true),
                TextField(
                  controller: name,
                  onChanged: (v) {
                    errors.clear('name');
                    if (!codeTouched) {
                      code.text = TenantService.codeFromName(v, store.tenants.length);
                      errors.clear('code');
                    }
                    setSt(() {});
                  },
                  decoration: InputDecoration(errorText: errors['name']),
                ),
                const SizedBox(height: 8),
                FieldLabel('المعرّف', key: errors.key('code'), requiredField: true),
                TextField(
                  controller: code,
                  onChanged: (_) {
                    codeTouched = true;
                    if (errors.clear('code')) setSt(() {});
                  },
                  decoration: InputDecoration(errorText: errors['code']),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel('اسم المستخدم', key: errors.key('username'), requiredField: true),
                          TextField(
                            controller: username,
                            onChanged: (_) {
                              if (errors.clear('username')) setSt(() {});
                            },
                            decoration: InputDecoration(errorText: errors['username']),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel(
                            existing == null ? 'كلمة المرور' : 'كلمة مرور جديدة',
                            key: errors.key('password'),
                            requiredField: existing == null,
                          ),
                          TextField(
                            controller: password,
                            onChanged: (_) {
                              if (errors.clear('password')) setSt(() {});
                            },
                            decoration: InputDecoration(
                              errorText: errors['password'],
                              hintText: existing == null ? null : 'فارغة = بلا تغيير',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FieldLabel(
                  existing == null ? 'كلمة مرور المدير' : 'كلمة مرور مدير جديدة',
                  key: errors.key('admin'),
                  requiredField: existing == null,
                ),
                TextField(
                  controller: adminPassword,
                  onChanged: (_) {
                    if (errors.clear('admin')) setSt(() {});
                  },
                  decoration: InputDecoration(
                    errorText: errors['admin'],
                    hintText: existing == null ? 'لتعيين أدوار الأجهزة — تختلف عن كلمة الدخول' : 'فارغة = بلا تغيير',
                  ),
                ),
                const SizedBox(height: 8),
                const FieldLabel('نوع التعاقد'),
                AppDropdown<String>(
                  value: planType,
                  items: const [
                    DropdownMenuItem(value: 'rental', child: Text('محدد المدة')),
                    DropdownMenuItem(value: 'lifetime', child: Text('دائم (بلا تاريخ انتهاء)')),
                  ],
                  onChanged: (v) => setSt(() => planType = v ?? 'rental'),
                ),
                // المدة تُسأل عند الإضافة أو التحويل من دائم؛ تاريخ الاشتراك القائم يُمدَّد من «تمديد»
                if (planType == 'rental' && (existing == null || existing.isLifetime)) ...[
                  const SizedBox(height: 8),
                  FieldLabel('مدة الاشتراك (أشهر)', key: errors.key('months'), requiredField: true),
                  TextField(
                    controller: months,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      if (errors.clear('months')) setSt(() {});
                    },
                    decoration: InputDecoration(errorText: errors['months']),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('اسم المالك'),
                          TextField(controller: ownerName),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('هاتف المالك'),
                          TextField(controller: ownerPhone, keyboardType: TextInputType.phone),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const FieldLabel('ملاحظات'),
                TextField(controller: notes, maxLines: 2),
                const SizedBox(height: 8),
                // يظهر في الترويسة والشهادات والسندات، ويصل أجهزة المدرسة مع السحب
                const FieldLabel('شعار المدرسة'),
                Row(
                  children: [
                    if (logo != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: Image.memory(base64Decode(logo!.split(',').last), height: 48, width: 48, fit: BoxFit.contain),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final file = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 512,
                          maxHeight: 512,
                          imageQuality: 90,
                        );
                        if (file == null) return;
                        final bytes = await file.readAsBytes();
                        setSt(() {
                          logo = 'data:${file.mimeType ?? 'image/png'};base64,${base64Encode(bytes)}';
                          logoChanged = true;
                        });
                      },
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: Text(logo == null ? 'اختيار' : 'تغيير'),
                    ),
                    if (logo != null)
                      TextButton(
                        onPressed: () => setSt(() {
                          logo = null;
                          logoChanged = true;
                        }),
                        child: const Text('إزالة'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const FieldLabel('الاسم تحت الأيقونة'),
                Tooltip(
                  message: 'يظهر تحت أيقونة نسخة المدرسة من البناء التالي',
                  child: TextField(
                    controller: iconName,
                    maxLength: 14,
                    decoration: const InputDecoration(hintText: 'فارغ = اسم المدرسة'),
                  ),
                ),
                // رفض السحابة يبقى داخل النموذج مع ما كُتب، فيُصحَّح ويُعاد بلا إعادة كتابة
                if (failure != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(Corner.box),
                      border: Border.all(color: AppColors.dangerBorder),
                    ),
                    child: Text(
                      failure!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                ActionButtons(
                  primaryFlex: 1,
                  gap: 8,
                  primary: PrimaryButton(
                        label: saving ? 'جارِ الحفظ...' : (existing == null ? 'إضافة' : 'حفظ'),
                        busy: saving,
                        onPressed: saving
                            ? null
                            : () async {
                                final monthCount = int.tryParse(months.text.trim());
                                final user = username.text.trim().toLowerCase();
                                final pass = password.text.trim();
                                final adminPass = adminPassword.text.trim();
                                final userChanged = existing == null || user != existing.username.trim().toLowerCase();
                                // قواعد `handleCreate` و`handleSaveEdit`: عند التعديل تُفحص الكلمة إن كُتبت فقط
                                final passwordProblem = (existing == null || pass.isNotEmpty) && pass.length < 6
                                    ? 'كلمة المرور 6 أحرف على الأقل'
                                    : null;
                                final adminProblem = (existing == null || adminPass.isNotEmpty) && adminPass.length < 6
                                    ? 'كلمة مرور المدير 6 أحرف على الأقل'
                                    : adminPass.isNotEmpty && adminPass == pass
                                        ? 'كلمة مرور المدير يجب أن تختلف عن كلمة الدخول'
                                        : null;
                                final asksMonths = planType == 'rental' && (existing == null || existing.isLifetime);
                                setSt(() {
                                  failure = null;
                                  errors
                                    ..reset()
                                    ..check('name', name.text.trim().isEmpty, 'يرجى إدخال اسم المنشأة')
                                    ..check('code', code.text.trim().isEmpty, 'يرجى إدخال المعرّف')
                                    ..check(
                                      'username',
                                      (userChanged || pass.isNotEmpty) && !SupabaseAuth.isValidUsername(user),
                                      _usernameRule,
                                    )
                                    ..check('password', passwordProblem != null, passwordProblem ?? '')
                                    ..check('admin', adminProblem != null, adminProblem ?? '')
                                    ..check(
                                      'months',
                                      asksMonths && (monthCount == null || monthCount <= 0),
                                      'يرجى إدخال عدد أشهر صحيح',
                                    );
                                });
                                if (errors.report(ctx)) return;
                                setSt(() => saving = true);

                                final now = DateTime.now();
                                final draft = Tenant(
                                  id: existing?.id ?? '',
                                  name: name.text.trim(),
                                  code: code.text.trim(),
                                  username: user,
                                  password: '',
                                  expiresAt: asksMonths
                                      ? DateTime(now.year, now.month + (monthCount ?? 12), now.day)
                                      : existing?.expiresAt ?? now,
                                  ownerName: ownerName.text.trim(),
                                  ownerPhone: ownerPhone.text.trim(),
                                  notes: notes.text.trim(),
                                  planType: planType,
                                  active: existing?.active ?? true,
                                  createdAt: existing?.createdAt,
                                  updatedAt: now.toUtc().toIso8601String(),
                                );

                                String? error;
                                Tenant? saved;
                                if (existing == null) {
                                  final result = await store.tenantApi.create(draft, password: pass, adminPassword: adminPass);
                                  error = result.error;
                                  saved = result.tenant;
                                } else {
                                  error = await store.tenantApi.update(
                                    existing.id,
                                    {
                                      'name': draft.name,
                                      'code': draft.code,
                                      'plan_type': draft.planType,
                                      'expires_at': draft.isLifetime ? null : draft.expiresAt.toUtc().toIso8601String(),
                                      'owner_name': draft.ownerName,
                                      'owner_phone': draft.ownerPhone,
                                      'notes': draft.notes,
                                    },
                                    username: userChanged ? user : null,
                                    newPassword: pass.isEmpty ? null : pass,
                                    newAdminPassword: adminPass.isEmpty ? null : adminPass,
                                  );
                                  saved = draft;
                                }
                                if (!ctx.mounted) return;
                                if (error != null) {
                                  setSt(() {
                                    saving = false;
                                    failure = error;
                                  });
                                  return;
                                }
                                final savedId = saved?.id ?? '';
                                if (logoChanged && savedId.isNotEmpty) {
                                  try {
                                    await saveTenantLogo(savedId, logo);
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      showAppSnack(
                                        ctx,
                                        existing == null
                                            ? 'أُضيفت المنشأة وتعذّر حفظ الشعار؛ ارفعه من «تعديل»'
                                            : 'حُفظت المنشأة وتعذّر حفظ الشعار',
                                        error: true,
                                      );
                                    }
                                  }
                                }
                                final shortName = iconName.text.trim();
                                if (shortName != savedIconName && savedId.isNotEmpty) {
                                  try {
                                    await saveTenantIconName(savedId, shortName);
                                  } catch (e) {
                                    if (ctx.mounted) showAppSnack(ctx, 'تعذّر حفظ الاسم تحت الأيقونة', error: true);
                                  }
                                }
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (saved != null) store.upsertTenant(saved);
                                if (context.mounted) {
                                  showAppSnack(context, existing == null ? 'تمت إضافة المنشأة' : 'تم حفظ التعديلات');
                                }
                                // القائمة كما حفظتها السحابة: المعرّف يُولَّد هناك والرمز بحروف صغيرة
                                unawaited(store.refreshTenantsFromCloud());
                              },
                      ),
                  secondary: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final c in [name, code, username, password, adminPassword, ownerName, ownerPhone, notes, months, iconName]) {
      c.dispose();
    }
  }
}

class _TenantRow extends StatelessWidget {
  const _TenantRow({
    required this.tenant,
    required this.onEdit,
    required this.onExtend,
    required this.onToggle,
    required this.onEnter,
    required this.onDelete,
  });

  final Tenant tenant;
  final VoidCallback onEdit;
  final VoidCallback onExtend;
  final VoidCallback onToggle;
  final VoidCallback onEnter;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final expired = !tenant.isLifetime && tenant.expiresAt.isBefore(DateTime.now());
    final daysLeft = tenant.expiresAt.difference(DateTime.now()).inDays;
    final meta = [tenant.code, if (tenant.username != tenant.code) tenant.username].where((e) => e.isNotEmpty).join('  ·  ');

    return Container(
      color: expired || !tenant.active ? AppColors.dangerSoft.withValues(alpha: 0.5) : null,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(tenant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.heading)),
                    ),
                    const SizedBox(width: 8),
                    if (tenant.isDemo)
                      StatusChip.amber(
                          'تجريبية · ${(tenant.demoExpiresAt ?? tenant.expiresAt).difference(DateTime.now()).inDays.clamp(0, 999)} يوم')
                    else if (!tenant.active)
                      StatusChip.danger('موقوف')
                    else if (expired)
                      StatusChip.danger('منتهٍ')
                    else if (tenant.isLifetime)
                      StatusChip.muted('دائم')
                    else if (daysLeft <= 30)
                      StatusChip.amber('باقٍ $daysLeft يوماً'),
                  ],
                ),
                const SizedBox(height: 3),
                Text(meta,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11, fontFamily: 'monospace')),
                if (!tenant.isLifetime)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('ينتهي ${formatDate(tenant.expiresAt)}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: expired ? AppColors.danger : AppColors.muted)),
                  ),
                if (tenant.ownerName.isNotEmpty || tenant.ownerPhone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text([tenant.ownerName, tenant.ownerPhone].where((e) => e.isNotEmpty).join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ),
                if (tenant.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(tenant.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.faint)),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
            onSelected: (v) => switch (v) {
              'enter' => onEnter(),
              'edit' => onEdit(),
              'extend' => onExtend(),
              'toggle' => onToggle(),
              _ => onDelete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'enter', child: Text('دخول للمنشأة')),
              const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
              const PopupMenuItem(value: 'extend', child: Text('تمديد الاشتراك')),
              PopupMenuItem(value: 'toggle', child: Text(tenant.active ? 'إيقاف الاشتراك' : 'تفعيل الاشتراك')),
              PopupMenuItem(value: 'delete', child: Text('حذف نهائياً', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        ],
      ),
    );
  }
}

/// شعار مدرسة من سجل هويتها السحابي (لوحة المطور، خارج جلسة المدرسة) — `fetchTenantLogo`.
Future<String?> fetchTenantLogo(String tenantId) async {
  final rows = await supabaseSelect('institution_settings', columns: 'logo', filters: {'tenant_id': 'eq.$tenantId'}, limit: 1);
  if (rows == null) throw Exception('تعذّر قراءة الشعار');
  final logo = rows.isEmpty ? null : rows.first['logo'];
  return logo is String && logo.isNotEmpty ? logo : null;
}

/// الاسم تحت أيقونة نسخة المدرسة (`tenants.icon_name`)؛ فارغ = اسم المدرسة.
Future<String> fetchTenantIconName(String tenantId) async {
  final rows = await supabaseSelect('tenants', columns: 'icon_name', filters: {'id': 'eq.$tenantId'}, limit: 1);
  if (rows == null) throw Exception('تعذّر قراءة الاسم تحت الأيقونة');
  return rows.isEmpty ? '' : '${rows.first['icon_name'] ?? ''}'.trim();
}

/// يُقرأ عند بناء نسخ المدارس (`get_school_download_page`)، فيصل الأجهزة مع البناء التالي.
Future<void> saveTenantIconName(String tenantId, String name) => supabaseUpdate(
      'tenants',
      {'id': 'eq.$tenantId'},
      {'icon_name': name.isEmpty ? null : name, 'updated_at': DateTime.now().toUtc().toIso8601String()},
    );

/// يرفع المطور شعار المدرسة من لوحته دون الدخول عليها — `saveTenantLogo`: يُكتب في سجل
/// هويتها السحابي، وأجهزتها تأخذه مع السحب التالي كما لو رفعه مديرها.
Future<void> saveTenantLogo(String tenantId, String? logo) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final rows = await supabaseSelect('institution_settings', columns: 'id', filters: {'tenant_id': 'eq.$tenantId'}, limit: 1);
  if (rows == null) throw Exception('تعذّر قراءة سجل المدرسة');
  if (rows.isNotEmpty) {
    await supabaseUpdate('institution_settings', {'id': 'eq.${rows.first['id']}'}, {'logo': logo, 'updated_at': now});
    return;
  }
  await supabaseInsert('institution_settings', [
    {
      'id': tenantId,
      'tenant_id': tenantId,
      'institution_type': 'school',
      'institution_name': '',
      'logo': logo,
      'created_at': now,
      'updated_at': now,
    },
  ]);
}
