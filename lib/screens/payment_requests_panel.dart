import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'receipt_screen.dart';

/// دفعة ولي أمر في قائمة الموافقات — صفوف `useParentPayments` في الويب.
///
/// ولي الأمر حوّل ثم أرسل صورة الإشعار من بوابته. القبول يصدر سند قبض عادياً،
/// والرفض يتطلب سبباً مكتوباً يراه ولي الأمر. تعرضها لوحة الموافقات مع طلبات
/// الموظفين في قائمة واحدة.
class ParentRequestCard extends StatefulWidget {
  const ParentRequestCard({super.key, required this.store, required this.request});

  final AppStore store;
  final PaymentRequest request;

  @override
  State<ParentRequestCard> createState() => _ParentRequestCardState();
}

class _ParentRequestCardState extends State<ParentRequestCard> {
  bool open = false;

  AppStore get store => widget.store;

  Future<void> _approve(PaymentRequest r) async {
    final payment = await showModalBottomSheet<Payment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _ApproveSheet(store: store, request: r),
    );
    if (payment == null || !mounted) return;
    showAppSnack(context, 'صدر السند ${payment.receiptNumber}');
    await ReceiptScreen.open(context, payment);
  }

  Future<void> _reject(PaymentRequest r) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _RejectSheet(store: store, request: r),
    );
    if (done == true && mounted) showAppSnack(context, 'رُفض الطلب وأُبلغ ولي الأمر بالسبب');
  }

  @override
  Widget build(BuildContext context) => _card(widget.request, store.can('finance.collect'));

  Widget _card(PaymentRequest r, bool canDecide) {
    final approved = r.status == 'approved';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.studentName.isEmpty ? 'طالب' : r.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.text),
                  ),
                ),
                Text(money(r.amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, fontFamily: 'monospace')),
                const SizedBox(width: 8),
                _StatusPill(status: r.status, label: r.statusLabel),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                'من ${r.senderName}',
                if (r.transferChannel.isNotEmpty) 'إلى ${r.transferChannel}',
                if (r.transferDate.isNotEmpty) r.transferDate,
                if (r.referenceNumber.isNotEmpty) 'مرجع ${r.referenceNumber}',
              ].join('  ·  '),
              style: const TextStyle(color: AppColors.text, fontSize: 11.5, height: 1.4),
            ),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(r.notes, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
            const SizedBox(height: 2),
            Text(
              'أُرسل ${(r.createdAt ?? '').replaceFirst('T', ' ').split('.').first}',
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
            if (r.status != 'pending') ...[
              const SizedBox(height: 4),
              Text(
                [
                  approved ? 'قبله' : 'رفضه',
                  if (r.decidedByName.isNotEmpty) r.decidedByName,
                  if ((r.decidedAt ?? '').isNotEmpty) (r.decidedAt ?? '').split('T').first,
                  if (r.rejectionReason.isNotEmpty) '— ${r.rejectionReason}',
                ].join(' '),
                style: TextStyle(
                  color: approved ? AppColors.success : AppColors.danger,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                GhostButton(
                  label: '${open ? 'إخفاء' : 'الإشعار'} (${r.imagePaths.length})',
                  icon: Icons.image_outlined,
                  onPressed: () => setState(() => open = !open),
                ),
                const Spacer(),
                if (r.status == 'pending' && canDecide) ...[
                  PrimaryButton(label: 'قبول', color: AppColors.success, onPressed: () => _approve(r)),
                  const SizedBox(width: 8),
                  GhostButton(label: 'رفض', onPressed: () => _reject(r)),
                ],
              ],
            ),
            if (open) ...[
              const SizedBox(height: 8),
              _RequestImages(store: store, request: r),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      'approved' => (const Color(0xFF15803D), const Color(0xFFF0FDF4)),
      'rejected' => (const Color(0xFFB91C1C), const Color(0xFFFEF2F2)),
      _ => (const Color(0xFF854D0E), const Color(0xFFFEFCE8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// صور الإشعار: تُنزَّل عند الفتح وحده، ولمسها يكبّرها.
class _RequestImages extends StatefulWidget {
  const _RequestImages({required this.store, required this.request});

  final AppStore store;
  final PaymentRequest request;

  @override
  State<_RequestImages> createState() => _RequestImagesState();
}

class _RequestImagesState extends State<_RequestImages> {
  late final Future<List<String?>> images = widget.store.paymentRequestImages(widget.request);

  void _zoom(String src) {
    showDialog<void>(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(child: Image.memory(base64Decode(src.split(',').last), fit: BoxFit.contain)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String?>>(
      future: images,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Text('جارِ تحميل الإشعار...', style: TextStyle(color: AppColors.muted, fontSize: 11));
        }
        final list = snap.data!;
        if (list.every((s) => s == null)) {
          return const Text('تعذّر تحميل الصور (يحتاج اتصالاً)', style: TextStyle(color: AppColors.danger, fontSize: 11));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final src in list)
              if (src != null)
                GestureDetector(
                  onTap: () => _zoom(src),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Corner.box),
                    child: Image.memory(base64Decode(src.split(',').last), height: 96, fit: BoxFit.contain),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// الموافقة: تأكيد المبلغ ووسيلة القبض.
class _ApproveSheet extends StatefulWidget {
  const _ApproveSheet({required this.store, required this.request});

  final AppStore store;
  final PaymentRequest request;

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  late final amount = TextEditingController(text: trimNum(widget.request.amount));
  late final methods = [for (final m in widget.store.activePaymentMethods) if (m.type != 'cash') m];
  late String method = widget.request.paymentMethod.isNotEmpty
      ? widget.request.paymentMethod
      : (methods.isNotEmpty ? methods.first.id : 'bank_transfer');
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final payment = await widget.store.approvePaymentRequest(
        widget.request.id,
        amount: double.tryParse(amount.text.trim()) ?? 0,
        method: method,
      );
      if (mounted) Navigator.pop(context, payment);
    } on StoreException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر القبول');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    final changed = (value - r.amount).abs() > 0.004;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('قبول الدفعة — ${r.studentName}', style: AppText.title),
          const SizedBox(height: 12),
          const FieldLabel('المبلغ المقبوض (كما في الإشعار)'),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (changed) ...[
            const SizedBox(height: 4),
            Text('يختلف عن مبلغ الطلب ${money(r.amount)}', style: TextStyle(color: AppColors.amberDark, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          const FieldLabel('وسيلة القبض'),
          AppDropdown<String>(
            value: method,
            items: [
              for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name)),
              if (!methods.any((m) => m.id == method))
                DropdownMenuItem(value: method, child: Text(r.transferChannel.isNotEmpty ? r.transferChannel : widget.store.paymentMethodLabel(method))),
            ],
            onChanged: (v) => setState(() => method = v ?? method),
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          ActionButtons(
            primary: PrimaryButton(
              label: busy ? 'جارِ الحفظ...' : 'قبول وإصدار السند',
              color: AppColors.success,
              onPressed: busy || !(value > 0) ? null : _submit,
            ),
            secondary: GhostButton(label: 'تراجع', onPressed: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

/// الرفض: سبب واضح إلزامي يراه ولي الأمر.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.store, required this.request});

  final AppStore store;
  final PaymentRequest request;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final reason = TextEditingController();
  String error = '';

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      widget.store.rejectPaymentRequest(widget.request.id, reason.text);
      Navigator.pop(context, true);
    } on StoreException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final clean = reason.text.trim();
    final enough = clean.length >= minRejectionReason;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('رفض دفعة ${money(r.amount)} — ${r.studentName}', style: AppText.title.copyWith(color: AppColors.danger)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in rejectionReasonPresets)
                  SheetChoiceChip(
                    label: p,
                    selected: reason.text == p,
                    onTap: () => setState(() => reason.text = p),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'السبب كما سيقرؤه ولي الأمر'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Text(
              enough ? 'يظهر لولي الأمر في بوابته' : '$minRejectionReason أحرف على الأقل',
              style: TextStyle(color: enough ? AppColors.muted : AppColors.amberDark, fontSize: 11),
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            ActionButtons(
              primary: PrimaryButton(label: 'رفض الطلب', color: AppColors.danger, onPressed: enough ? _submit : null),
              secondary: GhostButton(label: 'تراجع', onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}
