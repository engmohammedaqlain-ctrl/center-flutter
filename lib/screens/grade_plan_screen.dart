import 'package:flutter/material.dart';

import '../data/fee_plan.dart';
import '../data/grade_plan_sync.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

/// محرر خطة أقساط المرحلة — المقابل لـ `GradePlanModal.tsx`.
///
/// توليد جدول وتعديل الأقساط ثم حفظ يفتح معاينة الأثر على الطلاب.
/// تواريخ الفصلين تُدار من «الأعوام الدراسية» لا من هنا.
class GradePlanScreen extends StatefulWidget {
  const GradePlanScreen({super.key, required this.fee});

  final GradeFee fee;

  @override
  State<GradePlanScreen> createState() => _GradePlanScreenState();
}

class _GradePlanScreenState extends State<GradePlanScreen> {
  late List<_EditablePlanItem> items = [
    for (final i in widget.fee.planItems) _EditablePlanItem.from(i),
  ];

  /// بعد أول حفظ: ممنوع إعادة التوليد حتى لا تتغيّر المعرّفات وتزدوج الأقساط.
  late bool planLocked = widget.fee.planItems.isNotEmpty;

  late final countCtl = TextEditingController(text: items.isEmpty ? '10' : '${items.length}');
  late final amountCtl = TextEditingController(text: trimNum(widget.fee.monthlyFee));
  late final everyCtl = TextEditingController(text: '1');
  bool busy = false;
  String message = '';

  String get _defaultFirstDue =>
      items.isNotEmpty && items.first.dueDate.isNotEmpty
          ? items.first.dueDate
          : isoDate(DateTime.now());

  @override
  void initState() {
    super.initState();
    // مرحلة بلا خطة تفتح بجدول مقترح جاهز: المدير يراجع ويحفظ
    if (items.isEmpty && !planLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _generate();
      });
    }
  }

  @override
  void dispose() {
    countCtl.dispose();
    amountCtl.dispose();
    everyCtl.dispose();
    for (final i in items) {
      i.dispose();
    }
    super.dispose();
  }

  List<PlanItem> _cleanItems() => [
        for (final i in items)
          if (i.title.text.trim().isNotEmpty && i.dueDate.isNotEmpty)
            PlanItem(
              id: i.id,
              title: i.title.text.trim(),
              amount: double.tryParse(i.amount.text.trim()) ?? 0,
              dueDate: i.dueDate,
            ),
      ];

  GradeFee _draftFee() {
    final f = widget.fee;
    // تواريخ الفصلين تبقى كما في السجل؛ لا تُعدَّل من شاشة الخطة (كويب).
    return GradeFee(
      id: f.id,
      gradeName: f.gradeName,
      monthlyFee: f.monthlyFee,
      tier: f.tier,
      orderIndex: f.orderIndex,
      isCustom: f.isCustom,
      term1Start: f.term1Start,
      term1End: f.term1End,
      term2Start: f.term2Start,
      term2End: f.term2End,
      planItems: _cleanItems(),
      createdAt: f.createdAt,
    );
  }

  Future<void> _pickDate(String current, ValueChanged<String> onPicked) async {
    final initial = parseIsoDate(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) onPicked(isoDate(picked));
  }

  void _generate() {
    if (planLocked) return;
    final store = StoreScope.of(context);
    final next = generatePlanItems(
      count: int.tryParse(countCtl.text.trim()) ?? 0,
      amount: double.tryParse(amountCtl.text.trim()) ?? 0,
      firstDueDate: _defaultFirstDue,
      everyMonths: int.tryParse(everyCtl.text.trim()) ?? 1,
      newId: store.newId,
    );
    setState(() {
      for (final i in items) {
        i.dispose();
      }
      items = [for (final i in next) _EditablePlanItem.from(i)];
      message = '';
    });
  }

  void _addItem() {
    final store = StoreScope.of(context);
    setState(() {
      items.add(
        _EditablePlanItem(
          id: store.newId(),
          title: 'القسط ${items.length + 1}',
          amount: double.tryParse(amountCtl.text.trim()) ?? 0,
          dueDate: _defaultFirstDue,
        ),
      );
    });
  }

  /// حفظ الخطة، ثم فتح معاينة الأثر على الطلاب دائماً — أسئلة التطبيق كما على الويب.
  Future<void> _save() async {
    final store = StoreScope.of(context);
    setState(() => busy = true);
    await yieldUi(2);
    try {
      final draft = _draftFee();
      store.updateGradeFee(draft);
      if (draft.planItems.isNotEmpty) {
        setState(() => planLocked = true);
      }
      if (!mounted) return;

      final preview = store.syncGradePlan(widget.fee.gradeName);
      final summary = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => GradePlanSyncSheet(
          gradeName: widget.fee.gradeName,
          initialPreview: preview,
        ),
      );
      if (!mounted) return;
      if (summary != null) {
        showAppSnack(context, summary);
        Navigator.pop(context);
      } else if (preview.isEmpty) {
        // أُلغيت الورقة بلا تطبيق، والخطة محفوظة بلا أثر على الطلاب
        showAppSnack(context, 'تم حفظ خطة «${widget.fee.gradeName}»');
        Navigator.pop(context);
      }
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final title = 'خطة ${widget.fee.gradeName}';
    if (!store.can('settings')) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: NoAccess(section: 'settings', roleName: store.roleName),
      );
    }

    final total = planTotal(_cleanItems());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      bottomNavigationBar: FormActionBar(
        label: 'حفظ الخطة',
        busy: busy,
        onSave: () => _save(),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (!planLocked) ...[
              const FormSection(icon: Icons.auto_awesome_outlined, title: 'توليد جدول'),
              FieldPair(
                start: [
                  const FieldLabel('عدد الأقساط'),
                  TextField(
                    controller: countCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '10'),
                  ),
                ],
                end: [
                  const FieldLabel('قيمة القسط (شيكل)'),
                  TextField(
                    controller: amountCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '0'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FieldPair(
                start: [
                  const FieldLabel('كل كم شهر'),
                  TextField(
                    controller: everyCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '1'),
                  ),
                ],
                end: [
                  const FieldLabel(' '),
                  GhostButton(
                    label: 'توليد',
                    icon: Icons.auto_awesome,
                    onPressed: busy ? null : _generate,
                  ),
                ],
              ),
            ],

            FormSection(
              icon: Icons.playlist_add_check_outlined,
              title: 'الأقساط',
              note: 'الإجمالي ${money(total)}',
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('لا أقساط', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
              )
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _PlanItemRow(
                  index: i + 1,
                  item: items[i],
                  onPickDue: () => _pickDate(items[i].dueDate, (v) => setState(() => items[i].dueDate = v)),
                  onDelete: () => setState(() {
                    items[i].dispose();
                    items.removeAt(i);
                  }),
                ),
              ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GhostButton(label: 'إضافة قسط', icon: Icons.add, onPressed: busy ? null : _addItem),
            ),

            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

/// معاينة وتنفيذ مزامنة الخطة — `GradePlanSyncModal`.
class GradePlanSyncSheet extends StatefulWidget {
  const GradePlanSyncSheet({
    super.key,
    required this.gradeName,
    this.initialPreview,
  });

  final String gradeName;
  final GradePlanSyncResult? initialPreview;

  @override
  State<GradePlanSyncSheet> createState() => _GradePlanSyncSheetState();
}

class _GradePlanSyncSheetState extends State<GradePlanSyncSheet> {
  GradePlanSyncResult? preview;
  String error = '';
  bool includePaid = false;
  bool removePaid = false;
  bool resetUnexplained = false;
  bool busy = false;
  GradePlanSyncResult? done;

  @override
  void initState() {
    super.initState();
    preview = widget.initialPreview;
    if (preview == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
  }

  void _loadPreview() {
    final store = StoreScope.of(context);
    try {
      setState(() {
        preview = store.syncGradePlan(widget.gradeName);
        error = '';
      });
    } on StoreException catch (e) {
      setState(() => error = e.message);
    }
  }

  String _signed(double n) => '${n >= 0 ? '+' : '−'}${money(n.abs())}';

  Future<void> _apply() async {
    final store = StoreScope.of(context);
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = store.syncGradePlan(
        widget.gradeName,
        apply: true,
        includePaid: includePaid,
        removePaid: removePaid,
        resetUnexplained: resetUnexplained,
      );
      if (!mounted) return;
      setState(() => done = result);
    } on StoreException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'تطبيق خطة ${widget.gradeName} على الطلاب',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.navy),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
              ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (error.isNotEmpty)
            Text(error, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12)),
          if (p == null && error.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('جارِ حساب الأثر...', style: TextStyle(color: AppColors.muted, fontSize: 12))),
            ),
          if (done != null) ...[
            const Text('تم التطبيق', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._doneLines(done!),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, 'طُبّقت خطة ${widget.gradeName}'),
                child: const Text('إغلاق'),
              ),
            ),
          ] else if (p != null) ...[
            Text('${p.considered} طالب على خطة المرحلة', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            if (p.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'كل الطلاب مطابقون للخطة — لا شيء للتطبيق',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (p.build.students > 0)
                      _SyncRow('${p.build.students} طالب بلا أقساط لهذا العام: تُبنى لهم الخطة كاملة'),
                    if (p.add.installments > 0)
                      _SyncRow('${p.add.students} طالب ناقصهم أقساط: يُضاف ${p.add.installments} قسط'),
                    if (p.reprice.installments > 0)
                      _SyncRow(
                        '${p.reprice.students} طالب أقساطهم القادمة بسعر مختلف: ${p.reprice.installments} قسط، الفرق ${_signed(p.reprice.difference)}',
                      ),
                    if (p.remove.installments > 0)
                      _SyncRow(
                        '${p.remove.installments} قسط لم يعد في الخطة يُحذف عند ${p.remove.students} طالب'
                        '${p.remove.wasDue > 0 ? ' (منها ${p.remove.wasDue} حلّ موعده)' : ''}',
                      ),
                    if (p.repricePaid.installments > 0)
                      _SyncCheck(
                        value: includePaid,
                        onChanged: (v) => setState(() => includePaid = v),
                        child:
                            'حدّث أيضاً ${p.repricePaid.installments} قسطاً دُفع منها (${p.repricePaid.students} طالب)، الفرق ${_signed(p.repricePaid.difference)}',
                      ),
                    if (p.removePaid.installments > 0)
                      _SyncCheck(
                        value: removePaid,
                        onChanged: (v) => setState(() => removePaid = v),
                        child:
                            'احذف أيضاً ${p.removePaid.installments} قسطاً محذوفاً من الخطة دُفع منها (${money(p.removePaid.amount)})',
                      ),
                    if (p.unexplained.installments > 0)
                      _SyncCheck(
                        value: resetUnexplained,
                        onChanged: (v) => setState(() => resetUnexplained = v),
                        child:
                            '${p.unexplained.students} طالب أقساطهم مختلفة عن الخطة بلا خصم مسجَّل (${p.unexplained.installments} قسط): أعِدها لسعر الخطة',
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Text(
                        'لا يُمسّ: الأقساط التي حلّ موعدها ولم يُدفع منها، المعفاة، والخصم المسجَّل على كل قسط.'
                        '${p.skipped.customPlan > 0 ? ' · ${p.skipped.customPlan} طالب على خطة مخصصة.' : ''}'
                        '${p.skipped.manualInstallments > 0 ? ' · ${p.skipped.manualInstallments} طالب له أقساط يدوية: راجع ملفه.' : ''}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!p.isEmpty) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : _apply,
                      child: Text(busy ? 'جارِ التطبيق...' : 'تطبيق'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _doneLines(GradePlanSyncResult d) {
    final lines = <String>[
      if (d.build.students > 0) 'بُنيت الخطة لـ ${d.build.students} طالب',
      if (d.add.installments > 0) 'أُضيف ${d.add.installments} قسط لـ ${d.add.students} طالب',
      if (d.reprice.installments > 0) 'حُدّث ${d.reprice.installments} قسط',
      if (includePaid && d.repricePaid.installments > 0) 'حُدّث ${d.repricePaid.installments} قسط مدفوع منه',
      if (d.remove.installments > 0) 'حُذف ${d.remove.installments} قسط لم يعد في الخطة',
      if (removePaid && d.removePaid.installments > 0) 'حُذف ${d.removePaid.installments} قسط مدفوع منه',
      if (resetUnexplained && d.unexplained.installments > 0) 'أُعيد ${d.unexplained.installments} قسط لسعر الخطة',
    ];
    return [
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('• $line', style: const TextStyle(fontSize: 12)),
        ),
    ];
  }
}

class _SyncRow extends StatelessWidget {
  const _SyncRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35)),
    );
  }
}

class _SyncCheck extends StatelessWidget {
  const _SyncCheck({required this.value, required this.onChanged, required this.child});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(child, style: const TextStyle(fontSize: 12, height: 1.35)),
      ),
    );
  }
}

class _EditablePlanItem {
  _EditablePlanItem({
    required this.id,
    required String title,
    required double amount,
    required this.dueDate,
  })  : title = TextEditingController(text: title),
        amount = TextEditingController(text: trimNum(amount));

  factory _EditablePlanItem.from(PlanItem i) => _EditablePlanItem(
        id: i.id,
        title: i.title,
        amount: i.amount,
        dueDate: i.dueDate,
      );

  final String id;
  final TextEditingController title;
  final TextEditingController amount;
  String dueDate;

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}

class _PlanItemRow extends StatelessWidget {
  const _PlanItemRow({
    required this.index,
    required this.item,
    required this.onPickDue,
    required this.onDelete,
  });

  final int index;
  final _EditablePlanItem item;
  final VoidCallback onPickDue;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('$index', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: item.title,
                  decoration: const InputDecoration(hintText: 'عنوان القسط', isDense: true),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FieldPair(
            start: [
              const FieldLabel('المبلغ'),
              TextField(
                controller: item.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0', isDense: true),
              ),
            ],
            end: [
              const FieldLabel('الاستحقاق'),
              SelectField(
                text: item.dueDate.isEmpty ? 'اختر' : item.dueDate,
                icon: Icons.calendar_today_outlined,
                placeholder: item.dueDate.isEmpty,
                onTap: onPickDue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
