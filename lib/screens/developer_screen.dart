import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final top = MediaQuery.paddingOf(context).top;
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(14, top + 10, 12, 12),
                color: AppColors.navy,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      color: AppColors.amberSoft,
                      child: const Icon(Icons.apartment, color: AppColors.navy, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('بوابة المطور والاشتراكات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                          Text('لوحة التحكم المركزية', style: TextStyle(color: AppColors.amber, fontSize: 10)),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: store.logout,
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
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
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('الاشتراكات والمنشآت', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                        ),
                        PrimaryButton(label: 'منشأة جديدة', icon: Icons.add, onPressed: () => _edit(context, null)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final t in store.tenants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          onTap: () => _edit(context, t),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading))),
                                  t.active && t.expiresAt.isAfter(DateTime.now())
                                      ? StatusChip.success('سارٍ')
                                      : StatusChip.danger('منتهٍ'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('رمز: ${t.code} · مستخدم: ${t.username}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                              Text('ينتهي: ${formatDate(t.expiresAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  GhostButton(
                                    label: 'تمديد سنة',
                                    onPressed: () {
                                      t.expiresAt = t.expiresAt.add(const Duration(days: 365));
                                      store.upsertTenant(t);
                                    },
                                  ),
                                  const Spacer(),
                                  GhostButton(
                                    label: 'حذف',
                                    onPressed: () async {
                                      final ok = await confirmSheet(context, title: 'حذف المنشأة', message: 'حذف ${t.name}؟', confirmLabel: 'حذف');
                                      if (ok) store.deleteTenant(t.id);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Tenant? t) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: t?.name ?? '');
    final code = TextEditingController(text: t?.code ?? '');
    final user = TextEditingController(text: t?.username ?? '');
    final pass = TextEditingController(text: t?.password ?? '');
    final phone = TextEditingController(text: t?.ownerPhone ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t == null ? 'إضافة منشأة' : 'تعديل الاشتراك', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
              const SizedBox(height: 10),
              const FieldLabel('اسم المنشأة'),
              TextField(controller: name),
              const SizedBox(height: 8),
              const FieldLabel('الرمز'),
              TextField(controller: code),
              const SizedBox(height: 8),
              const FieldLabel('اسم المستخدم'),
              TextField(controller: user),
              const SizedBox(height: 8),
              const FieldLabel('كلمة المرور'),
              TextField(controller: pass),
              const SizedBox(height: 8),
              const FieldLabel('هاتف المالك'),
              TextField(controller: phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              PrimaryButton(
                expand: true,
                label: 'حفظ',
                onPressed: () {
                  try {
                    store.upsertTenant(
                      Tenant(
                        id: t?.id ?? store.newId(),
                        name: name.text.trim(),
                        code: code.text.trim(),
                        username: user.text.trim(),
                        password: pass.text.trim(),
                        expiresAt: t?.expiresAt ?? DateTime.now().add(const Duration(days: 365)),
                        ownerPhone: phone.text.trim(),
                        active: true,
                      ),
                    );
                    Navigator.pop(ctx);
                  } on StoreException catch (e) {
                    showAppSnack(context, e.message, error: true);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
