import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

const generalIncomeCategories = [
  'تبرعات',
  'منح',
  'إيجار',
  'بيع',
  'أنشطة',
  'أخرى',
];

/// قبض من غير طالب — سند عادي لا يمسّ رصيد أي طالب.
Future<bool> showGeneralIncomeSheet(
  BuildContext context,
  AppStore store, {
  GeneralIncome? income,
}) async {
  final title = TextEditingController(text: income?.title ?? '');
  final category = TextEditingController(
    text: income?.category ?? generalIncomeCategories.first,
  );
  final amount = TextEditingController(
    text: income == null ? '' : trimNum(income.amount),
  );
  final note = TextEditingController(text: income?.note ?? '');
  var date = income?.date ?? DateTime.now();
  var method =
      income?.method ?? store.activePaymentMethods.firstOrNull?.id ?? 'cash';

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          12 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  income == null ? 'قبض من غير طالب' : 'تعديل الإيراد',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                FieldPair(
                  start: [
                    const FieldLabel('الجهة / الشخص *'),
                    TextField(
                      controller: title,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'مثلاً: جمعية الأمل',
                      ),
                    ),
                  ],
                  end: [
                    const FieldLabel('نوع الإيراد *'),
                    TextField(
                      controller: category,
                      decoration: const InputDecoration(
                        hintText: 'تبرعات، منحة، إيجار...',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FieldPair(
                  start: [
                    const FieldLabel('المبلغ (₪) *'),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(hintText: '0'),
                    ),
                  ],
                  end: [
                    const FieldLabel('التاريخ *'),
                    SelectField(
                      text: isoDate(date),
                      icon: Icons.calendar_today_outlined,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (picked != null) setSt(() => date = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const FieldLabel('طريقة القبض'),
                AppDropdown<String>(
                  value: method,
                  items: [
                    for (final m in store.activePaymentMethods)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) => setSt(() => method = v ?? method),
                ),
                const SizedBox(height: 10),
                const FieldLabel('البيان'),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'مثلاً: تبرع لصيانة الصفوف',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'يُصدر سند قبض ولا يمسّ حساب أي طالب.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'إلغاء',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: 'حفظ وإصدار الوصل',
                        color: AppColors.navy,
                        onPressed: () {
                          try {
                            final value =
                                double.tryParse(amount.text.trim()) ?? 0;
                            if (income == null) {
                              store.addGeneralIncome(
                                title: title.text,
                                category: category.text,
                                amount: value,
                                date: date,
                                note: note.text,
                                method: method,
                              );
                            } else {
                              income
                                ..title = title.text
                                ..category = category.text
                                ..amount = value
                                ..date = date
                                ..note = note.text
                                ..method = method;
                              store.updateGeneralIncome(income);
                            }
                            Navigator.pop(ctx, true);
                          } on StoreException catch (e) {
                            showAppSnack(ctx, e.message, error: true);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  title.dispose();
  category.dispose();
  amount.dispose();
  note.dispose();
  return saved ?? false;
}
