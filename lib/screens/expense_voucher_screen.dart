import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/finance_documents.dart';
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

class _VoucherSheet extends StatefulWidget {
  const _VoucherSheet({required this.voucher});

  final ExpenseVoucher voucher;

  @override
  State<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends State<_VoucherSheet> {
  final _document = GlobalKey();
  Uint8List? _notice;
  bool _ready = false;

  ExpenseVoucher get voucher => widget.voucher;

  @override
  void initState() {
    super.initState();
    _loadNotice();
  }

  Future<void> _loadNotice() async {
    final raw = await AppStore.instance.loadNoticeImage(voucher.id);
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
  }

  String get _fileName => 'سند صرف ${expenseVoucherNumber(voucher)}';

  /// المستند كما يُرى، ملف PDF بعرض 130مم كطباعة الويب.
  Future<Uint8List?> _pdf() => captureDocumentPdf(_document, widthMm: 130, title: _fileName);

  Future<void> _run(Future<void> Function(Uint8List bytes) send) => runBusyOp(context, () async {
        final bytes = await _pdf();
        if (!mounted) return;
        if (bytes == null) {
          showAppSnack(context, 'تعذّر تجهيز السند', error: true);
          return;
        }
        await send(bytes);
      }, message: 'جارٍ تجهيز السند...');

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final day = parseIsoDate(voucher.date.length >= 10 ? voucher.date.substring(0, 10) : voucher.date);
    final issuer = voucher.issuedBy.isEmpty ? store.receiptReceiver : voucher.issuedBy;
    final view = VoucherView(
      institutionName: store.institutionName.trim().isEmpty ? appName : store.institutionName.trim(),
      logo: store.institutionLogo,
      stamp: store.institutionStamp,
      title: voucher.title,
      number: expenseVoucherNumber(voucher),
      date: day == null ? voucher.date : formatDate(day),
      amount: voucher.amount,
      methodLabel: store.paymentMethodLabel(voucher.method),
      paidTo: voucher.description,
      amountWords: amountInArabicWords(voucher.amount),
      aboutLine: voucher.aboutLine,
      issuedBy: issuer.trim().isEmpty ? 'الإدارة' : issuer,
      notice: _notice,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ما يُرى هو ما يُحفظ ويُرسل
            RepaintBoundary(key: _document, child: VoucherDocument(view: view)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'تنزيل السند (PDF)',
                    icon: Icons.download_outlined,
                    onPressed: _ready ? () => _run((b) => DocExport.download(context, b, _fileName)) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'واتساب',
                    icon: Icons.chat_outlined,
                    onPressed: _ready
                        ? () => _run((b) => DocExport.whatsapp(
                              context,
                              b,
                              _fileName,
                              caption: '${voucher.title} رقم ${expenseVoucherNumber(voucher)} — ${webMoney(voucher.amount)}',
                            ))
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PrimaryButton(label: 'تم', expand: true, height: 48, onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}
