import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/printing.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// سند صرف قابل للطباعة — المقابل لـ `ExpenseVoucherModal.tsx`.
///
/// بنفس شكل سند القبض المعتمد: المصروف كان يُسجَّل بلا وصل يُسلَّم لمن قبض المبلغ.
class ExpenseVoucher {
  const ExpenseVoucher({
    required this.id,
    required this.isPayout,
    required this.date,
    required this.category,
    required this.description,
    required this.amount,
    this.method = 'cash',
    this.notes = '',
    this.issuedBy = '',
    this.recipient = '',
  });

  final String id;

  /// سند أجر معلم أو سند مصروف عام.
  final bool isPayout;
  final String date;
  final String category;

  /// اسم المستفيد (صُرف إلى).
  final String description;
  final double amount;
  final String method;
  final String notes;

  /// من صرف السند — اسم مجمَّد لحظة التسجيل (الصارف).
  final String issuedBy;

  /// المستلم إن وُجد (اسم المعلم في سند الأجر).
  final String recipient;

  String get title => isPayout ? 'سند صرف أجر معلم' : 'سند صرف';

  /// «وذلك عن: التصنيف — الملاحظة» كما في الويب.
  String get aboutLine {
    final cat = category.trim();
    final note = notes.trim();
    if (cat.isEmpty) return note;
    if (note.isEmpty) return cat;
    return '$cat — $note';
  }

  factory ExpenseVoucher.fromExpense(Expense e) => ExpenseVoucher(
        id: e.id,
        isPayout: false,
        date: e.expenseDate,
        category: expenseCategoryLabel(e.category),
        description: e.description,
        amount: e.amount,
        method: e.method,
        notes: e.notes,
        issuedBy: e.recordedByName,
      );

  factory ExpenseVoucher.fromPayout(TeacherPayout p, {String fallbackName = ''}) {
    final name = p.teacherName.trim().isNotEmpty
        ? p.teacherName.trim()
        : fallbackName.trim();
    final typeMonth =
        '${payoutTypeNames[p.payoutType] ?? 'راتب'} ${monthLabel(salaryMonthOf(p))}';
    final note = p.notes.trim();
    return ExpenseVoucher(
      id: p.id,
      isPayout: true,
      date: p.paymentDate,
      category: payoutExpenseCategory,
      description: name.isEmpty ? 'معلم' : name,
      amount: p.amount,
      method: p.method,
      notes: note.isEmpty ? typeMonth : '$typeMonth — $note',
      issuedBy: p.paidByName,
      recipient: name,
    );
  }

  static Future<void> open(BuildContext context, ExpenseVoucher voucher) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _VoucherSheet(voucher: voucher),
    );
  }
}

/// رقم السند للعرض والطباعة — مطابق لـ `voucherNumber`.
///
/// المصروفات بلا عمود ترقيم متسلسل في السحابة، فيُشتق رقم ثابت من تاريخ السند
/// ومعرّفه: لا يتغيّر بين الأجهزة ولا عند إعادة الطباعة.
String expenseVoucherNumber(ExpenseVoucher v) {
  final datePart = v.date.replaceAll('-', '');
  final date = datePart.length >= 8 ? datePart.substring(0, 8) : datePart;
  final clean = v.id.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  final tail = clean.length <= 4 ? clean : clean.substring(clean.length - 4);
  return '${v.isPayout ? 'أ' : 'ص'}-$date-${tail.toUpperCase()}';
}

class _VoucherSheet extends StatelessWidget {
  const _VoucherSheet({required this.voucher});

  final ExpenseVoucher voucher;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final day = parseIsoDate(voucher.date.length >= 10 ? voucher.date.substring(0, 10) : voucher.date);
    final methodLabel = store.paymentMethodLabel(voucher.method);
    final issuer = voucher.issuedBy.isEmpty ? store.receiptReceiver : voucher.issuedBy;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: AppColors.navy, width: 1.4),
              ),
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
                            Text(voucher.title, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            expenseVoucherNumber(voucher),
                            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber, fontSize: 12.5),
                          ),
                          Text(
                            day == null ? voucher.date : formatDate(day),
                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.line),
                  const SizedBox(height: 8),
                  _row('صُرف إلى', voucher.description),
                  _row('وذلك عن', voucher.aboutLine),
                  _row('المبلغ المصروف', money(voucher.amount)),
                  _row('وقدره كتابةً', amountInArabicWords(voucher.amount)),
                  _row('طريقة الصرف', methodLabel),
                  _NoticeImage(recordId: voucher.id),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الصارف: $issuer',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                            if (voucher.recipient.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'المستلم: ${voucher.recipient.trim()}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (store.institutionStamp.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120, maxHeight: 46),
                          child: Image.memory(
                            base64Decode(store.institutionStamp.split(',').last),
                            fit: BoxFit.contain,
                            cacheHeight: (64 * MediaQuery.devicePixelRatioOf(context)).round(),
                          ),
                        )
                      else
                        const Text('التوقيع: ....................',
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'تنزيل السند (PDF)',
              icon: Icons.print_outlined,
              onPressed: () => _print(context, store),
            ),
            const SizedBox(height: 8),
            PrimaryButton(label: 'تم', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ),
          ],
        ),
      );

  Future<void> _print(BuildContext context, AppStore store) async {
    final stamp = PdfKit.decodeImage(store.institutionStamp);
    final day = parseIsoDate(voucher.date.length >= 10 ? voucher.date.substring(0, 10) : voucher.date);
    final dateLabel = day == null ? voucher.date : formatDate(day);
    final methodLabel = store.paymentMethodLabel(voucher.method);
    final issuer = voucher.issuedBy.isEmpty ? store.receiptReceiver : voucher.issuedBy;
    final voucherNo = expenseVoucherNumber(voucher);
    final noticeRaw = voucher.method == 'cash' ? null : await store.loadNoticeImage(voucher.id);
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
      title: voucher.title,
      institutionName: store.institutionName.isEmpty ? appName : store.institutionName,
      logoBase64: store.institutionLogo,
      subtitle: 'التاريخ: $dateLabel',
      body: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700),
                color: PdfColors.grey100,
              ),
              child: pw.Text('سند صرف معتمد', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  children: [
                    pw.Text('رقم السند: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ltr(voucherNo, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
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
                  pw.Text('المبلغ المصروف:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ltr(money(voucher.amount), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('طريقة الصرف:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text(methodLabel, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        dottedRow(
          'صُرف إلى',
          pw.Text(voucher.description, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        ),
        dottedRow('وقدره كتابة', pw.Text(amountInArabicWords(voucher.amount), style: const pw.TextStyle(fontSize: 9))),
        dottedRow('وذلك عن', pw.Text(voucher.aboutLine, style: const pw.TextStyle(fontSize: 9))),
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
        pw.SizedBox(height: 22),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('الصارف: $issuer', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 14),
                pw.Container(
                  width: 100,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500)),
                  ),
                ),
              ],
            ),
            pw.Column(
              children: [
                pw.Text('المستلم', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                if (voucher.recipient.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(voucher.recipient.trim(), style: const pw.TextStyle(fontSize: 8)),
                  ),
                pw.SizedBox(height: 14),
                pw.Container(
                  width: 90,
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
    try {
      await PdfKit.share(bytes, 'voucher_$voucherNo.pdf');
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر تنزيل السند', error: true);
    }
  }
}

/// صورة إشعار التحويل المرفقة بالسند — تُنزَّل عند فتحه وحده.
class _NoticeImage extends StatelessWidget {
  const _NoticeImage({required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return FutureBuilder<String?>(
      future: store.loadNoticeImage(recordId),
      builder: (context, snapshot) {
        final image = snapshot.data ?? '';
        if (image.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Corner.box),
            child: Image.memory(
              base64Decode(image.split(',').last),
              height: 150,
              fit: BoxFit.cover,
              cacheHeight: (150 * MediaQuery.devicePixelRatioOf(context)).round(),
            ),
          ),
        );
      },
    );
  }
}
