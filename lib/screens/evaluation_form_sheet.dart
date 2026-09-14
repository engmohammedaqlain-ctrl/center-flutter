import 'package:flutter/material.dart';

import '../data/grading.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

/// نافذة «رصد درجات جديدة» — المقابل لـ `isRecordModalOpen` في Evaluations.tsx.
///
/// تُعيد عدد الدرجات المرصودة (صفر إن أُلغيت).
Future<int> showEvaluationSheet(BuildContext context, AppStore store) async {
  final result = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _EvaluationSheet(store: store),
  );
  return result ?? 0;
}

class _EvaluationSheet extends StatefulWidget {
  const _EvaluationSheet({required this.store});
  final AppStore store;

  @override
  State<_EvaluationSheet> createState() => _EvaluationSheetState();
}

class _EvaluationSheetState extends State<_EvaluationSheet> {
  String groupId = '';
  String type = 'quiz';

  /// الفصل والمكوّن من مخطط المدرسة — فارغان لمن لا مخطط له.
  String term = 'term_1';
  String componentId = '';
  final title = TextEditingController();
  final maxScore = TextEditingController(text: '100');
  late String date = isoDate(DateTime.now());

  /// درجة كل طالب. الحقل الفارغ يعني «لم يُرصد» فيُتخطّى، لا صفراً.
  final scores = <String, TextEditingController>{};

  /// ملاحظة اختيارية لكل طالب — مطابق لـ `studentScores[id].notes`.
  final notes = <String, TextEditingController>{};

  bool submitting = false;
  String? error;
  final errors = FieldErrors();

  @override
  void dispose() {
    title.dispose();
    maxScore.dispose();
    for (final c in [...scores.values, ...notes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectGroup(String? id) {
    setState(() {
      groupId = id ?? '';
      error = null;
      errors.reset();
      for (final c in [...scores.values, ...notes.values]) {
        c.dispose();
      }
      scores.clear();
      notes.clear();
      for (final s in widget.store.studentsInGroup(groupId)) {
        scores[s.id] = TextEditingController();
        notes[s.id] = TextEditingController();
      }
    });
  }

  Future<void> _pickDate() async {
    final current = parseIsoDate(date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 5),
    );
    if (picked != null) setState(() => date = isoDate(picked));
  }

  void _save() {
    final parsedMax = double.tryParse(maxScore.text.trim());
    final max = parsedMax ?? 100;

    errors.reset();
    errors.check('group', groupId.isEmpty, 'يرجى اختيار الشعبة');
    errors.check('title', title.text.trim().isEmpty, 'يرجى تحديد عنوان التقييم');
    errors.check('max', parsedMax == null || parsedMax <= 0, 'درجة قصوى غير صالحة');

    final entered = <String, double>{};
    for (final entry in scores.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      final value = double.tryParse(raw);
      if (value == null) {
        errors.check('score:${entry.key}', true, 'ليست رقماً');
      } else if (value < 0 || value > max) {
        errors.check('score:${entry.key}', true, 'بين 0 و${trimNum(max)}');
      } else {
        entered[entry.key] = value;
      }
    }
    // الفارغ لا يُحفظ صفراً: لا بد من درجة واحدة مرصودة على الأقل
    final anyScoreError = scores.keys.any((id) => errors['score:$id'] != null);
    errors.check(
      'scores',
      groupId.isNotEmpty && scores.isNotEmpty && entered.isEmpty && !anyScoreError,
      'يرجى رصد درجة واحدة على الأقل',
    );

    setState(() => error = null);
    if (errors.report(context)) return;

    setState(() => submitting = true);
    try {
      final saved = widget.store.saveEvaluationBatch(
        groupId: groupId,
        title: title.text,
        type: type,
        maxScore: max,
        evaluationDate: date,
        scores: entered,
        notes: {for (final e in notes.entries) e.key: e.value.text},
        term: componentId.isEmpty ? '' : term,
        componentId: componentId,
      );
      if (mounted) Navigator.pop(context, saved);
    } on StoreException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final roster = store.studentsInGroup(groupId);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'رصد درجات جديدة',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  SquareIconButton(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context, 0),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                children: [
                  FieldLabel('الشعبة المستهدفة', key: errors.key('group'), requiredField: true),
                  AppDropdown<String>(
                    value: groupId.isEmpty ? null : groupId,
                    hint: 'اختر الشعبة',
                    errorText: errors['group'],
                    items: [
                      for (final g in store.groups)
                        DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: _selectGroup,
                  ),
                  const SizedBox(height: 10),

                  FieldLabel('عنوان التقييم / الاختبار', key: errors.key('title'), requiredField: true),
                  TextField(
                    controller: title,
                    onChanged: (_) {
                      if (errors.clear('title')) setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'مثلاً: اختبار الشهر الأول، نشاط عملي...',
                      errorText: errors['title'],
                    ),
                  ),
                  const SizedBox(height: 10),

                  const FieldLabel('نوع التقييم'),
                  AppDropdown<String>(
                    value: type,
                    items: [
                      for (final e in evaluationTypeNames.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => type = v ?? type),
                  ),
                  const SizedBox(height: 10),

                  // مخطط العلامات إن عُرّف: الفصل ومكوّنه يجعلان للتقييم وزناً
                  // في المعدل بدل متوسط بسيط يساوي بين النهائي والواجب
                  if (!store.gradingScheme.isEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const FieldLabel('الفصل الدراسي'),
                              AppDropdown<String>(
                                value: term,
                                items: [
                                  for (final e in gradingTermLabels.entries)
                                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                                ],
                                onChanged: (v) => setState(() {
                                  term = v ?? term;
                                  componentId = '';
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const FieldLabel('مكوّن العلامة'),
                              AppDropdown<String>(
                                value: componentId.isEmpty ? null : componentId,
                                hint: 'بلا وزن',
                                items: [
                                  for (final c in store.gradingScheme.of(term))
                                    DropdownMenuItem(value: c.id, child: Text('${c.name} (${trimNum(c.weight)}%)')),
                                ],
                                onChanged: (v) => setState(() => componentId = v ?? ''),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FieldLabel('الدرجة القصوى', key: errors.key('max')),
                            TextField(
                              controller: maxScore,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(fontFamily: 'monospace'),
                              onChanged: (_) => setState(() => errors.clear('max')),
                              decoration: InputDecoration(errorText: errors['max']),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('تاريخ التقييم'),
                            InkWell(
                              onTap: _pickDate,
                              child: Container(
                                height: 42,
                                alignment: AlignmentDirectional.centerStart,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(Corner.box),
                                  color: AppColors.bg,
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.event,
                                      size: 15,
                                      color: AppColors.muted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (groupId.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: EmptyState(
                        message: 'اختر الشعبة لعرض طلابها ورصد درجاتهم.',
                      ),
                    )
                  else if (roster.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: EmptyState(
                        message: 'لا يوجد طلاب مسجلون في هذه الشعبة.',
                      ),
                    )
                  else ...[
                    KeyedSubtree(key: errors.key('scores'), child: SectionTitle('طلاب الشعبة (${roster.length})')),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'اترك الحقل فارغاً لمن لم تُرصد درجته — الفارغ لا يُحفظ صفراً.',
                        style: TextStyle(
                          color: AppColors.faint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    if (errors['scores'] != null)
                      Padding(padding: const EdgeInsets.only(bottom: 8), child: FormErrorText(errors['scores'])),
                    for (final s in roster)
                      Padding(
                        key: errors.key('score:${s.id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: scores[s.id],
                                    onChanged: (_) {
                                      if (errors.clear('score:${s.id}')) setState(() {});
                                    },
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      errorText: errors['score:${s.id}'],
                                      hintText:
                                          'من ${trimNum(double.tryParse(maxScore.text.trim()) ?? 100)}',
                                      hintStyle: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.faint,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: notes[s.id],
                              style: const TextStyle(fontSize: 11.5),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'ملاحظات (اختياري)',
                                hintStyle: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.faint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],

                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'إلغاء',
                      onPressed: () => Navigator.pop(context, 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: submitting ? 'جاري الحفظ...' : 'حفظ الدرجات',
                      color: AppColors.navy,
                      busy: submitting,
                      onPressed: submitting ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
