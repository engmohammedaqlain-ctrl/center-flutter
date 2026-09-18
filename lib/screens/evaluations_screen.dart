import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/academic_matching.dart';
import '../data/grading.dart';
import '../data/monthly_averages.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'evaluation_form_sheet.dart';
import 'evaluations_print.dart';

/// الدرجات والتقييمات الأكاديمية — المقابل لـ `pages/Evaluations.tsx`.
///
/// بنمط المعدل الشهري تُستبدل القائمة بواجهة رصد شهرية (EV-05).
/// الميزة قابلة للتعطيل من إعدادات المطور؛ الشاشة تُغلق نفسها إن عُطّلت.
class EvaluationsScreen extends StatefulWidget {
  const EvaluationsScreen({super.key});

  @override
  State<EvaluationsScreen> createState() => _EvaluationsScreenState();
}

class _EvaluationsScreenState extends State<EvaluationsScreen> {
  final search = TextEditingController();
  String gradeFilter = 'all';
  String roomFilter = 'all';
  String groupId = 'all';
  String type = 'all';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.features.enableEvaluations || !store.can('evaluations')) {
          return Scaffold(
            appBar: AppBar(title: const Text('الدرجات والتقييمات')),
            body: NoAccess(section: 'evaluations', roleName: store.roleName),
          );
        }

        final grading = store.gradingForViewedYear;
        if (grading.mode == 'monthly') {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('الدرجات والتقييمات')),
            body: const _MonthlyGradesPanel(),
          );
        }

        return _weightedBody(store);
      },
    );
  }

  Widget _weightedBody(AppStore store) {
    final q = search.text.trim().toLowerCase();
    final rooms = store.roomsInViewedYear;
    final grades = <String>{
      for (final r in rooms)
        if (r.gradeLevel.trim().isNotEmpty) r.gradeLevel.trim(),
      for (final s in store.studentsInViewedYear)
        if (s.gradeLevel.trim().isNotEmpty) s.gradeLevel.trim(),
    }.toList()
      ..sort();

    final roomsForGrade = gradeFilter == 'all'
        ? rooms
        : rooms.where((r) => isSameGrade(r.gradeLevel, gradeFilter)).toList();

    final groups = store.groupsInViewedYear.where((g) {
      if (gradeFilter != 'all' && g.gradeLevel.isNotEmpty && !isSameGrade(g.gradeLevel, gradeFilter)) {
        return false;
      }
      if (roomFilter != 'all' && g.allRoomIds.isNotEmpty && !g.includesRoom(roomFilter)) {
        return false;
      }
      return true;
    }).toList();

    final list = store.evaluations.where((e) {
      // المعدلات الشهرية (بلا مادة) ليست تقييمات مادة في النمط الموزون
      if (isMonthlyAverage(e)) return false;

      final student = store.studentById(e.studentId);
      final group = store.groupById(e.groupId);

      if (gradeFilter != 'all') {
        final studentOk = student != null && isSameGrade(student.gradeLevel, gradeFilter);
        final groupOk = group != null && group.gradeLevel.isNotEmpty && isSameGrade(group.gradeLevel, gradeFilter);
        if (!studentOk && !groupOk) return false;
      }
      if (roomFilter != 'all') {
        final room = store.roomById(roomFilter);
        final studentOk = student != null && room != null && studentBelongsToRoom(student, room);
        final groupOk = group != null && group.includesRoom(roomFilter);
        if (!studentOk && !groupOk) return false;
      }
      if (groupId != 'all' && e.groupId != groupId) return false;
      if (type != 'all' && e.type != type) return false;
      if (q.isEmpty) return true;
      final name = (student?.fullName ?? '').toLowerCase();
      return name.contains(q) || e.title.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('الدرجات والتقييمات'),
        actions: [
          IconButton(
            tooltip: 'تنزيل الكشف',
            icon: const Icon(Icons.print_outlined),
            onPressed: list.isEmpty
                ? null
                : () => printEvaluations(
                      context,
                      store: store,
                      evaluations: list,
                      groupName: groupId == 'all' ? '' : (store.groupById(groupId)?.name ?? ''),
                    ),
          ),
        ],
      ),
      body: ThumbActionLayer(
        action: store.can('evaluations')
            ? ThumbAction(
                label: 'رصد درجات جديدة',
                icon: Icons.edit_note,
                color: AppColors.navy,
                onPressed: () => _record(context, store),
              )
            : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: _stats(list),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SearchField(
                controller: search,
                hint: 'ابحث باسم الطالب أو عنوان التقييم...',
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      value: gradeFilter,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('كل المراحل')),
                        for (final g in grades) DropdownMenuItem(value: g, child: Text(g)),
                      ],
                      onChanged: (v) => setState(() {
                        gradeFilter = v ?? 'all';
                        roomFilter = 'all';
                        groupId = 'all';
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppDropdown<String>(
                      value: roomFilter,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('كل الشعب')),
                        for (final r in roomsForGrade)
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              r.gradeLevel.isEmpty ? r.name : '${r.gradeLevel} — ${r.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        roomFilter = v ?? 'all';
                        groupId = 'all';
                      }),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      value: groups.any((g) => g.id == groupId) ? groupId : 'all',
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('كل المواد')),
                        for (final g in groups)
                          DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => groupId = v ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppDropdown<String>(
                      value: type,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('كل الأنواع')),
                        for (final e in evaluationTypeNames.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => type = v ?? 'all'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: EmptyState(message: 'لا توجد تقييمات مرصودة مطابقة للبحث.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, thumbActionClearance),
                      itemCount: list.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EvalCard(
                          evaluation: list[i],
                          studentName: store.studentById(list[i].studentId)?.fullName ?? 'طالب محذوف',
                          subjectLine: () {
                            final e = list[i];
                            final group = store.groupById(e.groupId);
                            final subject = store.subjectById(e.subjectId)?.name ??
                                (group != null ? store.subjectName(group.subjectId) : '');
                            final grade = group?.gradeLevel.trim() ?? '';
                            final teacher = group == null || group.teacherId.isEmpty
                                ? ''
                                : store.teacherName(group.teacherId);
                            return [
                              if (subject.isNotEmpty && subject != 'غير محدد') subject,
                              if (grade.isNotEmpty) grade,
                              if (teacher.isNotEmpty && teacher != 'غير محدد') teacher,
                            ].join(' · ');
                          }(),
                          onDelete: store.can('evaluations') ? () => _delete(context, store, list[i]) : null,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// أربع إحصاءات سريعة — نفس حساب `stats` في Evaluations.tsx: النسبة تُحسب
  /// من كل تقييم على حدة ثم تُعدّل، لا من مجموع الدرجات على مجموع القصوى.
  Widget _stats(List<Evaluation> list) {
    var totalPercent = 0;
    var passCount = 0;
    var highest = 0;
    for (final e in list) {
      totalPercent += e.percent;
      if (e.passed) passCount++;
      if (e.percent > highest) highest = e.percent;
    }
    final average = list.isEmpty ? 0 : (totalPercent / list.length).round();
    final passRate = list.isEmpty ? 0 : ((passCount / list.length) * 100).round();

    return Row(
      children: [
        _stat('التقييمات', '${list.length}', AppColors.heading),
        const SizedBox(width: 6),
        _stat('المعدل العام', '$average%', AppColors.success),
        const SizedBox(width: 6),
        _stat('النجاح (50%)', '$passRate%', AppColors.info),
        const SizedBox(width: 6),
        _stat('الأعلى', '$highest%', AppColors.amber),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: Colors.white,
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _record(BuildContext context, AppStore store) async {
    final saved = await showEvaluationSheet(context, store);
    if (saved > 0 && context.mounted) {
      showAppSnack(context, 'تم رصد $saved درجة');
    }
  }

  Future<void> _delete(BuildContext context, AppStore store, Evaluation e) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف التقييم',
      message: 'هل أنت متأكد من حذف تقييم «${e.title}»؟',
      confirmLabel: 'حذف',
    );
    if (!ok) return;
    store.deleteEvaluation(e.id);
    if (context.mounted) showAppSnack(context, 'تم حذف التقييم');
  }
}

/// رصد المعدل الشهري — المقابل لـ `MonthlyGrades.tsx` بواجهة الجوال.
class _MonthlyGradesPanel extends StatefulWidget {
  const _MonthlyGradesPanel();

  @override
  State<_MonthlyGradesPanel> createState() => _MonthlyGradesPanelState();
}

class _MonthlyGradesPanelState extends State<_MonthlyGradesPanel> {
  late String month;
  String roomId = '';
  final draft = <String, TextEditingController>{};
  bool busy = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    month = '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    for (final c in draft.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _clearDraft() {
    for (final c in draft.values) {
      c.dispose();
    }
    draft.clear();
  }

  TextEditingController _ctrl(String studentId, String? storedScore) {
    final existing = draft[studentId];
    if (existing != null) return existing;
    final c = TextEditingController(text: storedScore ?? '');
    draft[studentId] = c;
    return c;
  }

  Future<void> _pickMonth() async {
    final parts = month.split('-');
    final initial = DateTime(
      int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? DateTime.now().year,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      helpText: 'اختر الشهر',
    );
    if (picked == null) return;
    setState(() {
      month = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
      _clearDraft();
    });
  }

  Future<void> _save(AppStore store, List<Student> students, Map<String, Evaluation> saved) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final entries = <({String studentId, double? score})>[];
      for (final s in students) {
        final c = draft[s.id];
        if (c == null) continue;
        final raw = c.text.trim();
        final stored = saved[s.id];
        if (raw.isEmpty) {
          if (stored != null) entries.add((studentId: s.id, score: null));
          continue;
        }
        final score = double.tryParse(raw);
        if (score == null) continue;
        if (stored != null && stored.score == score.clamp(0, 100)) continue;
        entries.add((studentId: s.id, score: score));
      }
      final count = store.saveMonthlyAverages(month, entries);
      if (!mounted) return;
      setState(() {
        _clearDraft();
        message = count > 0 ? 'حُفظ $count' : 'بلا تغيير';
      });
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => message = '');
      });
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذر الحفظ', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _applyRewards(AppStore store, List<String> eligibleIds) async {
    if (busy || eligibleIds.isEmpty) return;
    final ok = await confirmSheet(
      context,
      title: 'تطبيق خصم التفوق',
      message: 'خصم تفوق لـ${eligibleIds.length} طالب على قسطهم القادم؟',
      confirmLabel: 'تنفيذ',
    );
    if (!ok) return;
    setState(() => busy = true);
    try {
      final r = store.applyMonthlyRewards(month, studentIds: eligibleIds);
      if (!mounted) return;
      final parts = <String>[
        'قُيّد ${r.applied}',
        if (r.noInstallment > 0) 'بلا قسط ${r.noInstallment}',
      ];
      setState(() => message = parts.join(' · '));
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => message = '');
      });
    } catch (e) {
      if (mounted) showAppSnack(context, '$e', error: true);
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
        final rules = store.gradingForViewedYear.monthlyDiscountRules;
        final rooms = [...store.roomsInViewedYear]
          ..sort((a, b) {
            final g = a.gradeLevel.compareTo(b.gradeLevel);
            return g != 0 ? g : a.name.compareTo(b.name);
          });
        final activeRoomId = rooms.any((r) => r.id == roomId)
            ? roomId
            : (rooms.isNotEmpty ? rooms.first.id : '');
        final room = store.roomById(activeRoomId);
        final students = room == null
            ? <Student>[]
            : (store.studentsOf(room).where((s) => s.status == 'active').toList()
              ..sort((a, b) => a.fullName.compareTo(b.fullName)));

        final saved = loadMonthlyAverages(store.evaluations, month);
        final rewarded = rewardedStudentIds(store.payments, month);

        final rows = [
          for (final s in students)
            () {
              final stored = saved[s.id];
              final ctrl = _ctrl(s.id, stored == null ? null : trimNum(stored.score));
              final value = ctrl.text.trim();
              final score = value.isEmpty ? null : double.tryParse(value);
              final percent = score == null ? 0.0 : rewardPercent(score, rules);
              final storedText = stored == null ? '' : trimNum(stored.score);
              final rowDirty = value != storedText;
              return (
                student: s,
                ctrl: ctrl,
                score: score,
                percent: percent,
                stored: stored,
                dirty: rowDirty,
              );
            }(),
        ];

        // إزالة متحكمات طلاب غادروا الشعبة/الشهر
        final liveIds = {for (final s in students) s.id};
        draft.removeWhere((id, c) {
          if (liveIds.contains(id)) return false;
          c.dispose();
          return true;
        });

        final dirty = rows.any((r) => r.dirty);
        final recorded = rows.where((r) => r.stored != null).length;
        final eligible = [
          for (final r in rows)
            if (r.percent > 0 && r.stored != null && !rewarded.contains(r.student.id)) r.student.id,
        ];
        final canSave = store.can('evaluations');
        final canReward = store.can('finance.discount');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Text(
                    'مرصود: $recorded / ${rows.length}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        message,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.success),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: busy ? null : _pickMonth,
                      borderRadius: BorderRadius.circular(Corner.field),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          prefixIcon: Icon(Icons.calendar_month_outlined, size: 18),
                          prefixIconConstraints: BoxConstraints(minWidth: 36),
                        ),
                        child: Text(
                          month,
                          style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AppDropdown<String>(
                      value: activeRoomId.isEmpty ? null : activeRoomId,
                      hint: 'الشعبة',
                      items: [
                        for (final r in rooms)
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              r.gradeLevel.isEmpty ? r.name : '${r.gradeLevel} — ${r.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (busy) return;
                        setState(() {
                          roomId = v ?? '';
                          _clearDraft();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (canSave)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SizedBox(
                  width: double.infinity,
                  height: controlHeight,
                  child: FilledButton(
                    onPressed: busy || !dirty ? null : () => _save(store, students, saved),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
                    ),
                    child: Text(busy ? '...' : 'حفظ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            Expanded(
              child: rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: EmptyState(message: 'لا طلاب في هذه الشعبة.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    r.student.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                      color: AppColors.heading,
                                    ),
                                  ),
                                ),
                                if (rewarded.contains(r.student.id))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: StatusChip.success('خُصم'),
                                  )
                                else if (r.percent > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: StatusChip.amber('خصم ${trimNum(r.percent)}%'),
                                  ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 72,
                                  height: 36,
                                  child: TextField(
                                    controller: r.ctrl,
                                    enabled: canSave && !busy,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                    ],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w700),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                      hintText: '0–100',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (rules.isNotEmpty && eligible.isNotEmpty && !dirty && canReward)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'مستحقو الخصم: ${eligible.length}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
                      ),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => _applyRewards(store, eligible),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
                      ),
                      child: const Text('تطبيق الخصم', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EvalCard extends StatelessWidget {
  const _EvalCard({
    required this.evaluation,
    required this.studentName,
    required this.subjectLine,
    this.onDelete,
  });

  final Evaluation evaluation;
  final String studentName;
  final String subjectLine;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final e = evaluation;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                    ),
                    if (subjectLine.isNotEmpty)
                      Text(subjectLine, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ],
                ),
              ),
              StatusChip.muted(e.typeLabel),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                SquareIconButton(
                  icon: Icons.delete_outline,
                  color: AppColors.danger,
                  bg: AppColors.dangerSoft,
                  border: AppColors.dangerBorder,
                  onTap: onDelete!,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    Text(
                      e.evaluationDate,
                      style: const TextStyle(color: AppColors.faint, fontSize: 10.5, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${trimNum(e.score)} / ${trimNum(e.maxScore)}',
                    style: TextStyle(
                      color: _tierColor(e.percent),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '${e.percent}%',
                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
          if (e.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.notes, style: const TextStyle(color: AppColors.faint, fontSize: 10.5, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

/// لون النسبة بثلاث درجات — مطابق لشارة النسبة في جدول Evaluations.tsx:
/// 85% فأكثر ممتاز، 50% فأكثر مقبول، وما دونها راسب.
Color _tierColor(int percent) {
  if (percent >= 85) return AppColors.success;
  if (percent >= 50) return AppColors.amber;
  return AppColors.danger;
}
