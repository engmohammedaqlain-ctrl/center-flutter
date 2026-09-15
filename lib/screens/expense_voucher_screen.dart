import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/printing.dart';
import '../data/store.dart';
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
  });

  final String id;

  /// سند أجر معلم أو سند مصروف عام.
  final bool isPayout;
  final String date;
  final String category;

  /// البيان أو اسم المستفيد.
  final String description;
  final double amount;
  final String method;
  final String notes;

  /// من صرف السند — اسم مجمَّد لحظة التسجيل.
  final String issuedBy;

  String get title => isPayout ? 'سند صرف أجر معلم' : 'سند صرف';

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

  factory ExpenseVoucher.fromPayout(TeacherPayout p) => ExpenseVoucher(
        id: p.id,
        isPayout: true,
        date: p.paymentDate,
        category: 'أجور تدريس',
        description: p.teacherName.trim().isEmpty ? 'أجر معلم' : p.teacherName.trim(),
        amount: p.amount,
        method: p.method,
        notes: p.notes,
        issuedBy: p.paidByName,
      );

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
                  _row(voucher.isPayout ? 'صُرف إلى' : 'البيان', voucher.description),
                  _row('التصنيف', voucher.category),
                  _row('المبلغ المصروف', money(voucher.amount)),
                  _row('وقدره كتابةً', amountInArabicWords(voucher.amount)),
                  _row('طريقة الصرف', expenseMethodNames[voucher.method] ?? voucher.method),
                  if (voucher.notes.isNotEmpty) _row('ملاحظات', voucher.notes),
                  _NoticeImage(recordId: voucher.id),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'صرفها: ${voucher.issuedBy.isEmpty ? store.receiptReceiver : voucher.issuedBy}',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted),
                        ),
                      ),
                      if (store.institutionStamp.isNotEmpty)
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
    final bytes = await PdfKit.build(
      title: '${voucher.title} رقم ${expenseVoucherNumber(voucher)}',
      institutionName: store.institutionName.isEmpty ? appName : store.institutionName,
      logoBase64: store.institutionLogo,
      subtitle: 'التاريخ: ${day == null ? voucher.date : formatDate(day)}',
      body: (ctx) => [
        PdfKit.table(
          headers: const ['البيان', 'التفاصيل'],
          rows: [
            [voucher.isPayout ? 'صُرف إلى' : 'البيان', voucher.description],
            ['التصنيف', voucher.category],
            ['المبلغ المصروف', money(voucher.amount)],
            ['وقدره كتابةً', amountInArabicWords(voucher.amount)],
            ['طريقة الصرف', expenseMethodNames[voucher.method] ?? voucher.method],
            if (voucher.notes.isNotEmpty) ['ملاحظات', voucher.notes],
          ],
          flex: [3, 8],
        ),
        pw.SizedBox(height: 26),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'صرفها: ${voucher.issuedBy.isEmpty ? store.receiptReceiver : voucher.issuedBy}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (stamp != null)
              pw.SizedBox(width: 90, height: 42, child: pw.Image(stamp, fit: pw.BoxFit.contain))
            else
              pw.Text('التوقيع: ....................', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );
    await PdfKit.share(bytes, 'voucher_${expenseVoucherNumber(voucher)}.pdf');
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
            child: Image.memory(base64Decode(image.split(',').last), height: 150, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}
