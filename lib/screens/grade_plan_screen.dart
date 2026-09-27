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
/// نظامان: أقساط بتواريخ ثابتة للمرحلة (توليد جدول وتعديله ثم حفظ، وإن وُجد أثر على
/// الطلاب تُفتح معاينته)، أو رسوم شهرية من تاريخ تسجيل كل طالب داخل فصول المرحلة.
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
  late final bool hadPlan = widget.fee.planItems.isNotEmpty;

  late final countCtl = TextEditingController(text: items.isEmpty ? '10' : '${items.length}');
  late final amountCtl = TextEditingController(text: trimNum(widget.fee.monthlyFee));
  late final everyCtl = TextEditingController(text: '1');

  /// نظام الرسوم، والنظام عند الفتح: تغييره يستبدل خطة الطلاب كلها.
  late String mode = widget.fee.feeMode;
  late final String originalMode = widget.fee.feeMode;
  bool get modeSwitch => mode != originalMode;
  late final monthlyCtl = TextEditingController(text: widget.fee.monthlyFee > 0 ? trimNum(widget.fee.monthlyFee) : '');

  /// تواريخ فصول خاصة بالمرحلة (التمهيدي قد ينتهي فصله قبل العاشر)؛ الفارغ من العام.
  late final gradeTerms = <String, String>{
    'term_1_start': widget.fee.term1Start,
    'term_1_end': widget.fee.term1End,
    'term_2_start': widget.fee.term2Start,
    'term_2_end': widget.fee.term2End,
  };
  late bool customTerms = gradeTerms.values.any((v) => v.isNotEmpty);

  bool busy = false;
  String message = '';

  /// سنة غير عام التشغيل = للعرض فقط — كويب.
  bool readOnly = false;

  /// بنود مقفلة (حلّ موعدها أو دُفع منها) — `null` حتى تُحسب.
  Set<String>? lockedIds;

  String get _defaultFirstDue =>
      items.isNotEmpty && items.first.dueDate.isNotEmpty
          ? items.first.dueDate
          : isoDate(DateTime.now());

  bool _isRowLocked(String id) => readOnly || (lockedIds?.contains(id) ?? false);

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocks());
  }

  void _loadLocks() {
    final store = StoreScope.of(context);
    final opId = store.operationalAcademicYear?.id ?? '';
    final yearId = widget.fee.academicYearId;
    final pastYear = yearId.isNotEmpty && opId.isNotEmpty && yearId != opId;
    final ids = lockedPlanItemIds(store, [
      for (final i in items)
        PlanItem(
          id: i.id,
          title: i.title.text,
          amount: double.tryParse(i.amount.text.trim()) ?? 0,
          dueDate: i.dueDate,
        ),
    ]);
    if (!mounted) return;
    setState(() {
      readOnly = pastYear;
      lockedIds = ids;
    });
  }

  @override
  void dispose() {
    countCtl.dispose();
    amountCtl.dispose();
    everyCtl.dispose();
    monthlyCtl.dispose();
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
      feeMode: 'installments',
      academicYearId: f.academicYearId,
      syncStatus: f.syncStatus,
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
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
    if (planLocked || readOnly) return;
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
    if (readOnly) return;
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

  /// المرحلة بتواريخ فصولها الخاصة، أو بتواريخ العام حين لا تواريخ خاصة.
  GradeFee _termsFee() => GradeFee(
        id: widget.fee.id,
        gradeName: widget.fee.gradeName,
        monthlyFee: 0,
        term1Start: customTerms ? gradeTerms['term_1_start']! : '',
        term1End: customTerms ? gradeTerms['term_1_end']! : '',
        term2Start: customTerms ? gradeTerms['term_2_start']! : '',
        term2End: customTerms ? gradeTerms['term_2_end']! : '',
      );

  /// تغيير النظام أو الرسوم الشهرية: تأكيد بسيط ثم حفظ وتطبيق معاً. لا يُكتب شيء
  /// قبل التأكيد، وعند تغيير النظام تُحذف أقساط الخطة القديمة ولو دُفع منها،
  /// والمدفوع يُحسب على الجديدة — `confirmAndApply`.
  Future<void> _confirmAndApply(String message, GradeFee draft) async {
    final ok = await confirmSheet(
      context,
      title: 'حفظ الخطة',
      message: message,
      confirmLabel: 'حفظ',
      confirmColor: AppColors.heading,
    );
    if (!ok || !mounted) return;
    final store = StoreScope.of(context);
    setState(() => busy = true);
    await yieldUi(2);
    try {
      store.updateGradeFee(draft);
      store.syncGradePlan(widget.fee.gradeName, apply: true, removePaid: modeSwitch);
      if (!mounted) return;
      showAppSnack(context, 'تم الحفظ');
      Navigator.pop(context);
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// حفظ الخطة، ثم فتح معاينة الأثر فقط إن وُجد أثر — كويب `handleSave`.
  Future<void> _save() async {
    if (readOnly || lockedIds == null) return;
    final store = StoreScope.of(context);
    if (mode == 'monthly') {
      final amount = double.tryParse(monthlyCtl.text.trim()) ?? 0;
      if (!(amount > 0)) {
        showAppSnack(context, 'أدخل المبلغ الشهري', error: true);
        return;
      }
      // خطة الأقساط المحفوظة تبقى كما هي، وتواريخ الفصول الفارغة تُؤخذ من العام
      final terms = _termsFee();
      final draft = _draftFee()
        ..feeMode = 'monthly'
        ..monthlyFee = amount
        ..planItems = widget.fee.planItems
        ..term1Start = terms.term1Start
        ..term1End = terms.term1End
        ..term2Start = terms.term2Start
        ..term2End = terms.term2End;
      await _confirmAndApply(
        modeSwitch ? 'سيتم استبدال أقساط طلاب المرحلة بالرسوم الشهرية. متابعة؟' : 'سيتم تحديث الرسوم الشهرية لطلاب المرحلة. متابعة؟',
        draft,
      );
      return;
    }
    final today = isoDate(DateTime.now());
    // رسوم جديدة بتاريخ قبل اليوم تُسجَّل متأخرةً فوراً
    if (hadPlan &&
        items.any(
          (i) =>
              !_isRowLocked(i.id) &&
              i.dueDate.isNotEmpty &&
              i.dueDate.compareTo(today) < 0,
        )) {
      showAppSnack(context, 'التاريخ قبل اليوم', error: true);
      return;
    }
    if (modeSwitch) {
      await _confirmAndApply('سيتم استبدال الرسوم الشهرية لطلاب المرحلة بخطة الأقساط. متابعة؟', _draftFee());
      return;
    }

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
      if (preview.isEmpty) {
        showAppSnack(context, 'تم حفظ خطة «${widget.fee.gradeName}»');
        Navigator.pop(context);
        return;
      }

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
    final canEdit = !readOnly && lockedIds != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      bottomNavigationBar: readOnly
          ? FormActionBar(
              label: 'إغلاق',
              busy: false,
              onSave: () => Navigator.pop(context),
            )
          : FormActionBar(
              label: 'حفظ الخطة',
              busy: busy || lockedIds == null,
              onSave: canEdit ? () => _save() : null,
            ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const SizedBox(height: 12),
            _ModeToggle(
              value: mode,
              enabled: !readOnly && !busy,
              onChanged: (v) => setState(() => mode = v),
            ),
            if (mode == 'monthly')
              ..._monthlyPanel(store)
            else ...[
            if (readOnly) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Text(
                  'للعرض فقط',
                  style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ),
            ] else if (!planLocked) ...[
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
                  locked: _isRowLocked(items[i].id),
                  onPickDue: _isRowLocked(items[i].id)
                      ? null
                      : () => _pickDate(items[i].dueDate, (v) => setState(() => items[i].dueDate = v)),
                  onDelete: (readOnly || _isRowLocked(items[i].id))
                      ? null
                      : () => setState(() {
                            items[i].dispose();
                            items.removeAt(i);
                          }),
                ),
              ],
            if (!readOnly) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: GhostButton(label: 'إضافة قسط', icon: Icons.add, onPressed: busy ? null : _addItem),
              ),
            ],

            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
            ],
          ],
        ),
      ),
    );
  }

  /// الرسوم الشهرية: مبلغ واحد، والمواعيد لكل طالب من يوم تسجيله داخل فصول المرحلة.
  /// جدول المثال لطالب سجّل أول يوم في الفصل الأول، ومنه الدفعة الناقصة آخر كل فصل.
  List<Widget> _monthlyPanel(AppStore store) {
    final year = store.operationalAcademicYear;
    final effective = feeTermsFor(customTerms ? _termsFee() : null, year);
    final amount = double.tryParse(monthlyCtl.text.trim()) ?? 0;
    final sampleStart = effective.isNotEmpty ? effective.first.start : isoDate(DateTime.now());
    final sample = monthlyPlanItems(amount: amount, enrollmentDate: sampleStart, terms: effective);
    String termLabel(String key) => key == 'term_1' ? 'الفصل الأول' : key == 'term_2' ? 'الفصل الثاني' : 'العام';

    Widget dateField(String key) {
      final value = gradeTerms[key]!;
      return SelectField(
        text: value.isEmpty ? 'من العام' : value,
        icon: Icons.calendar_today_outlined,
        placeholder: value.isEmpty,
        onTap: readOnly ? null : () => _pickDate(value, (v) => setState(() => gradeTerms[key] = v)),
      );
    }

    return [
      const FormSection(icon: Icons.payments_outlined, title: 'الرسوم الشهرية'),
      const FieldLabel('المبلغ الشهري (شيكل)'),
      TextField(
        controller: monthlyCtl,
        enabled: !readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '0'),
        onChanged: (_) => setState(() {}),
      ),
      const FormSection(icon: Icons.date_range_outlined, title: 'الفصول'),
      CheckboxListTile(
        value: customTerms,
        onChanged: readOnly ? null : (v) => setState(() => customTerms = v ?? false),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('تواريخ فصول خاصة بهذه المرحلة', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
      if (customTerms) ...[
        FieldPair(
          start: [const FieldLabel('بداية الفصل الأول'), dateField('term_1_start')],
          end: [const FieldLabel('نهايته'), dateField('term_1_end')],
        ),
        const SizedBox(height: 10),
        FieldPair(
          start: [const FieldLabel('بداية الفصل الثاني'), dateField('term_2_start')],
          end: [const FieldLabel('نهايته'), dateField('term_2_end')],
        ),
      ] else if (effective.isEmpty)
        Text('لم تُضبط تواريخ الفصول في العام الدراسي', style: TextStyle(fontSize: 12, color: AppColors.amberDark))
      else
        for (final t in effective)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${termLabel(t.key)}: ${t.start} ← ${t.end}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
      if (sample.isNotEmpty) ...[
        FormSection(
          icon: Icons.playlist_add_check_outlined,
          title: 'مثال: تسجيل $sampleStart',
          note: '${sample.length} دفعة · ${money(planTotal(sample))}',
        ),
        for (final item in sample)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text(item.title, style: const TextStyle(fontSize: 12))),
                Text(item.dueDate, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontFamily: 'monospace')),
                const SizedBox(width: 12),
                Text(
                  money(item.amount),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: item.amount < amount ? AppColors.amberDark : AppColors.heading,
                  ),
                ),
              ],
            ),
          ),
      ],
    ];
  }
}

/// نظام الرسوم: أقساط بتواريخ ثابتة، أو رسوم شهرية من تاريخ التسجيل.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.value, required this.enabled, required this.onChanged});

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(String key, String label) {
      final selected = value == key;
      return Expanded(
        child: GestureDetector(
          onTap: enabled && !selected ? () => onChanged(key) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected ? const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))] : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.heading : AppColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          segment('installments', 'أقساط بتواريخ ثابتة'),
          const SizedBox(width: 3),
          segment('monthly', 'شهري من تاريخ التسجيل'),
        ],
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
                    if (p.reschedule.installments > 0)
                      _SyncRow(
                        '${p.reschedule.students} طالب: تحديث تاريخ أو اسم ${p.reschedule.installments} قسط',
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
      if (d.reschedule.installments > 0) 'حُدّث تاريخ أو اسم ${d.reschedule.installments} قسط',
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
    required this.locked,
    this.onPickDue,
    this.onDelete,
  });

  final int index;
  final _EditablePlanItem item;
  final bool locked;
  final VoidCallback? onPickDue;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
        color: locked ? AppColors.surface : null,
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
                  enabled: !locked,
                  decoration: const InputDecoration(hintText: 'عنوان القسط', isDense: true),
                ),
              ),
              if (locked)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.lock_outline, size: 18, color: AppColors.muted),
                )
              else if (onDelete != null)
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
                enabled: !locked,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0', isDense: true),
              ),
            ],
            end: [
              const FieldLabel('الاستحقاق'),
              SelectField(
                text: item.dueDate.isEmpty ? 'اختر' : item.dueDate,
                icon: locked ? Icons.lock_outline : Icons.calendar_today_outlined,
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
