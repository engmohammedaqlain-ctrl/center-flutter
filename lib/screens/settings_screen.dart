import 'package:flutter/material.dart';

import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'reports_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (Icons.payments_outlined, 'الرسوم والمراحل'),
      (Icons.school_outlined, 'المدرسين'),
      (Icons.menu_book_outlined, 'المواد الدراسية'),
      (Icons.groups_outlined, 'المستخدمين والصلاحيات'),
      (Icons.storage_outlined, 'البيانات والمطور'),
    ];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  InkWell(
                    onTap: () => setState(() => tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: tab == i ? AppColors.amber : Colors.transparent, width: 2)),
                      ),
                      child: Row(
                        children: [
                          Icon(tabs[i].$1, size: 14, color: tab == i ? AppColors.amber : AppColors.muted),
                          const SizedBox(width: 5),
                          Text(tabs[i].$2, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tab == i ? AppColors.heading : AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: tab,
            children: const [
              _FeesTab(),
              _TeachersTab(),
              _SubjectsTab(),
              _UsersTab(),
              _BackupTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeesTab extends StatelessWidget {
  const _FeesTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            for (final f in store.gradeFees)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => _edit(context, f),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.gradeName, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                            const SizedBox(height: 4),
                            StatusChip.muted('الثانوية'),
                          ],
                        ),
                      ),
                      Text(money(f.monthlyFee), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.amber)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, GradeFee f) async {
    final store = StoreScope.of(context);
    final fee = TextEditingController(text: f.monthlyFee.toStringAsFixed(0));
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تعديل رسم ${f.gradeName}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
              const SizedBox(height: 10),
              const FieldLabel('الرسم الشهري (₪)'),
              TextField(controller: fee, keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              PrimaryButton(
                expand: true,
                label: 'حفظ',
                onPressed: () {
                  try {
                    store.updateGradeFee(GradeFee(id: f.id, gradeName: f.gradeName, monthlyFee: double.tryParse(fee.text) ?? f.monthlyFee, tier: f.tier));
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

class _TeachersTab extends StatelessWidget {
  const _TeachersTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PrimaryButton(label: 'معلم جديد', icon: Icons.add, onPressed: () => _edit(context)),
            ),
            const SizedBox(height: 8),
            for (final t in store.teachers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => _edit(context, t),
                  child: Row(
                    children: [
                      Container(width: 36, height: 36, color: AppColors.amberSoft, child: const Icon(Icons.person, color: AppColors.amber, size: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 13)),
                            Text('${t.subject} · ${t.phone}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      Text(money(t.rate), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, [Teacher? t]) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: t?.name ?? '');
    final phone = TextEditingController(text: t?.phone ?? '');
    final email = TextEditingController(text: t?.email ?? '');
    final notes = TextEditingController(text: t?.notes ?? '');
    final rate = TextEditingController(text: '${t?.rate ?? 3000}');
    String subject = t?.subject ?? store.subjects.first.name;
    String paymentType = t?.paymentType ?? 'monthly';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t == null ? 'معلم جديد' : 'تعديل المعلم', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                  const SizedBox(height: 10),
                  const FieldLabel('الاسم'),
                  TextField(controller: name),
                  const SizedBox(height: 8),
                  const FieldLabel('الهاتف'),
                  TextField(controller: phone, keyboardType: TextInputType.phone),
                  const SizedBox(height: 8),
                  const FieldLabel('البريد الإلكتروني'),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 8),
                  const FieldLabel('المادة'),
                  AppDropdown<String>(
                    value: subject,
                    items: store.subjects.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                    onChanged: (v) => setSt(() => subject = v ?? subject),
                  ),
                  const SizedBox(height: 8),
                  const FieldLabel('نوع الاستحقاق'),
                  AppDropdown<String>(
                    value: teacherPaymentTypes.containsKey(paymentType) ? paymentType : 'monthly',
                    items: teacherPaymentTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setSt(() => paymentType = v ?? paymentType),
                  ),
                  const SizedBox(height: 8),
                  const FieldLabel('قيمة الاستحقاق / الراتب'),
                  TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  const SizedBox(height: 8),
                  const FieldLabel('ملاحظات'),
                  TextField(controller: notes),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (t != null)
                        Expanded(
                          child: GhostButton(
                            label: 'حذف',
                            onPressed: () {
                              store.deleteTeacher(t.id);
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      if (t != null) const SizedBox(width: 8),
                      Expanded(
                        child: PrimaryButton(
                          label: 'حفظ',
                          onPressed: () {
                            try {
                              store.upsertTeacher(
                                Teacher(
                                  id: t?.id ?? store.newId(),
                                  name: name.text.trim(),
                                  phone: phone.text.trim(),
                                  subject: subject,
                                  rate: double.tryParse(rate.text.trim()) ?? t?.rate ?? 3000,
                                  email: email.text.trim(),
                                  paymentType: paymentType,
                                  notes: notes.text.trim(),
                                  subjectIds: store.subjects.where((s) => s.name == subject).map((s) => s.id).toList(),
                                ),
                              );
                              Navigator.pop(ctx);
                            } on StoreException catch (e) {
                              showAppSnack(context, e.message, error: true);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SubjectsTab extends StatelessWidget {
  const _SubjectsTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PrimaryButton(label: 'مادة جديدة', icon: Icons.add, onPressed: () => _edit(context)),
            ),
            const SizedBox(height: 8),
            for (final s in store.subjects)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => _edit(context, s),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 36,
                        alignment: Alignment.center,
                        color: const Color(0xFFF1F5F9),
                        child: Text(s.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.navy)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                            Text(s.gradeLevel, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, [SubjectItem? s]) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: s?.name ?? '');
    final code = TextEditingController(text: s?.code ?? '');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s == null ? 'مادة جديدة' : 'تعديل المادة', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
              const SizedBox(height: 10),
              const FieldLabel('الاسم'),
              TextField(controller: name),
              const SizedBox(height: 8),
              const FieldLabel('الرمز'),
              TextField(controller: code),
              const SizedBox(height: 12),
              PrimaryButton(
                expand: true,
                label: 'حفظ',
                onPressed: () {
                  try {
                    store.upsertSubject(SubjectItem(id: s?.id ?? store.newId(), name: name.text.trim(), code: code.text.trim().toUpperCase(), gradeLevel: s?.gradeLevel ?? 'عام / كل المراحل'));
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

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            AppCard(
              color: const Color(0xFFFAF5FF),
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFF6B21A8), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('صلاحية هذا الجهاز', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6B21A8), fontSize: 12.5)),
                        Text(store.roleName, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PrimaryButton(label: 'مستخدم جديد', icon: Icons.add, onPressed: () => _add(context)),
            ),
            const SizedBox(height: 8),
            for (final u in store.users)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Row(
                    children: [
                      const Icon(Icons.badge_outlined, color: AppColors.navy, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                            Text(u.role, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      StatusChip.success('نشط'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context) async {
    final store = StoreScope.of(context);
    final name = TextEditingController();
    String role = 'سكرتير';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مستخدم جديد', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                  const SizedBox(height: 10),
                  const FieldLabel('الاسم'),
                  TextField(controller: name),
                  const SizedBox(height: 8),
                  const FieldLabel('الصلاحية'),
                  AppDropdown<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(value: 'مدير', child: Text('مدير')),
                      DropdownMenuItem(value: 'سكرتير', child: Text('سكرتير')),
                    ],
                    onChanged: (v) => setSt(() => role = v ?? role),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    expand: true,
                    label: 'حفظ',
                    onPressed: () {
                      try {
                        store.addUser(AppUser(id: store.newId(), name: name.text.trim(), role: role));
                        Navigator.pop(ctx);
                      } on StoreException catch (e) {
                        showAppSnack(context, e.message, error: true);
                      }
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _BackupTab extends StatelessWidget {
  const _BackupTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final counts = {
          'الطلاب': store.students.length,
          'الشعب والصفوف': store.rooms.length,
          'المراحل الدراسية': store.gradeFees.length,
          'المدرسين': store.teachers.length,
          'المواد': store.subjects.length,
          'المقبوضات': store.payments.length,
          'الأقساط': store.installments.length,
          'الحضور': store.attendance.length,
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('حالة المزامنة مع السحابة'),
                  Text(
                    store.pendingPush == 0 ? 'لا توجد تعديلات متعثرة للرفع.' : '${store.pendingPush} تعديلات محلية بانتظار الرفع',
                    style: TextStyle(color: store.pendingPush == 0 ? AppColors.muted : AppColors.amber, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  if (store.sync.getFailedActions().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'عمليات فاشلة بعد $maxSyncRetries محاولات: ${store.sync.getFailedActions().length}',
                      style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    for (final a in store.sync.getFailedActions().take(5))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${tableLabelsAr[a.tableName] ?? a.tableName}: ${a.lastError ?? ''}', style: const TextStyle(color: AppColors.danger, fontSize: 11)),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('حالة البيانات المحلية'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in counts.entries)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
                          child: Column(
                            children: [
                              Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                              Text(e.key, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                children: [
                  PrimaryButton(
                    expand: true,
                    label: 'تصدير نسخة احتياطية',
                    icon: Icons.download,
                    onPressed: () => showAppSnack(context, 'تم تجهيز النسخة الاحتياطية محلياً (${store.students.length} طالب)'),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: GhostButton(
                      label: 'التقارير',
                      icon: Icons.bar_chart,
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
