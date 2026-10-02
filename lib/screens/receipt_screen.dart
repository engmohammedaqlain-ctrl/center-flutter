import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/balance.dart';
import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/finance_documents.dart';
import '../widgets/widgets.dart';

/// سند القبض — المقابل لـ `features/finance/ReceiptModal.tsx`.
class ReceiptScreen {
  /// إرسال السند نفسه بواتساب لولي الأمر — يُفتح السند ثم يُرسل ملفه، لا نص رسالة.
  /// متاحة لملف الطالب وسجل المقبوضات كي يُرسل السند نفسه من كل موضع.
  static Future<void> sendWhatsApp(BuildContext context, Payment payment, Student student) {
    final raw = student.parentPhone.isNotEmpty ? student.parentPhone : student.phone;
    if (raw.trim().isEmpty) {
      showAppSnack(context, 'لا يوجد رقم هاتف مسجل للطالب أو ولي الأمر.', error: true);
      return Future.value();
    }
    return open(context, payment, sendWhatsApp: true);
  }

  static Future<void> open(BuildContext context, Payment payment, {bool sendWhatsApp = false}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _ReceiptSheet(payment: payment, sendOnOpen: sendWhatsApp),
    );
  }
}

/// السند كما يبنيه الويب من الدفعة — `ReceiptModal.tsx`.
ReceiptView receiptViewOf(AppStore store, Payment payment, {Uint8List? notice}) {
  final student = store.studentById(payment.studentId);
  final outgoing = payment.amount < 0;
  final reversal = isReversalPurpose(payment.purpose);
  final generalIncome = payment.studentId.isEmpty;
  final due = payment.remainingAfter < 0 ? 0.0 : payment.remainingAfter;
  final ownAdvance = paymentAdvance(payment);
  final advance = ownAdvance > 0 ? ownAdvance : (due == 0 && (student?.balance ?? 0) > 0 ? student!.balance : 0.0);
  final discount = payment.discountAmount;
  return ReceiptView(
    institutionName: store.institutionName.trim().isEmpty ? appName : store.institutionName.trim(),
    logo: store.institutionLogo,
    stamp: store.institutionStamp,
    title: !outgoing ? 'سند قبض' : (reversal ? 'سند عكس' : 'سند رد مبلغ'),
    receiptNumber: payment.receiptNumber,
    date: formatDate(payment.date),
    amount: payment.amount,
    outgoing: outgoing,
    reversal: reversal,
    showLedger: !generalIncome && !outgoing,
    payerName: _payerName(payment, student),
    gradeLevel: student?.gradeLevel ?? '',
    methodLabel: _cleanMethod(store, payment),
    amountWords: amountInArabicWords(payment.amount.abs()),
    purposeText: _purposeText(payment),
    receiverName: _receiverName(payment, store),
    advance: advance,
    dueRemaining: due,
    senderName: payment.senderName.trim(),
    reference: payment.reference.trim(),
    discountAmount: discount,
    originalAmount: (payment.originalAmount ?? (payment.amount + discount)).abs(),
    discountReason: payment.discountReason,
    notice: notice,
    cancelled: payment.cancelled,
    cancelReason: payment.cancelReason,
  );
}

class _ReceiptSheet extends StatefulWidget {
  const _ReceiptSheet({required this.payment, this.sendOnOpen = false});

  final Payment payment;

  /// فُتح من زر واتساب في قائمة: يُرسل السند فور رسمه.
  final bool sendOnOpen;

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  final _document = GlobalKey();
  Uint8List? _notice;
  bool _ready = false;

  Payment get payment => widget.payment;

  @override
  void initState() {
    super.initState();
    _loadNotice();
  }

  Future<void> _loadNotice() async {
    final raw = payment.method == 'cash' ? null : await AppStore.instance.loadNoticeImage(payment.id);
    Uint8List? bytes;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        bytes = base64Decode(raw.split(',').last);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _notice = bytes;
      _ready = true;
    });
    if (widget.sendOnOpen) {
      // بعد أن يُرسم السند كاملاً: الالتقاط قبلها يلتقط صفحةً ناقصة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _whatsapp();
      });
    }
  }

  String get _fileName => 'سند قبض ${payment.receiptNumber}';

  Future<Uint8List?> _pdf() => captureDocumentPdf(_document, widthMm: 140, title: _fileName);

  Future<void> _download() => runBusyOp(context, () async {
        final bytes = await _pdf();
        if (!mounted) return;
        if (bytes == null) {
          showAppSnack(context, 'تعذّر تجهيز السند', error: true);
          return;
        }
        await DocExport.download(context, bytes, _fileName);
      }, message: 'جارٍ تجهيز السند...');

  Future<void> _whatsapp() => runBusyOp(context, () async {
        final store = AppStore.instance;
        final student = store.studentById(payment.studentId);
        final phone = student == null ? '' : (student.parentPhone.isNotEmpty ? student.parentPhone : student.phone);
        final bytes = await _pdf();
        if (!mounted) return;
        if (bytes == null) {
          showAppSnack(context, 'تعذّر تجهيز السند', error: true);
          return;
        }
        await DocExport.whatsapp(
          context,
          bytes,
          _fileName,
          phone: phone,
          caption: '${receiptViewOf(store, payment).title} رقم ${payment.receiptNumber} — ${webMoney(payment.amount.abs())}',
        );
      }, message: 'جارٍ تجهيز السند...');

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final view = receiptViewOf(store, payment, notice: _notice);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ما يُرى هو ما يُحفظ ويُرسل: المستند نفسه يُلتقط لملف PDF
            RepaintBoundary(key: _document, child: ReceiptDocument(view: view)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'تنزيل السند (PDF)',
                    icon: Icons.download_outlined,
                    onPressed: _ready ? _download : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'واتساب',
                    icon: Icons.chat_outlined,
                    onPressed: _ready && payment.studentId.isNotEmpty ? _whatsapp : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // إلغاء السند من سجل المقبوضات وحده: زرٌّ أحمر بجانب «تم» في نافذة
            // السند كان دعوةً للخطأ بعد قبض ناجح
            PrimaryButton(
              label: 'تم',
              expand: true,
              height: 48,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// طريقة السداد بلا تكرار — `cleanPaymentMethod` في ReceiptModal.
String _cleanMethod(AppStore store, Payment payment) {
  if (payment.method == 'cash') return 'نقداً';
  final raw = store.paymentMethodLabel(payment.method);
  final channel = payment.channel.trim();
  String normalize(String s) => s
      .replaceAll(RegExp(r'[\s\-_]'), '')
      .replaceAll('بي', 'باي')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .toLowerCase();
  final m = normalize(raw);
  final c = normalize(channel);
  if (m.isNotEmpty && c.isNotEmpty && (m.contains(c) || c.contains(m))) return channel.isNotEmpty ? channel : raw;
  if (channel.isNotEmpty && !const ['bank', 'wallet', 'other', 'bank_transfer', 'transfer'].contains(payment.method)) {
    return raw;
  }
  if (channel.isNotEmpty) return channel;
  return raw;
}

/// «وذلك عن» — `paymentPurposeText` في ReceiptModal.
String _purposeText(Payment payment) {
  if (payment.studentId.isEmpty && payment.incomeCategory.trim().isNotEmpty) return payment.incomeCategory.trim();
  final base = paymentPurposeLabel(payment.purpose);
  final note = payment.notes.trim();
  if (note.isNotEmpty && note != payment.purpose && !note.contains(base)) return '$base — $note';
  return note.isNotEmpty ? note : base;
}

/// اسم دافع السند كالويب: اسم الطالب المجمَّد وقت الإصدار، ثم الطالب، ثم الدافع.
String _payerName(Payment payment, Student? student) {
  final frozen = payment.studentName.trim();
  if (frozen.isNotEmpty) return frozen;
  if (student != null && student.fullName.trim().isNotEmpty) return student.fullName.trim();
  if (payment.payerName.trim().isNotEmpty) return payment.payerName.trim();
  return 'عميل عام';
}

/// اسم المستلم: المجمَّد وقت الإصدار، وإلا مستلم هذا الجهاز الآن.
String _receiverName(Payment payment, AppStore store) {
  final frozen = payment.receivedByName.trim();
  return frozen.isEmpty ? store.receiptReceiver : frozen;
}
