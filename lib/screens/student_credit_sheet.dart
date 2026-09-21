import 'package:flutter/material.dart';

import '../data/balance.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

const _creditReasonChips = ['دفع مكرر بالخطأ', 'انسحاب الطالب', 'تخرج وله رصيد'];

Future<Payment?> showStudentCreditSheet(
  BuildContext context,
  AppStore store,
  Student student,
) async {
  final amount = TextEditingController();
  final reason = TextEditingController();
  final credit = store.studentCredit(student.id);
  final refundable = store.studentRefundable(student.id);
  amount.text = credit > 0 ? trimNum(credit) : '';
  final methods = store.activePaymentMethods.isNotEmpty
      ? store.activePaymentMethods
      : store.paymentMethods;
  var method =
      methods.where((m) => m.isDefault).firstOrNull?.id ??
      methods.firstOrNull?.id ??
      'cash';
  var forfeit = false;
  var busy = false;

  final result = await showModalBottomSheet<Payment?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final value = double.tryParse(amount.text) ?? 0;
        final viaRequest = !store.can('finance.refund');
        final reopens = (value - credit).clamp(0, double.infinity);
        final canSubmit = reason.text.trim().isNotEmpty &&
            (forfeit || (value > 0 && value <= refundable + cent));

        Future<void> submit() async {
          if (reason.text.trim().isEmpty) {
            showAppSnack(context, 'اكتب سبب الرد أو الإسقاط', error: true);
            return;
          }
          if (!forfeit && (value <= 0 || value > refundable + cent)) {
            showAppSnack(
              context,
              'أدخل مبلغاً صحيحاً لا يتجاوز ما دفعه الطالب',
              error: true,
            );
            return;
          }
          setSheetState(() => busy = true);
          try {
            if (forfeit) {
              store.forfeitStudentCredit(student.id, reason.text);
              if (context.mounted) Navigator.pop(context);
            } else if (viaRequest) {
              store.submitFinanceRequest(
                kind: 'refund',
                summary:
                    'رد ${money(value)} لولي الأمر${reopens > cent ? ' (يعيد ${money(reopens)} مطلوباً عليه)' : ''}',
                studentId: student.id,
                payload: {'amount': value, 'payment_method': method},
                amount: value,
                reason: reason.text,
              );
              if (context.mounted) Navigator.pop(context);
            } else {
              final receipt = store.refundStudentCredit(
                student.id,
                amount: value,
                method: method,
                reason: reason.text,
              );
              if (context.mounted) Navigator.pop(context, receipt);
            }
          } on StoreException catch (e) {
            if (context.mounted) showAppSnack(context, e.message, error: true);
          } finally {
            if (context.mounted) setSheetState(() => busy = false);
          }
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              14 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'رد مبلغ لولي الأمر',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (student.status == 'active') ...[
                    const SizedBox(height: 8),
                    Text(
                      'طالب نشط يريد استرداد أقساط لم يحن وقتها؟ غيّر حالته إلى «منسحب» من ملفه أولاً.',
                      style: TextStyle(
                        color: AppColors.amberDark,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _AmountBox(
                          label: 'دفع الطالب',
                          value: refundable,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _AmountBox(
                          label: 'رصيد زائد له',
                          value: credit,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  if (!viaRequest && credit > cent) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ModeButton(
                            label: 'رد المبلغ',
                            selected: !forfeit,
                            onTap: () => setSheetState(() => forfeit = false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _ModeButton(
                            label: 'إسقاط (غير مسترد)',
                            selected: forfeit,
                            danger: true,
                            onTap: () => setSheetState(() => forfeit = true),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!forfeit) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المردود',
                      ),
                    ),
                    if (refundable > 0)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(
                          spacing: 6,
                          children: [
                            if (credit > cent && credit < refundable)
                              TextButton(
                                onPressed: () => setSheetState(
                                  () => amount.text = trimNum(credit),
                                ),
                                child: const Text('الزائد فقط'),
                              ),
                            TextButton(
                              onPressed: () => setSheetState(
                                () => amount.text = trimNum(refundable),
                              ),
                              child: const Text('كل ما دفعه'),
                            ),
                          ],
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الرد',
                      ),
                      items: [
                        for (final m in methods)
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                      ],
                      onChanged: (v) =>
                          setSheetState(() => method = v ?? method),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'يصدر «سند رد» بتاريخ اليوم ويُخصم من رصيد الطالب.',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                      ),
                    ),
                    if (reopens > cent)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'يزيد الرد على الرصيد الزائد بـ ${money(reopens)}؛ يعود هذا المبلغ مطلوباً على أقساط الطالب.',
                          style: TextStyle(
                            color: AppColors.amberDark,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                      ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'الإسقاط يلغي الرصيد الزائد دون صرف نقدي — لا سند رد.',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'السبب (إجباري)',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final r in _creditReasonChips)
                        ActionChip(
                          label: Text(r, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          onPressed: () => setSheetState(() => reason.text = r),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  if (viaRequest)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'لا تملك صلاحية الرد: سيُرسل الطلب للمدير ولا يتغير الحساب حتى يوافق.',
                        style: TextStyle(
                          color: AppColors.amberDark,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: busy
                        ? 'جارِ الحفظ...'
                        : forfeit
                        ? 'إسقاط الرصيد'
                        : viaRequest
                        ? 'إرسال للمدير'
                        : 'رد وإصدار السند',
                    color: forfeit ? AppColors.danger : AppColors.navy,
                    onPressed: busy || !canSubmit ? null : submit,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  amount.dispose();
  reason.dispose();
  return result;
}

class _AmountBox extends StatelessWidget {
  const _AmountBox({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: AppColors.bg,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(Corner.box),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
        ),
        const SizedBox(height: 3),
        Text(
          money(value),
          style: TextStyle(
            color: color ?? AppColors.heading,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: selected
          ? Colors.white
          : (danger ? AppColors.danger : AppColors.heading),
      backgroundColor: selected
          ? (danger ? AppColors.danger : AppColors.accent)
          : Colors.white,
      side: BorderSide(
        color: danger ? AppColors.dangerBorder : AppColors.lineStrong,
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
    ),
  );
}
