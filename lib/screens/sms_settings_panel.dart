import 'package:flutter/material.dart';

import '../data/sms_service.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

/// «رسائل SMS» بتبويب المدرسة — `SmsSettings`: ربط المدرسة ببوابة الرسائل بمفتاح من تطبيق البوابة
/// على جوال الشريحة. للمدير وحده. بيحمّل الحالة لما ينفتح التبويب بس.
class SmsSettingsPanel extends StatefulWidget {
  const SmsSettingsPanel({super.key});

  @override
  State<SmsSettingsPanel> createState() => _SmsSettingsPanelState();
}

class _SmsSettingsPanelState extends State<SmsSettingsPanel> {
  final _service = const SmsService();
  final _token = TextEditingController();
  SmsStatus? status;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _service.status().then((s) {
      if (mounted) setState(() => status = s);
    }, onError: (Object e) {
      if (mounted) setState(() => status = SmsStatus(connected: false, error: '$e'));
    });
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_token.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final s = await _service.connect(_token.text);
      if (!mounted) return;
      _token.clear();
      setState(() => status = s);
      showAppSnack(context, 'انربطت بوابة الرسائل');
    } on SmsException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirmSheet(
      context,
      title: 'فصل بوابة الرسائل',
      message: 'ما بتقدر تبعت SMS لحد ما تربطها من جديد',
      confirmLabel: 'فصل',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      final s = await _service.disconnect();
      if (mounted) setState(() => status = s);
    } on SmsException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
              const Icon(Icons.sms_outlined, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Text('رسائل SMS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(width: 4),
              const Tooltip(
                message: 'رسائل لأولياء الأمور من شريحة المدرسة، عن طريق تطبيق بوابة الرسائل على جوال الشريحة',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(Icons.info_outline_rounded, size: 14, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: AppLoader(message: 'جارٍ التحميل', compact: true, size: 20),
            )
          else if (s.connected)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: NoonText.style(13, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        s.hasDevice ? '${s.deviceModel ?? 'الجوال'} · ${smsTimeAgo(s.lastSeen)}' : 'الجوال ما دخل التطبيق لسا',
                        style: NoonText.style(11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                NoonBadge(s.online ? 'متصل' : 'مش متصل', tone: s.online ? NoonBadgeTone.green : NoonBadgeTone.sun),
                const SizedBox(width: 4),
                NoonButton(
                  icon: Icons.link_off_rounded,
                  tone: NoonTone.danger,
                  small: true,
                  tooltip: 'فصل',
                  busy: busy,
                  onPressed: busy ? null : _disconnect,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'من تطبيق بوابة الرسائل على جوال الشريحة: المفتاح ← نسخ',
                    child: TextField(
                      controller: _token,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        hintText: 'مفتاح البوابة (API)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _connect(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                NoonButton(
                  label: 'ربط',
                  icon: Icons.link_rounded,
                  tone: NoonTone.ink,
                  busy: busy,
                  onPressed: busy || _token.text.trim().isEmpty ? null : _connect,
                ),
              ],
            ),
          if (s?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s!.error!, style: NoonText.style(11, color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}
