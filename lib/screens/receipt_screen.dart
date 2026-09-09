import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

class ReceiptScreen {
  static Future<void> open(BuildContext context, Payment payment) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: AppColors.navy, width: 1.4)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: AppColors.amberSoft, border: Border.all(color: AppColors.amber)),
                      child: const Icon(Icons.school, color: AppColors.amber, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(store.institutionName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
                          const Text('سند قبض رسمي', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(payment.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber, fontSize: 12.5)),
                        Text(formatDate(payment.date), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppColors.line),
                const SizedBox(height: 8),
                _row('استلمنا من', student?.fullName ?? '—'),
                _row('المرحلة', student?.gradeLevel ?? '—'),
                _row('المبلغ', money(payment.amount)),
                _row('الطريقة', paymentMethodNames[payment.method] ?? payment.method),
                _row('الغرض', paymentPurposeNames[payment.purpose] ?? payment.purpose),
                if (payment.reference.isNotEmpty) _row('المرجع', payment.reference),
                if (payment.senderName.isNotEmpty) _row('المحول', payment.senderName),
                if (payment.notes.isNotEmpty) _row('البيان', payment.notes),
                _row('المتبقي بذمة الطالب', payment.remainingAfter <= 0 ? '0 ₪ (مسدد بالكامل)' : money(payment.remainingAfter)),
                if (payment.cancelled)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: StatusChip(label: 'هذا السند ملغى', fg: Color(0xFF991B1B), bg: AppColors.dangerSoft, border: AppColors.dangerBorder),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context))),
              if (!payment.cancelled) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: 'إلغاء السند',
                    color: AppColors.danger,
                    onPressed: () async {
                      final ok = await confirmSheet(
                        context,
                        title: 'تأكيد إلغاء الدفعة',
                        message: 'هل أنت متأكد من إلغاء الدفعة رقم ${payment.receiptNumber} بمبلغ ${money(payment.amount)}؟',
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
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading))),
        ],
      ),
    );
  }
}
