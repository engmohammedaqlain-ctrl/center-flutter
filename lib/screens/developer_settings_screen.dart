import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/demo_data.dart';
import '../data/institution.dart';
import '../data/store.dart';
import '../data/supabase.dart';
import '../data/tenant_service.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/panels.dart';
import '../widgets/widgets.dart';

/// إعدادات المطور — المقابل لـ `features/settings/DeveloperSettings.tsx`.
///
/// محمية بكلمة مرور المطور. بتخطيط النماذج: أقسام بعنوان وخط لا بطاقات، وحفظ
/// هوية المنشأة ثابت أسفل الشاشة. الميزات تُحفظ فور تبديلها، وأدوات البيانات
/// تُنفَّذ بتأكيد.
class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  State<DeveloperSettingsScreen> createState() => _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {

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
  final errors = FieldErrors();

  bool busy = false;

  @override
  void initState() {
    super.initState();
    final store = AppStore.instance;
    type = store.institutionType;
    name = TextEditingController(text: store.institutionName);
    logo = store.institutionLogo;
    colors = store.institutionColors;
    seatFee = TextEditingController(text: trimNum(store.seatReservationFee));
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('تخصيص المنشأة وأدوات المطور'),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
      bottomNavigationBar: unlocked
          ? FormActionBar(
              label: 'حفظ وتطبيق الإعدادات',
              icon: Icons.save_outlined,
              busy: busy,
              onSave: busy ? null : () => _save(store),
            )
          : null,
      body: unlocked ? _body(context, store) : _gate(),
    );
  }

  // ── بوابة كلمة المرور ───────────────────────────────────────────────────

  Widget _gate() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Corner.card),
                    color: AppColors.amberSoft,
                    border: Border.all(color: AppColors.amberBorder),
                  ),
                  child: Icon(Icons.lock_outline, size: 26, color: AppColors.amber),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'هذا القسم خاص بالمطور',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.heading),
              ),
              const SizedBox(height: 4),
              const Text(
                'أدخل كلمة مرور المطور للوصول إلى هوية المنشأة وأدوات البيانات.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 18),
              const FieldLabel('كلمة مرور المطور', requiredField: true),
              TextField(
                controller: gate,
                obscureText: true,
                onSubmitted: (_) => _unlock(),
                onChanged: (_) {
                  if (gateError != null) setState(() => gateError = null);
                },
                decoration: InputDecoration(hintText: '••••••••', errorText: gateError),
              ),
              const SizedBox(height: 14),
              PrimaryButton(expand: true, height: 44, label: 'فتح القسم', icon: Icons.key, onPressed: _unlock),
            ],
          ),
        ),
      ),
    );
  }

  void _unlock() {
    final entered = gate.text.trim();
    if (!TenantService.hasMasterAccount) {
      // نسخة وُزّعت بلا حساب مطور: لا باب خلفياً يُفتح بكلمة محفوظة في الكود
      setState(() => gateError = 'هذه النسخة بُنيت بلا حساب مطور');
    } else if (entered.isEmpty) {
      setState(() => gateError = 'يرجى إدخال كلمة مرور المطور');
    } else if (entered != TenantService.masterPassword.trim()) {
      setState(() => gateError = 'كلمة المرور غير صحيحة');
    } else {
      setState(() {
        unlocked = true;
        gateError = null;
      });
    }
  }

  // ── المحتوى ──────────────────────────────────────────────────────────────

  Widget _body(BuildContext context, AppStore store) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ..._institutionType(),
          ..._identity(),
          ..._colors(),
          ..._financeRules(),
          ..._connection(),
          ..._features(store),
          ..._tools(context, store),
          ..._systemInfo(store),
        ],
      ),
    );
  }

  List<Widget> _institutionType() => [
        const FormSection(icon: Icons.apartment_outlined, title: 'نوع المنشأة التشغيلي'),
        for (final e in institutionTypes.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _choiceTile(
              selected: type == e.key,
              title: e.value,
              subtitle: institutionTypeHints[e.key] ?? '',
              onTap: () => setState(() => type = e.key),
            ),
          ),
        const Text(
          'تغيير النوع يبدّل قسم «الصفوف» بقسم «الجدول والمجموعات» وبالعكس.',
          style: TextStyle(color: AppColors.faint, fontSize: 10.5),
        ),
      ];

  Widget _choiceTile({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.box),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: selected ? AppColors.amberSoft : Colors.white,
          border: Border.all(color: selected ? AppColors.amber : AppColors.line),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.amber : AppColors.faint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _identity() => [
        const FormSection(icon: Icons.badge_outlined, title: 'اسم المنشأة وشعارها'),
        const FieldLabel('اسم المنشأة والترويسة الرسمية'),
        TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: مدرسة الأمل الخاصة')),
        const SizedBox(height: 12),
        const FieldLabel('شعار المنشأة'),
        Row(
          children: [
            InstitutionBadge(logo: logo, size: 56, onDark: false),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TileButton(
                    label: logo.isEmpty ? 'رفع شعار' : 'تغيير الشعار',
                    icon: const Icon(Icons.upload_outlined, size: 13),
                    color: AppColors.heading,
                    background: Colors.white,
                    border: AppColors.lineStrong,
                    onTap: _pickLogo,
                  ),
                  if (logo.isNotEmpty)
                    TileButton(
                      label: 'إزالة',
                      icon: const Icon(Icons.delete_outline, size: 13),
                      color: AppColors.danger,
                      background: Colors.white,
                      border: AppColors.dangerBorder,
                      onTap: () => setState(() => logo = ''),
                    ),
                ],
              ),
            ),
          ],
        ),
      ];

  List<Widget> _colors() {
    final swatches = <(String, String, String)>[
      ('sidebarBg', colors.sidebarBg, 'خلفية الترويسة والقوائم'),
      ('activeItem', colors.activeItem, 'تمييز القسم المفتوح'),
      ('primaryButton', colors.primaryButton, 'الأزرار الأساسية والعناوين'),
      ('actionButton', colors.actionButton, 'أزرار الإجراء وبادجات المبالغ'),
      ('appBg', colors.appBg, 'خلفية مساحة العمل'),
    ];

    return [
      const FormSection(icon: Icons.palette_outlined, title: 'ألوان هوية المنشأة', note: 'اضغط اللون لتغييره'),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            for (var i = 0; i < swatches.length; i++)
              InkWell(
                onTap: () => _pickColor(swatches[i].$1, swatches[i].$2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    border: i == swatches.length - 1
                        ? null
                        : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Corner.box),
                          color: parseHexColor(swatches[i].$2) ?? Colors.white,
                          border: Border.all(color: AppColors.lineStrong),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          swatches[i].$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text),
                        ),
                      ),
                      Text(
                        swatches[i].$2.toUpperCase(),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted, fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 18, color: AppColors.faint),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const FieldLabel('تشكيلات جاهزة'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final preset in colorPresets)
            InkWell(
              onTap: () => setState(() => colors = preset.$2),
              borderRadius: BorderRadius.circular(Corner.box),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: tileDecoration(white: true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dot(preset.$2.sidebarBg),
                    const SizedBox(width: 2),
                    _dot(preset.$2.actionButton),
                    const SizedBox(width: 6),
                    Text(preset.$1, style: const TextStyle(fontSize: 11, color: AppColors.text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];
  }

  Widget _dot(String hex) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.chip),
          color: parseHexColor(hex) ?? Colors.white,
        ),
      );

  List<Widget> _financeRules() => [
        const FormSection(icon: Icons.payments_outlined, title: 'القواعد المالية'),
        FieldLabel('رسم حجز المقعد (₪)', key: errors.key('seatFee')),
        TextField(
          controller: seatFee,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {
            if (errors.clear('seatFee')) setState(() {});
          },
          decoration: InputDecoration(errorText: errors['seatFee']),
        ),
        const SizedBox(height: 4),
        const Text(
          'يُضاف إلى رصيد الطالب عند تعليم «تم تسديد حجز المقعد». اتركه صفراً إن لم تعتمد الإدارة رسماً.',
          style: TextStyle(color: AppColors.faint, fontSize: 10.5, height: 1.4),
        ),
      ];

  List<Widget> _connection() => [
        const FormSection(icon: Icons.cloud_outlined, title: 'الاتصال بالسحابة'),
        FieldLabel('عنوان Supabase', key: errors.key('url')),
        TextField(
          controller: supabaseUrlCtrl,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          onChanged: (_) {
            if (errors.clear('url')) setState(() {});
          },
          decoration: InputDecoration(hintText: SupabaseConfig.defaultUrl, errorText: errors['url']),
        ),
        const SizedBox(height: 12),
        const FieldLabel('مفتاح النشر'),
        TextField(
          controller: supabaseKeyCtrl,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'اتركه فارغاً للمفتاح الافتراضي'),
        ),
        const SizedBox(height: 4),
        Text(
          SupabaseConfig.isCustom ? 'يعمل حالياً على عنوان مخصص.' : 'يعمل حالياً على العنوان الافتراضي.',
          style: const TextStyle(color: AppColors.faint, fontSize: 10.5),
        ),
      ];

  /// خيارات التحكم بالميزات — المقابل لتبويب «features» في DeveloperSettings.tsx.
  ///
  /// الحفظ محلي لكل جهاز كما في سطح المكتب: `institution_settings` المشترك
  /// لا يحمل عموداً لها، فإرسالها فيه كان يُسقطها صامتاً.
  List<Widget> _features(AppStore store) {
    final f = store.features;
    return [
      const FormSection(icon: Icons.toggle_on_outlined, title: 'الميزات والموديولات', note: 'تُحفظ فور تبديلها'),
      _featureRow(
        title: 'إدارة المصروفات وأجور المعلمين',
        hint: 'إظهار تبويب وسجلات المصروفات وسندات الصرف وأجور المعلمين داخل الشاشة المالية.',
        value: f.enableExpenses,
        onChanged: (v) => store.saveFeatures(enableExpenses: v),
      ),
      _featureRow(
        title: 'تقييمات ودرجات الطلاب',
        hint: 'إتاحة رصد درجات الطلاب للمعلم، وظهور التقييمات بالإدارة، وعرض النتائج في بوابة وملف الطالب.',
        value: f.enableEvaluations,
        onChanged: (v) => store.saveFeatures(enableEvaluations: v),
      ),
      _featureRow(
        title: 'مرفقات الطلاب (الصور والوثائق)',
        hint: 'تخزين صورة الهوية وشهادة الميلاد. الصور ثقيلة وتُرفع مباشرةً للسحابة، وتُجلب عند فتح ملف الطالب.',
        value: f.enableStudentAttachments,
        onChanged: (v) => store.saveFeatures(enableStudentAttachments: v),
      ),
      _featureRow(
        title: 'بوابة الطالب الإلكترونية',
        hint: 'تمكين الطلاب وأولياء الأمور من الدخول برقم الهوية ورمز الدخول لاستعراض الحضور والرسوم والمواد.',
        value: f.enableStudentPortal,
        onChanged: (v) => store.saveFeatures(enableStudentPortal: v),
      ),
    ];
  }

  Widget _featureRow({
    required String title,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corner.card),
        color: Colors.white,
        border: Border.all(color: value ? AppColors.successBorder : AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                const SizedBox(height: 3),
                Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 6),
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

  List<Widget> _tools(BuildContext context, AppStore store) => [
        const FormSection(icon: Icons.build_outlined, title: 'أدوات الاختبار والبيانات'),
        _toolTile(
          icon: Icons.science_outlined,
          title: 'حقن بيانات تجريبية',
          subtitle: 'تغذية النظام بسجلات للتجربة والاختبار',
          onTap: () async {
            final ok = await confirmSheet(
              context,
              title: 'حقن بيانات تجريبية',
              message: 'ستُضاف منشآت وطلاب ومدرّسون تجريبيون إلى قاعدة البيانات المحلية. هل تريد المتابعة؟',
              confirmLabel: 'حقن',
            );
            if (!ok || !context.mounted) return;
            final stats = injectDemoData(store);
            await store.flush();
            if (context.mounted) showDemoDataResult(context, stats);
          },
        ),
        const SizedBox(height: 8),
        _toolTile(
          icon: Icons.delete_forever_outlined,
          title: 'تصفير القاعدة المحلية',
          subtitle: 'حذف كل السجلات من هذا الجهاز — بيانات السحابة لا تتأثر',
          danger: true,
          onTap: () async {
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
      ];

  Widget _toolTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.amber;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.card),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.card),
          color: danger ? AppColors.dangerSoft : Colors.white,
          border: Border.all(color: danger ? AppColors.dangerBorder : AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: danger ? AppColors.danger : AppColors.heading,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: danger ? AppColors.danger : AppColors.faint),
          ],
        ),
      ),
    );
  }

  List<Widget> _systemInfo(AppStore store) {
    final tenant = store.currentTenant;
    final rows = <(String, String)>[
      ('إصدار المنظومة', appVersion),
      ('قاعدة البيانات المحلية', 'SQLite'),
      ('وضع التخزين', 'محلي / مستقل (Offline Ready)'),
      ('المنشأة الحالية', tenant?.name ?? '—'),
      ('رمز المنشأة', tenant?.code ?? '—'),
      ('نوع الاشتراك', tenant == null ? '—' : (tenant.isLifetime ? 'دائم' : 'محدد المدة')),
      ('تعديلات معلّقة', '${store.pendingPush}'),
    ];

    return [
      const FormSection(icon: Icons.info_outline, title: 'معلومات النظام وبيئة التشغيل'),
      InfoStrip(
        child: Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(r.$1, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        r.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // ── الإجراءات ────────────────────────────────────────────────────────────

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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Corner.dialog))),
        title: const Text('لون مخصص', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: '#0B2545'),
        ),
        actions: [
          GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx)),
          PrimaryButton(label: 'تطبيق', onPressed: () => Navigator.pop(ctx, ctrl.text.trim())),
        ],
      ),
    );
    if (picked == null) return;
    if (parseHexColor(picked) == null) {
      if (mounted) showAppSnack(context, 'صيغة اللون غير صحيحة — مثال: #0B2545', error: true);
      return;
    }
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
    final fee = seatFee.text.trim();
    final feeValue = double.tryParse(fee);
    final url = supabaseUrlCtrl.text.trim();
    setState(() {
      errors
        ..reset()
        ..check('seatFee', fee.isNotEmpty && (feeValue == null || feeValue < 0), 'يرجى إدخال رسم صحيح')
        ..check('url', url.isNotEmpty && !url.startsWith('https://'), 'العنوان يجب أن يبدأ بـ https://');
    });
    if (errors.report(context)) return;

    setState(() => busy = true);
    await store.saveInstitution(type: type, name: name.text, logo: logo, colors: colors);
    await store.setSeatReservationFee(feeValue ?? 0);
    await store.db.setSetting(SupabaseConfig.urlSettingKey, url.isEmpty ? null : url);
    await store.db.setSetting(
      SupabaseConfig.keySettingKey,
      supabaseKeyCtrl.text.trim().isEmpty ? null : supabaseKeyCtrl.text.trim(),
    );
    SupabaseConfig.applyOverrides(store.db.settings);
    if (!mounted) return;
    setState(() => busy = false);
    showAppSnack(context, 'تم حفظ إعدادات المنشأة وتطبيقها');
  }
}

/// حصيلة التوليد وحسابا الدخول التجريبيان — المقابل لرسالة النجاح في
/// `DeveloperSettings.tsx`. تُعرض ورقةً لا إشعاراً عابراً لأن رمز الدخول
/// يُنسخ ويُجرَّب، فلا يصحّ أن يختفي بعد ثانيتين.
Future<void> showDemoDataResult(BuildContext context, DemoDataStats stats) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.science_outlined, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(child: Text('تم توليد البيانات التجريبية', style: AppText.cardTitle)),
              ],
            ),
            const SizedBox(height: 8),
            InfoStrip(
              child: Text(
                '${stats.students} طالباً  ·  ${stats.groups} شعبة/مادة  ·  ${stats.evaluations} تقييماً',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 12),
            _demoAccount('حساب معلم للتجربة', stats.teacher),
            const SizedBox(height: 8),
            _demoAccount('حساب طالب للتجربة', stats.student),
            const SizedBox(height: 8),
            _demoAccount('حساب ولي أمر للتجربة', stats.parent),
            const SizedBox(height: 14),
            GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    ),
  );
}

/// بطاقة حساب: الاسم، ثم رقم الهوية ورمز الدخول قابلَين للنسخ.
Widget _demoAccount(String title, DemoAccount account) {
  return Container(
    padding: const EdgeInsets.all(11),
    decoration: tileDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.heading, fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('الهوية:', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(width: 4),
            SelectableText(
              account.nationalId,
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            const Text('الرمز:', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(width: 4),
            SelectableText(
              account.portalCode,
              style: TextStyle(
                color: AppColors.heading,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
