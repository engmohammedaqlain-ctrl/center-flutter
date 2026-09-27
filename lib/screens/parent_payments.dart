import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/portal.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// تسديد دفعة من بوابة ولي الأمر — المقابل لـ `ParentPayments.tsx`.
///
/// ولي الأمر يحوّل (بنك أو محفظة) ثم يرسل صورة الإشعار ومن حوّل وإلى أين والمبلغ.
/// الطلب لا يمسّ حساب الطالب: المالية تراجعه، فإن قبلته صدر سند قبض عادي، وإن
/// رفضته كتبت سبباً يراه هنا.
class ParentPaymentsSection extends StatefulWidget {
  const ParentPaymentsSection({
    super.key,
    required this.user,
    required this.suggestedAmount,
    required this.accent,
    this.refreshTick = 0,
    this.service = const PortalService(),
  });

  final PortalUser user;

  /// المستحق الآن: يُقترح مبلغاً للدفعة.
  final double suggestedAmount;
  final Color accent;

  /// يتغير مع كل إشارة «تغيّر» من المدرسة: تُعاد القائمة فيظهر القرار.
  final int refreshTick;
  final PortalService service;

  @override
  State<ParentPaymentsSection> createState() => _ParentPaymentsSectionState();
}

class _ParentPaymentsSectionState extends State<ParentPaymentsSection> {
  List<PaymentRequest> requests = const [];
  bool sent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ParentPaymentsSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick || old.user.id != widget.user.id) _load();
  }

  Future<void> _load() async {
    final list = await widget.service.paymentRequestsOf(widget.user.id);
    if (mounted && list != null) setState(() => requests = list);
  }

  Future<void> _openForm() async {
    setState(() => sent = false);
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PaymentRequestForm(
          user: widget.user,
          suggestedAmount: widget.suggestedAmount,
          accent: widget.accent,
          service: widget.service,
        ),
      ),
    );
    if (done != true || !mounted) return;
    setState(() => sent = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = requests.where((r) => r.status == 'pending').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'تسديد دفعة',
          icon: Icons.send_rounded,
          color: widget.accent,
          height: 44,
          onPressed: _openForm,
        ),
        if (sent) ...[
          const SizedBox(height: 8),
          _Note(
            text: 'أُرسل الطلب. يُحسب بعد مراجعة المالية.',
            fg: const Color(0xFF047857),
            bg: const Color(0xFFECFDF5),
          ),
        ],
        if (requests.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'طلبات الدفع (${requests.length})',
                    style: TextStyle(fontFamily: AppText.family, color: AppColors.heading, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                if (pending > 0)
                  Text(
                    '$pending قيد المراجعة',
                    style: const TextStyle(fontFamily: AppText.family, color: Color(0xFFB45309), fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final r in requests) _RequestCard(request: r),
        ],
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Corner.box)),
      child: Text(text, style: TextStyle(fontFamily: AppText.family, color: fg, fontSize: 12, fontWeight: FontWeight.w700, height: 1.5)),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final PaymentRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final (fg, bg, icon) = switch (r.status) {
      'approved' => (const Color(0xFF047857), const Color(0xFFECFDF5), Icons.check_circle_outline),
      'rejected' => (const Color(0xFFBE123C), const Color(0xFFFFF1F2), Icons.cancel_outlined),
      _ => (const Color(0xFFB45309), const Color(0xFFFFFBEB), Icons.schedule_rounded),
    };
    final date = (r.transferDate.isNotEmpty ? r.transferDate : (r.createdAt ?? '')).split('T').first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Corner.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(money(r.amount), style: TextStyle(fontFamily: AppText.family, color: AppColors.heading, fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          'من ${r.senderName}',
                          if (r.transferChannel.isNotEmpty) 'إلى ${r.transferChannel}',
                          if (date.isNotEmpty) date,
                        ].join(' · '),
                        style: const TextStyle(fontFamily: AppText.family, color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: fg),
                      const SizedBox(width: 4),
                      Text(r.statusLabel, style: TextStyle(fontFamily: AppText.family, color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            if (r.status == 'rejected' && r.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Note(text: 'سبب الرفض: ${r.rejectionReason}', fg: const Color(0xFF9F1239), bg: const Color(0xFFFFF1F2)),
            ],
            if (r.status == 'approved') ...[
              const SizedBox(height: 6),
              const Text('أُضيفت إلى سجل الدفعات', style: TextStyle(fontFamily: AppText.family, color: Color(0xFF047857), fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── نموذج الإرسال ─────────────────────────────────────────────────────────────

class _PaymentRequestForm extends StatefulWidget {
  const _PaymentRequestForm({required this.user, required this.suggestedAmount, required this.accent, required this.service});

  final PortalUser user;
  final double suggestedAmount;
  final Color accent;
  final PortalService service;

  @override
  State<_PaymentRequestForm> createState() => _PaymentRequestFormState();
}

class _PaymentRequestFormState extends State<_PaymentRequestForm> {
  late final amount = TextEditingController(text: widget.suggestedAmount > 0 ? trimNum(widget.suggestedAmount) : '');
  late final sender = TextEditingController(
    text: widget.user.name.trim().isNotEmpty && widget.user.name != 'ولي الأمر' ? widget.user.name.trim() : '',
  );
  final channel = TextEditingController();
  final reference = TextEditingController();
  final notes = TextEditingController();
  List<({String id, String name})> methods = const [];

  /// الوسيلة المختارة؛ الفارغ = جهة أخرى تُكتب باليد.
  String methodId = '';
  String date = isoDate(DateTime.now());
  final images = <String>[];
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    widget.service.transferMethods(widget.user.tenantId).then((list) {
      if (!mounted) return;
      setState(() {
        methods = list;
        if (list.isNotEmpty) methodId = list.first.id;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    amount.dispose();
    sender.dispose();
    channel.dispose();
    reference.dispose();
    notes.dispose();
    super.dispose();
  }

  bool get _ready =>
      (double.tryParse(amount.text.trim()) ?? 0) > 0 &&
      sender.text.trim().isNotEmpty &&
      images.isNotEmpty &&
      (methodId.isNotEmpty || channel.text.trim().isNotEmpty);

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1400, maxHeight: 1400);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // حد حاوية الطلبات 2 ميجابايت
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) showAppSnack(context, 'الصورة أكبر من 2 ميجابايت', error: true);
        return;
      }
      if (!mounted) return;
      setState(() => images.add('data:${file.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}'));
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر اختيار الصورة', error: true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseIsoDate(date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => date = isoDate(picked));
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final methodName = methods.where((m) => m.id == methodId).map((m) => m.name).firstOrNull;
      await widget.service.submitPaymentRequest(
        tenantId: widget.user.tenantId,
        studentId: widget.user.id,
        studentName: widget.user.studentName.isNotEmpty ? widget.user.studentName : widget.user.name,
        amount: double.tryParse(amount.text.trim()) ?? 0,
        senderName: sender.text,
        paymentMethod: methodId,
        transferChannel: methodId.isNotEmpty ? (methodName ?? '') : channel.text,
        transferDate: date,
        referenceNumber: reference.text,
        notes: notes.text,
        images: images,
      );
      if (mounted) Navigator.pop(context, true);
    } on PortalException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'الإرسال يحتاج اتصالاً بالإنترنت');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('تسديد دفعة')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            const FieldLabel('المبلغ المحوَّل (شيكل)'),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const FieldLabel('اسم صاحب الحساب المحوِّل'),
            TextField(controller: sender, onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            const FieldLabel('إلى أين حوّلت'),
            if (methods.isNotEmpty)
              AppDropdown<String>(
                value: methodId,
                items: [
                  for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name)),
                  const DropdownMenuItem(value: '', child: Text('جهة أخرى')),
                ],
                onChanged: (v) => setState(() => methodId = v ?? ''),
              ),
            if (methodId.isEmpty) ...[
              if (methods.isNotEmpty) const SizedBox(height: 8),
              TextField(
                controller: channel,
                decoration: const InputDecoration(hintText: 'اسم البنك أو المحفظة'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('تاريخ التحويل'),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        label: Text(date),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('رقم الحركة'),
                      TextField(controller: reference, textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldLabel('صور الإشعار (حتى $maxRequestImages)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < images.length; i++)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Corner.box),
                        child: Image.memory(base64Decode(images[i].split(',').last), width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      PositionedDirectional(
                        top: -6,
                        end: -6,
                        child: GestureDetector(
                          onTap: () => setState(() => images.removeAt(i)),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: AppColors.danger,
                            child: Icon(Icons.close, size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (images.length < maxRequestImages)
                  InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(Corner.box),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Corner.box),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.faint),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const FieldLabel('ملاحظة للمالية'),
            TextField(controller: notes, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'مثال: عن قسط شهر 10')),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Note(text: error, fg: const Color(0xFFBE123C), bg: const Color(0xFFFFF1F2)),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: busy ? 'جارِ الإرسال...' : 'إرسال للمراجعة',
              icon: Icons.send_rounded,
              color: widget.accent,
              height: 44,
              onPressed: busy || !_ready ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
