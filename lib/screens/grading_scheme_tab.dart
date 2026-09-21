import 'package:flutter/material.dart';

import '../data/academic_matching.dart';
import '../data/grading.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

double _round1(double n) => (n * 10).round() / 10;

/// نظام العلامات — المقابل لـ `GradingSchemeSettings.tsx` بترتيبه نفسه:
/// الطريقة في الأعلى والحفظ يظهر عند التعديل وحده، ثم أقسام تُطوى بملخص
/// يُقرأ وهي مغلقة: توزيع العلامات، والنتيجة، وعلامات المواد.
class GradingSchemeTab extends StatefulWidget {
  const GradingSchemeTab({super.key});

  @override
  State<GradingSchemeTab> createState() => _GradingSchemeTabState();
}

class _GradingSchemeTabState extends State<GradingSchemeTab> {
  /// المسودّة: `null` يعني لا تعديل غير محفوظ.
  GradingSettings? draft;

  /// المرحلة المعروضة في «علامات المواد»، والمادة المفتوح توزيعها.
  String gradeFilter = '';
  String? openSubjectKey;

  GradingSettings get settings => draft ?? StoreScope.of(context).gradingForViewedYear;

  bool get dirty => draft != null;

  void _edit(GradingSettings next) => setState(() => draft = next);

  void _patch(GradingSettings Function(GradingSettings s) fn) => _edit(fn(settings));

  /// فصل بلا مكوّنات يُعرض بالنموذج الافتراضي، وهو ما تعتمده شاشات الرصد فعلاً.
  GradingScheme _withDefaults(GradingScheme scheme, String Function() newId) {
    if (scheme.term1.isNotEmpty || scheme.term2.isNotEmpty) {
      return GradingScheme(
        term1: scheme.term1.isEmpty ? defaultTermComponents(newId) : scheme.term1,
        term2: scheme.term2.isEmpty ? scheme.term1 : scheme.term2,
      );
    }
    return defaultGradingScheme(newId);
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    final scheme = _withDefaults(settings.scheme, store.newId);
    final clean = settings.copyWith(
      scheme: GradingScheme(
        term1: scheme.term1.where((c) => c.name.trim().isNotEmpty).toList(),
        term2: scheme.term2.where((c) => c.name.trim().isNotEmpty).toList(),
      ),
    );
    try {
      await store.saveGradingSettings(clean);
      if (!mounted) return;
      setState(() => draft = null);
      showAppSnack(context, 'تم الحفظ');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = settings;
    final scheme = _withDefaults(s.scheme, store.newId);
    final grades = [
      for (final g in store.gradeFeesInViewedYear)
        if (g.gradeName.trim().isNotEmpty) g.gradeName.trim(),
    ];
    final grade = grades.contains(gradeFilter) ? gradeFilter : (grades.isEmpty ? '' : grades.first);
    final subjectsOfGrade = [
      for (final sub in store.subjectsInViewedYear)
        if (grade.isEmpty || subjectCoversGrade(sub, grade)) sub,
    ];
    final customized = s.subjects.length;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, dirty ? 92 : 24),
          children: [
            // الطريقة: مفتاح مقسّم لا قائمة منسدلة
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الطريقة', style: AppText.label),
                  const SizedBox(height: 8),
                  _Segmented(
                    value: s.mode,
                    options: const {'weighted': 'علامات بمكوّنات', 'monthly': 'معدل شهري عام'},
                    onPick: (v) => _patch((x) => x.copyWith(mode: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (s.mode == 'monthly')
              _Section(
                icon: Icons.workspace_premium_outlined,
                title: 'خصم التفوق',
                summary: s.monthlyDiscountRules.isEmpty ? 'بلا خصم' : '${s.monthlyDiscountRules.length} قاعدة',
                initiallyOpen: true,
                child: _MonthlyRulesEditor(
                  rules: s.monthlyDiscountRules,
                  onChange: (rules) => _patch((x) => x.copyWith(monthlyDiscountRules: rules)),
                ),
              )
            else ...[
              _Section(
                icon: Icons.percent_rounded,
                title: 'توزيع العلامات',
                summary: termsAreSame(scheme) ? '${scheme.term1.length} مكوّنات' : 'لكل فصل توزيعه',
                initiallyOpen: true,
                child: _SchemeEditor(
                  scheme: scheme,
                  fullMark: defaultFullMark,
                  onChange: (next) => _patch((x) => x.copyWith(scheme: next)),
                  onReset: () => _patch((x) => x.copyWith(scheme: defaultGradingScheme(store.newId))),
                ),
              ),
              const SizedBox(height: 10),
              _Section(
                icon: Icons.emoji_events_outlined,
                title: 'النتيجة',
                summary: '${_yearResultLabels[s.yearResultMode] ?? ''} · النجاح ${trimNum(s.passPercent)}%',
                initiallyOpen: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Text('نتيجة السنة', style: AppText.label),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: _Segmented(
                        value: s.yearResultMode,
                        options: _yearResultLabels,
                        onPick: (v) => _patch((x) => x.copyWith(yearResultMode: v)),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.line),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        children: [
                          Expanded(child: Text('علامة النجاح', style: AppText.label)),
                          SizedBox(
                            width: 74,
                            child: _NumberField(
                              value: s.passPercent,
                              suffix: '%',
                              onChanged: (v) => _patch((x) => x.copyWith(passPercent: v <= 0 ? defaultPassPercent : v)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _Section(
                icon: Icons.menu_book_outlined,
                title: 'علامات المواد',
                summary: customized == 0 ? 'كلها من ${trimNum(defaultFullMark)}' : '$customized مخصصة',
                child: _SubjectMarks(
                  grades: grades,
                  grade: grade,
                  subjects: subjectsOfGrade,
                  settings: s,
                  openKey: openSubjectKey,
                  onGrade: (g) => setState(() {
                    gradeFilter = g;
                    openSubjectKey = null;
                  }),
                  onOpenKey: (k) => setState(() => openSubjectKey = k),
                  onPatch: (key, value) {
                    final next = Map<String, SubjectGrading>.from(s.subjects);
                    // علامة كاملة بلا توزيع خاص = لا تخصيص، فيُحذف المفتاح
                    if (value == null ||
                        ((value.fullMark == null || value.fullMark == defaultFullMark) && value.scheme == null)) {
                      next.remove(key);
                    } else {
                      next[key] = value;
                    }
                    _patch((x) => x.copyWith(subjects: next));
                  },
                  newId: store.newId,
                  schoolScheme: scheme,
                ),
              ),
            ],
          ],
        ),
        // الحفظ يظهر عند التعديل وحده، ومعه التراجع
        if (dirty)
          PositionedDirectional(
            start: 12,
            end: 12,
            bottom: 12,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(Corner.card),
              shadowColor: AppColors.navy.withValues(alpha: 0.2),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Corner.card),
                  border: Border.all(color: AppColors.line),
                ),
                child: ActionButtons(
                  gap: 8,
                  primary: PrimaryButton(label: 'حفظ', icon: Icons.check, expand: true, onPressed: _save),
                  secondary: GhostButton(
                    label: 'تراجع',
                    onPressed: () => setState(() => draft = null),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const _yearResultLabels = {
  'average': 'متوسط الفصلين',
  'sum': 'مجموع الفصلين',
  'term_2_only': 'الفصل الثاني فقط',
};

/// قسم يُطوى: عنوانه وأيقونته وملخّصه، ومحتواه عند الفتح.
class _Section extends StatefulWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.summary,
    required this.child,
    this.initiallyOpen = false,
  });

  final IconData icon;
  final String title;
  final String summary;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 8, 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.amberSoft,
                      borderRadius: BorderRadius.circular(Corner.field),
                      border: Border.all(color: AppColors.amberBorder),
                    ),
                    child: Icon(widget.icon, size: 17, color: AppColors.amberDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            color: AppColors.heading,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.faint, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Container(
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                    child: widget.child,
                  ),
          ),
        ],
      ),
    );
  }
}

/// مفتاح مقسّم بخيارات قصيرة.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onPick});

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: e.key == value
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 5, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        e.value,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: e.key == value ? AppColors.heading : AppColors.muted,
                          fontSize: 12.5,
                          fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// حقل رقم: يكتب ما يُدخَل ولا يُعيد بناء نفسه فوق أصابع المستخدم.
class _NumberField extends StatefulWidget {
  const _NumberField({super.key, required this.value, required this.onChanged, this.hint, this.suffix});

  final double? value;
  final ValueChanged<double> onChanged;
  final String? hint;
  final String? suffix;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value == null ? '' : trimNum(widget.value!),
  );

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    // قيمة وصلت من الخارج (تراجع أو استعادة افتراضي) تُكتب في الحقل
    final shown = double.tryParse(_c.text.trim());
    if (widget.value != old.value && widget.value != shown) {
      _c.text = widget.value == null ? '' : trimNum(widget.value!);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppText.family,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixText: widget.suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onChanged: (v) => widget.onChanged(double.tryParse(v.trim()) ?? 0),
    );
  }
}

/// محرّر التوزيع: مفتاح «الفصل الثاني مختلف»، ثم محرّر واحد للفصلين أو محرّران.
class _SchemeEditor extends StatefulWidget {
  const _SchemeEditor({
    super.key,
    required this.scheme,
    required this.fullMark,
    required this.onChange,
    this.onReset,
  });

  final GradingScheme scheme;
  final double fullMark;
  final ValueChanged<GradingScheme> onChange;
  final VoidCallback? onReset;

  @override
  State<_SchemeEditor> createState() => _SchemeEditorState();
}

class _SchemeEditorState extends State<_SchemeEditor> {
  late bool separate = !termsAreSame(widget.scheme);

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            value: separate,
            onChanged: (on) {
              setState(() => separate = on);
              // عند الفصل يبدأ الثاني نسخةً من الأول، فلا تنفكّ علامة عن مكوّنها
              widget.onChange(GradingScheme(
                term1: scheme.term1,
                term2: [for (final c in scheme.term1) c.copyWith()],
              ));
            },
            title: const Text(
              'الفصل الثاني مختلف',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          if (separate) ...[
            _TermEditor(
              title: gradingTermLabels['term_1'] ?? 'الفصل الأول',
              components: scheme.term1,
              fullMark: widget.fullMark,
              onChange: (c) => widget.onChange(scheme.copyWith(term1: c)),
            ),
            const SizedBox(height: 10),
            _TermEditor(
              title: gradingTermLabels['term_2'] ?? 'الفصل الثاني',
              components: scheme.term2,
              fullMark: widget.fullMark,
              onChange: (c) => widget.onChange(scheme.copyWith(term2: c)),
            ),
          ] else
            _TermEditor(
              title: 'الفصلان',
              components: scheme.term1,
              fullMark: widget.fullMark,
              onChange: (c) => widget.onChange(GradingScheme(term1: c, term2: [for (final x in c) x.copyWith()])),
            ),
          if (widget.onReset != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: widget.onReset,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('استعادة الافتراضي'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// مكوّنات فصل بعلامات لا بنسب: مادة من 150 نهائيّها 60 علامة. المخزَّن يبقى
/// نسبة فلا تتغيّر الحسابات، والمعروض علامة ومجموعها يساوي علامة المادة.
class _TermEditor extends StatelessWidget {
  const _TermEditor({
    required this.title,
    required this.components,
    required this.fullMark,
    required this.onChange,
  });

  final String title;
  final List<GradingComponent> components;
  final double fullMark;
  final ValueChanged<List<GradingComponent>> onChange;

  double _markOf(GradingComponent c) => _round1((c.weight * fullMark) / 100);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final totalMark = _round1(components.fold<double>(0, (a, c) => a + _markOf(c)));
    final complete = (totalMark - fullMark).abs() < 0.05;
    final tone = complete ? const Color(0xFF2E7D57) : const Color(0xFFA5484A);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.sunken,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                Text(
                  '${trimNum(totalMark)} / ${trimNum(fullMark)}',
                  style: TextStyle(
                    fontFamily: AppText.family,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: fullMark <= 0 ? 0 : (totalMark / fullMark).clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: AppColors.hover,
            color: tone,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(
              children: [
                for (var i = 0; i < components.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _NameField(
                            key: ValueKey('${components[i].id}_name'),
                            value: components[i].name,
                            onChanged: (v) {
                              final list = [...components];
                              list[i] = list[i].copyWith(name: v);
                              onChange(list);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: _NumberField(
                            key: ValueKey('${components[i].id}_mark'),
                            value: components[i].weight == 0 ? null : _markOf(components[i]),
                            hint: trimNum(fullMark),
                            onChanged: (mark) {
                              final weight = fullMark > 0 ? _round1((mark * 100) / fullMark) : 0.0;
                              final list = [...components];
                              list[i] = list[i].copyWith(weight: weight);
                              onChange(list);
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.faint),
                          onPressed: () => onChange([...components]..removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => onChange([
                      ...components,
                      GradingComponent(id: store.newId(), name: '', weight: 0),
                    ]),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('مكوّن'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.amberDark,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
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

/// حقل اسم المكوّن — يحفظ موضع المؤشر أثناء الكتابة.
class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _NameField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text),
      decoration: const InputDecoration(
        hintText: 'المكوّن',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// علامات المواد: مرحلة تُختار، ثم لكل مادة علامتها الكاملة وتوزيعها الخاص.
class _SubjectMarks extends StatelessWidget {
  const _SubjectMarks({
    required this.grades,
    required this.grade,
    required this.subjects,
    required this.settings,
    required this.openKey,
    required this.onGrade,
    required this.onOpenKey,
    required this.onPatch,
    required this.newId,
    required this.schoolScheme,
  });

  final List<String> grades;
  final String grade;
  final List<SubjectItem> subjects;
  final GradingSettings settings;
  final String? openKey;
  final ValueChanged<String> onGrade;
  final ValueChanged<String?> onOpenKey;
  final void Function(String key, SubjectGrading? value) onPatch;
  final String Function() newId;
  final GradingScheme schoolScheme;

  int _customizedIn(String g) => settings.subjects.keys.where((k) => k.split('|').first == g).length;

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('لا مراحل معرّفة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            children: [
              for (final g in grades)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: _Pill(
                    label: _customizedIn(g) > 0 ? '$g (${_customizedIn(g)})' : g,
                    selected: g == grade,
                    onTap: () => onGrade(g),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (subjects.isEmpty)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('لا مواد لهذه المرحلة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          )
        else
          for (final sub in subjects) ...[
            const Divider(height: 1, color: AppColors.hover),
            () {
              final key = subjectGradingKey(grade, sub.id);
              final value = settings.subjects[key];
              final mark = value?.fullMark ?? defaultFullMark;
              final hasScheme = value?.scheme != null;
              final open = openKey == key && hasScheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sub.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text('من', style: AppText.label),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 70,
                          child: _NumberField(
                            key: ValueKey('${key}_mark'),
                            value: value?.fullMark,
                            hint: trimNum(defaultFullMark),
                            onChanged: (v) => onPatch(
                              key,
                              SubjectGrading(
                                fullMark: v <= 0 ? null : v,
                                scheme: value?.scheme,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: hasScheme ? 'توزيع خاص' : 'توزيع المدرسة',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            hasScheme ? Icons.tune_rounded : Icons.tune_outlined,
                            size: 18,
                            color: hasScheme ? AppColors.amberDark : AppColors.faint,
                          ),
                          onPressed: () {
                            if (hasScheme) {
                              onPatch(key, SubjectGrading(fullMark: value?.fullMark));
                              onOpenKey(null);
                            } else {
                              onPatch(
                                key,
                                SubjectGrading(
                                  fullMark: value?.fullMark,
                                  scheme: GradingScheme(
                                    term1: [for (final c in schoolScheme.term1) c.copyWith()],
                                    term2: [for (final c in schoolScheme.term2) c.copyWith()],
                                  ),
                                ),
                              );
                              onOpenKey(key);
                            }
                          },
                        ),
                        if (hasScheme)
                          IconButton(
                            tooltip: open ? 'إخفاء' : 'فتح',
                            visualDensity: VisualDensity.compact,
                            icon: AnimatedRotation(
                              turns: open ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.faint),
                            ),
                            onPressed: () => onOpenKey(open ? null : key),
                          ),
                      ],
                    ),
                  ),
                  if (open && value?.scheme != null)
                    Container(
                      color: AppColors.sunken,
                      child: _SchemeEditor(
                        key: ValueKey('${key}_scheme'),
                        scheme: value!.scheme!,
                        fullMark: mark,
                        onChange: (scheme) => onPatch(key, SubjectGrading(fullMark: value.fullMark, scheme: scheme)),
                      ),
                    ),
                ],
              );
            }(),
          ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.amber : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? AppColors.amber : AppColors.lineStrong),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontFamily: AppText.family,
            color: selected ? Colors.white : AppColors.heading,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// قواعد خصم التفوق في النمط الشهري: معدل فأعلى ← خصم % من الرسوم القادمة.
class _MonthlyRulesEditor extends StatelessWidget {
  const _MonthlyRulesEditor({required this.rules, required this.onChange});

  final List<({double minAverage, double discountPercent})> rules;
  final ValueChanged<List<({double minAverage, double discountPercent})>> onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('بلا خصم', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else
            for (var i = 0; i < rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // تلتفّ على الشاشات الضيقة بدل أن تطفح
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text('معدل', style: AppText.label),
                    SizedBox(
                      width: 64,
                      child: _NumberField(
                        key: ValueKey('rule_min_$i'),
                        value: rules[i].minAverage,
                        onChanged: (v) {
                          final list = [...rules];
                          list[i] = (minAverage: v, discountPercent: list[i].discountPercent);
                          onChange(list);
                        },
                      ),
                    ),
                    Text('فأعلى ← خصم', style: AppText.label),
                    SizedBox(
                      width: 70,
                      child: _NumberField(
                        key: ValueKey('rule_pct_$i'),
                        value: rules[i].discountPercent,
                        suffix: '%',
                        onChanged: (v) {
                          final list = [...rules];
                          list[i] = (minAverage: list[i].minAverage, discountPercent: v);
                          onChange(list);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'حذف',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.faint),
                      onPressed: () => onChange([...rules]..removeAt(i)),
                    ),
                  ],
                ),
              ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => onChange([...rules, (minAverage: 90, discountPercent: 10)]),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('قاعدة'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amberDark,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
