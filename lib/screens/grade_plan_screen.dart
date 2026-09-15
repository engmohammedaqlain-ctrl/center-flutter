import 'package:flutter/material.dart';

import '../data/fee_plan.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

/// محرر خطة أقساط المرحلة — المقابل لـ `GradePlanModal.tsx`.
///
/// تواريخ الفصلين، توليد جدول، تعديل/إضافة/حذف أقساط، ثم حفظ أو تطبيق أو
/// تحديث أسعار الطلاب القائمين.
class GradePlanScreen extends StatefulWidget {
  const GradePlanScreen({super.key, required this.fee});

  final GradeFee fee;

  @override
  State<GradePlanScreen> createState() => _GradePlanScreenState();
}

class _GradePlanScreenState extends State<GradePlanScreen> {
  late String term1Start = widget.fee.term1Start;
  late String term1End = widget.fee.term1End;
  late String term2Start = widget.fee.term2Start;
  late String term2End = widget.fee.term2End;

  late List<_EditablePlanItem> items = [
    for (final i in widget.fee.planItems) _EditablePlanItem.from(i),
  ];

  late final countCtl = TextEditingController(text: items.isEmpty ? '10' : '${items.length}');
  late final amountCtl = TextEditingController(text: trimNum(widget.fee.monthlyFee));
  late final everyCtl = TextEditingController(text: '1');
  bool busy = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    // مرحلة بلا خطة تفتح بجدول مقترح جاهز: المدير يراجع ويحفظ
    if (items.isEmpty) {
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
    return GradeFee(
      id: f.id,
      gradeName: f.gradeName,
      monthlyFee: f.monthlyFee,
      tier: f.tier,
      orderIndex: f.orderIndex,
      isCustom: f.isCustom,
      term1Start: term1Start,
      term1End: term1End,
      term2Start: term2Start,
      term2End: term2End,
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
    final store = StoreScope.of(context);
    final next = generatePlanItems(
      count: int.tryParse(countCtl.text.trim()) ?? 0,
      amount: double.tryParse(amountCtl.text.trim()) ?? 0,
      firstDueDate: term1Start.isEmpty ? isoDate(DateTime.now()) : term1Start,
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
          dueDate: term1Start.isEmpty ? isoDate(DateTime.now()) : term1Start,
        ),
      );
    });
  }

  Future<void> _save({bool pop = true}) async {
    final store = StoreScope.of(context);
    setState(() => busy = true);
    try {
      store.updateGradeFee(_draftFee());
      if (!mounted) return;
      showAppSnack(context, 'تم حفظ خطة «${widget.fee.gradeName}»');
      if (pop) Navigator.pop(context);
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _apply() async {
    final store = StoreScope.of(context);
    final ok = await confirmSheet(
      context,
      title: 'تطبيق خطة «${widget.fee.gradeName}»',
      message: 'تُقيَّد أقساط الخطة على طلاب المرحلة النشطين ممن لا أقساط لهم بعد.',
      confirmLabel: 'تطبيق',
      confirmColor: AppColors.navy,
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      store.updateGradeFee(_draftFee());
      final result = store.applyGradePlan(widget.fee.gradeName);
      if (!mounted) return;
      setState(() {
        message = result.applied == 0
            ? 'لا طالب بلا أقساط في هذه المرحلة'
            : 'طُبّقت على ${result.applied}${result.skipped > 0 ? ' — تُركت ${result.skipped} خطة قائمة' : ''}';
      });
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reprice() async {
    final store = StoreScope.of(context);
    setState(() => busy = true);
    try {
      store.updateGradeFee(_draftFee());
      final preview = store.repriceGradePlan(widget.fee.gradeName);
      if (!mounted) return;
      if (preview.installments == 0) {
        setState(() => message = 'لا أقساط قابلة للتحديث');
        return;
      }
      final sign = preview.difference >= 0 ? '+' : '−';
      final ok = await confirmSheet(
        context,
        title: 'تحديث أسعار خطة «${widget.fee.gradeName}»',
        message:
            'تحديث ${preview.installments} قسط لـ${preview.students} طالب.\n'
            'الفرق: $sign${money(preview.difference.abs())}\n\n'
            'لا يشمل المدفوع ولا ما حان موعده.',
        confirmLabel: 'تحديث',
        confirmColor: AppColors.navy,
      );
      if (!ok || !mounted) return;
      final done = store.repriceGradePlan(widget.fee.gradeName, apply: true);
      if (!mounted) return;
      setState(() => message = 'حُدِّث ${done.installments} قسط لـ${done.students} طالب');
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
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
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
            const FormSection(icon: Icons.event_outlined, title: 'تواريخ الفصلين'),
            FieldPair(
              start: [
                const FieldLabel('الفصل الأول — من'),
                SelectField(
                  text: term1Start.isEmpty ? 'اختر التاريخ' : term1Start,
                  icon: Icons.calendar_today_outlined,
                  placeholder: term1Start.isEmpty,
                  onTap: () => _pickDate(term1Start, (v) => setState(() => term1Start = v)),
                ),
              ],
              end: [
                const FieldLabel('إلى'),
                SelectField(
                  text: term1End.isEmpty ? 'اختر التاريخ' : term1End,
                  icon: Icons.calendar_today_outlined,
                  placeholder: term1End.isEmpty,
                  onTap: () => _pickDate(term1End, (v) => setState(() => term1End = v)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldPair(
              start: [
                const FieldLabel('الفصل الثاني — من'),
                SelectField(
                  text: term2Start.isEmpty ? 'اختر التاريخ' : term2Start,
                  icon: Icons.calendar_today_outlined,
                  placeholder: term2Start.isEmpty,
                  onTap: () => _pickDate(term2Start, (v) => setState(() => term2Start = v)),
                ),
              ],
              end: [
                const FieldLabel('إلى'),
                SelectField(
                  text: term2End.isEmpty ? 'اختر التاريخ' : term2End,
                  icon: Icons.calendar_today_outlined,
                  placeholder: term2End.isEmpty,
                  onTap: () => _pickDate(term2End, (v) => setState(() => term2End = v)),
                ),
              ],
            ),

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
                const FieldLabel('قيمة القسط (₪)'),
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
                GhostButton(label: 'توليد', icon: Icons.auto_awesome, onPressed: busy ? null : _generate),
              ],
            ),

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
              Text(message, style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 12)),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'تطبيق على الطلاب',
                    icon: Icons.playlist_add_check,
                    onPressed: busy || items.isEmpty ? null : _apply,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'تحديث الأسعار',
                    icon: Icons.trending_up,
                    onPressed: busy || items.isEmpty ? null : _reprice,
                  ),
                ),
              ],
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.line),
        color: AppColors.bg,
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text('$index', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: TextField(
                  controller: item.title,
                  decoration: const InputDecoration(hintText: 'عنوان القسط'),
                ),
              ),
              IconButton(
                tooltip: 'حذف',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
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
                decoration: const InputDecoration(hintText: '0'),
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
