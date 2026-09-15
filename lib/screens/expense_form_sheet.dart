import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/payment_methods.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

/// نافذة «تسجيل سند صرف جديد» — المقابل لـ `isExpenseModalOpen` في Finance.tsx.
///
/// سندٌ عام أو صرف أجر معلم، بنفس النموذج كما في النسخة المكتبية.
/// تُعيد `true` إن حُفظ السند.
Future<bool> showExpenseSheet(
  BuildContext context,
  AppStore store, {
  String payoutTeacherId = '',
  double? payoutAmount,
  String salaryMonth = '',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ExpenseSheet(
      store: store,
      payoutTeacherId: payoutTeacherId,
      payoutAmount: payoutAmount,
      salaryMonth: salaryMonth,
    ),
  );
  return result == true;
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({
    required this.store,
    this.payoutTeacherId = '',
    this.payoutAmount,
    this.salaryMonth = '',
  });

  final AppStore store;

  /// صرف راتب معلم بعينه: النموذج يُفتح مهيّأً بالباقي من راتب شهره.
  final String payoutTeacherId;
  final double? payoutAmount;
  final String salaryMonth;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  /// `expense` سند مصروف عام، و`payout` صرف أجر معلم.
  late String entryType = widget.payoutTeacherId.isEmpty ? 'expense' : 'payout';
  String category = expenseCategories.first;
  late String teacherId = widget.payoutTeacherId;
  late String method = _defaultMethod();
  final description = TextEditingController();
  late final amount = TextEditingController(
    text: widget.payoutAmount == null ? '' : trimNum(widget.payoutAmount!),
  );
  final notes = TextEditingController();
  late String date = isoDate(DateTime.now());

  /// صورة إشعار التحويل: تُرفق بسند الصرف وبسند أجر المعلم كما تُرفق بسند القبض.
  String notice = '';

  bool submitting = false;
  String? error;
  final errors = FieldErrors();

  bool get isPayout => entryType == 'payout';

  /// وسائل الدفع المعرّفة في المنشأة — الصرف يتبعها كالقبض، لا قائمة ثابتة.
  List<PaymentMethodItem> get methods => widget.store.activePaymentMethods;

  /// اختيار صورة الإشعار وضغطها — الحدّ ٢ ميجابايت كما في حاوية الإشعارات.
  Future<void> _pickNotice() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) showAppSnack(context, 'الصورة أكبر من 2 ميجابايت', error: true);
        return;
      }
      if (!mounted) return;
      setState(() => notice = 'data:${file.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}');
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر اختيار الصورة', error: true);
    }
  }

  String _defaultMethod() {
    final active = widget.store.activePaymentMethods;
    if (active.isEmpty) return 'cash';
    return active.firstWhere((m) => m.isDefault, orElse: () => active.first).id;
  }

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = parseIsoDate(date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 5),
    );
    if (picked != null) setState(() => date = isoDate(picked));
  }

  void _switchType(String type) {
    if (entryType == type) return;
    setState(() {
      entryType = type;
      error = null;
      errors.reset();
    });
  }

  void _save() {
    final value = double.tryParse(amount.text.trim()) ?? 0;
    setState(() {
      error = null;
      errors
        ..reset()
        ..check('teacher', isPayout && teacherId.isEmpty, 'اختر المعلم المستفيد')
        ..check('description', !isPayout && description.text.trim().isEmpty, 'البيان / المستفيد مطلوب')
        ..check('amount', value <= 0, 'المبلغ يجب أن يكون أكبر من صفر');
    });
    if (errors.report(context)) return;

    setState(() => submitting = true);
    try {
      final String recordId;
      if (isPayout) {
        recordId = widget.store.addTeacherPayout(
          teacherId: teacherId,
          amount: value,
          paymentDate: date,
          // الصرف يُنسب لشهر الراتب لا ليوم صرفه
          periodStart: widget.salaryMonth.isEmpty ? '' : '${widget.salaryMonth}-01',
          method: method,
          notes: notes.text,
        ).id;
      } else {
        recordId = widget.store.addExpense(
          category: category,
          description: description.text,
          amount: value,
          expenseDate: date,
          method: method,
          notes: notes.text,
        ).id;
      }
      // الإشعار يلحق بالسند: يُحفظ على الجهاز ويُرفع بأول اتصال
      unawaited(widget.store.saveFinanceAttachment(
        recordId,
        isPayout ? 'payout' : 'expense',
        notice.isEmpty ? null : notice,
      ));
      if (mounted) Navigator.pop(context, true);
    } on StoreException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teachers = widget.store.teachers;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isPayout ? 'تسجيل صرف أجر معلم' : 'تسجيل سند صرف جديد',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                  ),
                ),
                SquareIconButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context, false),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _TypeTabs(active: entryType, onSelect: _switchType),
            const SizedBox(height: 12),

            if (isPayout) ...[
              FieldLabel('المعلم المستفيد:', key: errors.key('teacher'), requiredField: true),
              AppDropdown<String>(
                value: teacherId.isEmpty ? null : teacherId,
                hint: '-- اختر المعلم --',
                errorText: errors['teacher'],
                items: [
                  for (final t in teachers) DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() {
                  teacherId = v ?? '';
                  errors.clear('teacher');
                }),
              ),
            ] else ...[
              const FieldLabel('بند المصروف / التصنيف:'),
              AppDropdown<String>(
                value: category,
                items: [
                  for (final c in expenseCategories)
                    DropdownMenuItem(value: c, child: Text(expenseCategoryLabel(c))),
                ],
                onChanged: (v) => setState(() => category = v ?? category),
              ),
              const SizedBox(height: 10),

              FieldLabel('البيان / المستفيد:', key: errors.key('description'), requiredField: true),
              TextField(
                controller: description,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (errors.clear('description')) setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'مثال: شراء أوراق وطباعة كشوفات...',
                  errorText: errors['description'],
                ),
              ),
            ],
            const SizedBox(height: 10),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FieldLabel('المبلغ ($currency):', key: errors.key('amount'), requiredField: true),
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontFamily: 'monospace'),
                        onChanged: (_) {
                          if (errors.clear('amount')) setState(() {});
                        },
                        decoration: InputDecoration(hintText: '0.00', errorText: errors['amount']),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('التاريخ:'),
                      InkWell(
                        onTap: _pickDate,
                        child: Container(
                          height: 42,
                          alignment: AlignmentDirectional.centerStart,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Corner.box),
                            color: AppColors.bg,
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event, size: 15, color: AppColors.muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  date,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            const FieldLabel('طريقة الدفع:'),
            AppDropdown<String>(
              value: methods.any((m) => m.id == method) ? method : null,
              items: [
                for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => setState(() => method = v ?? method),
            ),
            const SizedBox(height: 10),

            const FieldLabel('ملاحظات (اختياري):'),
            TextField(
              controller: notes,
              decoration: const InputDecoration(hintText: 'أي تفاصيل أو ملاحظات إضافية...'),
            ),
            if (method != 'cash') ...[
              const SizedBox(height: 10),
              const FieldLabel('إشعار التحويل'),
              NoticeBox(
                image: notice,
                onPick: _pickNotice,
                onClear: () => setState(() => notice = ''),
              ),
            ],

            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context, false))),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: submitting
                        ? 'جاري الحفظ...'
                        : isPayout
                            ? 'تسجيل صرف الأجر'
                            : 'حفظ سند الصرف',
                    color: AppColors.navy,
                    busy: submitting,
                    onPressed: submitting ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// تبويبا نوع السند: مصروف عام أو أجر معلم.
class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.active, required this.onSelect});

  final String active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _tab('expense', 'مصروف عام', AppColors.heading),
          _tab('payout', 'صرف أجر معلم', AppColors.amberDark),
        ],
      ),
    );
  }

  Widget _tab(String id, String label, Color activeColor) {
    final selected = active == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(id),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(Corner.input),
            border: selected ? Border.all(color: AppColors.line) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? activeColor : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
