import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/features.dart';
import '../data/school_options.dart';
import '../data/store.dart';
import '../data/user_message.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'sms_settings_panel.dart';

/// ترتيب المدير: ما يراه هو أولاً، ثم ما يصل الأهل، ثم الإشعارات، ثم المعلم — `SchoolFeatures`.
const _groups = <({String title, IconData icon, List<String> keys})>[
  (
    title: 'الأقسام',
    icon: Icons.grid_view_rounded,
    keys: ['attendance', 'evaluations', 'moodle', 'finance.expenses', 'students.attachments'],
  ),
  (
    title: 'بوابة الأسرة',
    icon: Icons.groups_outlined,
    keys: [
      'portal.parent',
      'portal.student',
      'portal.attendance',
      'portal.grades',
      'portal.finance',
      'portal.notes',
      'portal.student.moodle',
    ],
  ),
  (
    title: 'إشعارات الأهل',
    icon: Icons.notifications_active_outlined,
    keys: ['notify.absence', 'notify.installments', 'notify.payments', 'notify.grades', 'notify.messages'],
  ),
  (
    title: 'بوابة المعلم',
    icon: Icons.school_outlined,
    keys: ['portal.teacher', 'portal.teacher.attendance', 'portal.teacher.grades', 'portal.teacher.moodle'],
  ),
];

/// أسماء مفاتيح البوابة بعبارة تفرّقها عن أقسام التطبيق المسمّاة بالاسم نفسه.
const _portalLabels = {
  'portal.attendance': 'الحضور بالبوابة',
  'portal.grades': 'العلامات بالبوابة',
  'portal.finance': 'الرسوم بالبوابة',
  'portal.notes': 'الرسائل بالبوابة',
};

/// مفتاح فرعي يتبع بوابة: يتعطل ما دامت بوابته مطفأة.
bool _parentOff(String key, Map<String, bool> c) {
  if (key == 'portal.parent' || key == 'portal.student' || !key.startsWith('portal.')) return false;
  if (key.startsWith('portal.teacher')) return key != 'portal.teacher' && !(c['portal.teacher'] ?? false);
  return !(c['portal.parent'] ?? false) && !(c['portal.student'] ?? false);
}

/// تبويب «المدرسة» في الإعدادات — `SchoolFeatures` و`SchoolOptions`: الأقسام الظاهرة،
/// وما يُطبع على الأوراق، والأدوات، وبطاقات الرئيسية. الإيقاف يخفي ولا يحذف.
class SchoolSettingsTab extends StatefulWidget {
  const SchoolSettingsTab({super.key});

  @override
  State<SchoolSettingsTab> createState() => _SchoolSettingsTabState();
}

class _SchoolSettingsTabState extends State<SchoolSettingsTab> {
  Map<String, bool>? draft;
  bool saving = false;

  Future<void> _saveFeatures(AppStore store, Map<String, bool> saved) async {
    final changes = describeFeatureChanges(saved, draft);
    if (changes.isEmpty) return;
    final ok = await confirmSheet(
      context,
      title: 'حفظ الأقسام',
      message: changes.join('\n'),
      confirmLabel: 'حفظ',
      confirmColor: AppColors.navy,
    );
    if (!ok || !mounted) return;
    setState(() => saving = true);
    try {
      // مفاتيح الاشتراك يفعّلها المطور وحده، ولا تقبلها `school_set_features`
      await store.saveSchoolFeatures({
        for (final k in featureKeys)
          if (!developerOnlyFeatures.contains(k)) k: draft![k] ?? false,
      });
      if (!mounted) return;
      setState(() => draft = null);
      showAppSnack(context, 'حُفظ');
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickStamp(AppStore store) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 420, imageQuality: 90);
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    await store.saveInstitutionStamp('data:image/png;base64,${base64Encode(bytes)}');
    if (mounted) showAppSnack(context, 'حُفظ الختم');
  }

  Widget _panel(IconData icon, String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      );

  Widget _check({required bool value, required String label, String? hint, ValueChanged<bool>? onChanged}) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
        title: Text(label, style: const TextStyle(fontSize: 12.5)),
        subtitle: hint == null ? null : Text(hint, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
      );

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final isAdmin = store.isAdminUser;
    final saved = selectedFeatures(store.currentTenant?.features);
    final current = draft ?? saved;
    final effective = resolveFeatures(current);
    final changes = describeFeatureChanges(saved, current);
    final options = store.settings;
    final stamp = store.institutionStamp;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final group in _groups)
          _panel(group.icon, group.title, [
            for (final key in group.keys)
              _check(
                value: current[key] ?? false,
                label: _portalLabels[key] ?? features[key]!.label,
                hint: _parentOff(key, current)
                    ? 'يتعطل لأن البوابة مطفأة'
                    : (current[key] ?? false) && !(effective[key] ?? false)
                    ? 'لا يعمل: ${featureBlockers(key, current).map((b) => features[b]!.label).join(features[key]!.requiresAny.isNotEmpty ? ' أو ' : ' و')}'
                    : features[key]!.description,
                onChanged: !isAdmin || saving || _parentOff(key, current)
                    ? null
                    : (v) => setState(() => draft = {...current, key: v}),
              ),
          ]),
        if (isAdmin && changes.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: GhostButton(label: 'تراجع', onPressed: saving ? null : () => setState(() => draft = null))),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: 'حفظ (${changes.length})',
                  expand: true,
                  busy: saving,
                  onPressed: saving ? null : () => _saveFeatures(store, saved),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // رسائل SMS: للمدير وحده، والحالة بتتحمّل لما ينفتح التبويب بس
        if (isAdmin) const SmsSettingsPanel(),
        _panel(Icons.workspace_premium_outlined, 'الأوراق والسندات', [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text('الختم: يُطبع على الشهادات والسندات والأوراق', style: TextStyle(fontSize: 12)),
                ),
                if (stamp.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Image.memory(base64Decode(stamp.split(',').last), height: 40, fit: BoxFit.contain),
                  ),
                GhostButton(
                  label: stamp.isEmpty ? 'رفع' : 'تغيير',
                  onPressed: isAdmin ? () => _pickStamp(store) : null,
                ),
                if (stamp.isNotEmpty && isAdmin) ...[
                  const SizedBox(width: 6),
                  GhostButton(
                    label: 'حذف',
                    onPressed: () async {
                      await store.saveInstitutionStamp('');
                      if (mounted) showAppSnack(this.context, 'حُذف الختم');
                    },
                  ),
                ],
              ],
            ),
          ),
          _TextSetting(
            key: ValueKey('principal_${options.principalName}'),
            label: 'اسم المدير',
            value: options.principalName,
            hint: store.currentTenant?.ownerName.trim().isNotEmpty == true ? store.currentTenant!.ownerName : 'يُكتب تحت «المدير»',
            enabled: isAdmin,
            onSave: (v) => store.writeSchoolOption({'principal_name': v}),
          ),
          _TextSetting(
            key: ValueKey('note_${options.receiptNote}'),
            label: 'الجملة أسفل سند القبض',
            value: options.receiptNote,
            hint: 'بلا جملة',
            enabled: isAdmin,
            onSave: (v) => store.writeSchoolOption({'receipt_note': v}),
          ),
          _check(
            value: options.certificateQr,
            label: 'رمز التحقق على الشهادات',
            hint: 'رقم الشهادة ورمز QR يفتح صفحة تؤكد أنها صادرة من المدرسة',
            onChanged: isAdmin ? (v) => store.writeSchoolOption({'certificate_qr': v}) : null,
          ),
        ]),
        _panel(Icons.build_outlined, 'الأدوات', [
          for (final t in schoolTools)
            _check(
              value: !options.toolsOff.contains(t.id),
              label: t.label,
              hint: t.hint,
              onChanged: isAdmin
                  ? (on) => store.writeSchoolOption({
                        'tools_off': on
                            ? options.toolsOff.where((x) => x != t.id).toList()
                            : [...options.toolsOff, t.id],
                      })
                  : null,
            ),
        ]),
        _panel(Icons.dashboard_outlined, 'بطاقات الرئيسية', [
          for (final c in dashboardCards)
            _check(
              value: !options.dashboardHidden.contains(c.id),
              label: c.label,
              onChanged: isAdmin
                  ? (on) => store.writeSchoolOption({
                        'dashboard_hidden': on
                            ? options.dashboardHidden.where((x) => x != c.id).toList()
                            : [...options.dashboardHidden, c.id],
                      })
                  : null,
            ),
        ]),
      ],
    );
  }
}

/// نص يُحفظ عند الخروج من الحقل، فلا زر حفظ لكل سطر — `TextSetting`.
class _TextSetting extends StatefulWidget {
  const _TextSetting({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.enabled,
    required this.onSave,
  });

  final String label;
  final String value;
  final String hint;
  final bool enabled;
  final Future<void> Function(String value) onSave;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController ctl = TextEditingController(text: widget.value);
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    focus
      ..removeListener(_onFocus)
      ..dispose();
    ctl.dispose();
    super.dispose();
  }

  Future<void> _onFocus() async {
    if (focus.hasFocus) return;
    final v = ctl.text.trim();
    if (v == widget.value.trim()) return;
    final messenger = context;
    await widget.onSave(v);
    if (messenger.mounted) showAppSnack(messenger, 'حُفظ');
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: ctl,
          focusNode: focus,
          enabled: widget.enabled,
          decoration: InputDecoration(isDense: true, labelText: widget.label, hintText: widget.hint),
        ),
      );
}
