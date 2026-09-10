import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'expense_form_sheet.dart';
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
        if (!store.canOpenSection('finance')) {
          return NoAccess(section: 'finance', roleName: store.roleName);
        }
        final q = search.text.trim().toLowerCase();
        final pays = store.payments.where((p) {
          final stu = store.studentById(p.studentId);
          final name = (stu?.fullName ?? '').toLowerCase();
          // البحث يشمل البيان والمحوِّل وجهة التحويل، كما في Finance.tsx
          final matchQ = q.isEmpty ||
              p.receiptNumber.toLowerCase().contains(q) ||
              name.contains(q) ||
              p.reference.toLowerCase().contains(q) ||
              p.notes.toLowerCase().contains(q) ||
              p.senderName.toLowerCase().contains(q) ||
              p.channel.toLowerCase().contains(q);
          final matchM = method.isEmpty || p.method == method;
          final matchS = status.isEmpty || (status == 'active' && !p.cancelled) || (status == 'cancelled' && p.cancelled);
          return matchQ && matchM && matchS;
        }).toList();
        sortPayments(pays);

        final allDues = store.dueItems();
        final dues = allDues.where((d) {
          final matchQ = q.isEmpty ||
              d.student.fullName.toLowerCase().contains(q) ||
              d.student.phone.contains(q) ||
              d.title.toLowerCase().contains(q);
          final matchS = dueStage == 'all' ||
              (dueStage == 'late' && d.late && !d.exception) ||
              (dueStage == 'due' && !d.late && !d.exception) ||
              (dueStage == 'exception' && d.exception);
          return matchQ && matchS;
        }).toList();

        // الميزة معطّلة أو بلا صلاحية: التبويب يختفي، ومن كان واقفاً عليه يعود
        // للمقبوضات بدل شاشة فارغة — مطابق لحساب `activeTab` في Finance.tsx
        final showExpenses = store.features.enableExpenses && store.can('finance.expenses');
        if (tab == 2 && !showExpenses) tab = 0;

        final totalDue = dues.fold<double>(0, (a, d) => a + d.amount);
        final lateCount = allDues.where((d) => d.late && !d.exception).length;
        final dueCount = allDues.where((d) => !d.late && !d.exception).length;
        final exceptionCount = allDues.where((d) => d.exception).length;

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
              child: Row(
                children: [
                  Expanded(child: _tab('المقبوضات', Icons.receipt_long, 0, '${store.payments.length}', false)),
                  Expanded(child: _tab('المستحقات', Icons.schedule, 1, '${allDues.length}', allDues.isNotEmpty)),
                  if (showExpenses)
                    Expanded(
                      child: _tab(
                        'المصروفات',
                        Icons.payments_outlined,
                        2,
                        '${store.expenses.length + store.teacherPayouts.length}',
                        false,
                      ),
                    ),
                  if (tab != 2 && store.can('finance.collect'))
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
            if (tab != 2)
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
            else if (tab == 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('إجمالي المستحق: ${money(totalDue)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12)),
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
            if (tab == 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    _stat('متأخر', lateCount, AppColors.danger),
                    const SizedBox(width: 6),
                    _stat('مستحق', dueCount, AppColors.amber),
                    const SizedBox(width: 6),
                    _stat('استثناء', exceptionCount, AppColors.success),
                  ],
                ),
              ),
            if (tab == 2) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: _expensesSummary(context, store),
              ),
              Expanded(child: _expensesList(store)),
            ] else
            Expanded(
              child: tab == 0
                  ? (pays.isEmpty
                      ? const Padding(padding: EdgeInsets.all(12), child: EmptyState(message: 'لا توجد دفعات مسجلة مطابقة للبحث'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: pays.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PayCard(
                              payment: pays[i],
                              student: store.studentById(pays[i].studentId),
                              onCancel: !pays[i].cancelled && store.can('finance.cancel')
                                  ? () => _cancel(context, store, pays[i])
                                  : null,
                            ),
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
                                                Text(d.student.fullName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
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
                                              onPressed: !store.can('finance.collect') ? null : () {
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

  /// ملخص المصروفات وزر «إضافة سند صرف» — المقابل لرأس تبويب expenses.
  Widget _expensesSummary(BuildContext context, AppStore store) {
    final expenses = store.expenses;
    final payouts = store.teacherPayouts;
    final total = store.totalExpenses + store.totalPayouts;

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'إجمالي المصروفات والأجور:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                child: Text(
                  money(total),
                  style: const TextStyle(
                    color: Color(0xFFBA1A1A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatusChip.muted(
                  'تشغيلية: ${money(store.totalExpenses)} (${expenses.length})',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: StatusChip.amber(
                  'أجور معلمين: ${money(store.totalPayouts)} (${payouts.length})',
                ),
              ),
            ],
          ),
          if (store.can('finance.expenses')) ...[
            const SizedBox(height: 10),
            PrimaryButton(
              expand: true,
              label: 'إضافة سند صرف',
              icon: Icons.add,
              color: AppColors.navy,
              onPressed: () async {
                final saved = await showExpenseSheet(context, store);
                if (saved && context.mounted) showAppSnack(context, 'تم حفظ سند الصرف');
              },
            ),
          ],
        ],
      ),
    );
  }

  /// سجل موحّد للمصروفات وأجور المعلمين مرتّب بالتاريخ تنازلياً —
  /// نفس دمج القائمتين في جدول واحد في Finance.tsx.
  Widget _expensesList(AppStore store) {
    final items = <_SpendRow>[
      for (final e in store.expenses)
        _SpendRow(
          id: e.id,
          date: e.expenseDate,
          isPayout: false,
          category: expenseCategoryLabel(e.category),
          description: e.description,
          amount: e.amount,
          method: e.method,
        ),
      for (final p in store.teacherPayouts)
        _SpendRow(
          id: p.id,
          date: p.paymentDate,
          isPayout: true,
          category: 'أجور تدريس',
          description: store.teacherById(p.teacherId) != null
              ? 'صرف مستحقات المعلم: ${store.teacherById(p.teacherId)!.name}'
              : 'صرف مستحقات معلم',
          amount: p.amount,
          method: p.method,
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: EmptyState(message: 'لا توجد سندات صرف أو دفعات أجور مسجلة حتى الآن.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _SpendCard(row: items[i]),
      ),
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
        child: Column(
          children: [
            Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, AppStore store, Payment p) async {
    final ok = await confirmSheet(
      context,
      title: 'تأكيد إلغاء الدفعة',
      message: 'هل أنت متأكد من إلغاء الدفعة رقم ${p.receiptNumber} بمبلغ ${money(p.amount)}؟ '
          'سيُعكس رصيد الطالب تلقائياً.',
      confirmLabel: 'إلغاء السند',
    );
    if (!ok || !context.mounted) return;
    store.cancelPayment(p);
    showAppSnack(context, 'تم إلغاء السند وعكس الرصيد');
  }

  Widget _tab(String label, IconData icon, int i, String count, bool danger) {
    final on = tab == i;
    return InkWell(
      onTap: () => setState(() => tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? AppColors.accent : Colors.transparent, width: 2)),
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

/// صف موحّد يمثّل سند صرف أو دفعة أجر معلم في سجل واحد.
class _SpendRow {
  const _SpendRow({
    required this.id,
    required this.date,
    required this.isPayout,
    required this.category,
    required this.description,
    required this.amount,
    required this.method,
  });

  final String id;
  final String date;
  final bool isPayout;
  final String category;
  final String description;
  final double amount;
  final String method;
}

class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.row});
  final _SpendRow row;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                ),
              ),
              const SizedBox(width: 8),
              row.isPayout ? StatusChip.amber(row.category) : StatusChip.muted(row.category),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event, size: 13, color: AppColors.faint),
              const SizedBox(width: 4),
              Text(row.date, style: const TextStyle(color: AppColors.faint, fontSize: 10.5, fontFamily: 'monospace')),
              const SizedBox(width: 10),
              const Icon(Icons.account_balance_wallet_outlined, size: 13, color: AppColors.faint),
              const SizedBox(width: 4),
              Text(
                expenseMethodNames[row.method] ?? row.method,
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
              const Spacer(),
              Text(
                money(row.amount),
                style: const TextStyle(
                  color: Color(0xFFBA1A1A),
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayCard extends StatelessWidget {
  const _PayCard({required this.payment, required this.student, this.onCancel});
  final Payment payment;
  final Student? student;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => ReceiptScreen.open(context, payment),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 14, color: AppColors.amber),
              const SizedBox(width: 6),
              Text(payment.receiptNumber, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
              const Spacer(),
              Text(formatDate(payment.date), style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(width: 6),
              payment.cancelled ? StatusChip.danger('ملغى') : StatusChip.success('معتمد'),
              if (onCancel != null)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 16, color: AppColors.muted),
                  onSelected: (_) => onCancel!(),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('إلغاء السند'))],
                ),
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
                  Text('عرض الوصل', style: TextStyle(color: AppColors.amber, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
