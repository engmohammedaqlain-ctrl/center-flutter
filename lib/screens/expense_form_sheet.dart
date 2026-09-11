import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// نافذة «تسجيل سند صرف جديد» — المقابل لـ `isExpenseModalOpen` في Finance.tsx.
///
/// تُعيد `true` إن حُفظ السند.
Future<bool> showExpenseSheet(BuildContext context, AppStore store) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ExpenseSheet(store: store),
  );
  return result == true;
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.store});
  final AppStore store;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  String category = expenseCategories.first;
  String method = 'cash';
  final description = TextEditingController();
  final amount = TextEditingController();
  late String date = isoDate(DateTime.now());

  bool submitting = false;
  String? error;

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
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

  void _save() {
    setState(() => error = null);
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (description.text.trim().isEmpty) {
      setState(() => error = 'البيان / المستفيد مطلوب');
      return;
    }
    if (value <= 0) {
      setState(() => error = 'المبلغ يجب أن يكون أكبر من صفر');
      return;
    }

    setState(() => submitting = true);
    try {
      widget.store.addExpense(
        category: category,
        description: description.text,
        amount: value,
        expenseDate: date,
        method: method,
      );
      if (mounted) Navigator.pop(context, true);
    } on StoreException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'تسجيل سند صرف جديد',
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

            const FieldLabel('البيان / المستفيد:'),
            TextField(
              controller: description,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'مثال: شراء أوراق وطباعة كشوفات...'),
            ),
            const SizedBox(height: 10),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('المبلغ ($currency):'),
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: const InputDecoration(hintText: '0.00'),
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
                              Text(date, style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
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
              value: method,
              items: [
                for (final e in expenseMethodNames.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => method = v ?? method),
            ),


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
                    label: submitting ? 'جاري الحفظ...' : 'حفظ سند الصرف',
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
