import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/demo_data.dart';
import '../data/institution.dart';
import '../data/store.dart';
import '../data/supabase.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// إعدادات المطور — المقابل لـ `features/settings/DeveloperSettings.tsx`.
///
/// محمية بكلمة مرور المطور، وتضم: نوع المنشأة، الاسم، الشعار، ألوان الهوية،
/// البيانات التجريبية، تصفير القاعدة، ومعلومات النظام.
class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  State<DeveloperSettingsScreen> createState() => _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  static const _devPassword = 'anas2026';

  bool unlocked = false;
  final gate = TextEditingController();
  String? gateError;

  late String type;
  late TextEditingController name;
  late String logo;
  late InstitutionColors colors;
  late TextEditingController seatFee;
  late TextEditingController supabaseUrlCtrl;
  late TextEditingController supabaseKeyCtrl;

  bool busy = false;

  @override
  void initState() {
    super.initState();
    final store = AppStore.instance;
    type = store.institutionType;
    name = TextEditingController(text: store.institutionName);
    logo = store.institutionLogo;
    colors = store.institutionColors;
    seatFee = TextEditingController(text: '${store.seatReservationFee}');
    supabaseUrlCtrl = TextEditingController(text: store.db.settings[SupabaseConfig.urlSettingKey] ?? '');
    supabaseKeyCtrl = TextEditingController(text: store.db.settings[SupabaseConfig.keySettingKey] ?? '');
  }

  @override
  void dispose() {
    gate.dispose();
    name.dispose();
    seatFee.dispose();
    supabaseUrlCtrl.dispose();
    supabaseKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('تخصيص المنشأة وأدوات المطور')),
      body: unlocked ? _body(context, store) : _gate(context),
    );
  }

  Widget _gate(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 32, color: AppColors.amber),
                const SizedBox(height: 10),
                Text(
                  'هذا القسم خاص بالمطور',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                ),
                const SizedBox(height: 4),
                const Text(
                  'أدخل كلمة مرور المطور للوصول إلى إعدادات الهوية وأدوات البيانات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: gate,
                  obscureText: true,
                  onSubmitted: (_) => _unlock(),
                  decoration: const InputDecoration(hintText: 'كلمة مرور المطور'),
                ),
                if (gateError != null) ...[
                  const SizedBox(height: 8),
                  Text(gateError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                PrimaryButton(expand: true, label: 'فتح القسم', icon: Icons.key, onPressed: _unlock),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _unlock() {
    if (gate.text.trim() == _devPassword) {
      setState(() {
        unlocked = true;
        gateError = null;
      });
    } else {
      setState(() => gateError = 'كلمة المرور غير صحيحة');
    }
  }

  Widget _body(BuildContext context, AppStore store) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _institutionType(store),
        const SizedBox(height: 8),
        _identity(store),
        const SizedBox(height: 8),
        _colors(store),
        const SizedBox(height: 8),
        _financeRules(store),
        const SizedBox(height: 8),
        _features(store),
        const SizedBox(height: 8),
        _connection(store),
        const SizedBox(height: 8),
        _tools(context, store),
        const SizedBox(height: 8),
        _systemInfo(store),
      ],
    );
  }

  Widget _institutionType(AppStore store) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('نوع المنشأة التشغيلي'),
          for (final e in institutionTypes.entries)
            InkWell(
              onTap: () => setState(() => type = e.key),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: type == e.key ? AppColors.amberSoft : Colors.white,
                  border: Border.all(color: type == e.key ? AppColors.amber : AppColors.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      type == e.key ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 16,
                      color: type == e.key ? AppColors.amber : AppColors.faint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                          Text(institutionTypeHints[e.key] ?? '',
                              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Text(
            'تغيير النوع يبدّل قسم «الصفوف» بقسم «الجدول والمجموعات» وبالعكس.',
            style: TextStyle(color: AppColors.faint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _identity(AppStore store) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('اسم المنشأة وشعارها'),
          const FieldLabel('اسم المنشأة والترويسة الرسمية'),
          TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: مدرسة الأمل الخاصة')),
          const SizedBox(height: 10),
          const FieldLabel('شعار المنشأة'),
          Row(
            children: [
              InstitutionBadge(logo: logo, size: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GhostButton(label: 'رفع شعار جديد', icon: Icons.upload_outlined, onPressed: _pickLogo),
                    if (logo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      GhostButton(
                        label: 'إزالة الشعار',
                        icon: Icons.delete_outline,
                        onPressed: () => setState(() => logo = ''),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            expand: true,
            label: 'حفظ وتطبيق إعدادات المنشأة',
            icon: Icons.save_outlined,
            busy: busy,
            onPressed: () => _save(store),
          ),
        ],
      ),
    );
  }

  Widget _colors(AppStore store) {
    final swatches = <(String, String, String)>[
      ('sidebarBg', colors.sidebarBg, 'خلفية الترويسة والقوائم'),
      ('activeItem', colors.activeItem, 'تمييز القسم المفتوح'),
      ('primaryButton', colors.primaryButton, 'الأزرار الأساسية والعناوين'),
      ('actionButton', colors.actionButton, 'أزرار الإجراء وبادجات المبالغ'),
      ('appBg', colors.appBg, 'خلفية مساحة العمل'),
    ];

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('ألوان هوية المنشأة'),
          for (final s in swatches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _pickColor(s.$1, s.$2),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: parseHexColor(s.$2) ?? Colors.white,
                        border: Border.all(color: AppColors.lineStrong),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.$3, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        Text(s.$2, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text('تشكيلات جاهزة:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in colorPresets)
                InkWell(
                  onTap: () => setState(() => colors = preset.$2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 12, height: 12, color: parseHexColor(preset.$2.sidebarBg)),
                        Container(width: 12, height: 12, color: parseHexColor(preset.$2.actionButton)),
                        const SizedBox(width: 6),
                        Text(preset.$1, style: const TextStyle(fontSize: 10.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _financeRules(AppStore store) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('القواعد المالية'),
          const FieldLabel('رسم حجز المقعد (₪)'),
          TextField(controller: seatFee, keyboardType: TextInputType.number),
          const SizedBox(height: 4),
          const Text(
            'يُضاف إلى رصيد الطالب عند تعليم «تم تسديد حجز المقعد». اتركه صفراً إن لم تعتمد الإدارة رسماً.',
            style: TextStyle(color: AppColors.faint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  /// خيارات التحكم بالميزات — المقابل لتبويب «features» في DeveloperSettings.tsx.
  ///
  /// الحفظ محلي لكل جهاز كما في سطح المكتب: `institution_settings` المشترك
  /// لا يحمل عموداً لها، فإرسالها فيه كان يُسقطها صامتاً.
  Widget _features(AppStore store) {
    final f = store.features;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('خيارات التحكم بالميزات والموديولات'),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'تفعيل أو تعطيل الأقسام والوظائف بحسب متطلبات واحتياجات المدرسة',
              style: TextStyle(color: AppColors.faint, fontSize: 10.5),
            ),
          ),
          _featureRow(
            title: 'إدارة المصروفات وأجور المعلمين',
            hint: 'إظهار تبويب وسجلات المصروفات وسندات الصرف وأجور المعلمين داخل الشاشة المالية.',
            value: f.enableExpenses,
            onChanged: (v) => store.saveFeatures(enableExpenses: v),
          ),
          _featureRow(
            title: 'تقييمات ودرجات الطلاب (موديول أكاديمي)',
            hint: 'إتاحة رصد درجات الطلاب للمعلم، وظهور تبويب التقييمات بالإدارة، وعرض النتائج في بوابة وملف الطالب.',
            value: f.enableEvaluations,
            onChanged: (v) => store.saveFeatures(enableEvaluations: v),
          ),
          _featureRow(
            title: 'بوابة الطالب الإلكترونية',
            hint: 'تمكين الطلاب وأولياء الأمور من الدخول برقم الهوية ورمز الدخول لاستعراض الحضور والرسوم والمواد.',
            value: f.enableStudentPortal,
            onChanged: (v) => store.saveFeatures(enableStudentPortal: v),
          ),
        ],
      ),
    );
  }

  Widget _featureRow({
    required String title,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.line),
      ),
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
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    value ? StatusChip.success('مفعل') : StatusChip.muted('معطل'),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.success,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _connection(AppStore store) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('الاتصال بالسحابة'),
          const FieldLabel('عنوان Supabase'),
          TextField(
            controller: supabaseUrlCtrl,
            decoration: InputDecoration(hintText: SupabaseConfig.defaultUrl),
          ),
          const SizedBox(height: 8),
          const FieldLabel('مفتاح النشر'),
          TextField(
            controller: supabaseKeyCtrl,
            decoration: const InputDecoration(hintText: 'اتركه فارغاً للمفتاح الافتراضي'),
          ),
          const SizedBox(height: 4),
          Text(
            SupabaseConfig.isCustom ? 'يعمل حالياً على عنوان مخصص.' : 'يعمل حالياً على العنوان الافتراضي.',
            style: const TextStyle(color: AppColors.faint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _tools(BuildContext context, AppStore store) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('أدوات الاختبار والبيانات'),
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('توليد بيانات تجريبية',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                const Text('تغذية النظام بسجلات للتجربة والاختبار',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                const SizedBox(height: 8),
                GhostButton(
                  label: 'حقن البيانات التجريبية',
                  icon: Icons.science_outlined,
                  onPressed: () async {
                    final ok = await confirmSheet(
                      context,
                      title: 'حقن بيانات تجريبية',
                      message: 'ستُضاف منشآت وطلاب ومدرّسون تجريبيون إلى قاعدة البيانات المحلية. هل تريد المتابعة؟',
                      confirmLabel: 'حقن',
                    );
                    if (!ok || !context.mounted) return;
                    injectDemoData(store);
                    await store.flush();
                    if (context.mounted) showAppSnack(context, 'تم حقن البيانات التجريبية');
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.dangerSoft, border: Border.all(color: AppColors.dangerBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('مسح وتصفير قاعدة البيانات',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.danger)),
                const Text('حذف كل السجلات المحلية للبدء بقاعدة نظيفة',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                const SizedBox(height: 8),
                GhostButton(
                  label: 'تصفير القاعدة المحلية',
                  icon: Icons.delete_forever_outlined,
                  onPressed: () async {
                    final ok = await confirmSheet(
                      context,
                      title: 'تصفير قاعدة البيانات',
                      message: 'سيتم حذف كل الطلاب والدفعات والحضور من هذا الجهاز نهائياً. '
                          'البيانات المرفوعة للسحابة تبقى كما هي. هل أنت متأكد؟',
                      confirmLabel: 'تصفير',
                    );
                    if (!ok || !context.mounted) return;
                    await store.wipeAllData();
                    if (context.mounted) showAppSnack(context, 'تم تصفير قاعدة البيانات المحلية');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemInfo(AppStore store) {
    final rows = <(String, String)>[
      ('إصدار المنظومة', appVersion),
      ('قاعدة البيانات المحلية', 'SQLite'),
      ('وضع التخزين', 'محلي / مستقل (Offline Ready)'),
      ('المنشأة الحالية', store.currentTenant?.name ?? '—'),
      ('رمز المنشأة', store.currentTenant?.code ?? '—'),
      ('نوع الاشتراك', store.currentTenant == null
          ? '—'
          : (store.currentTenant!.isLifetime ? 'دائم' : 'محدد المدة')),
      ('تعديلات معلّقة', '${store.pendingPush}'),
    ];

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('معلومات النظام وبيئة التشغيل'),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(r.$1, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
                  Expanded(
                    child: Text(r.$2,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.heading)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => logo = 'data:image/png;base64,${base64Encode(bytes)}');
  }

  Future<void> _pickColor(String key, String current) async {
    final ctrl = TextEditingController(text: current);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('لون مخصص', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '#0B2545'),
        ),
        actions: [
          GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx)),
          PrimaryButton(label: 'تطبيق', onPressed: () => Navigator.pop(ctx, ctrl.text.trim())),
        ],
      ),
    );
    ctrl.dispose();
    if (picked == null || parseHexColor(picked) == null) return;
    setState(() {
      colors = switch (key) {
        'sidebarBg' => colors.copyWith(sidebarBg: picked),
        'activeItem' => colors.copyWith(activeItem: picked),
        'primaryButton' => colors.copyWith(primaryButton: picked),
        'actionButton' => colors.copyWith(actionButton: picked),
        _ => colors.copyWith(appBg: picked),
      };
    });
  }

  Future<void> _save(AppStore store) async {
    setState(() => busy = true);
    await store.saveInstitution(type: type, name: name.text, logo: logo, colors: colors);
    await store.setSeatReservationFee(double.tryParse(seatFee.text.trim()) ?? 0);
    await store.db.setSetting(SupabaseConfig.urlSettingKey, supabaseUrlCtrl.text.trim().isEmpty ? null : supabaseUrlCtrl.text.trim());
    await store.db.setSetting(SupabaseConfig.keySettingKey, supabaseKeyCtrl.text.trim().isEmpty ? null : supabaseKeyCtrl.text.trim());
    SupabaseConfig.applyOverrides(store.db.settings);
    if (!mounted) return;
    setState(() => busy = false);
    showAppSnack(context, 'تم حفظ إعدادات المنشأة وتطبيقها');
  }
}
