import 'package:flutter/material.dart';

import '../data/grading.dart';
import '../data/academic_matching.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/list_paging.dart';
import '../widgets/widgets.dart';

/// صفحة «رصد درجات» — المقابل لـ `isRecordModalOpen` في Evaluations.tsx.
///
/// تُفتح صفحة كاملة (لا ورقة) لأن كشف الطلاب قد يطول، وتُعيد عدد الدرجات
/// المرصودة (صفر إن أُلغيت).
Future<int> showEvaluationSheet(BuildContext context, AppStore store) async {
  final result = await Navigator.of(context).push<int>(
    MaterialPageRoute(
      builder: (_) => EvaluationFormScreen(store: store),
    ),
  );
  return result ?? 0;
}

class EvaluationFormScreen extends StatefulWidget {
  const EvaluationFormScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<EvaluationFormScreen> createState() => _EvaluationFormScreenState();
}

class _EvaluationFormScreenState extends State<EvaluationFormScreen> {
  /// تسلسل الويب نفسه: الصف ← الشعبة ← المادة، ومنه تتحدد المجموعة وطلابها.
  String grade = '';
  String roomId = '';
  String subjectId = '';
  String type = 'quiz';

  /// الفصل والمكوّن من مخطط المدرسة — فارغان بلا ربط بفصل.
  String term = '';
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
  int rosterVisible = kListPageSize;

  @override
  void initState() {
    super.initState();
    // الفصل من تاريخ الرصد كما في الويب — لا يُسأل عنه في كل مرة عند النمط الموزون
    if (widget.store.gradingForViewedYear.mode != 'monthly') {
      term = termForDate(date, term2Start: widget.store.viewedAcademicYear?.term2Start);
    }
  }

  @override
  void dispose() {
    title.dispose();
    maxScore.dispose();
    for (final c in [...scores.values, ...notes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// شعب الصف المختار.
  List<Classroom> get _rooms => grade.isEmpty
      ? widget.store.roomsInViewedYear
      : widget.store.roomsInViewedYear.where((r) => isSameGrade(r.gradeLevel, grade)).toList();

  /// مجموعات الصف والشعبة المختارين — منها تُشتق المواد المتاحة.
  List<Group> get _scopeGroups => widget.store.groupsInViewedYear.where((g) {
        if (grade.isNotEmpty && g.gradeLevel.trim().isNotEmpty && !isSameGrade(g.gradeLevel, grade)) return false;
        if (roomId.isNotEmpty && g.allRoomIds.isNotEmpty && !g.includesRoom(roomId)) return false;
        return true;
      }).toList();

  /// مواد الشعبة المختارة بلا تكرار.
  List<({String id, String name})> get _subjects {
    final seen = <String, String>{};
    for (final g in _scopeGroups) {
      seen.putIfAbsent(g.subjectId, () {
        final name = widget.store.subjectName(g.subjectId);
        return name.isEmpty || name == 'غير محدد' ? g.name : name;
      });
    }
    return [for (final e in seen.entries) (id: e.key, name: e.value)];
  }

  /// المجموعة التي يحفظ إليها الرصد: الصف والشعبة والمادة تحددها.
  Group? get _group {
    if (roomId.isEmpty || subjectId.isEmpty) return null;
    return _scopeGroups.where((g) => g.subjectId == subjectId).firstOrNull;
  }

  String get groupId => _group?.id ?? '';

  /// طلاب الرصد: طلاب الشعبة المختارة.
  ///
  /// المصدر هو الشعبة نفسها لا تسجيلات المادة: المدرسة تُسند المادة للشعبة،
  /// وربط كل طالب بالمادة تسجيلاً قد لا يكون تمّ بعد — فكان الكشف يظهر فارغاً
  /// رغم وجود طلاب في الشعبة. التسجيلات تُستعمل حين تضيف طلاباً من خارجها.
  List<Student> get _roster {
    final g = _group;
    final room = widget.store.roomById(roomId);
    if (g == null || room == null) return const [];

    final ofRoom = widget.store.studentsOf(room);
    final seen = {for (final s in ofRoom) s.id};
    final extra = [
      for (final s in widget.store.studentsInGroup(g.id))
        if (!seen.contains(s.id) && (g.allRoomIds.length <= 1 || studentBelongsToRoom(s, room))) s,
    ];
    return [...ofRoom, ...extra];
  }

  void _fillMaxFromGroup() {
    final g = _group;
    if (g == null) return;
    final mark = widget.store.gradingForViewedYear.fullMarkForSubject(g.gradeLevel, g.subjectId);
    maxScore.text = trimNum(mark);
  }

  /// كل تبديل في التسلسل يعيد بناء كشف الطلاب.
  void _rebuildRoster() {
    for (final c in [...scores.values, ...notes.values]) {
      c.dispose();
    }
    scores.clear();
    notes.clear();
    for (final s in _roster) {
      scores[s.id] = TextEditingController();
      notes[s.id] = TextEditingController();
    }
    if (_group != null) _fillMaxFromGroup();
    rosterVisible = kListPageSize;
  }

  void _selectGrade(String? value) {
    setState(() {
      grade = value ?? '';
      error = null;
      errors.reset();
      // صفٌّ بشعبة واحدة يختارها تلقائياً، وكذلك المادة الوحيدة
      final rooms = _rooms;
      roomId = rooms.length == 1 ? rooms.first.id : '';
      final subs = _subjects;
      subjectId = roomId.isNotEmpty && subs.length == 1 ? subs.first.id : '';
      _rebuildRoster();
    });
  }

  void _selectRoom(String? value) {
    setState(() {
      roomId = value ?? '';
      error = null;
      errors.reset();
      final subs = _subjects;
      if (!subs.any((x) => x.id == subjectId)) {
        subjectId = subs.length == 1 ? subs.first.id : '';
      }
      _rebuildRoster();
    });
  }

  void _selectSubject(String? value) {
    setState(() {
      subjectId = value ?? '';
      error = null;
      errors.reset();
      _rebuildRoster();
    });
  }

  void _selectComponent(String? id) {
    setState(() {
      componentId = id ?? '';
      final c = _components.where((x) => x.id == componentId).firstOrNull;
      if (c == null) return;
      title.text = c.name;
      final g = _group;
      final full = g == null
          ? defaultFullMark
          : widget.store.gradingForViewedYear.fullMarkForSubject(g.gradeLevel, g.subjectId);
      final mark = componentMark(c, full);
      maxScore.text = trimNum(mark > 0 ? mark : full);
      type = evaluationTypeForComponent(c.name);
      errors.clear('title');
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
    if (picked == null) return;
    setState(() {
      date = isoDate(picked);
      if (_isWeighted) {
        term = termForDate(date, term2Start: widget.store.viewedAcademicYear?.term2Start);
        if (!_components.any((c) => c.id == componentId)) {
          componentId = '';
          title.clear();
        }
      }
    });
  }

  bool get _isWeighted => widget.store.gradingForViewedYear.mode != 'monthly';

  GradingScheme get _recordingScheme {
    if (!_isWeighted) return GradingScheme.empty;
    final g = _group;
    if (g == null) {
      return withDefaultTerms(widget.store.gradingForViewedYear.scheme);
    }
    return widget.store.gradingForViewedYear.recordingSchemeForSubject(g.gradeLevel, g.subjectId);
  }

  List<GradingComponent> get _components => term.isEmpty ? const [] : _recordingScheme.of(term);

  bool get _useComponents => term.isNotEmpty && _components.isNotEmpty;

  void _save() {
    final parsedMax = double.tryParse(maxScore.text.trim());
    final max = parsedMax ?? 100;

    errors.reset();
    errors.check('grade', grade.isEmpty, 'يرجى اختيار الصف');
    errors.check('room', roomId.isEmpty, 'يرجى اختيار الشعبة');
    errors.check('subject', subjectId.isEmpty || groupId.isEmpty, 'يرجى اختيار المادة');
    errors.check(
      'title',
      _useComponents ? componentId.isEmpty : title.text.trim().isEmpty,
      _useComponents ? 'يرجى اختيار التقييم' : 'يرجى تحديد عنوان التقييم',
    );
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
        type: componentId.isNotEmpty
            ? evaluationTypeForComponent(_components.where((c) => c.id == componentId).firstOrNull?.name)
            : type,
        maxScore: max,
        evaluationDate: date,
        scores: entered,
        notes: {for (final e in notes.entries) e.key: e.value.text},
        term: term,
        componentId: term.isNotEmpty && componentId.isNotEmpty ? componentId : '',
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
    // طلاب الشعبة المختارة وحدهم — لا كل مسجّلي المجموعة
    final roster = _roster;
    final visibleRoster = listPage(roster, rosterVisible);
    final useComponents = _useComponents;
    final fullMark = _group == null
        ? defaultFullMark
        : store.gradingForViewedYear.fullMarkForSubject(_group!.gradeLevel, _group!.subjectId);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'رصد درجات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
                  FieldLabel('الصف', key: errors.key('grade'), requiredField: true),
                  AppDropdown<String>(
                    value: grade.isEmpty ? null : grade,
                    hint: 'اختر الصف',
                    errorText: errors['grade'],
                    items: [
                      for (final g in {
                        for (final r in store.roomsInViewedYear)
                          if (r.gradeLevel.trim().isNotEmpty) r.gradeLevel.trim(),
                      }.toList()
                        ..sort())
                        DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _selectGrade,
                  ),
                  const SizedBox(height: 10),
                  FieldLabel('الشعبة', key: errors.key('room'), requiredField: true),
                  AppDropdown<String>(
                    value: roomId.isEmpty ? null : roomId,
                    hint: grade.isEmpty ? 'اختر الصف أولاً' : 'اختر الشعبة',
                    errorText: errors['room'],
                    items: [
                      for (final r in _rooms)
                        DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (grade.isNotEmpty) _selectRoom(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  FieldLabel('المادة', key: errors.key('subject'), requiredField: true),
                  AppDropdown<String>(
                    value: subjectId.isEmpty ? null : subjectId,
                    hint: roomId.isEmpty ? 'اختر الشعبة أولاً' : 'اختر المادة',
                    errorText: errors['subject'],
                    items: [
                      for (final sub in _subjects)
                        DropdownMenuItem(value: sub.id, child: Text(sub.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (roomId.isNotEmpty) _selectSubject(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  FieldLabel('عنوان التقييم / الاختبار', key: errors.key('title'), requiredField: true),
                  if (useComponents)
                    AppDropdown<String>(
                      value: componentId.isEmpty ? null : componentId,
                      hint: 'اختر التقييم',
                      errorText: errors['title'],
                      items: [
                        for (final c in _components)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              '${c.name} (من ${trimNum(componentMark(c, fullMark))})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _selectComponent,
                    )
                  else
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('الفصل'),
                            AppDropdown<String>(
                              value: term.isEmpty && _isWeighted ? 'term_1' : term,
                              items: [
                                if (!_isWeighted) const DropdownMenuItem(value: '', child: Text('بدون فصل')),
                                for (final e in gradingTermLabels.entries)
                                  DropdownMenuItem(value: e.key, child: Text(e.value)),
                              ],
                              onChanged: (v) => setState(() {
                                term = v ?? '';
                                componentId = '';
                                title.clear();
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
                            const FieldLabel('تاريخ التقييم'),
                            InkWell(
                              onTap: _pickDate,
                              child: Container(
                                height: 42,
                                alignment: AlignmentDirectional.centerStart,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(Corner.box),
                                  color: AppColors.bg,
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.event, size: 15, color: AppColors.muted),
                                    const SizedBox(width: 6),
                                    Text(date, style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!useComponents) ...[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const FieldLabel('نوع التقييم'),
                              AppDropdown<String>(
                                value: type,
                                items: [
                                  for (final e in evaluationTypeNames.entries)
                                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                                ],
                                onChanged: (v) => setState(() => type = v ?? type),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FieldLabel('الدرجة القصوى', key: errors.key('max')),
                            TextField(
                              controller: maxScore,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontFamily: 'monospace'),
                              onChanged: (_) => setState(() => errors.clear('max')),
                              decoration: InputDecoration(errorText: errors['max']),
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
                      child: EmptyState(message: 'اختر الصف والشعبة والمادة لعرض الطلاب'),
                    )
                  else if (roster.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: EmptyState(message: 'لا يوجد طلاب مسجلون في هذه الشعبة.'),
                    )
                  else ...[
                    KeyedSubtree(
                      key: errors.key('scores'),
                      child: Row(
                        children: [
                          Expanded(child: SectionTitle('الطلاب (${roster.length})')),
                          const Text(
                            'اترك الدرجة فارغة لمن لم يختبر',
                            style: TextStyle(color: AppColors.faint, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (errors['scores'] != null)
                      Padding(padding: const EdgeInsets.only(bottom: 8), child: FormErrorText(errors['scores'])),
                    for (final s in visibleRoster)
                      Padding(
                        key: errors.key('score:${s.id}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 88,
                              child: TextField(
                                controller: scores[s.id],
                                onChanged: (_) {
                                  if (errors.clear('score:${s.id}')) setState(() {});
                                },
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                                decoration: InputDecoration(
                                  isDense: true,
                                  errorText: errors['score:${s.id}'],
                                  hintText: 'من ${trimNum(double.tryParse(maxScore.text.trim()) ?? 100)}',
                                  hintStyle: const TextStyle(fontSize: 11, color: AppColors.faint),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: notes[s.id],
                                style: const TextStyle(fontSize: 11.5),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'ملاحظات (اختياري)',
                                  hintStyle: TextStyle(fontSize: 11, color: AppColors.faint),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    LoadMoreButton(
                      shown: visibleRoster.length,
                      total: roster.length,
                      onMore: () => setState(() => rosterVisible += kListPageSize),
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
      bottomNavigationBar: FormActionBar(
        label: submitting ? 'جاري الحفظ...' : 'حفظ الدرجات',
        busy: submitting,
        onSave: submitting ? null : _save,
        onCancel: () => Navigator.pop(context, 0),
      ),
    );
  }
}
