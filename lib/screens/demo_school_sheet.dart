import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../data/demo_tenant.dart';
import '../data/institution.dart';
import '../data/user_message.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// المدرسة التجريبية من لوحة المطور: الإنشاء برسالته الجاهزة — `DemoSchoolModal`. يعيد `true` إن أُنشئت.
Future<bool> showDemoSchoolSheet(BuildContext context) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    builder: (_) => const _DemoSchoolSheet(),
  );
  return created == true;
}

class _DemoSchoolSheet extends StatefulWidget {
  const _DemoSchoolSheet();

  @override
  State<_DemoSchoolSheet> createState() => _DemoSchoolSheetState();
}

class _DemoSchoolSheetState extends State<_DemoSchoolSheet> {
  final name = TextEditingController();
  Uint8List? logoBytes;
  String? logo;
  InstitutionColors? colors;
  var busy = false;
  var copied = false;
  String? error;
  DemoSchoolResult? result;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      logoBytes = bytes;
      logo = 'data:${file.mimeType ?? 'image/png'};base64,${base64Encode(bytes)}';
      colors = null;
    });
  }

  Future<void> _extract() async {
    final palette = await extractColorsFromLogo(logoBytes);
    if (mounted) setState(() => colors = palette.colors);
  }

  Future<void> _create() async {
    if (busy || name.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final res = await createDemoSchool(name: name.text, logo: logo, colors: colors?.toMap());
      if (mounted) setState(() => result = res);
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e, 'تعذّر إنشاء المدرسة'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = result;
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(done?.tenant.name ?? 'مدرسة تجريبية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.heading)),
            const SizedBox(height: 12),
            if (done != null) ...[
              Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.sunken,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.line),
                ),
                child: SingleChildScrollView(child: SelectableText(done.message, style: const TextStyle(fontSize: 13, height: 1.6))),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context, true)),
                  const SizedBox(width: 8),
                  GhostButton(label: 'مشاركة', icon: Icons.share_outlined, onPressed: () => SharePlus.instance.share(ShareParams(text: done.message))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: copied ? 'نُسخت' : 'نسخ الرسالة',
                      icon: copied ? Icons.check : Icons.copy_rounded,
                      expand: true,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: done.message));
                        if (mounted) setState(() => copied = true);
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: name,
                enabled: !busy,
                autofocus: true,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true, labelText: 'اسم المدرسة', hintText: 'مدرسة المدير', counterText: ''),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (logoBytes != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: Image.memory(logoBytes!, height: 48, width: 48, fit: BoxFit.contain),
                    ),
                  GhostButton(label: logoBytes == null ? 'الشعار' : 'تغيير الشعار', icon: Icons.image_outlined, onPressed: busy ? null : _pickLogo),
                  if (logoBytes != null) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                logoBytes = null;
                                logo = null;
                                colors = null;
                              }),
                      child: const Text('إزالة'),
                    ),
                  ],
                ],
              ),
              if (logoBytes != null && colors == null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(onPressed: busy ? null : _extract, child: const Text('اقتباس الألوان من الشعار')),
                ),
              if (colors != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final hex in colors!.toMap().values)
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Color(int.tryParse('FF${hex.replaceAll('#', '')}', radix: 16) ?? 0xFFCCCCCC),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.line),
                          ),
                        ),
                    ],
                  ),
                ),
              if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: Text('جارٍ التعبئة…', style: TextStyle(fontSize: 12, color: AppColors.muted))),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  GhostButton(label: 'إلغاء', onPressed: busy ? null : () => Navigator.pop(context, false)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: 'إنشاء',
                      expand: true,
                      busy: busy,
                      onPressed: busy || name.text.trim().isEmpty ? null : _create,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
