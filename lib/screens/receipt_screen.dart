import 'dart:convert';

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

    final remainingText = payment.remainingAfter > 0
        ? '${_shekel(payment.remainingAfter)} شيكل'
        : (student.balance < 0
            ? '${_shekel(student.balance.abs())} شيكل'
            : '0 شيكل (مسدد بالكامل)');

    final purpose = paymentPurposeLabel(payment.purpose);
    final note = payment.notes.trim();
    final statement = note.isNotEmpty && note != purpose ? '$purpose — $note' : purpose;

    final msg = StringBuffer()
      ..writeln('السلام عليكم ورحمة الله وبركاته')
      ..writeln('حضرة ولي أمر الطالب/ة: *${student.fullName}* المحترم')
      ..writeln()
      ..writeln('إشعار استلام دفعة مالية:')
      ..writeln('- رقم الوصل: ${payment.receiptNumber}')
      ..writeln('- المبلغ: ${_shekel(payment.amount.abs())} شيكل')
      ..writeln('- طريقة الدفع: ${StoreScope.of(context).paymentMethodLabel(payment.method)}')
      ..writeln('- البيان: $statement');
    if (payment.senderName.isNotEmpty) msg.writeln('- اسم المحول: ${payment.senderName}');
    if (payment.reference.isNotEmpty) msg.writeln('- الرقم المرجعي: ${payment.reference}');
    msg
      ..writeln('- تاريخ الدفعة: ${formatDate(payment.date)}')
      ..write('- المتبقي: $remainingText');
    if (paymentAdvance(payment) > 0) {
      msg
        ..writeln()
        ..write('- رصيد مقدم: ${_shekel(paymentAdvance(payment))} شيكل');
    }

    await launchWaWithText(raw, msg.toString());
  }

  static String _shekel(num value) {
    final n = value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
    return n;
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
    final outgoing = payment.amount < 0;
    final reversal = isReversalPurpose(payment.purpose);
    final generalIncome = payment.studentId.isEmpty || isGeneralIncomePurpose(payment.purpose);
    final sheetTitle = !outgoing
        ? (generalIncome ? 'سند إيراد' : 'سند قبض مالي')
        : (reversal ? 'سند عكس' : 'سند رد مبلغ');
    final absAmount = payment.amount.abs();
    final payerLabel = outgoing
        ? (reversal ? 'عكس لحساب' : 'رُدّ إلى ولي أمر')
        : 'وصلنا من';
    final amountLabel = outgoing ? 'المبلغ المردود' : 'المبلغ المقبوض';

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
                            Text(sheetTitle, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
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
                  _row(payerLabel, _payerName(payment, student)),
                  if (student != null) _row('المرحلة', student.gradeLevel),
                  if (generalIncome && payment.incomeCategory.trim().isNotEmpty)
                    _row('نوع الإيراد', payment.incomeCategory),
                  _row(amountLabel, money(absAmount)),
                  // «وقدره كتابةً» — بند رسمي في السند لا يجوز إسقاطه
                  _row('وقدره كتابةً', amountInArabicWords(absAmount)),
                  if (payment.discountAmount.abs() > 0) ...[
                    _row(
                      'الأصلي',
                      money((payment.originalAmount ?? (payment.amount + payment.discountAmount)).abs()),
                    ),
                    _row(
                      'الخصم',
                      '-${money(payment.discountAmount.abs())}${payment.discountReason.isEmpty ? '' : ' (${payment.discountReason})'}',
                    ),
                  ],
                  _row(
                    'طريقة السداد',
                    [
                      store.paymentMethodLabel(payment.method),
                      if (payment.channel.trim().isNotEmpty) '(${payment.channel.trim()})',
                    ].join(' '),
                  ),
                  _row(
                    'وذلك عن',
                    _statementLine(payment),
                  ),
                  if (payment.senderName.isNotEmpty) _row('اسم المحول منه', payment.senderName),
                  if (payment.reference.isNotEmpty) _row('الرقم المرجعي', payment.reference),
                  if (payment.customMethodNotes.isNotEmpty) _row('تفاصيل الوسيلة', payment.customMethodNotes),
                  _NoticeRow(payment: payment),
                  if (!outgoing && !generalIncome) ...[
                    const SizedBox(height: 6),
                    _ledger(payment),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('المستلم: ${_receiverName(payment, store)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ),
                      if (store.institutionStamp.isNotEmpty)
                        // ختمٌ عريض كان يطفح عن السطر: يُحصر بعرضه وارتفاعه
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120, maxHeight: 46),
                          child: Image.memory(
                            base64Decode(store.institutionStamp.split(',').last),
                            fit: BoxFit.contain,
                          ),
                        )
                      else
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
          cell('المتبقي المستحق', p.remainingAfter <= 0 ? '0 شيكل' : money(p.remainingAfter),
              color: p.remainingAfter <= 0 ? AppColors.success : AppColors.danger),
        const SizedBox(width: 4),
        cell('الحالة', p.cancelled ? 'ملغى' : (p.remainingAfter <= 0 ? 'مسدد بالكامل' : 'مستمر'),
            color: p.cancelled
                ? AppColors.danger
                : (p.remainingAfter <= 0 ? AppColors.success : AppColors.amber)),
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
    final outgoing = payment.amount < 0;
    final reversal = isReversalPurpose(payment.purpose);
    final generalIncome = payment.studentId.isEmpty || isGeneralIncomePurpose(payment.purpose);
    final sheetTitle = !outgoing
        ? (generalIncome ? 'سند إيراد' : 'سند قبض مالي')
        : (reversal ? 'سند عكس' : 'سند رد مبلغ');
    final absAmount = payment.amount.abs();
    final methodLine = [
      store.paymentMethodLabel(payment.method),
      if (payment.channel.trim().isNotEmpty) '(${payment.channel.trim()})',
    ].join(' ');
    final stamp = PdfKit.decodeImage(store.institutionStamp);
    final noticeRaw = payment.method == 'cash' ? null : await store.loadNoticeImage(payment.id);
    final notice = PdfKit.decodeImage(noticeRaw);

    pw.Widget dottedRow(String label, pw.Widget value) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 6),
          margin: const pw.EdgeInsets.only(bottom: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, style: pw.BorderStyle.dotted)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('$label:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(width: 6),
              pw.Expanded(child: value),
            ],
          ),
        );

    final bytes = await PdfKit.build(
      title: sheetTitle,
      institutionName: store.institutionName.isEmpty ? appName : store.institutionName,
      logoBase64: store.institutionLogo,
      subtitle: 'التاريخ: ${formatDate(payment.date)}',
      body: (ctx) => [
        // شارة الاعتماد ورقم الوصل — كالويب ReceiptModal
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700),
                color: PdfColors.grey100,
              ),
              child: pw.Text('وصل مالي معتمد', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  children: [
                    pw.Text('رقم الوصل: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ltr(payment.receiptNumber, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Text(formatDate(payment.date), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(outgoing ? 'المبلغ المردود:' : 'المبلغ المقبوض:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ltr(money(absAmount), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('طريقة السداد:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text(methodLine, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        if (payment.discountAmount.abs() > 0) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'الأصلي: ${money((payment.originalAmount ?? (payment.amount + payment.discountAmount)).abs())}'
            '   ·   الخصم: -${money(payment.discountAmount.abs())}'
            '${payment.discountReason.isEmpty ? '' : ' (${payment.discountReason})'}',
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ],
        pw.SizedBox(height: 10),
        dottedRow(
          outgoing ? (reversal ? 'عكس لحساب' : 'رُدّ إلى ولي أمر') : 'وصلنا من',
          pw.Text(
            [
              _payerName(payment, student),
              if (student != null && student.gradeLevel.trim().isNotEmpty) '(${student.gradeLevel})',
            ].join(' '),
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if (payment.senderName.isNotEmpty)
          dottedRow('اسم المحول منه', pw.Text(payment.senderName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        dottedRow('وقدره كتابة', pw.Text(amountInArabicWords(absAmount), style: const pw.TextStyle(fontSize: 9))),
        dottedRow('وذلك عن', pw.Text(_statementLine(payment), style: const pw.TextStyle(fontSize: 9))),
        if (payment.reference.isNotEmpty)
          dottedRow('الرقم المرجعي', ltr(payment.reference, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        if (payment.channel.trim().isNotEmpty)
          dottedRow('جهة التحويل', pw.Text(payment.channel.trim(), style: const pw.TextStyle(fontSize: 9))),
        if (notice != null) ...[
          pw.SizedBox(height: 8),
          pw.Text('إشعار التحويل المرفق:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Container(
              constraints: const pw.BoxConstraints(maxHeight: 140),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Image(notice, fit: pw.BoxFit.contain, height: 140),
            ),
          ),
        ],
        if (!outgoing && !generalIncome) ...[
          pw.SizedBox(height: 10),
          PdfKit.table(
            headers: [
              'المبلغ المسدد',
              paymentAdvance(payment) > 0 ? 'رصيد مقدم' : 'المتبقي المستحق',
              'الحالة',
            ],
            rows: [
              [
                money(absAmount),
                paymentAdvance(payment) > 0
                    ? money(paymentAdvance(payment))
                    : (payment.remainingAfter <= 0 ? '0 شيكل (مسدد بالكامل)' : money(payment.remainingAfter)),
                payment.cancelled
                    ? 'ملغى'
                    : (payment.remainingAfter <= 0 ? 'مسدد بالكامل' : 'مستمر'),
              ],
            ],
          ),
        ],
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
        pw.SizedBox(height: 22),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('المستلم: ${_receiverName(payment, store)}', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 14),
                pw.Container(
                  width: 100,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500)),
                  ),
                ),
              ],
            ),
            if (stamp != null)
              pw.SizedBox(width: 90, height: 42, child: pw.Image(stamp, fit: pw.BoxFit.contain))
            else
              pw.Text('الختم الرسمي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ],
    );

    if (!context.mounted) return;
    try {
      await PdfKit.preview(bytes, PdfKit.fileName('سند قبض ${payment.receiptNumber}'));
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر تنزيل السند', error: true);
    }
  }

  /// إرسال الإيصال بالواتساب لولي الأمر — مطابق لـ `handleSendWhatsAppReceipt`.
  Future<void> _whatsapp(BuildContext context, AppStore store, Student student) =>
      ReceiptScreen.sendWhatsApp(context, payment, student);
}

/// اسم دافع السند: المجمَّد وقت الإصدار أولاً، فلا يتغيّر وصل قديم إن تغيّر اسم الطالب.
String _payerName(Payment payment, Student? student) {
  if (payment.payerName.trim().isNotEmpty) return payment.payerName.trim();
  final frozen = payment.studentName.trim();
  if (frozen.isNotEmpty) return frozen;
  return student?.fullName ?? 'عميل عام';
}

/// «وذلك عن: البند — الملاحظة» مدموجاً كما في الويب.
String _statementLine(Payment payment) {
  final purpose = paymentPurposeLabel(payment.purpose);
  if (isGeneralIncomePurpose(payment.purpose) && payment.incomeCategory.trim().isNotEmpty) {
    final note = payment.notes.trim();
    final cat = payment.incomeCategory.trim();
    return note.isEmpty ? cat : '$cat — $note';
  }
  final note = payment.notes.trim();
  if (note.isEmpty || note == purpose || note == payment.purpose) return purpose;
  return '$purpose — $note';
}

/// اسم المستلم: المجمَّد وقت الإصدار، وإلا مستلم هذا الجهاز الآن.
String _receiverName(Payment payment, AppStore store) {
  final frozen = payment.receivedByName.trim();
  return frozen.isEmpty ? store.receiptReceiver : frozen;
}

/// صورة إشعار التحويل داخل السند — تُنزَّل من الحاوية عند فتحه، لا مع كل مزامنة.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (payment.method == 'cash') return const SizedBox.shrink();

    return FutureBuilder<String?>(
      future: store.loadNoticeImage(payment.id),
      builder: (context, snapshot) {
        final image = snapshot.data ?? '';
        if (image.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('إشعار التحويل', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(Corner.box),
                child: Image.memory(base64Decode(image.split(',').last), height: 160, fit: BoxFit.cover),
              ),
            ],
          ),
        );
      },
    );
  }
}
