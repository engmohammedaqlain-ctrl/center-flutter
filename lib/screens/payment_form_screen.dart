import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'receipt_screen.dart';

class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({super.key, this.studentId, this.installmentId, this.amount});

  final String? studentId;
  final String? installmentId;
  final double? amount;

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  late String? studentId;
  late final TextEditingController amount;
  String method = 'cash';
  late String purpose;
  DateTime date = DateTime.now();
  final notes = TextEditingController();
  final reference = TextEditingController();
  final sender = TextEditingController();
  final search = TextEditingController();
  final customMethod = TextEditingController();
  final customPurpose = TextEditingController();
  final channelCtl = TextEditingController();
  String channel = '';
  DateTime? transferDate;
  String? installmentId;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    studentId = widget.studentId;
    installmentId = widget.installmentId;
    purpose = widget.installmentId != null ? 'installment' : 'monthly_fee';
    amount = TextEditingController(text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(0));
  }

  @override
  void dispose() {
    amount.dispose();
    notes.dispose();
    reference.dispose();
    sender.dispose();
    search.dispose();
    customMethod.dispose();
    customPurpose.dispose();
    channelCtl.dispose();
    super.dispose();
  }

  Future<void> _save(AppStore store, Student selected) async {
    final n = double.tryParse(amount.text.trim()) ?? 0;
    setState(() => busy = true);
    try {
      final p = store.addPayment(
        studentId: selected.id,
        amount: n,
        method: method,
        date: date,
        purpose: purpose == 'other' && customPurpose.text.trim().isNotEmpty ? customPurpose.text.trim() : purpose,
        notes: notes.text.trim(),
        reference: reference.text.trim(),
        senderName: sender.text.trim(),
        channel: channelCtl.text.trim().isEmpty ? (method == 'cash' ? '' : channel) : channelCtl.text.trim(),
        transferDate: transferDate == null ? '' : isoDate(transferDate!),
        customMethodNotes: customMethod.text.trim(),
        installmentId: installmentId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      await ReceiptScreen.open(context, p);
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final q = search.text.trim();
        final unpaid = store.students.where((s) {
          final isUnpaid = s.balance < 0 || s.paymentStatus == 'unpaid' || s.paymentStatus == 'in_progress';
          if (!isUnpaid && widget.studentId != s.id) return false;
          if (q.isEmpty) return true;
          return s.fullName.contains(q) || s.phone.contains(q) || s.parentPhone.contains(q) || s.gradeLevel.contains(q);
        }).toList();
        final selected = studentId == null ? null : store.studentById(studentId!);
        final insts = selected == null ? <Installment>[] : store.installments.where((i) => i.studentId == selected.id).toList();
        final electronic = method != 'cash';

        final scope = StoreScope.of(context);
        if (!scope.can('finance.collect')) {
          return Scaffold(
            appBar: AppBar(title: const Text('تسديد دفعة')),
            body: NoAccess(section: 'finance', roleName: scope.roleName),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            title: Text(selected == null ? 'تسديد دفعة جديدة' : 'تسديد دفعة للطالب: ${selected.fullName}'),
            // شريط الهوية الغامق كبقية الشاشات
            titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              AppCard(
                color: selected == null ? Colors.white : AppColors.amberSoft,
                child: selected != null
                    ? Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('الطالب المحدد', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                Text(selected.fullName, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                                Text(
                                  selected.balance < 0 ? '${money(selected.balance)} مطلوبة' : '${money(selected.balance)} رصيد دائن',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: selected.balance < 0 ? AppColors.danger : AppColors.amber),
                                ),
                              ],
                            ),
                          ),
                          if (widget.studentId == null)
                            GhostButton(
                              label: 'تغيير الطالب',
                              onPressed: () => setState(() {
                                studentId = null;
                                installmentId = null;
                              }),
                            ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FieldLabel('البحث عن الطالب (الطلاب غير المسددين والمطلوبين مالياً فقط) *'),
                          SearchField(controller: search, hint: 'اكتب الاسم، رقم الهاتف، أو المرحلة...', onChanged: (_) => setState(() {})),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
                            child: unpaid.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('لا يوجد طلاب غير مسددين مطابقين للبحث', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: unpaid.length,
                                    itemBuilder: (_, i) {
                                      final s = unpaid[i];
                                      return InkWell(
                                        onTap: () => setState(() => studentId = s.id),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text('${s.fullName}  (${s.gradeLevel})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                                              ),
                                              Text(money(s.balance), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
              if (insts.isNotEmpty) ...[
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FieldLabel('أقساط مجدولة مسجلة للطالب (${insts.length})'),
                      AppDropdown<String>(
                        value: installmentId ?? '',
                        items: [
                          const DropdownMenuItem(value: '', child: Text('-- دفعة رسوم عامة بدون ربط بقسط مجدول --')),
                          ...insts.map(
                            (i) => DropdownMenuItem(
                              value: i.id,
                              child: Text('${i.title} — المتبقي: ${money(i.remaining)}${i.isPaid ? ' ✓' : ''}'),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            installmentId = (v == null || v.isEmpty) ? null : v;
                            if (installmentId != null) {
                              final inst = insts.firstWhere((i) => i.id == installmentId);
                              amount.text = inst.remaining.toStringAsFixed(0);
                              purpose = 'installment';
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('المبلغ المقبوض (₪) *'),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.amber),
                      decoration: const InputDecoration(hintText: '0'),
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('سبب/غرض الدفع *'),
                    AppDropdown<String>(
                      value: purpose,
                      items: paymentPurposeNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setState(() {
                        purpose = v ?? purpose;
                        if (purpose == 'seat_reservation') {
                          amount.text = '50';
                          notes.text = 'سداد رسم حجز مقعد (تُخصم من رسوم الشهر الأول)';
                          installmentId = null;
                        } else if (purpose == 'monthly_fee') {
                          installmentId = null;
                        }
                      }),
                    ),
                    if (purpose == 'other') ...[
                      const SizedBox(height: 10),
                      const FieldLabel('الغرض المخصص'),
                      TextField(controller: customPurpose, decoration: const InputDecoration(hintText: 'اكتب سبب الدفع...')),
                    ],
                    const SizedBox(height: 10),
                    const FieldLabel('تاريخ الدفع', requiredField: true),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (picked != null) setState(() => date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(),
                        child: Text(isoDate(date), style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('طريقة الدفع *'),
                    AppDropdown<String>(
                      value: method,
                      items: paymentMethodNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setState(() {
                        method = v ?? method;
                        if (method == 'bop') {
                          channelCtl.text = 'بنك فلسطين';
                        } else if (method == 'palpay') {
                          channelCtl.text = 'محفظة بال بي';
                        } else if (method == 'jawwal_pay') {
                          channelCtl.text = 'جوال بي';
                        } else if (method == 'cash') {
                          channelCtl.text = '';
                        }
                      }),
                    ),
                    if (electronic) ...[
                      const SizedBox(height: 10),
                      const FieldLabel('جهة التحويل'),
                      TextField(controller: channelCtl, decoration: const InputDecoration(hintText: 'اسم البنك أو المحفظة')),
                      const SizedBox(height: 10),
                      const FieldLabel('تاريخ التحويل'),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: transferDate ?? date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                          );
                          if (picked != null) setState(() => transferDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(),
                          child: Text(transferDate == null ? isoDate(date) : isoDate(transferDate!), style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const FieldLabel('اسم المحول منه'),
                      TextField(controller: sender),
                      const SizedBox(height: 10),
                      const FieldLabel('الرقم المرجعي'),
                      TextField(controller: reference, decoration: const InputDecoration(hintText: 'رقم الحركة')),
                    ],
                    if (method == 'other') ...[
                      const SizedBox(height: 10),
                      const FieldLabel('تفاصيل طريقة الدفع الأخرى'),
                      TextField(controller: customMethod, decoration: const InputDecoration(hintText: 'اكتب طريقة الدفع...')),
                    ],
                    const SizedBox(height: 10),
                    const FieldLabel('البيان'),
                    TextField(controller: notes, maxLines: 2),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                expand: true,
                busy: busy,
                label: 'اعتماد الدفعة وإصدار الوصل',
                icon: Icons.check,
                onPressed: selected == null ? null : () => _save(store, selected),
              ),
            ],
          ),
        );
      },
    );
  }
}
