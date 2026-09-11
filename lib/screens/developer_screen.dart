import 'package:flutter/material.dart';

import '../data/store.dart';
import '../data/tenant_service.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
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

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            children: [
              _header(context, store),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                    children: [
                      if (notice != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Corner.box),
                            color: AppColors.amberSoft,
                            border: Border.all(color: AppColors.amberBorder),
                          ),
                          child: Text(notice!, style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A4F05))),
                        ),
                      AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('الاشتراكات والمنشآت',
                                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                                      Text('المعروض: ${list.length} من ${store.tenants.length}',
                                          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                GhostButton(
                                  label: 'تحديث',
                                  icon: Icons.refresh,
                                  onPressed: loading ? null : _refresh,
                                ),
                                const SizedBox(width: 6),
                                PrimaryButton(
                                  label: 'منشأة',
                                  icon: Icons.add,
                                  onPressed: () => _edit(context, null),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SearchField(
                              controller: search,
                              hint: 'ابحث بالاسم أو الرمز أو المالك...',
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (loading && store.tenants.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator(color: AppColors.amber)),
                        )
                      else if (list.isEmpty)
                        const EmptyState(message: 'لا توجد منشآت مسجلة مطابقة للبحث')
                      else
                        for (final t in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _TenantCard(
                              tenant: t,
                              onEdit: () => _edit(context, t),
                              onExtend: () => _extend(context, t),
                              onToggle: () => _toggleStatus(context, t),
                              onEnter: () => _enterTenant(context, t),
                              onDelete: () => _delete(context, t),
                            ),
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
      padding: EdgeInsets.fromLTRB(14, top + 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.navy,
        border: Border(bottom: BorderSide(color: AppColors.navyMid)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: AppColors.amberSoft, border: Border.all(color: AppColors.amber)),
            child: Icon(Icons.tune, color: AppColors.navy, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('بوابة المطور والاشتراكات',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                Text('لوحة التحكم المركزية', style: TextStyle(color: AppColors.amber, fontSize: 10)),
              ],
            ),
          ),
          InkWell(
            onTap: () async {
              final ok = await confirmSheet(
                context,
                title: 'تسجيل الخروج',
                message: 'هل ترغب في الخروج من بوابة المطور؟',
                confirmLabel: 'خروج',
              );
              if (ok) await store.logout();
            },
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corner.box),
                color: const Color(0xFF4C0519).withValues(alpha: 0.6),
                border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout, size: 14, color: Color(0xFFFB7185)),
                  SizedBox(width: 4),
                  Text('خروج', style: TextStyle(color: Color(0xFFFECDD3), fontSize: 10, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «دخول للمنشأة» — تقمّص المنشأة لمعاينة بياناتها كما يراها موظفوها.
  Future<void> _enterTenant(BuildContext context, Tenant t) async {
    final store = StoreScope.of(context);
    final problem = store.subscriptionProblem(t);
    if (problem != null) {
      showAppSnack(context, problem, error: true);
      return;
    }
    final ok = await confirmSheet(
      context,
      title: 'دخول للمنشأة',
      message: 'سيتم فتح واجهة «${t.name}» بصلاحية مدير النظام. تُسحب بياناتها من السحابة.',
      confirmLabel: 'دخول',
    );
    if (!ok || !context.mounted) return;
    await store.login(t.username, t.password);
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
    t.active = !t.active;
    t.updatedAt = DateTime.now().toUtc().toIso8601String();
    await _persist(context, store, t, suspending ? 'تم إيقاف الاشتراك' : 'تم تفعيل الاشتراك');
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
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
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
                      fontWeight: FontWeight.w800,
                      color: n <= 0 ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        label: 'تمديد',
                        onPressed: n <= 0
                            ? null
                            : () async {
                                t.expiresAt = preview;
                                t.planType = 'rental';
                                t.updatedAt = DateTime.now().toUtc().toIso8601String();
                                Navigator.pop(ctx);
                                if (context.mounted) {
                                  await _persist(context, store, t, 'تم تمديد الاشتراك حتى ${formatDate(preview)}');
                                }
                              },
                      ),
                    ),
                  ],
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
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.danger)),
              const SizedBox(height: 6),
              Text(
                'سيُحذف اشتراك «${t.name}» من المنصة ولن يستطيع موظفوها الدخول. '
                'اكتب اسم المنشأة حرفياً للتأكيد.',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: typed,
                onChanged: (_) => setSt(() {}),
                decoration: InputDecoration(hintText: t.name),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: 'حذف نهائياً',
                      color: AppColors.danger,
                      onPressed: typed.text.trim() == t.name.trim() ? () => Navigator.pop(ctx, true) : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    typed.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      await store.tenantApi.remove(t.id);
    } catch (_) {
      // الحذف المحلي يتم على أي حال؛ التحديث التالي يعيد المزامنة
    }
    store.deleteTenant(t.id);
    store.markDirty('tenants');
    if (context.mounted) showAppSnack(context, 'تم حذف المنشأة');
  }

  Future<void> _persist(BuildContext context, AppStore store, Tenant t, String okMessage) async {
    store.upsertTenant(t);
    store.markDirty('tenants');
    try {
      await store.tenantApi.save(t);
      if (context.mounted) showAppSnack(context, okMessage);
    } catch (e) {
      if (context.mounted) {
        showAppSnack(context, 'حُفظ محلياً، وتعذّر الرفع للسحابة: $e', error: true);
      }
    }
  }

  Future<void> _edit(BuildContext context, Tenant? existing) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    final code = TextEditingController(text: existing?.code ?? '');
    final username = TextEditingController(text: existing?.username ?? '');
    final password = TextEditingController(text: existing?.password ?? '');
    final ownerName = TextEditingController(text: existing?.ownerName ?? '');
    final ownerPhone = TextEditingController(text: existing?.ownerPhone ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final months = TextEditingController(text: '12');
    var planType = existing?.planType ?? 'rental';
    var codeTouched = existing != null;
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
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
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
                FieldLabel('رمز المنشأة', key: errors.key('code'), requiredField: true),
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
                          FieldLabel('كلمة المرور', key: errors.key('password'), requiredField: true),
                          TextField(
                            controller: password,
                            onChanged: (_) {
                              if (errors.clear('password')) setSt(() {});
                            },
                            decoration: InputDecoration(errorText: errors['password']),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                if (planType == 'rental') ...[
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        label: existing == null ? 'إضافة' : 'حفظ',
                        onPressed: () async {
                          final monthCount = int.tryParse(months.text.trim());
                          setSt(() {
                            errors
                              ..reset()
                              ..check('name', name.text.trim().isEmpty, 'يرجى إدخال اسم المنشأة')
                              ..check('code', code.text.trim().isEmpty, 'يرجى إدخال رمز المنشأة')
                              ..check('username', username.text.trim().isEmpty, 'يرجى إدخال اسم المستخدم')
                              ..check('password', password.text.trim().isEmpty, 'يرجى إدخال كلمة المرور')
                              ..check(
                                'months',
                                planType == 'rental' && (monthCount == null || monthCount <= 0),
                                'يرجى إدخال عدد أشهر صحيح',
                              );
                          });
                          if (errors.report(ctx)) return;
                          final n = int.tryParse(months.text.trim()) ?? 12;
                          final tenant = Tenant(
                            id: existing?.id ?? store.newId(),
                            name: name.text.trim(),
                            code: code.text.trim(),
                            username: username.text.trim(),
                            password: password.text.trim(),
                            expiresAt: existing != null && planType == 'rental'
                                ? existing.expiresAt
                                : DateTime(DateTime.now().year, DateTime.now().month + n, DateTime.now().day),
                            ownerName: ownerName.text.trim(),
                            ownerPhone: ownerPhone.text.trim(),
                            notes: notes.text.trim(),
                            planType: planType,
                            active: existing?.active ?? true,
                            createdAt: existing?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
                            updatedAt: DateTime.now().toUtc().toIso8601String(),
                          );
                          Navigator.pop(ctx);
                          if (context.mounted) {
                            await _persist(context, store, tenant,
                                existing == null ? 'تمت إضافة المنشأة' : 'تم حفظ التعديلات');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final c in [name, code, username, password, ownerName, ownerPhone, notes, months]) {
      c.dispose();
    }
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({
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

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tenant.name,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
              ),
              if (!tenant.active)
                StatusChip.danger('موقوف')
              else if (expired)
                StatusChip.danger('منتهٍ')
              else if (tenant.isLifetime)
                StatusChip.success('دائم')
              else
                StatusChip.success('ساري'),
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
                  const PopupMenuItem(value: 'delete', child: Text('حذف نهائياً')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          _line('الرمز', tenant.code),
          _line('الدخول', '${tenant.username}  /  ${tenant.password}'),
          if (tenant.isLifetime)
            _line('الاشتراك', 'دائم (غير محدد بتاريخ انتهاء)')
          else
            _line(
              'الانتهاء',
              '${formatDate(tenant.expiresAt)}'
              '${expired ? '  (منتهٍ)' : daysLeft <= 30 ? '  (باقٍ $daysLeft يوماً)' : ''}',
              color: expired ? AppColors.danger : (daysLeft <= 30 ? AppColors.amber : null),
            ),
          if (tenant.ownerName.isNotEmpty || tenant.ownerPhone.isNotEmpty)
            _line('المالك', [tenant.ownerName, tenant.ownerPhone].where((e) => e.isNotEmpty).join('  ·  ')),
          if (tenant.notes.isNotEmpty) _line('ملاحظات', tenant.notes),
        ],
      ),
    );
  }

  Widget _line(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 62, child: Text(k, style: const TextStyle(color: AppColors.faint, fontSize: 11))),
            Expanded(
              child: Text(v,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color ?? AppColors.muted)),
            ),
          ],
        ),
      );
}
