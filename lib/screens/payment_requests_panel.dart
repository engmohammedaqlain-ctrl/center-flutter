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

  /// سطر «العنوان: القيمة» في تفاصيل الطلب.
  Widget _kv(String label, String value) => value.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 74, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
              Expanded(child: Text(value, style: const TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.35))),
            ],
          ),
        );

  /// دفعة ولي أمر: الاسم والمبلغ وحالته، فتفاصيل التحويل، فصورة الإشعار بعرض البطاقة، وأزرار القرار بعرض متساوٍ.
  /// بلا إطار خاص: تُوضع داخل لوحة الطلبات فلا يصير صندوقاً داخل صندوق.
  Widget _card(PaymentRequest r, bool canDecide) {
    final approved = r.status == 'approved';
    final sent = (r.createdAt ?? '').replaceFirst('T', ' ').split('.').first;
    final transferDay = r.transferDate.split('T').first;
    final sentDay = isoDate((DateTime.tryParse(r.createdAt ?? '') ?? DateTime.now()).toLocal());
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.studentName.isEmpty ? 'طالب' : r.studentName,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.heading),
                    ),
                    const SizedBox(height: 2),
                    Text('من ${r.senderName}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(r.amount), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.heading)),
                  const SizedBox(height: 4),
                  _StatusPill(status: r.status, label: r.statusLabel),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: AppColors.line),
          const SizedBox(height: 6),
          _kv('إلى', r.transferChannel),
          _kv('المرجع', r.referenceNumber),
          if (transferDay.isNotEmpty && transferDay != sentDay) _kv('تاريخ التحويل', transferDay),
          _kv('ملاحظة', r.notes),
          _kv('أُرسل', sent),
          if (r.status != 'pending') ...[
            const SizedBox(height: 6),
            Text(
              [
                approved ? 'قبله' : 'رفضه',
                if (r.decidedByName.isNotEmpty) r.decidedByName,
                if ((r.decidedAt ?? '').isNotEmpty) (r.decidedAt ?? '').split('T').first,
                if (r.rejectionReason.isNotEmpty) '— ${r.rejectionReason}',
              ].join(' '),
              style: TextStyle(
                color: approved ? AppColors.success : AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (r.imagePaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => open = !open),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 18, color: AppColors.navy),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إشعار التحويل (${r.imagePaths.length})',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
                      ),
                    ),
                    Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
            if (open) _RequestImages(store: store, request: r),
          ],
          if (r.status == 'pending' && canDecide) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(label: 'قبول', color: AppColors.success, expand: true, height: 46, onPressed: () => _approve(r)),
                ),
                const SizedBox(width: 10),
                Expanded(child: GhostButton(label: 'رفض', height: 46, onPressed: () => _reject(r))),
              ],
            ),
          ],
        ],
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final src in list)
              if (src != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => _zoom(src),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.sunken,
                        borderRadius: BorderRadius.circular(Corner.box),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Image.memory(base64Decode(src.split(',').last), height: 240, fit: BoxFit.contain),
                    ),
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

  bool busy = false;

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      await widget.store.rejectPaymentRequest(widget.request.id, reason.text);
      if (mounted) Navigator.pop(context, true);
    } on StoreException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
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
              primary: PrimaryButton(label: 'رفض الطلب', color: AppColors.danger, onPressed: enough && !busy ? _submit : null),
              secondary: GhostButton(label: 'تراجع', onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}
