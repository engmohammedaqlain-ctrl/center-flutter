import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/permissions.dart';
import '../data/phone.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'developer_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// تبويب في شاشة الإعدادات، مع صلاحيته ونوع المنشأة الذي يظهر فيه.
class _Tab {
  const _Tab(this.id, this.icon, this.label, this.body, {this.capability, this.schoolOnly, this.centerOnly = false});
  final String id;
  final IconData icon;
  final String label;
  final Widget body;
  final String? capability;
  final bool? schoolOnly;
  final bool centerOnly;
}

class _SettingsScreenState extends State<SettingsScreen> {
  String current = 'teachers';

  /// التبويبات المتاحة — تُخفى بحسب الصلاحية ونوع المنشأة، تماماً كما في Settings.tsx.
  List<_Tab> _tabs(AppStore store) {
    final school = store.isSchool;
    final all = <_Tab>[
      const _Tab('grade_fees', Icons.payments_outlined, 'الرسوم والمراحل', _FeesTab(),
          capability: 'settings.fees', schoolOnly: true),
      const _Tab('teachers', Icons.school_outlined, 'المدرسين', _TeachersTab()),
      const _Tab('subjects', Icons.menu_book_outlined, 'المواد الدراسية', _SubjectsTab()),
      const _Tab('rooms', Icons.meeting_room_outlined, 'القاعات', _RoomsTab(), centerOnly: true),
      const _Tab('users', Icons.groups_outlined, 'المستخدمين والصلاحيات', _UsersTab(), capability: 'settings.users'),
      const _Tab('backup', Icons.storage_outlined, 'البيانات والمطور', _BackupTab(), capability: 'settings.backup'),
    ];
    return all.where((t) {
      if (t.schoolOnly == true && !school) return false;
      if (t.centerOnly && school) return false;
      if (t.capability != null && !store.can(t.capability!)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('settings')) {
          return NoAccess(section: 'settings', roleName: store.roleName);
        }
        final tabs = _tabs(store);
        if (tabs.isEmpty) return NoAccess(section: 'settings', roleName: store.roleName);
        var tab = tabs.indexWhere((t) => t.id == current);
        if (tab < 0) tab = 0;

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
                    onTap: () => setState(() => current = tabs[i].id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: tab == i ? AppColors.amber : Colors.transparent, width: 2)),
                      ),
                      child: Row(
                        children: [
                          Icon(tabs[i].icon, size: 14, color: tab == i ? AppColors.amber : AppColors.muted),
                          const SizedBox(width: 5),
                          Text(tabs[i].label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tab == i ? AppColors.heading : AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
                if (store.currentTenant?.code.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'رمز المنشأة: ${store.currentTenant!.code}',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: tab,
            children: [for (final t in tabs) t.body],
          ),
        ),
        _LogoutBar(store: store),
      ],
        );
      },
    );
  }
}

/// قسم إنهاء الجلسة — مكان مخصص محمي بتأكيد، كما في أسفل Settings.tsx.
class _LogoutBar extends StatelessWidget {
  const _LogoutBar({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('جلسة العمل على هذا الجهاز',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
                Text('تسجيل الخروج ينهي جلستك ويتطلب إدخال بيانات الدخول مرة أخرى.',
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
              ],
            ),
          ),
          GhostButton(
            label: 'تسجيل الخروج',
            icon: Icons.logout,
            onPressed: () async {
              final ok = await confirmSheet(
                context,
                title: 'تسجيل الخروج',
                message: 'هل أنت متأكد من رغبتك في تسجيل الخروج من النظام على هذا الجهاز؟',
                confirmLabel: 'خروج',
              );
              if (ok) await store.logout();
            },
          ),
        ],
      ),
    );
  }
}

class _FeesTab extends StatefulWidget {
  const _FeesTab();
  @override
  State<_FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<_FeesTab> {
  bool adding = false;
  final name = TextEditingController();
  final fee = TextEditingController();
  final section = TextEditingController();
  String tier = 'secondary';

  @override
  void dispose() {
    name.dispose();
    fee.dispose();
    section.dispose();
    super.dispose();
  }

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
              child: Row(
                children: [
                  Container(width: 36, height: 36, color: AppColors.amberSoft, child: const Icon(Icons.payments, color: AppColors.amber, size: 18)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المراحل الدراسية والرسوم والشعب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
                        Text('إدارة المراحل الدراسية ورسومها الشهرية والشعب التابعة لكل مرحلة', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  PrimaryButton(label: 'إضافة مرحلة دراسية جديدة', icon: Icons.add, onPressed: () => setState(() => adding = true)),
                ],
              ),
            ),
            if (adding) ...[
              const SizedBox(height: 8),
              AppCard(
                color: AppColors.bg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('إضافة مرحلة دراسية جديدة للنظام', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
                        IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => adding = false)),
                      ],
                    ),
                    const FieldLabel('اسم المرحلة أو الصف الدراسي', requiredField: true),
                    TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: الصف الثاني عشر...')),
                    const SizedBox(height: 8),
                    const FieldLabel('المرحلة التعليمية الكبرى', requiredField: true),
                    AppDropdown<String>(
                      value: tier,
                      items: educationalStageTiers.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setState(() => tier = v ?? tier),
                    ),
                    const SizedBox(height: 8),
                    const FieldLabel('الرسوم الشهرية المعتمدة (₪)', requiredField: true),
                    TextField(controller: fee, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'مثال: 200')),
                    const SizedBox(height: 8),
                    const FieldLabel('الشعبة الأولى (اختياري)'),
                    TextField(controller: section, decoration: const InputDecoration(hintText: 'مثال: الشعبة (أ)')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => setState(() => adding = false))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrimaryButton(
                            label: 'حفظ المرحلة وإدراجها',
                            onPressed: () {
                              try {
                                store.addGradeFee(
                                  GradeFee(
                                    id: store.newId(),
                                    gradeName: name.text.trim(),
                                    monthlyFee: double.tryParse(fee.text.trim()) ?? -1,
                                    tier: tier,
                                    isCustom: true,
                                    orderIndex: store.gradeFees.length + 1,
                                  ),
                                  initialSection: section.text.trim(),
                                );
                                name.clear();
                                fee.clear();
                                section.clear();
                                setState(() => adding = false);
                                showAppSnack(context, 'تم إضافة المرحلة الدراسية بنجاح');
                              } on StoreException catch (e) {
                                showAppSnack(context, e.message, error: true);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final f in store.gradeFees)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.gradeName, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                                const SizedBox(height: 4),
                                StatusChip.muted(stageTierLabel(f.tier)),
                              ],
                            ),
                          ),
                          Text(money(f.monthlyFee), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.amber)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in store.rooms.where((r) => r.gradeLevel == f.gradeName))
                            StatusChip.amber(r.name),
                          InkWell(
                            onTap: () => _quickSection(context, f.gradeName, f.tier),
                            child: const StatusChip(label: '+ شعبة', fg: AppColors.navy, bg: AppColors.amberSoft, border: AppColors.amberBorder),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          GhostButton(label: 'تعديل', icon: Icons.edit_outlined, onPressed: () => _edit(context, f)),
                          const SizedBox(width: 8),
                          GhostButton(
                            label: 'حذف',
                            icon: Icons.delete_outline,
                            onPressed: () async {
                              final ok = await confirmSheet(context, title: 'حذف المرحلة', message: 'هل أنت متأكد من حذف مرحلة "${f.gradeName}"؟', confirmLabel: 'حذف');
                              if (!ok) return;
                              try {
                                store.deleteGradeFee(f);
                              } on StoreException catch (e) {
                                if (context.mounted) showAppSnack(context, e.message, error: true);
                              }
                            },
                          ),
                        ],
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

  Future<void> _quickSection(BuildContext context, String gradeName, String tier) async {
    final store = StoreScope.of(context);
    final ctl = TextEditingController();
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
              Text('إضافة شعبة لمرحلة: $gradeName', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const FieldLabel('اسم الشعبة', requiredField: true),
              TextField(controller: ctl, decoration: const InputDecoration(hintText: 'مثال: الشعبة (ب)')),
              const SizedBox(height: 10),
              PrimaryButton(
                expand: true,
                label: 'حفظ الشعبة',
                onPressed: () {
                  try {
                    store.upsertRoom(Classroom(id: store.newId(), name: ctl.text.trim(), gradeLevel: gradeName, teacherId: '', capacity: 25, tier: tier));
                    Navigator.pop(ctx);
                    showAppSnack(context, 'تم إضافة الشعبة "${ctl.text.trim()}" إلى مرحلة $gradeName');
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

  Future<void> _edit(BuildContext context, GradeFee f) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: f.gradeName);
    final fee = TextEditingController(text: f.monthlyFee.toStringAsFixed(0));
    var tier = educationalStageTiers.containsKey(f.tier) ? f.tier : 'secondary';
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
                  Text('تعديل مرحلة ${f.gradeName}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                  const SizedBox(height: 10),
                  const FieldLabel('اسم المرحلة الدراسية', requiredField: true),
                  TextField(controller: name),
                  const SizedBox(height: 8),
                  const FieldLabel('المرحلة التعليمية الكبرى'),
                  AppDropdown<String>(
                    value: tier,
                    items: educationalStageTiers.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setSt(() => tier = v ?? tier),
                  ),
                  const SizedBox(height: 8),
                  const FieldLabel('الرسم الشهري (₪)', requiredField: true),
                  TextField(controller: fee, keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    expand: true,
                    label: 'حفظ',
                    onPressed: () {
                      try {
                        store.updateGradeFee(GradeFee(id: f.id, gradeName: name.text.trim(), monthlyFee: double.tryParse(fee.text) ?? f.monthlyFee, tier: tier, orderIndex: f.orderIndex, isCustom: f.isCustom));
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

class _TeachersTab extends StatefulWidget {
  const _TeachersTab();
  @override
  State<_TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<_TeachersTab> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = search.text.trim();
        final list = store.teachers.where((t) {
          if (q.isEmpty) return true;
          return t.name.contains(q) || t.phone.contains(q) || t.email.toLowerCase().contains(q.toLowerCase());
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(child: SearchField(controller: search, hint: 'بحث باسم المعلم أو رقم الهاتف...', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Text('${list.length} مدرس', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.heading)),
                  const SizedBox(width: 8),
                  PrimaryButton(label: 'إضافة مدرس', icon: Icons.add, onPressed: () => _edit(context)),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(message: 'لا يوجد مدرسين مسجلين.')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: [
                        for (var i = 0; i < list.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              onTap: () => _edit(context, list[i]),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('#${i + 1}', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontFamily: 'monospace')),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 13))),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(formatPhoneDisplay(list[i].phone), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  if (list[i].subjectIds.isNotEmpty || list[i].subject.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        for (final s in store.subjects.where((s) => list[i].subjectIds.contains(s.id) || s.name == list[i].subject))
                                          StatusChip.amber(s.name),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
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

  Future<void> _edit(BuildContext context, [Teacher? t]) async {
    final store = StoreScope.of(context);
    final parsed = parsePhoneAndPrefix(t?.phone);
    final name = TextEditingController(text: t?.name ?? '');
    final phone = TextEditingController(text: parsed.number);
    final email = TextEditingController(text: t?.email ?? '');
    final notes = TextEditingController(text: t?.notes ?? '');
    final teacherNationalId = TextEditingController(text: t?.nationalId ?? '');
    final teacherPortalCode = TextEditingController(
      text: (t?.portalCode.isNotEmpty ?? false) ? t!.portalCode : store.newPortalCode(),
    );
    final rate = TextEditingController(text: '${t?.rate ?? 70}');
    var prefix = parsed.prefix;
    var paymentType = teacherPaymentTypes.containsKey(t?.paymentType) ? t!.paymentType : 'percentage';
    var salaryOpen = false;
    final subjectIds = [...?t?.subjectIds];
    if (subjectIds.isEmpty && (t?.subject ?? '').isNotEmpty) {
      subjectIds.addAll(store.subjects.where((s) => s.name == t!.subject).map((s) => s.id));
    }
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
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t == null ? 'إضافة مدرس جديد' : 'تعديل بيانات: ${t.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                    const SizedBox(height: 10),
                    const FieldLabel('اسم المدرس', requiredField: true),
                    TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: أ. محمد العلي')),
                    const SizedBox(height: 8),
                    const FieldLabel('رقم الهاتف (بالمقدمة)', requiredField: true),
                    Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: AppDropdown<String>(
                              value: prefix,
                              items: phonePrefixes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                              onChanged: (v) => setSt(() => prefix = v ?? prefix),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: 'xxxxxxx')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const FieldLabel('البريد الإلكتروني'),
                    TextField(controller: email, keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 8),
                    // بيانات دخول المعلم إلى بوابته
                    const FieldLabel('رقم الهوية'),
                    TextField(
                      controller: teacherNationalId,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: const InputDecoration(hintText: '9 أرقام', counterText: ''),
                    ),
                    const SizedBox(height: 8),
                    const FieldLabel('رمز الدخول للبوابة'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: teacherPortalCode,
                            keyboardType: TextInputType.number,
                            maxLength: 10,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                            decoration: const InputDecoration(hintText: 'رمز من 6 أرقام', counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GhostButton(
                          label: 'توليد',
                          icon: Icons.autorenew,
                          onPressed: () => setSt(() {
                            teacherPortalCode.text = store.newPortalCode();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setSt(() => salaryOpen = !salaryOpen),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
                        child: Row(
                          children: [
                            const Icon(Icons.payments_outlined, size: 16, color: AppColors.amber),
                            const SizedBox(width: 6),
                            const Expanded(child: Text('نظام المحاسبة والراتب (بيانات إضافية)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                            Text(salaryOpen ? 'طي الإعدادات' : 'توسيع لتعديل الراتب', style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                            Icon(salaryOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: AppColors.muted),
                          ],
                        ),
                      ),
                    ),
                    if (salaryOpen) ...[
                      const SizedBox(height: 8),
                      const FieldLabel('نظام المحاسبة والراتب', requiredField: true),
                      AppDropdown<String>(
                        value: paymentType,
                        items: teacherPaymentTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                        onChanged: (v) => setSt(() => paymentType = v ?? paymentType),
                      ),
                      const SizedBox(height: 8),
                      FieldLabel(paymentType == 'percentage' ? 'النسبة (%)' : 'المبلغ (₪)', requiredField: true),
                      TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                    ],
                    const SizedBox(height: 8),
                    const FieldLabel('المواد التي يدرّسها المعلم:'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in store.subjects)
                          InkWell(
                            onTap: () => setSt(() {
                              if (subjectIds.contains(s.id)) {
                                subjectIds.remove(s.id);
                              } else {
                                subjectIds.add(s.id);
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: subjectIds.contains(s.id) ? AppColors.amber : Colors.white,
                                border: Border.all(color: subjectIds.contains(s.id) ? AppColors.amber : AppColors.line),
                              ),
                              child: Text(subjectIds.contains(s.id) ? '${s.name} ✓' : s.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: subjectIds.contains(s.id) ? Colors.white : AppColors.heading)),
                            ),
                          ),
                      ],
                    ),
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
                              onPressed: () async {
                                final ok = await confirmSheet(context, title: 'حذف المعلم', message: 'سيتم فك ارتباط المعلم بالمجموعات وحذف بياناته نهائياً.', confirmLabel: 'تأكيد الحذف');
                                if (ok) {
                                  store.deleteTeacher(t.id);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                }
                              },
                            ),
                          ),
                        if (t != null) const SizedBox(width: 8),
                        Expanded(
                          child: PrimaryButton(
                            label: t == null ? 'إضافة المدرس' : 'حفظ التعديلات',
                            onPressed: () {
                              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                                showAppSnack(context, 'يرجى إدخال اسم المدرس ورقم الهاتف', error: true);
                                return;
                              }
                              try {
                                final names = store.subjects.where((s) => subjectIds.contains(s.id)).map((s) => s.name).toList();
                                store.upsertTeacher(
                                  Teacher(
                                    id: t?.id ?? store.newId(),
                                    name: name.text.trim(),
                                    phone: combinePhoneAndPrefix(phone.text.trim(), prefix),
                                    subject: names.isEmpty ? '' : names.first,
                                    rate: double.tryParse(rate.text.trim()) ?? 70,
                                    email: email.text.trim(),
                                    paymentType: paymentType,
                                    notes: notes.text.trim(),
                                    nationalId: digitsOnly(teacherNationalId.text),
                                    portalCode: teacherPortalCode.text.trim(),
                                    subjectIds: [...subjectIds],
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
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SubjectsTab extends StatefulWidget {
  const _SubjectsTab();
  @override
  State<_SubjectsTab> createState() => _SubjectsTabState();
}

class _SubjectsTabState extends State<_SubjectsTab> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = search.text.trim();
        final list = store.subjects.where((s) {
          if (q.isEmpty) return true;
          return s.name.contains(q) || s.code.toLowerCase().contains(q.toLowerCase()) || s.gradeLevel.contains(q);
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(child: SearchField(controller: search, hint: 'بحث باسم المادة، الرمز، أو المرحلة...', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Text('${list.length} مادة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                  const SizedBox(width: 8),
                  PrimaryButton(label: 'إضافة مادة', icon: Icons.add, onPressed: () => _edit(context)),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(message: 'لا توجد مواد دراسية مسجلة.')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: [
                        for (final s in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              onTap: () => _edit(context, s),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 36,
                                    alignment: Alignment.center,
                                    color: const Color(0xFFF1F5F9),
                                    child: Text(s.code.isEmpty ? '—' : s.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: AppColors.navy)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                                        Text(s.gradeLevel.isEmpty ? 'عام / كل المراحل' : s.gradeLevel, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                                        if (s.description.isNotEmpty) Text(s.description, style: const TextStyle(color: AppColors.faint, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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

  Future<void> _edit(BuildContext context, [SubjectItem? s]) async {
    final store = StoreScope.of(context);
    final grades = <String>{'عام / كل المراحل', ...store.gradeFees.map((g) => g.gradeName), ...store.rooms.map((r) => r.gradeLevel)};
    final name = TextEditingController(text: s?.name ?? '');
    final code = TextEditingController(text: s?.code ?? '');
    final desc = TextEditingController(text: s?.description ?? '');
    var grade = s?.gradeLevel.isNotEmpty == true ? s!.gradeLevel : (store.gradeFees.isNotEmpty ? store.gradeFees.first.gradeName : 'عام / كل المراحل');
    if (!grades.contains(grade)) grades.add(grade);
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
                  Text(s == null ? 'إضافة مادة دراسية جديدة' : 'تعديل مادة: ${s.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                  const SizedBox(height: 10),
                  const FieldLabel('اسم المادة الدراسية', requiredField: true),
                  TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: الرياضيات، الفيزياء...')),
                  const SizedBox(height: 8),
                  const FieldLabel('رمز المادة (اختياري)'),
                  TextField(controller: code, decoration: const InputDecoration(hintText: 'مثال: MATH-1')),
                  const SizedBox(height: 8),
                  const FieldLabel('المرحلة الدراسية'),
                  AppDropdown<String>(
                    value: grade,
                    items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (v) => setSt(() => grade = v ?? grade),
                  ),
                  const SizedBox(height: 8),
                  const FieldLabel('وصف أو ملاحظات'),
                  TextField(controller: desc, decoration: const InputDecoration(hintText: 'ملاحظات توضيحية عن المنهاج...')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (s != null)
                        Expanded(
                          child: GhostButton(
                            label: 'حذف',
                            onPressed: () {
                              store.deleteSubject(s.id);
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      if (s != null) const SizedBox(width: 8),
                      Expanded(
                        child: PrimaryButton(
                          label: s == null ? 'إضافة المادة' : 'حفظ التعديلات',
                          onPressed: () {
                            try {
                              store.upsertSubject(SubjectItem(id: s?.id ?? store.newId(), name: name.text.trim(), code: code.text.trim(), gradeLevel: grade, description: desc.text.trim()));
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

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = store.users.where((u) => u.id == store.deviceUserId).firstOrNull ?? store.users.firstOrNull;
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
                        Text(active == null ? store.roleName : '${roleLabel(active.role)} · ${active.name}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        if (store.receiptReceiverLabel.isNotEmpty)
                          Text('اسم المستلم على السند: ${store.receiptReceiverLabel}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined, color: AppColors.navy, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                                Text(roleLabel(u.role), style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          StatusChip.success(u.isActive ? 'نشط' : 'موقوف'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          GhostButton(label: 'تثبيت على الجهاز', onPressed: () => _setIdentity(context, u)),
                          const SizedBox(width: 8),
                          GhostButton(label: 'الصلاحيات', onPressed: () => _editCaps(context, u)),
                          if (store.users.length > 1) ...[
                            const SizedBox(width: 8),
                            GhostButton(
                              label: 'حذف',
                              onPressed: () async {
                                final ok = await confirmSheet(context, title: 'حذف المستخدم', message: 'حذف ${u.name}؟', confirmLabel: 'حذف');
                                if (ok) {
                                  try {
                                    store.deleteUser(u.id);
                                  } on StoreException catch (e) {
                                    if (context.mounted) showAppSnack(context, e.message, error: true);
                                  }
                                }
                              },
                            ),
                          ],
                        ],
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

  Future<void> _setIdentity(BuildContext context, AppUser u) async {
    final store = StoreScope.of(context);
    final label = TextEditingController(text: store.receiptReceiverLabel.isEmpty ? u.name : store.receiptReceiverLabel);
    if (normalizeRole(u.role) == 'admin') {
      final pass = TextEditingController();
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
                const Text('تأكيد كلمة مرور المدير', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const FieldLabel('اسم المستلم على سند القبض'),
                TextField(controller: label),
                const SizedBox(height: 8),
                const FieldLabel('كلمة مرور المنشأة'),
                TextField(controller: pass, obscureText: true),
                const SizedBox(height: 10),
                PrimaryButton(
                  expand: true,
                  label: 'تثبيت',
                  onPressed: () {
                    final tenantPass = store.currentTenant?.password ?? 'amal2026';
                    final entered = pass.text.trim();
                    if (entered != tenantPass && entered != 'school2026' && entered != 'anas2026') {
                      showAppSnack(context, 'كلمة المرور غير صحيحة', error: true);
                      return;
                    }
                    store.setDeviceIdentity(u, label.text);
                    Navigator.pop(ctx);
                    showAppSnack(context, 'تم تثبيت هوية الجهاز');
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }
    store.setDeviceIdentity(u, label.text);
    showAppSnack(context, 'تم تثبيت هوية الجهاز');
  }

  Future<void> _editCaps(BuildContext context, AppUser u) async {
    final store = StoreScope.of(context);
    final selected = {...effectiveCapabilities(u.capabilities, u.role)};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              return SizedBox(
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صلاحيات ${u.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final g in capabilityGroups) ...[
                            Text(g.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.navy)),
                            for (final item in g.items)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: selected.contains(item.id),
                                title: Text(item.label, style: const TextStyle(fontSize: 12.5)),
                                subtitle: item.hint == null ? null : Text(item.hint!, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                                onChanged: (v) => setSt(() {
                                  if (v == true) {
                                    selected.add(item.id);
                                  } else {
                                    selected.remove(item.id);
                                  }
                                }),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                    PrimaryButton(
                      expand: true,
                      label: 'حفظ الصلاحيات',
                      onPressed: () {
                        store.updateUser(AppUser(id: u.id, name: u.name, role: u.role, email: u.email, isActive: u.isActive, capabilities: selected.toList()));
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _add(BuildContext context) async {
    final store = StoreScope.of(context);
    final name = TextEditingController();
    var role = 'receptionist';
    final caps = {...receptionistCapabilities};
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
              return SizedBox(
                height: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('مستخدم جديد', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                    const SizedBox(height: 10),
                    const FieldLabel('الاسم', requiredField: true),
                    TextField(controller: name),
                    const SizedBox(height: 8),
                    const FieldLabel('الدور (قالب بداية)'),
                    AppDropdown<String>(
                      value: role,
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('مدير النظام')),
                        DropdownMenuItem(value: 'receptionist', child: Text('سكرتير')),
                      ],
                      onChanged: (v) => setSt(() {
                        role = v ?? role;
                        caps
                          ..clear()
                          ..addAll(defaultCapsFor(role));
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Text('الصلاحيات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final g in capabilityGroups)
                            for (final item in g.items)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: caps.contains(item.id),
                                title: Text(item.label, style: const TextStyle(fontSize: 12)),
                                onChanged: (v) => setSt(() {
                                  if (v == true) {
                                    caps.add(item.id);
                                  } else {
                                    caps.remove(item.id);
                                  }
                                }),
                              ),
                        ],
                      ),
                    ),
                    PrimaryButton(
                      expand: true,
                      label: 'حفظ',
                      onPressed: () {
                        try {
                          store.addUser(AppUser(id: store.newId(), name: name.text.trim(), role: role, capabilities: caps.toList()));
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
                      'عمليات متعثرة بعد $maxSyncRetries محاولات: ${store.sync.getFailedActions().length}',
                      style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    for (final a in store.sync.getFailedActions().take(5))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${tableLabelsAr[a.tableName] ?? a.tableName}: ${a.lastError ?? ''}',
                          style: const TextStyle(color: AppColors.danger, fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'إعادة محاولة الرفع',
                            icon: Icons.refresh,
                            onPressed: () async {
                              final count = store.sync.retryFailedActions();
                              final result = await store.sync.push();
                              if (!context.mounted) return;
                              showAppSnack(
                                context,
                                count == 0 ? 'لا توجد عمليات متعثرة' : result.message,
                                error: !result.success,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GhostButton(
                            label: 'تجاهل المتعثرة',
                            icon: Icons.delete_outline,
                            onPressed: () async {
                              final failed = store.sync.getFailedActions();
                              final ok = await confirmSheet(
                                context,
                                title: 'تجاهل العمليات المتعثرة',
                                message:
                                    'سيتم إسقاط ${failed.length} عملية من طابور الرفع نهائياً. '
                                    'التعديلات تبقى على هذا الجهاز لكنها لن تصل السحابة.',
                                confirmLabel: 'تجاهل',
                              );
                              if (!ok) return;
                              for (final a in failed) {
                                store.sync.discardAction(a);
                              }
                              store.markAllDirty();
                              if (!context.mounted) return;
                              showAppSnack(context, 'تم إسقاط ${failed.length} عملية متعثرة');
                            },
                          ),
                        ),
                      ],
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('النسخ الاحتياطي والبيانات'),
                  PrimaryButton(
                    expand: true,
                    label: 'تصدير نسخة احتياطية',
                    icon: Icons.download,
                    onPressed: () => _export(context, store),
                  ),
                  const SizedBox(height: 8),
                  GhostButton(
                    label: 'استرجاع نسخة احتياطية',
                    icon: Icons.upload_file_outlined,
                    onPressed: () => _restore(context, store),
                  ),
                  if (store.can('settings.branding')) ...[
                    const SizedBox(height: 8),
                    GhostButton(
                      label: 'إعدادات المطور وهوية المنشأة',
                      icon: Icons.tune,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DeveloperSettingsScreen()),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _export(BuildContext context, AppStore store) async {
    try {
      final path = await const BackupService().export(store);
      if (!context.mounted) return;
      showAppSnack(context, 'تم حفظ النسخة الاحتياطية في: $path');
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'تعذّر تصدير النسخة: $e', error: true);
    }
  }

  Future<void> _restore(BuildContext context, AppStore store) async {
    const service = BackupService();
    String? json;
    try {
      json = await service.pickFile();
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'تعذّر فتح الملف: $e', error: true);
      return;
    }
    if (json == null || !context.mounted) return;

    Map<String, int> summary;
    try {
      summary = service.summarize(json);
    } catch (_) {
      if (!context.mounted) return;
      showAppSnack(context, 'الملف ليس نسخة احتياطية صالحة', error: true);
      return;
    }

    final lines = summary.entries.map((e) => '${tableLabelsAr[e.key] ?? e.key}: ${e.value}').join('\n');
    final ok = await confirmSheet(
      context,
      title: 'استرجاع نسخة احتياطية',
      message: 'سيتم استبدال كل البيانات المحلية بمحتوى الملف:\n\n$lines\n\n'
          'لا يمكن التراجع عن هذه العملية. هل تريد المتابعة؟',
      confirmLabel: 'استرجاع',
    );
    if (!ok || !context.mounted) return;

    try {
      final count = await service.restore(store, json);
      if (!context.mounted) return;
      showAppSnack(context, 'تم استرجاع $count سجلاً بنجاح');
    } catch (e) {
      if (!context.mounted) return;
      showAppSnack(context, 'فشل الاسترجاع: $e', error: true);
    }
  }
}

/// إدارة القاعات — المقابل لـ `features/settings/Rooms.tsx` (نظام المركز).
class _RoomsTab extends StatelessWidget {
  const _RoomsTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final rooms = [...store.rooms]..sort((a, b) => a.name.compareTo(b.name));
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('القاعات الدراسية',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
                        Text('القاعات التي تُحجز للمجموعات في الجدول الأسبوعي',
                            style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  PrimaryButton(label: 'إضافة قاعة', icon: Icons.add, onPressed: () => _edit(context, null)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (rooms.isEmpty)
              const EmptyState(message: 'لا توجد قاعات مسجلة بعد')
            else
              for (final r in rooms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => _edit(context, r),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                              Text(
                                [
                                  'السعة: ${r.capacity}',
                                  if (r.notes.isNotEmpty) r.notes,
                                ].join('  ·  '),
                                style: const TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${store.groups.where((g) => g.roomId == r.id && g.isActive).length} مجموعة',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Classroom? room) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: room?.name ?? '');
    final capacity = TextEditingController(text: '${room?.capacity ?? 25}');
    final notes = TextEditingController(text: room?.notes ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(room == null ? 'إضافة قاعة جديدة' : 'تعديل: ${room.name}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
            const SizedBox(height: 10),
            const FieldLabel('اسم القاعة', requiredField: true),
            TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: القاعة (أ)')),
            const SizedBox(height: 8),
            const FieldLabel('السعة'),
            TextField(controller: capacity, keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            const FieldLabel('ملاحظات وتجهيزات'),
            TextField(controller: notes, decoration: const InputDecoration(hintText: 'الطابق، التجهيزات...')),
            const SizedBox(height: 14),
            Row(
              children: [
                if (room != null)
                  Expanded(
                    child: GhostButton(
                      label: 'حذف',
                      icon: Icons.delete_outline,
                      onPressed: () async {
                        final used = store.groups.where((g) => g.roomId == room.id).length;
                        if (used > 0) {
                          showAppSnack(ctx, 'لا يمكن حذف القاعة لارتباطها بـ $used مجموعة', error: true);
                          return;
                        }
                        final ok = await confirmSheet(ctx,
                            title: 'حذف القاعة', message: 'حذف «${room.name}»؟', confirmLabel: 'حذف');
                        if (!ok || !ctx.mounted) return;
                        store.deleteRoom(room.id);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                if (room != null) const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: room == null ? 'إضافة القاعة' : 'حفظ',
                    onPressed: () {
                      try {
                        store.upsertRoom(
                          Classroom(
                            id: room?.id ?? store.newId(),
                            name: name.text.trim(),
                            gradeLevel: room?.gradeLevel ?? '',
                            teacherId: room?.teacherId ?? '',
                            capacity: int.tryParse(capacity.text.trim()) ?? 25,
                            notes: notes.text.trim(),
                            tier: room?.tier ?? 'secondary',
                            createdAt: room?.createdAt,
                          ),
                        );
                        Navigator.pop(ctx);
                      } on StoreException catch (e) {
                        showAppSnack(ctx, e.message, error: true);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    name.dispose();
    capacity.dispose();
    notes.dispose();
  }
}
