import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/balance.dart';
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

  /// البند: `inst:<معرّف>` لقسط مفتوح، أو `general` أو `monthly_fee` أو
  /// `seat_reservation` أو `other`. كان حقلين — «غرض الدفع» و«القسط المجدول» —
  /// يتناقضان: غرضٌ شهري مع قسطٍ مربوط، ولا يدري المستخدم أيهما يحكم السند.
  String item = '';
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

  /// صورة إشعار التحويل بصيغة `data:` — تُرفع إلى حاوية الإشعارات بعد الحفظ.
  String notice = '';
  bool busy = false;
  final errors = FieldErrors();

  static const _gap = SizedBox(height: 12);

  /// أقصى عدد من الطلاب يُعرض قبل أن يُطلب تضييق البحث.
  static const _pickerLimit = 8;

  @override
  void initState() {
    super.initState();
    studentId = widget.studentId;
    item = widget.installmentId == null ? '' : 'inst:${widget.installmentId}';
    amount = TextEditingController(text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(0));
    // البند الافتراضي يحتاج أقساط الطالب، وهي في المخزن لا في الوسائط
    if (studentId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _applyDefaults(StoreScope.of(context)));
      });
    }
  }

  /// الأقساط المفتوحة مرتّبة بالأقدم استحقاقاً — ترتيب السداد نفسه.
  List<Installment> _openOf(List<Installment> insts) {
    final open = insts.where((i) => i.remaining > 0.005).toList();
    open.sort(compareInstallments);
    return open;
  }

  /// ما حلّ موعده وحده. القسط القادم ليس ديناً اليوم فلا يُطالَب به ولا يظهر في السند.
  double _dueNow(Student student, List<Installment> insts) {
    if (insts.isEmpty) return student.balance < 0 ? -student.balance : 0;
    var total = 0.0;
    for (final i in _openOf(insts)) {
      if (isInstallmentDue(i)) total += i.remaining;
    }
    return total;
  }

  /// البند الافتراضي: أقدم قسط حلّ موعده، وإلا «دفعة عامة»، وإلا الرسوم الشهرية.
  /// ولا يُقترح قسط لم يحن موعده: الدفع المقدم يختاره صاحبه.
  void _applyDefaults(AppStore store) {
    final student = studentId == null ? null : store.studentById(studentId!);
    if (student == null) return;
    final open = _openOf(store.installments.where((i) => i.studentId == student.id).toList());
    final chosen = open.where((i) => 'inst:${i.id}' == item).firstOrNull ?? open.where(isInstallmentDue).firstOrNull;
    if (chosen != null) {
      item = 'inst:${chosen.id}';
      if (amount.text.trim().isEmpty) amount.text = trimNum(chosen.remaining);
      return;
    }
    if (item.isEmpty) item = open.isNotEmpty ? 'general' : 'monthly_fee';
  }

  /// ما تغطيه الدفعة: القسط المختار أولاً ثم الأقدم استحقاقاً، كما يوزّعها
  /// الرصيد نفسه. هو بيان السند.
  String _covers(List<Installment> open, double typed) {
    final selectedId = item.startsWith('inst:') ? item.substring(5) : '';
    if (selectedId.isEmpty && item != 'general') return '';
    var credit = typed;
    final ordered = [
      ...open.where((i) => i.id == selectedId),
      ...open.where((i) => i.id != selectedId),
    ];
    final parts = <String>[];
    for (final inst in ordered) {
      if (credit <= 0.005) break;
      final due = inst.remaining;
      parts.add(credit + 0.005 < due ? '${inst.title} (جزء)' : inst.title);
      credit -= due;
    }
    if (credit > 0.005) parts.add('دفعة مقدمة');
    return parts.join('، ');
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
        ..check('customPurpose', item == 'other' && customPurpose.text.trim().isEmpty, 'اكتب بند الدفعة');
    });
    if (errors.report(context) || selected == null) return;
    setState(() => busy = true);
    final open = _openOf(store.installments.where((i) => i.studentId == selected.id).toList());
    final covered = _covers(open, n);
    try {
      final p = store.addPayment(
        studentId: selected.id,
        amount: n,
        method: method,
        date: date,
        // بيان السند هو ما غطّته الدفعة فعلاً، لا اسم البند المختار
        purpose: item == 'other'
            ? customPurpose.text.trim()
            : (covered.isNotEmpty ? covered : (item == 'general' ? 'دفعة عامة' : item)),
        notes: notes.text.trim(),
        reference: reference.text.trim(),
        senderName: sender.text.trim(),
        channel: channelCtl.text.trim().isEmpty ? (method == 'cash' ? '' : channel) : channelCtl.text.trim(),
        transferDate: transferDate == null ? '' : isoDate(transferDate!),
        customMethodNotes: customMethod.text.trim(),
        installmentId: item.startsWith('inst:') ? item.substring(5) : null,
      );
      // الإشعار يلحق بالسند: يُحفظ على الجهاز الآن ويُرفع بأول اتصال
      unawaited(store.saveFinanceAttachment(p.id, 'payment', notice.isEmpty ? null : notice));
      if (!mounted) return;
      Navigator.pop(context);
      await ReceiptScreen.open(context, p);
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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

  Future<DateTime?> _pickDay(DateTime initial) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
  }

  void _onItem(AppStore store, List<Installment> open, String? v) {
    setState(() {
      item = v ?? item;
      if (item.startsWith('inst:')) {
        final chosen = open.where((i) => i.id == item.substring(5)).firstOrNull;
        if (chosen != null) amount.text = trimNum(chosen.remaining);
      } else if (item == 'seat_reservation') {
        // الرسم من إعدادات المنشأة لا رقم مثبّت في الكود
        final seat = store.seatReservationFee;
        if (seat > 0) amount.text = trimNum(seat);
      } else if (item == 'monthly_fee') {
        final student = studentId == null ? null : store.studentById(studentId!);
        final fee = student == null ? null : store.resolveMonthlyFee(student);
        if (fee != null && fee > 0) amount.text = trimNum(fee);
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

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.can('finance')) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('تسديد دفعة')),
            body: NoAccess(section: 'finance', roleName: store.roleName),
          );
        }

        final q = search.text.trim();
        final unpaid = store.students.where((s) {
          // البحث يشمل الجميع: الدفع المقدَّم يقبضه من لا ذمة عليه
          if (q.isNotEmpty) {
            return s.fullName.contains(q) || s.phone.contains(q) || s.parentPhone.contains(q) || s.gradeLevel.contains(q);
          }
          final isUnpaid = s.balance < 0 || s.paymentStatus == 'unpaid' || s.paymentStatus == 'in_progress';
          return isUnpaid || widget.studentId == s.id;
        }).toList();
        final selected = studentId == null ? null : store.studentById(studentId!);
        final insts = selected == null ? <Installment>[] : store.installments.where((i) => i.studentId == selected.id).toList();
        final open = _openOf(insts);
        final typed = double.tryParse(amount.text.trim()) ?? 0;
        final covered = _covers(open, typed);
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
                      // سطر «يغطي» يتبع المبلغ المكتوب، فيُعاد البناء مع كل رقم
                      onChanged: (_) => setState(() => errors.clear('amount')),
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
                    const FieldLabel('البند', requiredField: true),
                    AppDropdown<String>(
                      value: item.isEmpty ? null : item,
                      hint: 'اختر البند',
                      items: [
                        if (open.isNotEmpty) ...[
                          for (final i in open)
                            DropdownMenuItem(
                              value: 'inst:${i.id}',
                              child: Text(
                                '${i.title} — ${money(i.remaining)}${isInstallmentDue(i) ? '' : ' (قادم)'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const DropdownMenuItem(value: 'general', child: Text('دفعة عامة')),
                        ] else ...[
                          const DropdownMenuItem(value: 'monthly_fee', child: Text('رسوم شهرية')),
                          if (store.seatReservationFee > 0 && selected != null && !selected.seatReservationPaid)
                            const DropdownMenuItem(value: 'seat_reservation', child: Text('حجز مقعد')),
                        ],
                        const DropdownMenuItem(value: 'other', child: Text('أخرى')),
                      ],
                      onChanged: (v) => _onItem(store, open, v),
                    ),
                    if (covered.isNotEmpty && (item == 'general' || covered.contains('،')))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'يغطي: $covered',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                      ),
                  ],
                  end: [
                    const FieldLabel('طريقة الدفع', requiredField: true),
                    AppDropdown<String>(
                      value: method,
                      // الوسائل المفعّلة وحدها، ومعها وسيلة السند المعروض إن عُطّلت لاحقاً
                      items: [
                        for (final m in store.activePaymentMethods)
                          DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
                        if (store.activePaymentMethods.every((m) => m.id != method))
                          DropdownMenuItem(
                            value: method,
                            child: Text(store.paymentMethodLabel(method), overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _onMethod,
                    ),
                  ],
                ),
                if (item == 'other') ...[
                  _gap,
                  FieldLabel('البند المخصص', key: errors.key('customPurpose'), requiredField: true),
                  TextField(
                    controller: customPurpose,
                    onChanged: (_) {
                      if (errors.clear('customPurpose')) setState(() {});
                    },
                    decoration: InputDecoration(hintText: 'اكتب البند...', errorText: errors['customPurpose']),
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
                  const FieldLabel('إشعار التحويل'),
                  NoticeBox(
                    image: notice,
                    onPick: _pickNotice,
                    onClear: () => setState(() => notice = ''),
                  ),
                  _gap,
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

  /// الطالب المختار في سطر: الاسم ومرحلته والمستحق عليه الآن، وزر تغييره.
  List<Widget> _selectedStudent(Student s, List<Installment> insts) {
    final due = _dueNow(s, insts);
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
                        text: 'المستحق: ${money(due)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: due > 0 ? AppColors.danger : AppColors.success,
                        ),
                      ),
                      if (s.balance > 0)
                        TextSpan(
                          text: '  ·  له ${money(s.balance)}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber),
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
                item = '';
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
    ];
  }

  /// البحث عن الطالب ثم نتائجه صفوفاً مسطّحة على الصفحة — لا صندوق قائمة داخل بطاقة.
  List<Widget> _studentPicker(List<Student> matches) {
    final shown = matches.take(_pickerLimit).toList();
    return [
      FieldLabel('الطالب', key: errors.key('student'), requiredField: true),
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
            'لا طلاب مطابقون',
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
