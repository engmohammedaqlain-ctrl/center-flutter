import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/payment_methods.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

/// أنواع الإيراد المقترحة — مطابق لـ `GeneralIncomeForm.tsx`.
const generalIncomeCategories = [
  'تبرع',
  'منحة',
  'إيجار',
  'بيع',
  'نشاطات',
  'أخرى',
];

/// قبض من غير طالب — سند عادي لا يمسّ رصيد أي طالب.
Future<bool> showGeneralIncomeSheet(
  BuildContext context,
  AppStore store, {
  GeneralIncome? income,
}) async {
  final title = TextEditingController(text: income?.title ?? '');
  final amount = TextEditingController(
    text: income == null ? '' : trimNum(income.amount),
  );
  final note = TextEditingController(text: income?.note ?? '');
  final reference = TextEditingController();
  final sender = TextEditingController();
  final channelCtl = TextEditingController();
  var category = income?.category.trim().isNotEmpty == true
      ? income!.category.trim()
      : generalIncomeCategories.first;
  var date = income?.date ?? DateTime.now();
  var method = income?.method ??
      store.activePaymentMethods
          .where((m) => m.isDefault)
          .map((m) => m.id)
          .firstOrNull ??
      store.activePaymentMethods.firstOrNull?.id ??
      'cash';
  var notice = '';

  PaymentMethodItem? methodOf(String id) =>
      store.paymentMethods.where((m) => m.id == id).firstOrNull;

  bool needsTransfer(String id) {
    final type = methodOf(id)?.type ?? 'other';
    return type == 'bank' || type == 'wallet' || type == 'other';
  }

  void syncChannel(String id) {
    final m = methodOf(id);
    if (m == null) {
      channelCtl.text = store.paymentMethodLabel(id);
      return;
    }
    // النوع other يُدخل يدوياً؛ البنكي والمحفظة = اسم الوسيلة تلقائياً
    channelCtl.text = m.type == 'other' ? '' : m.name;
  }

  syncChannel(method);

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        final used = <String>{
          ...generalIncomeCategories,
          for (final row in store.generalIncomes)
            if (row.category.trim().isNotEmpty) row.category.trim(),
        }.toList();

        Future<void> pickNotice() async {
          try {
            final file = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 50,
              maxWidth: 900,
              maxHeight: 900,
            );
            if (file == null) return;
            final bytes = await file.readAsBytes();
            if (bytes.length > 2 * 1024 * 1024) {
              if (ctx.mounted) {
                showAppSnack(ctx, 'الصورة أكبر من 2 ميجابايت', error: true);
              }
              return;
            }
            setSt(
              () => notice =
                  'data:${file.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}',
            );
          } catch (_) {
            if (ctx.mounted) {
              showAppSnack(ctx, 'تعذّر اختيار الصورة', error: true);
            }
          }
        }

        return Padding(
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
                  const FieldLabel('الجهة / الشخص *'),
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'مثلاً: جمعية الأمل',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('نوع الإيراد *'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in used)
                        ChoiceChip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          selected: category == c,
                          onSelected: (_) => setSt(() => category = c),
                          selectedColor: AppColors.amberSoft,
                          side: BorderSide(
                            color: category == c
                                ? AppColors.amber
                                : AppColors.lineStrong,
                          ),
                          visualDensity: VisualDensity.compact,
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
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
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
                        DropdownMenuItem(
                          value: m.id,
                          child: Text(store.paymentMethodLabel(m.id)),
                        ),
                    ],
                    onChanged: (v) => setSt(() {
                      method = v ?? method;
                      syncChannel(method);
                    }),
                  ),
                  if (needsTransfer(method)) ...[
                    const SizedBox(height: 10),
                    const FieldLabel('إشعار التحويل'),
                    NoticeBox(
                      image: notice,
                      onPick: pickNotice,
                      onClear: () => setSt(() => notice = ''),
                    ),
                    const SizedBox(height: 10),
                    FieldPair(
                      start: [
                        const FieldLabel('جهة التحويل'),
                        TextField(
                          controller: channelCtl,
                          decoration: InputDecoration(
                            hintText: methodOf(method)?.type == 'other'
                                ? 'اكتب الجهة'
                                : store.paymentMethodLabel(method),
                          ),
                        ),
                      ],
                      end: [
                        const FieldLabel('اسم المحول منه'),
                        TextField(
                          controller: sender,
                          decoration: const InputDecoration(
                            hintText: 'كما في الحوالة',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('الرقم المرجعي'),
                    TextField(
                      controller: reference,
                      decoration: const InputDecoration(
                        hintText: 'رقم الحركة',
                      ),
                    ),
                  ],
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
                              final transfer = needsTransfer(method);
                              final ch = transfer
                                  ? (channelCtl.text.trim().isEmpty
                                      ? (methodOf(method)?.type == 'other'
                                          ? ''
                                          : store.paymentMethodLabel(method))
                                      : channelCtl.text.trim())
                                  : '';
                              if (income == null) {
                                final created = store.addGeneralIncome(
                                  title: title.text,
                                  category: category,
                                  amount: value,
                                  date: date,
                                  note: note.text,
                                  method: method,
                                  reference: transfer ? reference.text : '',
                                  senderName: transfer ? sender.text : '',
                                  channel: ch,
                                );
                                if (notice.isNotEmpty) {
                                  unawaited(
                                    store.saveFinanceAttachment(
                                      created.id,
                                      'payment',
                                      notice,
                                    ),
                                  );
                                }
                              } else {
                                income
                                  ..title = title.text
                                  ..category = category
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
        );
      },
    ),
  );

  title.dispose();
  amount.dispose();
  note.dispose();
  reference.dispose();
  sender.dispose();
  channelCtl.dispose();
  return saved ?? false;
}
