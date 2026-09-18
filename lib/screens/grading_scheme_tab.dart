import 'package:flutter/material.dart';

import '../data/academic_matching.dart';
import '../data/grading.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

double _round1(double n) => (n * 10).round() / 10;

/// مخطط علامات المدرسة — المقابل لـ `GradingSchemeSettings.tsx`.
///
/// يضبط النمط (موزون / معدل شهري)، ومكوّنات الفصلين بعلامات من علامة المادة،
/// وتخصيص مرحلة|مادة، وطريقة نتيجة السنة، وقواعد خصم التفوق.
class GradingSchemeTab extends StatefulWidget {
  const GradingSchemeTab({super.key});

  @override
  State<GradingSchemeTab> createState() => _GradingSchemeTabState();
}

class _GradingSchemeTabState extends State<GradingSchemeTab> {
  GradingSettings? draft;
  bool loaded = false;
  bool userEdited = false;
  bool savedFlash = false;

  String newSubject = '';
  final newMark = TextEditingController();
  final newGrades = <String>{};
  String? editingKey;

  @override
  void dispose() {
    newMark.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded && userEdited) return;
    final store = StoreScope.of(context);
    draft = null;
    loaded = true;
    // مدرسة بلا مخطط: لا نفرض مسودة حتى يحفظ المستخدم
    if (store.gradingSettings.scheme.isEmpty && store.gradingSettings.mode != 'monthly') {
      // يبقى العرض من gradingSettings (قد يكون فارغاً) — الزر «الافتراضي» يملأ
    }
  }

  GradingSettings get settings => draft ?? StoreScope.of(context).gradingSettings;

  void _edit(GradingSettings next) {
    setState(() {
      draft = next;
      userEdited = true;
    });
  }

  void _patch(GradingSettings Function(GradingSettings s) fn) => _edit(fn(settings));

  Future<void> _save() async {
    final store = StoreScope.of(context);
    final clean = GradingSettings(
      mode: settings.mode,
      scheme: GradingScheme(
        term1: settings.scheme.term1.where((c) => c.name.trim().isNotEmpty).toList(),
        term2: settings.scheme.term2.where((c) => c.name.trim().isNotEmpty).toList(),
      ),
      subjects: settings.subjects,
      yearResultMode: settings.yearResultMode,
      monthlyDiscountRules: settings.monthlyDiscountRules,
    );
    try {
      await store.saveGradingSettings(clean);
      if (!mounted) return;
      setState(() {
        draft = null;
        userEdited = false;
        savedFlash = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => savedFlash = false);
      });
      showAppSnack(context, 'تم حفظ نظام العلامات');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  void _addOverride() {
    if (newSubject.isEmpty || newGrades.isEmpty) return;
    final mark = double.tryParse(newMark.text.trim());
    final next = Map<String, SubjectGrading>.from(settings.subjects);
    for (final grade in newGrades) {
      final key = subjectGradingKey(grade, newSubject);
      next[key] = SubjectGrading(fullMark: mark, scheme: next[key]?.scheme);
    }
    _patch((s) => s.copyWith(subjects: next));
    newMark.clear();
    setState(() => newGrades.clear());
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = settings;
    final grades = [
      for (final g in store.gradeFeesInViewedYear)
        if (g.gradeName.trim().isNotEmpty) g.gradeName.trim(),
    ];
    final subjects = store.subjectsInViewedYear;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: AppDropdown<String>(
                  value: s.mode,
                  items: const [
                    DropdownMenuItem(value: 'weighted', child: Text('توزيع بأوزان')),
                    DropdownMenuItem(value: 'monthly', child: Text('معدل شهري')),
                  ],
                  onChanged: (v) => _patch((x) => x.copyWith(mode: v ?? 'weighted')),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: PrimaryButton(
                  label: savedFlash ? 'تم الحفظ' : 'حفظ',
                  icon: Icons.check,
                  color: savedFlash ? AppColors.success : AppColors.navy,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (s.mode == 'monthly')
          _MonthlyRulesEditor(
            rules: s.monthlyDiscountRules,
            onChange: (rules) => _patch((x) => x.copyWith(monthlyDiscountRules: rules)),
          )
        else ...[
          _SchemeEditor(
            scheme: s.scheme.isEmpty ? defaultGradingScheme(store.newId) : s.scheme,
            fullMark: defaultFullMark,
            onChange: (scheme) => _patch((x) => x.copyWith(scheme: scheme)),
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                const Text('نتيجة السنة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDropdown<String>(
                    value: s.yearResultMode,
                    items: const [
                      DropdownMenuItem(value: 'average', child: Text('متوسط الفصلين')),
                      DropdownMenuItem(value: 'sum', child: Text('مجموع الفصلين')),
                      DropdownMenuItem(value: 'term_2_only', child: Text('الفصل الثاني فقط')),
                    ],
                    onChanged: (v) => _patch((x) => x.copyWith(yearResultMode: v ?? 'average')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تخصيص مادة في مرحلة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppDropdown<String>(
                        value: newSubject.isEmpty ? null : newSubject,
                        hint: 'المادة',
                        items: [
                          for (final sub in subjects)
                            DropdownMenuItem(value: sub.id, child: Text(sub.name)),
                        ],
                        onChanged: (v) => setState(() {
                          newSubject = v ?? '';
                          newGrades.clear();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: newMark,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          hintText: 'من ${trimNum(defaultFullMark)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: newSubject.isEmpty || newGrades.isEmpty ? null : _addOverride,
                      style: IconButton.styleFrom(backgroundColor: AppColors.navy),
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ],
                ),
                if (newSubject.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in _gradesForSubject(subjects, grades, newSubject))
                        FilterChip(
                          label: Text(g, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          selected: newGrades.contains(g),
                          onSelected: (on) => setState(() {
                            if (on) {
                              newGrades.add(g);
                            } else {
                              newGrades.remove(g);
                            }
                          }),
                        ),
                      TextButton(
                        onPressed: () {
                          final all = _gradesForSubject(subjects, grades, newSubject);
                          setState(() {
                            if (newGrades.length == all.length) {
                              newGrades.clear();
                            } else {
                              newGrades
                                ..clear()
                                ..addAll(all);
                            }
                          });
                        },
                        child: Text(
                          newGrades.length == _gradesForSubject(subjects, grades, newSubject).length
                              ? 'إلغاء التحديد'
                              : 'تحديد الكل',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ],
                if (s.subjects.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final e in s.subjects.entries)
                    _OverrideTile(
                      gradingKey: e.key,
                      value: e.value,
                      subjectName: store.subjectName(e.key.contains('|') ? e.key.split('|').last : ''),
                      editing: editingKey == e.key,
                      onToggleEdit: () => setState(() => editingKey = editingKey == e.key ? null : e.key),
                      onRemove: () {
                        final next = Map<String, SubjectGrading>.from(s.subjects)..remove(e.key);
                        _patch((x) => x.copyWith(subjects: next));
                        if (editingKey == e.key) setState(() => editingKey = null);
                      },
                      onScheme: (scheme) {
                        final next = Map<String, SubjectGrading>.from(s.subjects);
                        next[e.key] = SubjectGrading(fullMark: e.value.fullMark, scheme: scheme);
                        _patch((x) => x.copyWith(subjects: next));
                      },
                      newId: store.newId,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          GhostButton(
            label: 'استعادة التوزيع الافتراضي',
            icon: Icons.refresh,
            onPressed: () => _patch((x) => x.copyWith(scheme: defaultGradingScheme(store.newId))),
          ),
        ],
      ],
    );
  }

  List<String> _gradesForSubject(List<SubjectItem> subjects, List<String> grades, String subjectId) {
    final subject = subjects.where((s) => s.id == subjectId).firstOrNull;
    if (subject == null) return grades;
    final own = grades.where((g) => subjectCoversGrade(subject, g)).toList();
    return own.isNotEmpty ? own : grades;
  }
}

class _MonthlyRulesEditor extends StatelessWidget {
  const _MonthlyRulesEditor({required this.rules, required this.onChange});

  final List<({double minAverage, double discountPercent})> rules;
  final ValueChanged<List<({double minAverage, double discountPercent})>> onChange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('خصم التفوق', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
              GhostButton(
                label: 'قاعدة',
                icon: Icons.add,
                onPressed: () => onChange([
                  ...rules,
                  (minAverage: 90, discountPercent: 10),
                ]),
              ),
            ],
          ),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('بلا خصم', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else
            for (var i = 0; i < rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Text('معدل', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 56,
                      child: TextField(
                        key: ValueKey('min_$i-${rules[i].minAverage}'),
                        controller: TextEditingController(text: trimNum(rules[i].minAverage)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w800),
                        onChanged: (v) {
                          final list = [...rules];
                          list[i] = (
                            minAverage: double.tryParse(v.trim()) ?? 0,
                            discountPercent: list[i].discountPercent,
                          );
                          onChange(list);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('فأعلى ← خصم', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 56,
                      child: TextField(
                        key: ValueKey('pct_$i-${rules[i].discountPercent}'),
                        controller: TextEditingController(text: trimNum(rules[i].discountPercent)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w800),
                        onChanged: (v) {
                          final list = [...rules];
                          list[i] = (
                            minAverage: list[i].minAverage,
                            discountPercent: double.tryParse(v.trim()) ?? 0,
                          );
                          onChange(list);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('%', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    SquareIconButton(
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                      onTap: () => onChange([...rules]..removeAt(i)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SchemeEditor extends StatelessWidget {
  const _SchemeEditor({required this.scheme, required this.fullMark, required this.onChange});

  final GradingScheme scheme;
  final double fullMark;
  final ValueChanged<GradingScheme> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TermEditor(
          term: 'term_1',
          components: scheme.term1,
          fullMark: fullMark,
          onChange: (c) => onChange(scheme.copyWith(term1: c)),
        ),
        const SizedBox(height: 10),
        _TermEditor(
          term: 'term_2',
          components: scheme.term2,
          fullMark: fullMark,
          onChange: (c) => onChange(scheme.copyWith(term2: c)),
        ),
      ],
    );
  }
}

class _TermEditor extends StatelessWidget {
  const _TermEditor({
    required this.term,
    required this.components,
    required this.fullMark,
    required this.onChange,
  });

  final String term;
  final List<GradingComponent> components;
  final double fullMark;
  final ValueChanged<List<GradingComponent>> onChange;

  double _markOf(GradingComponent c) => _round1((c.weight * fullMark) / 100);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final totalMark = _round1(components.fold<double>(0, (a, c) => a + _markOf(c)));
    final complete = (totalMark - fullMark).abs() < 0.05;
    final over = totalMark > fullMark;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    gradingTermLabels[term] ?? term,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                  ),
                ),
                Text(
                  '${trimNum(totalMark)} / ${trimNum(fullMark)}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: complete
                        ? AppColors.success
                        : over
                            ? AppColors.danger
                            : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: (components.fold<double>(0, (a, c) => a + c.weight) / 100).clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: AppColors.line,
            color: complete
                ? AppColors.success
                : over
                    ? AppColors.danger
                    : AppColors.navy,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                if (components.isEmpty)
                  GhostButton(
                    label: 'النموذج الافتراضي',
                    onPressed: () => onChange(defaultTermComponents(store.newId)),
                  )
                else
                  for (var i = 0; i < components.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: TextField(
                              key: ValueKey('${components[i].id}_name'),
                              controller: TextEditingController(text: components[i].name),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                              decoration: const InputDecoration(hintText: 'المكوّن'),
                              onChanged: (v) {
                                final list = [...components];
                                list[i] = list[i].copyWith(name: v);
                                onChange(list);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            child: TextField(
                              key: ValueKey('${components[i].id}_mark'),
                              controller: TextEditingController(
                                text: components[i].weight == 0 ? '' : trimNum(_markOf(components[i])),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w800),
                              onChanged: (v) {
                                final mark = double.tryParse(v.trim()) ?? 0;
                                final weight = fullMark > 0 ? _round1((mark * 100) / fullMark) : 0.0;
                                final list = [...components];
                                list[i] = list[i].copyWith(weight: weight);
                                onChange(list);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${trimNum(components[i].weight)}%',
                              style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontFamily: 'monospace'),
                            ),
                          ),
                          SquareIconButton(
                            icon: Icons.delete_outline,
                            color: AppColors.danger,
                            onTap: () => onChange([...components]..removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GhostButton(
                    label: 'مكوّن',
                    icon: Icons.add,
                    onPressed: () => onChange([
                      ...components,
                      GradingComponent(id: store.newId(), name: '', weight: 0),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverrideTile extends StatelessWidget {
  const _OverrideTile({
    required this.gradingKey,
    required this.value,
    required this.subjectName,
    required this.editing,
    required this.onToggleEdit,
    required this.onRemove,
    required this.onScheme,
    required this.newId,
  });

  final String gradingKey;
  final SubjectGrading value;
  final String subjectName;
  final bool editing;
  final VoidCallback onToggleEdit;
  final VoidCallback onRemove;
  final ValueChanged<GradingScheme?> onScheme;
  final String Function() newId;

  @override
  Widget build(BuildContext context) {
    final parts = gradingKey.split('|');
    final grade = parts.isNotEmpty ? parts.first : gradingKey;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Corner.box),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$grade · $subjectName',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              Text(
                'من ${trimNum(value.fullMark ?? defaultFullMark)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.muted),
              ),
              TextButton(
                onPressed: onToggleEdit,
                child: Text(
                  value.scheme != null ? 'توزيع خاص' : 'توزيع المدرسة',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              SquareIconButton(icon: Icons.delete_outline, color: AppColors.danger, onTap: onRemove),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 6),
            GhostButton(
              label: value.scheme != null ? 'العودة لتوزيع المدرسة' : 'توزيع خاص لهذه المادة',
              onPressed: () => onScheme(value.scheme != null ? null : defaultGradingScheme(newId)),
            ),
            if (value.scheme != null) ...[
              const SizedBox(height: 8),
              _SchemeEditor(
                scheme: value.scheme!,
                fullMark: value.fullMark ?? defaultFullMark,
                onChange: onScheme,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
