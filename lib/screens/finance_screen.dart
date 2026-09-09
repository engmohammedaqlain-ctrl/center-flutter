import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'payment_form_screen.dart';
import 'receipt_screen.dart';
import 'student_detail_screen.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  int tab = 0;
  final search = TextEditingController();
  String method = '';
  String status = '';
  String dueStage = 'all';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = search.text.trim();
        final pays = store.payments.where((p) {
          final stu = store.studentById(p.studentId);
          final name = stu?.fullName ?? '';
          final matchQ = q.isEmpty || p.receiptNumber.contains(q) || name.contains(q) || p.reference.contains(q);
          final matchM = method.isEmpty || p.method == method;
          final matchS = status.isEmpty || (status == 'active' && !p.cancelled) || (status == 'cancelled' && p.cancelled);
          return matchQ && matchM && matchS;
        }).toList();

        final dues = store.dueItems().where((d) {
          final matchQ = q.isEmpty || d.student.fullName.contains(q) || d.student.phone.contains(q);
          final matchS = dueStage == 'all' ||
              (dueStage == 'late' && d.late && !d.exception) ||
              (dueStage == 'due' && !d.late && !d.exception) ||
              (dueStage == 'exception' && d.exception);
          return matchQ && matchS;
        }).toList();

        final totalDue = dues.fold<double>(0, (a, d) => a + d.amount);

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
              child: Row(
                children: [
                  Expanded(child: _tab('المقبوضات', Icons.receipt_long, 0, '${store.payments.length}', false)),
                  Expanded(child: _tab('المستحقات', Icons.schedule, 1, '${store.dueItems().length}', store.dueItems().isNotEmpty)),
                  PrimaryButton(
                    label: 'دفعة',
                    icon: Icons.add,
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentFormScreen()));
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SearchField(
                controller: search,
                hint: tab == 0 ? 'ابحث برقم الوصل، الطالب، المرجع...' : 'ابحث باسم الطالب أو رقم الهاتف...',
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (tab == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: AppDropdown<String>(
                        value: method,
                        items: [
                          const DropdownMenuItem(value: '', child: Text('كل طرق الدفع')),
                          ...paymentMethodNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: (v) => setState(() => method = v ?? ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdown<String>(
                        value: status,
                        items: const [
                          DropdownMenuItem(value: '', child: Text('كل الحالات')),
                          DropdownMenuItem(value: 'active', child: Text('مقبوضة')),
                          DropdownMenuItem(value: 'cancelled', child: Text('ملغاة')),
                        ],
                        onChanged: (v) => setState(() => status = v ?? ''),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('إجمالي المبالغ المستحقة: ${money(totalDue)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    SizedBox(
                      width: 130,
                      child: AppDropdown<String>(
                        value: dueStage,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('كل الحالات')),
                          DropdownMenuItem(value: 'due', child: Text('مستحق')),
                          DropdownMenuItem(value: 'late', child: Text('متأخر عن السداد')),
                          DropdownMenuItem(value: 'exception', child: Text('استثناء')),
                        ],
                        onChanged: (v) => setState(() => dueStage = v ?? 'all'),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: tab == 0
                  ? (pays.isEmpty
                      ? const Padding(padding: EdgeInsets.all(12), child: EmptyState(message: 'لا توجد دفعات مسجلة مطابقة للبحث'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: pays.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PayCard(payment: pays[i], student: store.studentById(pays[i].studentId)),
                          ),
                        ))
                  : (dues.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: EmptyState(message: 'لا توجد دفعات أو أقساط مستحقة مطابقة للبحث. الحسابات منتظمة ومسددة.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: dues.length,
                          itemBuilder: (_, i) {
                            final d = dues[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppCard(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: d.student.id)),
                                              );
                                            },
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(d.student.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                                                Text(d.student.gradeLevel, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                                              ],
                                            ),
                                          ),
                                        ),
                                        d.exception
                                            ? StatusChip.success('استثناء')
                                            : (d.late ? StatusChip.danger(d.stageLabel) : StatusChip.amber(d.stageLabel)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(d.title, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                                              Text('استحقاق: ${formatDate(d.dueDate)}', style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(money(d.amount), style: const TextStyle(color: Color(0xFFBA1A1A), fontWeight: FontWeight.w800, fontSize: 14)),
                                            const SizedBox(height: 4),
                                            PrimaryButton(
                                              label: 'تسديد',
                                              height: 28,
                                              onPressed: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => PaymentFormScreen(
                                                      studentId: d.student.id,
                                                      installmentId: d.installmentId,
                                                      amount: d.amount,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
            ),
          ],
        );
      },
    );
  }

  Widget _tab(String label, IconData icon, int i, String count, bool danger) {
    final on = tab == i;
    return InkWell(
      onTap: () => setState(() => tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? AppColors.amber : Colors.transparent, width: 2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: on ? AppColors.heading : AppColors.muted),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? AppColors.heading : AppColors.muted)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              color: danger ? AppColors.dangerSoft : const Color(0xFFF3F4F6),
              child: Text(count, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: danger ? AppColors.danger : AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayCard extends StatelessWidget {
  const _PayCard({required this.payment, required this.student});
  final Payment payment;
  final Student? student;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => ReceiptScreen.open(context, payment),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, size: 14, color: AppColors.amber),
              const SizedBox(width: 6),
              Text(payment.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
              const Spacer(),
              Text(formatDate(payment.date), style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(width: 6),
              payment.cancelled ? StatusChip.danger('ملغى') : StatusChip.success('معتمد'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student?.fullName ?? 'سند عام', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    StatusChip.muted(paymentMethodNames[payment.method] ?? payment.method),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(payment.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: payment.cancelled ? AppColors.faint : AppColors.success,
                      decoration: payment.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const Text('عرض الوصل', style: TextStyle(color: AppColors.amber, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
