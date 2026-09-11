import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';
import 'receipt_screen.dart';

/// تسديد دفعة — المقابل لـ `PaymentForm` في النسخة المكتبية.
///
/// بتخطيط نموذج تسجيل الطالب: الحقول على الصفحة مباشرة في أقسام يفصلها عنوان
/// وخط، والقصيرة متجاورة، واعتماد الدفعة ثابت أسفل الشاشة. لا بطاقة تحبس
/// الحقول ولا صندوق قائمة داخلها.
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
  final errors = FieldErrors();

  static const _gap = SizedBox(height: 12);

  /// أقصى عدد من الطلاب يُعرض قبل أن يُطلب تضييق البحث.
  static const _pickerLimit = 8;

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

  Future<void> _save(AppStore store, Student? selected) async {
    final n = double.tryParse(amount.text.trim()) ?? 0;
    setState(() {
      errors
        ..reset()
        ..check('student', selected == null, 'يرجى اختيار الطالب أولاً')
        ..check('amount', n <= 0, 'يرجى إدخال مبلغ صحيح أكبر من صفر')
        ..check('customPurpose', purpose == 'other' && customPurpose.text.trim().isEmpty, 'يرجى كتابة غرض الدفع');
    });
    if (errors.report(context) || selected == null) return;
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

  Future<DateTime?> _pickDay(DateTime initial) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
  }

  void _onPurpose(String? v) {
    setState(() {
      purpose = v ?? purpose;
      if (purpose == 'seat_reservation') {
        amount.text = '50';
        notes.text = 'سداد رسم حجز مقعد (تُخصم من رسوم الشهر الأول)';
        installmentId = null;
      } else if (purpose == 'monthly_fee') {
        installmentId = null;
      }
    });
  }

  void _onMethod(String? v) {
    setState(() {
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
    });
  }

  void _onInstallment(List<Installment> insts, String? v) {
    setState(() {
      installmentId = (v == null || v.isEmpty) ? null : v;
      if (installmentId != null) {
        final inst = insts.firstWhere((i) => i.id == installmentId);
        amount.text = inst.remaining.toStringAsFixed(0);
        purpose = 'installment';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.can('finance.collect')) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('تسديد دفعة')),
            body: NoAccess(section: 'finance', roleName: store.roleName),
          );
        }

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

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(selected == null ? 'تسديد دفعة جديدة' : 'تسديد دفعة للطالب: ${selected.fullName}'),
            titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
          ),
          bottomNavigationBar: FormActionBar(
            label: 'اعتماد الدفعة وإصدار الوصل',
            busy: busy,
            onSave: () => _save(store, selected),
          ),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                // ── ١. الطالب ─────────────────────────────────────────────────
                const FormSection(icon: Icons.person_outline, title: 'الطالب', note: 'الحقول ذات * مطلوبة'),
                if (selected != null) ..._selectedStudent(selected, insts) else ..._studentPicker(unpaid),

                // ── ٢. بيانات الدفعة ──────────────────────────────────────────
                const FormSection(icon: Icons.payments_outlined, title: 'بيانات الدفعة'),
                FieldPair(
                  start: [
                    FieldLabel('المبلغ المقبوض (₪)', key: errors.key('amount'), requiredField: true),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.amber),
                      onChanged: (_) {
                        if (errors.clear('amount')) setState(() {});
                      },
                      decoration: InputDecoration(hintText: '0', errorText: errors['amount']),
                    ),
                  ],
                  end: [
                    const FieldLabel('تاريخ الدفع', requiredField: true),
                    SelectField(
                      text: isoDate(date),
                      icon: Icons.calendar_today_outlined,
                      onTap: () async {
                        final picked = await _pickDay(date);
                        if (picked != null) setState(() => date = picked);
                      },
                    ),
                  ],
                ),
                _gap,
                FieldPair(
                  start: [
                    const FieldLabel('غرض الدفع', requiredField: true),
                    AppDropdown<String>(
                      value: purpose,
                      items: paymentPurposeNames.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: _onPurpose,
                    ),
                  ],
                  end: [
                    const FieldLabel('طريقة الدفع', requiredField: true),
                    AppDropdown<String>(
                      value: method,
                      items: paymentMethodNames.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: _onMethod,
                    ),
                  ],
                ),
                if (purpose == 'other') ...[
                  _gap,
                  FieldLabel('الغرض المخصص', key: errors.key('customPurpose'), requiredField: true),
                  TextField(
                    controller: customPurpose,
                    onChanged: (_) {
                      if (errors.clear('customPurpose')) setState(() {});
                    },
                    decoration: InputDecoration(hintText: 'اكتب سبب الدفع...', errorText: errors['customPurpose']),
                  ),
                ],
                if (method == 'other') ...[
                  _gap,
                  const FieldLabel('تفاصيل طريقة الدفع الأخرى'),
                  TextField(controller: customMethod, decoration: const InputDecoration(hintText: 'اكتب طريقة الدفع...')),
                ],
                _gap,
                const FieldLabel('البيان'),
                TextField(
                  controller: notes,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'تفاصيل إضافية عن الدفعة...'),
                ),

                // ── ٣. تفاصيل التحويل (للدفع غير النقدي) ──────────────────────
                if (electronic) ...[
                  const FormSection(icon: Icons.account_balance_outlined, title: 'تفاصيل التحويل'),
                  FieldPair(
                    start: [
                      const FieldLabel('جهة التحويل'),
                      TextField(controller: channelCtl, decoration: const InputDecoration(hintText: 'البنك أو المحفظة')),
                    ],
                    end: [
                      const FieldLabel('تاريخ التحويل'),
                      SelectField(
                        text: isoDate(transferDate ?? date),
                        icon: Icons.calendar_today_outlined,
                        onTap: () async {
                          final picked = await _pickDay(transferDate ?? date);
                          if (picked != null) setState(() => transferDate = picked);
                        },
                      ),
                    ],
                  ),
                  _gap,
                  FieldPair(
                    start: [
                      const FieldLabel('اسم المحول منه'),
                      TextField(controller: sender, decoration: const InputDecoration(hintText: 'كما في الحوالة')),
                    ],
                    end: [
                      const FieldLabel('الرقم المرجعي'),
                      TextField(controller: reference, decoration: const InputDecoration(hintText: 'رقم الحركة')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// الطالب المختار في سطر: الاسم ومرحلته ورصيده بلونه، وزر تغييره.
  List<Widget> _selectedStudent(Student s, List<Installment> insts) {
    final owes = s.balance < 0;
    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      if (s.gradeLevel.trim().isNotEmpty) TextSpan(text: '${s.gradeLevel.trim()}  ·  '),
                      TextSpan(
                        text: owes
                            ? 'عليه ${money(s.balance)}'
                            : s.balance > 0
                                ? 'له ${money(s.balance)}'
                                : 'مسدد بالكامل',
                        style: TextStyle(fontWeight: FontWeight.w800, color: owes ? AppColors.danger : AppColors.success),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (widget.studentId == null)
            TextButton.icon(
              onPressed: () => setState(() {
                studentId = null;
                installmentId = null;
              }),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amber,
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('تغيير الطالب'),
            ),
        ],
      ),
      if (insts.isNotEmpty) ...[
        _gap,
        FieldLabel('القسط المجدول (${insts.length})'),
        AppDropdown<String>(
          value: installmentId ?? '',
          items: [
            const DropdownMenuItem(value: '', child: Text('دفعة رسوم عامة بدون ربط بقسط', overflow: TextOverflow.ellipsis)),
            ...insts.map(
              (i) => DropdownMenuItem(
                value: i.id,
                child: Text(
                  '${i.title} — المتبقي: ${money(i.remaining)}${i.isPaid ? ' ✓' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (v) => _onInstallment(insts, v),
        ),
      ],
    ];
  }

  /// البحث عن الطالب ثم نتائجه صفوفاً مسطّحة على الصفحة — لا صندوق قائمة داخل بطاقة.
  List<Widget> _studentPicker(List<Student> matches) {
    final shown = matches.take(_pickerLimit).toList();
    return [
      FieldLabel('ابحث عن الطالب (غير المسددين والمطلوبين مالياً)', key: errors.key('student'), requiredField: true),
      SearchField(
        controller: search,
        hint: 'الاسم، رقم الهاتف، أو المرحلة...',
        onChanged: (_) => setState(() {}),
      ),
      FormErrorText(errors['student']),
      const SizedBox(height: 4),
      if (matches.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'لا يوجد طلاب غير مسددين مطابقين للبحث',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        )
      else ...[
        for (final s in shown) _studentRow(s),
        if (matches.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'يظهر ${shown.length} من ${matches.length} — اكتب للبحث عن غيرهم',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.faint, fontSize: 11),
            ),
          ),
      ],
    ];
  }

  Widget _studentRow(Student s) {
    return InkWell(
      onTap: () => setState(() {
        studentId = s.id;
        search.clear();
        errors.clear('student');
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text),
                  ),
                  if (s.gradeLevel.trim().isNotEmpty)
                    Text(s.gradeLevel.trim(), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(money(s.balance), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12.5)),
            const SizedBox(width: 2),
            // «التالي» ينعكس مع الاتجاه فيُرسم «<»
            const Icon(Icons.chevron_right, size: 18, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}
