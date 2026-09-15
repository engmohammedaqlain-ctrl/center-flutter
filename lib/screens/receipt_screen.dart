import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/balance.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// سند القبض — المقابل لـ `features/finance/ReceiptModal.tsx`.
class ReceiptScreen {
  /// إرسال الإيصال بالواتساب لولي الأمر — مطابق لـ `handleSendWhatsAppReceipt`.
  /// متاحة لملف الطالب أيضاً كي تُرسل الرسالة نفسها من الموضعين.
  static Future<void> sendWhatsApp(BuildContext context, Payment payment, Student student) async {
    final raw = student.parentPhone.isNotEmpty ? student.parentPhone : student.phone;
    if (raw.trim().isEmpty) {
      showAppSnack(context, 'لا يوجد رقم هاتف مسجل للطالب أو ولي الأمر.', error: true);
      return;
    }

    final remaining = payment.remainingAfter > 0
        ? money(payment.remainingAfter)
        : (student.balance < 0 ? money(student.balance.abs()) : '0 ₪ (مسدد بالكامل)');

    final msg = StringBuffer()
      ..writeln('السلام عليكم ورحمة الله وبركاته')
      ..writeln('حضرة ولي أمر الطالب/ة: *${student.fullName}* المحترم')
      ..writeln()
      ..writeln('نحيطكم علماً بأنه تم تسديد دفعة مالية وتوثيق وصل رسمي:')
      ..writeln('📄 *رقم الوصل:* ${payment.receiptNumber}')
      ..writeln('💰 *المبلغ:* ${money(payment.amount)}')
      ..writeln('💳 *طريقة الدفع:* ${StoreScope.of(context).paymentMethodLabel(payment.method)}')
      ..writeln('📌 *البيان / الغرض:* ${paymentPurposeNames[payment.purpose] ?? payment.purpose}');
    if (payment.senderName.isNotEmpty) msg.writeln('👤 *اسم المحول منه:* ${payment.senderName}');
    if (payment.reference.isNotEmpty) msg.writeln('🔢 *الرقم المرجعي:* ${payment.reference}');
    msg
      ..writeln('📅 *تاريخ الدفعة:* ${formatDate(payment.date)}')
      ..write('⚖️ *المتبقي المستحق:* $remaining');
    // ما زاد عن المستحق يُقال رقماً لا عبارةً
    if (paymentAdvance(payment) > 0) {
      msg
        ..writeln()
        ..write('💠 *رصيد مقدم:* ${money(paymentAdvance(payment))}');
    }

    await launchWaWithText(raw, msg.toString());
  }

  static Future<void> open(BuildContext context, Payment payment) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _ReceiptSheet(payment: payment),
    );
  }
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final student = store.studentById(payment.studentId);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), border: Border.all(color: AppColors.navy, width: 1.4)),
              child: Column(
                children: [
                  Row(
                    children: [
                      InstitutionBadge(logo: store.institutionLogo, size: 36),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.institutionName.isEmpty ? appName : store.institutionName,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
                            ),
                            const Text('سند قبض رسمي', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(payment.receiptNumber,
                              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber, fontSize: 12.5)),
                          Text(formatDate(payment.date), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.line),
                  const SizedBox(height: 8),
                  _row('وصلنا من', _payerName(payment, student)),
                  _row('المرحلة', student?.gradeLevel ?? '—'),
                  _row('المبلغ المقبوض', money(payment.amount)),
                  // «وقدره كتابةً» — بند رسمي في السند لا يجوز إسقاطه
                  _row('وقدره كتابةً', amountInArabicWords(payment.amount)),
                  _row('طريقة السداد', store.paymentMethodLabel(payment.method)),
                  _row('وذلك عن', paymentPurposeNames[payment.purpose] ?? payment.purpose),
                  if (payment.senderName.isNotEmpty) _row('اسم المحول منه', payment.senderName),
                  if (payment.reference.isNotEmpty) _row('الرقم المرجعي', payment.reference),
                  if (payment.channel.isNotEmpty) _row('جهة التحويل', payment.channel),
                  if (payment.transferDate.isNotEmpty) _row('تاريخ التحويل', payment.transferDate),
                  if (payment.customMethodNotes.isNotEmpty) _row('تفاصيل الوسيلة', payment.customMethodNotes),
                  // بيانٌ يكرّر البند لا يُعرض مرتين
                  if (payment.notes.isNotEmpty && payment.notes != payment.purpose) _row('البيان', payment.notes),
                  const SizedBox(height: 6),
                  _ledger(payment),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('المستلم: ${_receiverName(payment, store)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ),
                      const Text('التوقيع: ....................',
                          style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                  if (payment.cancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          const StatusChip(
                            label: 'هذا السند ملغى',
                            fg: Color(0xFF991B1B),
                            bg: AppColors.dangerSoft,
                            border: AppColors.dangerBorder,
                          ),
                          if (payment.cancelReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(payment.cancelReason,
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.danger)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'تنزيل السند (PDF)',
                    icon: Icons.print_outlined,
                    onPressed: () => _print(context, store, student),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'واتساب',
                    icon: Icons.chat_outlined,
                    onPressed: student == null ? null : () => _whatsapp(context, store, student),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context))),
                if (!payment.cancelled && store.can('finance')) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: 'إلغاء السند',
                      color: AppColors.danger,
                      onPressed: () async {
                        final ok = await confirmSheet(
                          context,
                          title: 'تأكيد إلغاء الدفعة',
                          message:
                              'هل أنت متأكد من إلغاء الدفعة رقم ${payment.receiptNumber} بمبلغ ${money(payment.amount)}؟',
                          confirmLabel: 'إلغاء السند',
                        );
                        if (ok && context.mounted) {
                          store.cancelPayment(payment);
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledger(Payment p) {
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: AppColors.bg, border: Border.all(color: AppColors.line)),
            child: Column(
              children: [
                Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color ?? AppColors.heading)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        cell('المبلغ المسدد', money(p.amount), color: AppColors.success),
        const SizedBox(width: 4),
        // ما زاد عن المستحق يُقال رقماً: «دفعة مقدمة» وحدها لا تخبر بكم
        if (paymentAdvance(p) > 0)
          cell('رصيد مقدم', money(paymentAdvance(p)), color: AppColors.amber)
        else
          cell('المتبقي المستحق', p.remainingAfter <= 0 ? '0 ₪' : money(p.remainingAfter),
              color: p.remainingAfter <= 0 ? AppColors.success : AppColors.danger),
        const SizedBox(width: 4),
        cell('الحالة', p.cancelled ? 'ملغى' : 'معتمد', color: p.cancelled ? AppColors.danger : AppColors.success),
      ],
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
          Expanded(child: Text(v, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading))),
        ],
      ),
    );
  }

  Future<void> _print(BuildContext context, AppStore store, Student? student) async {
    final rows = <List<String>>[
      ['وصلنا من', _payerName(payment, student)],
      if (student != null) ['المرحلة الدراسية', student.gradeLevel],
      ['المبلغ المقبوض', money(payment.amount)],
      ['وقدره كتابةً', amountInArabicWords(payment.amount)],
      ['طريقة السداد', store.paymentMethodLabel(payment.method)],
      ['وذلك عن', paymentPurposeNames[payment.purpose] ?? payment.purpose],
      if (payment.senderName.isNotEmpty) ['اسم المحول منه', payment.senderName],
      if (payment.reference.isNotEmpty) ['الرقم المرجعي', payment.reference],
      if (payment.channel.isNotEmpty) ['جهة التحويل', payment.channel],
      if (payment.notes.isNotEmpty && payment.notes != payment.purpose) ['البيان', payment.notes],
    ];

    final bytes = await PdfKit.build(
      title: 'سند قبض رسمي رقم ${payment.receiptNumber}',
      institutionName: store.institutionName.isEmpty ? appName : store.institutionName,
      logoBase64: store.institutionLogo,
      subtitle: 'التاريخ: ${formatDate(payment.date)}',
      body: (ctx) => [
        PdfKit.table(headers: const ['البيان', 'التفاصيل'], rows: rows, flex: [3, 8]),
        pw.SizedBox(height: 12),
        PdfKit.table(
          headers: [
            'المبلغ المسدد',
            paymentAdvance(payment) > 0 ? 'رصيد مقدم' : 'المتبقي المستحق',
            'الحالة',
          ],
          rows: [
            [
              money(payment.amount),
              paymentAdvance(payment) > 0
                  ? money(paymentAdvance(payment))
                  : (payment.remainingAfter <= 0 ? '0 ₪ (مسدد بالكامل)' : money(payment.remainingAfter)),
              payment.cancelled ? 'ملغى' : 'معتمد',
            ],
          ],
        ),
        if (payment.cancelled) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red)),
            child: pw.Text(
              'هذا السند ملغى${payment.cancelReason.isEmpty ? '' : ' — ${payment.cancelReason}'}',
              style: const pw.TextStyle(color: PdfColors.red, fontSize: 10),
            ),
          ),
        ],
        pw.SizedBox(height: 26),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('المستلم: ${_receiverName(payment, store)}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('التوقيع: ....................', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );

    if (!context.mounted) return;
    await PdfKit.preview(bytes, PdfKit.fileName('سند قبض ${payment.receiptNumber}'));
  }

  /// إرسال الإيصال بالواتساب لولي الأمر — مطابق لـ `handleSendWhatsAppReceipt`.
  Future<void> _whatsapp(BuildContext context, AppStore store, Student student) =>
      ReceiptScreen.sendWhatsApp(context, payment, student);
}

/// اسم دافع السند: المجمَّد وقت الإصدار أولاً، فلا يتغيّر وصل قديم إن تغيّر اسم الطالب.
String _payerName(Payment payment, Student? student) {
  final frozen = payment.studentName.trim();
  if (frozen.isNotEmpty) return frozen;
  return student?.fullName ?? (payment.notes.isEmpty ? 'سند عام' : payment.notes);
}

/// اسم المستلم: المجمَّد وقت الإصدار، وإلا مستلم هذا الجهاز الآن.
String _receiverName(Payment payment, AppStore store) {
  final frozen = payment.receivedByName.trim();
  return frozen.isEmpty ? store.receiptReceiver : frozen;
}
