import 'package:flutter/material.dart';

import '../data/doc_export.dart';
import '../data/school_calendar.dart';
import '../data/store.dart';
import '../data/timetable_model.dart';
import '../data/timetable_print.dart';
import '../data/timetable_service.dart';
import '../data/timetable_solver.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'timetable_tabs.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// حالة شاشة الجداول ومنطقها — `useTimetable`.
class TimetableState extends ChangeNotifier {
  TimetableState(this.store) {
    store.addListener(_onStore);
    _recompute();
  }

  final AppStore store;
  TimetableRow? draft;
  TimetableRow? live;
  bool loading = true;
  bool failed = false;
  bool busy = false;

  String view = 'room';
  String _viewId = '';
  TimetableEntry? selectedEntry;
  Lesson? selectedLesson;
  final _undo = <List<TimetableEntry>>[];

  List<Classroom> rooms = const [];
  List<Teacher> teachers = const [];
  Map<String, Group> groupMap = const {};
  Map<String, String> _codes = const {};
  List<int> days = const [];
  TimetableSettings settings = TimetableSettings.fromMap(null);
  List<Lesson> lessons = const [];
  List<TimetableEntry> entries = const [];
  Map<String, int> placed = const {};

  TimetableRules get rules => draft?.rules ?? const TimetableRules({});
  PlanContext get ctx => PlanContext(groups: groupMap, rules: rules, settings: settings, days: days);
  bool get isPastYear => store.viewedAcademicYear?.isCurrent == false;
  bool get canUndo => _undo.isNotEmpty;
  bool get hasSelection => selectedEntry != null || selectedLesson != null;

  /// المسودة تختلف عن المعتمد.
  bool get unpublished {
    final d = draft;
    if (d == null) return false;
    final l = live;
    return l == null || entriesSignature(d.entries) != entriesSignature(l.entries);
  }

  String get currentId {
    if (_viewId.isNotEmpty) return _viewId;
    if (view == 'room') return rooms.firstOrNull?.id ?? '';
    return teachers.firstOrNull?.id ?? '';
  }

  String roomName(String id) {
    final r = rooms.where((x) => x.id == id).firstOrNull;
    return r == null ? '—' : [r.gradeLevel, r.name].where((s) => s.isNotEmpty).join(' ');
  }

  String roomCode(String id) => _codes[id] ?? '—';
  String teacherName(String id) => teachers.where((t) => t.id == id).firstOrNull?.name ?? 'بلا معلم';
  String teacherOfGroup(String groupId) => groupMap[groupId]?.teacherId ?? '';

  String subjectOf(String groupId) {
    final id = groupMap[groupId]?.subjectId ?? '';
    return store.subjects.where((s) => s.id == id).firstOrNull?.name ?? '—';
  }

  int remaining(Lesson l) {
    final left = l.count - (placed[lessonKeyOf(l.groupId, l.roomId)] ?? 0);
    return left < 0 ? 0 : left;
  }

  List<Lesson> get unplaced => lessons.where((l) => remaining(l) > 0).toList();

  void _onStore() {
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    rooms = [...store.roomsInViewedYear]..sort(compareSchoolRooms);
    teachers = [...store.teachingStaffInViewedYear]..sort((a, b) => a.name.compareTo(b.name));
    final groups = store.groupsInViewedYear.where((g) => g.status != 'archived').toList();
    groupMap = {for (final g in groups) g.id: g};
    _codes = roomCodes(rooms);
    days = schoolDays(store.settings.weekend);
    settings = TimetableSettings.fromMap(store.settings.extra['timetable']);
    lessons = buildLessons(groups, rooms);
    entries = draft == null ? const [] : pruneEntries(draft!.entries, lessons, days, settings);
    placed = placedCounts(entries);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  Future<void> load() async {
    loading = true;
    failed = false;
    notifyListeners();
    final found = await TimetableService.load(store.viewedAcademicYearId);
    loading = false;
    if (found == null) {
      failed = true;
    } else {
      draft = found.draft;
      live = found.live;
      _recompute();
    }
    notifyListeners();
  }

  void switchView(String next) {
    view = next;
    _viewId = '';
    clearSelection();
  }

  void setViewId(String id) {
    _viewId = id;
    clearSelection();
  }

  void clearSelection() {
    selectedEntry = null;
    selectedLesson = null;
    notifyListeners();
  }

  void selectEntry(TimetableEntry e) {
    selectedEntry = e;
    selectedLesson = null;
    notifyListeners();
  }

  void selectLesson(Lesson? l) {
    selectedEntry = null;
    selectedLesson = l;
    notifyListeners();
  }

  /// يرمي برسالة عند الفشل؛ الصلاحية في الكتابة لا في الزر.
  Future<void> commit(List<TimetableEntry> next, {bool undoable = true}) async {
    store.requireSection('timetable');
    final before = entries;
    draft = await TimetableService.saveDraft(
      tenantId: store.tenantId ?? '',
      yearId: store.viewedAcademicYearId,
      existing: draft,
      entries: next,
    );
    if (undoable) {
      _undo.add(before);
      if (_undo.length > 30) _undo.removeAt(0);
    }
    _recompute();
    notifyListeners();
  }

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    clearSelection();
    await commit(prev, undoable: false);
  }

  /// تعارضات وضع المختار في خانة؛ الحصة في الخانة تُبدَّل معه إن كانت للشعبة نفسها أو المعلم نفسه.
  ({List<Conflict> conflicts, TimetableEntry? swapWith}) moveConflicts(int day, int period) {
    final moving = selectedEntry;
    final lesson = selectedLesson;
    if (moving == null && lesson == null) return (conflicts: const [], swapWith: null);
    final roomId = moving?.roomId ?? lesson!.roomId;
    final groupId = moving?.groupId ?? lesson!.groupId;
    final teacher = teacherOfGroup(groupId);
    // في عرض المعلم الخانة قد تحمل حصته في شعبة أخرى: تُبدَّل وقتاً بوقت
    final target = entries
        .where((e) => e.day == day && e.period == period && (e.roomId == roomId || (teacher.isNotEmpty && teacherOfGroup(e.groupId) == teacher)))
        .firstOrNull;
    if (moving != null && target != null && target.same(moving)) return (conflicts: const [], swapWith: null);
    if (target != null && target.locked) return (conflicts: [Conflict('room_busy', groupId: target.groupId)], swapWith: null);
    final ignore = <TimetableEntry>{if (moving != null) moving, if (target != null) target};
    final conflicts = conflictsAt(ctx, entries, roomId, groupId, day, period, ignore: ignore);
    if (target != null) {
      if (moving == null) return (conflicts: [Conflict('room_busy', groupId: target.groupId)], swapWith: null);
      // الحصة المبدَّلة تذهب إلى خانة المختار
      final back = conflictsAt(ctx, entries, target.roomId, target.groupId, moving.day, moving.period, ignore: ignore);
      return (conflicts: [...conflicts, ...back], swapWith: target);
    }
    return (conflicts: conflicts, swapWith: null);
  }

  String reasons(List<Conflict> list) => list.map((c) => conflictText(c, room: roomName, subject: subjectOf)).join('، ');

  /// يعيد نص المانع إن وُجد.
  Future<String?> dropAt(int day, int period) async {
    final moving = selectedEntry;
    final lesson = selectedLesson;
    if (moving == null && lesson == null) return null;
    final r = moveConflicts(day, period);
    if (r.conflicts.isNotEmpty) return reasons(r.conflicts);
    final swap = r.swapWith;
    final List<TimetableEntry> next;
    if (moving != null) {
      next = [
        for (final e in entries)
          if (e.same(moving))
            moving.copyWith(day: day, period: period)
          else if (swap != null && e.same(swap))
            e.copyWith(day: moving.day, period: moving.period)
          else
            e,
      ];
    } else {
      next = [...entries, TimetableEntry(lesson!.roomId, day, period, lesson.groupId)];
    }
    selectedEntry = null;
    selectedLesson = null;
    await commit(next);
    return null;
  }

  Future<void> toggleLock(TimetableEntry entry) async {
    selectedEntry = null;
    await commit([for (final e in entries) e.same(entry) ? e.copyWith(locked: !e.locked) : e]);
  }

  Future<void> removeEntry(TimetableEntry entry) async {
    selectedEntry = null;
    await commit([
      for (final e in entries)
        if (!e.same(entry)) e,
    ]);
  }

  Future<void> saveRules(TimetableRules next) async {
    store.requireSection('timetable');
    draft = await TimetableService.saveDraft(
      tenantId: store.tenantId ?? '',
      yearId: store.viewedAcademicYearId,
      existing: draft,
      rules: next,
    );
    _recompute();
    notifyListeners();
  }

  Future<void> saveBell(TimetableSettings next) async {
    store.requireSection('timetable');
    await store.writeSchoolOption({'timetable': next.toJson()});
  }

  void setPeriods(String groupId, int? n) {
    store.requireSection('timetable');
    store.setGroupWeeklyPeriods(groupId, n);
  }

  Future<void> publish() async {
    store.requireSection('timetable');
    final d = draft;
    if (d == null) throw StoreException('لا جدول للاعتماد');
    busy = true;
    notifyListeners();
    try {
      final done = await TimetableService.publish(
        tenantId: store.tenantId ?? '',
        draft: d,
        live: live,
        actor: store.deviceUser?.name ?? 'الإدارة',
      );
      draft = done.draft;
      live = done.live;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  TimetableDoc doc() => TimetableDoc(
        institution: store.institutionName,
        logo: store.institutionLogo,
        year: store.viewedAcademicYear?.label == null ? '' : 'العام ${store.viewedAcademicYear!.label}',
        settings: settings,
        days: days,
        entries: entries,
        rules: rules,
        roomIds: [for (final r in rooms) r.id],
        roomName: roomName,
        roomCode: roomCode,
        teacherName: teacherName,
        subjectOf: subjectOf,
        teacherOfGroup: teacherOfGroup,
      );
}

/// الجداول: الجدول الأسبوعي وتحريره، الاحتياط، الحصص، والقيود — `Timetable`.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  TimetableState? _f;
  String tab = 'grid';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_f == null) {
      _f = TimetableState(StoreScope.of(context));
      WidgetsBinding.instance.addPostFrameCallback((_) => _f?.load());
    }
  }

  @override
  void dispose() {
    _f?.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() work, String fallback) async {
    try {
      await work();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, fallback), error: true);
    }
  }

  Future<void> _print(String kind, List<String> ids, String title) async {
    final doc = _f!.doc();
    await runBusyOp(context, () async {
      final bytes = await buildTimetablePdf(doc, kind, ids, title);
      if (!mounted) return;
      if (bytes == null) {
        showAppSnack(context, 'تعذّر إعداد الجدول', error: true);
        return;
      }
      DocExport.showActions(context, bytes, title);
    }, message: 'جارٍ التجهيز...');
  }

  void _menu(String v, List<String> teacherIds) {
    final f = _f!;
    switch (v) {
      case 'one':
        final title = 'جدول ${f.view == 'room' ? f.roomName(f.currentId) : f.teacherName(f.currentId)}';
        _print(f.view, [f.currentId], title);
      case 'rooms':
        _print('room', [for (final r in f.rooms) r.id], 'جداول الشعب');
      case 'teachers':
        _print('teacher', teacherIds, 'جداول المعلمين');
      case 'master':
        _print('master', teacherIds, 'الجدول العام');
      case 'xlsx':
        _guard(() => DocExport.download(context, buildTimetableXlsx(f.doc(), teacherIds), 'الجدول المدرسي.xlsx', mime: _xlsxMime), 'تعذّر التنزيل');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _f!;
    return ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        final teacherIds = [
          for (final t in f.teachers)
            if (f.entries.any((e) => f.teacherOfGroup(e.groupId) == t.id)) t.id,
        ];
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            titleSpacing: 0,
            title: const Text('الجداول'),
            actions: [
              IconButton(
                tooltip: 'الأوقات',
                icon: const Icon(Icons.schedule_rounded),
                onPressed: () => showBellSheet(context, f),
              ),
              if (tab == 'grid' && f.entries.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'طباعة',
                  icon: const Icon(Icons.print_outlined),
                  onSelected: (v) => _menu(v, teacherIds),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'one', child: Text(f.view == 'room' ? 'هذه الشعبة' : 'هذا المعلم')),
                    const PopupMenuItem(value: 'rooms', child: Text('كل الشعب')),
                    const PopupMenuItem(value: 'teachers', child: Text('كل المعلمين')),
                    const PopupMenuItem(value: 'master', child: Text('الجدول العام')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'xlsx', child: Text('Excel')),
                  ],
                ),
            ],
          ),
          body: f.loading
              ? const Center(child: AppLoader(compact: true))
              : f.failed
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: NoonOffline(what: 'الجداول', onRetry: f.load)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                          child: NoonSegment<String>(
                            value: tab,
                            options: const [('grid', 'الجدول'), ('covers', 'الاحتياط'), ('load', 'الحصص'), ('rules', 'القيود')],
                            onChanged: (v) => setState(() => tab = v),
                          ),
                        ),
                        if (tab == 'grid')
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                            child: Row(
                              children: [
                                if (f.draft != null)
                                  Text(
                                    f.live != null && !f.unpublished ? 'معتمد' : 'غير معتمد',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: f.live != null && !f.unpublished ? AppColors.success : const Color(0xFF475569),
                                    ),
                                  ),
                                const Spacer(),
                                GhostButton(
                                  label: 'توليد',
                                  icon: Icons.auto_fix_high_rounded,
                                  onPressed: f.isPastYear ? null : () => showGenerateSheet(context, f),
                                ),
                                const SizedBox(width: 6),
                                PrimaryButton(
                                  label: 'اعتماد',
                                  busy: f.busy,
                                  onPressed: f.isPastYear || f.draft == null || !f.unpublished
                                      ? null
                                      : () => _guard(() async {
                                            await f.publish();
                                            if (mounted) showAppSnack(context, 'اعتُمد الجدول');
                                          }, 'تعذّر الاعتماد'),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: switch (tab) {
                            'covers' => CoversTab(f: f),
                            'load' => LoadTab(f: f),
                            'rules' => RulesTab(f: f),
                            _ => GridTab(f: f),
                          },
                        ),
                      ],
                    ),
        );
      },
    );
  }
}

/// «توليد»: فحص فوري يكشف المستحيل، ثم المولِّد على شرائح بتقدّم وإيقاف. الناتج لا يُكتب حتى
/// «تطبيق»، والمثبَّت يبقى مكانه — `GenerateModal`.
Future<void> showGenerateSheet(BuildContext context, TimetableState f) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      builder: (_) => _GenerateSheet(f: f),
    );

class _GenerateSheet extends StatefulWidget {
  const _GenerateSheet({required this.f});

  final TimetableState f;

  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  var seed = 1;
  SolverRun? run;
  SolverResult? result;
  var running = false;
  late final SolverInput input = _input();
  late final List<SolverIssue> issues = precheck(input);

  SolverInput _input() {
    final f = widget.f;
    return toSolverInput(
      days: f.days,
      settings: f.settings,
      rules: f.rules,
      rooms: f.rooms,
      teachers: f.teachers,
      lessons: f.lessons,
      entries: f.entries,
      seed: 1,
    );
  }

  int get total => input.lessons.fold<int>(0, (n, l) => n + l.count);

  String _targetName(SolverIssue i) => switch (i.kind) {
        'CLASS_FULL' => widget.f.roomName(i.targetId),
        'TEACHER_FULL' => widget.f.teacherName(i.targetId),
        'FACILITY' => '${widget.f.rules.facilities.where((x) => x['id'] == i.targetId).firstOrNull?['name'] ?? '—'}',
        _ => widget.f.subjectOf(i.targetId),
      };

  Future<void> _start(int nextSeed) async {
    final r = SolverRun(input.withSeed(nextSeed));
    setState(() {
      seed = nextSeed;
      run = r;
      result = null;
      running = true;
    });
    // شرائح قصيرة تترك للواجهة وقتها
    await Future<void>.delayed(const Duration(milliseconds: 16));
    while (mounted && !r.step(24)) {
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    if (!mounted) return;
    setState(() {
      result = r.result();
      running = false;
    });
  }

  Future<void> _apply() async {
    final done = result;
    if (done == null) return;
    try {
      await widget.f.commit(fromSolverResult(done));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final done = result;
    final placedCount = done != null ? done.entries.length : run?.placed ?? 0;
    return PopScope(
      canPop: !running,
      child: NoonSheetFrame(
        title: 'توليد',
        footer: [
          if (running)
            Expanded(child: GhostButton(label: 'إيقاف', onPressed: () => run?.stop()))
          else if (done != null) ...[
            GhostButton(label: 'مرة أخرى', onPressed: () => _start(seed + 1)),
            const SizedBox(width: 8),
            Expanded(child: PrimaryButton(label: 'تطبيق', expand: true, onPressed: done.entries.isEmpty ? null : _apply)),
          ] else ...[
            GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context)),
            const SizedBox(width: 8),
            Expanded(child: PrimaryButton(label: 'توليد', expand: true, onPressed: total == 0 ? null : () => _start(seed))),
          ],
        ],
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          if (total == 0) const Text('أدخل حصص المواد أولاً', style: TextStyle(fontSize: 13)),
          if (issues.isNotEmpty) ...[
            const Text('لن يكتمل الجدول', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF475569))),
            const SizedBox(height: 4),
            for (final i in issues.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('${_targetName(i)}: ${i.need} > ${i.have} · ${issueLabels[i.kind] ?? ''}', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
          ],
          if (running || done != null) ...[
            Row(
              children: [
                const Expanded(child: Text('الموضوع', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                Text('$placedCount / $total', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: total == 0 ? 0 : (placedCount / total).clamp(0, 1).toDouble()),
            const SizedBox(height: 10),
          ],
          if (done != null && done.unplaced.isNotEmpty) ...[
            const Text('لم توضع', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
            const SizedBox(height: 4),
            for (final u in done.unplaced)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('${f.subjectOf(u.groupId)} · ${f.roomName(u.roomId)} (${u.count}) — ${u.detail}', style: const TextStyle(fontSize: 12)),
              ),
          ],
          if (done != null && done.unplaced.isEmpty)
            const Text('اكتمل الجدول', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }
}

/// الأوقات: الحصص بأوقاتها، الاستراحة، يوم أقصر، وحد الاحتياط — `BellModal`.
Future<void> showBellSheet(BuildContext context, TimetableState f) async {
  var periods = [...f.settings.periods];
  var breaks = [...f.settings.breaksAfter];
  final dayPeriods = {...f.settings.dayPeriods};
  var coverMax = f.settings.coverDailyMax;

  Future<String?> pick(BuildContext ctx, String value) async {
    final p = value.split(':');
    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (t == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  await showNoonSheet<void>(
    context,
    title: 'الأوقات',
    body: (ctx, setSheet) {
      final count = periods.length;
      return [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(width: 58, child: Text('الحصة ${i + 1}', style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                TextButton(
                  onPressed: () async {
                    final v = await pick(ctx, periods[i].start);
                    if (v != null) setSheet(() => periods[i] = BellPeriod(v, periods[i].end));
                  },
                  child: Text(periods[i].start, textDirection: TextDirection.ltr),
                ),
                TextButton(
                  onPressed: () async {
                    final v = await pick(ctx, periods[i].end);
                    if (v != null) setSheet(() => periods[i] = BellPeriod(periods[i].start, v));
                  },
                  child: Text(periods[i].end, textDirection: TextDirection.ltr),
                ),
                if (i < count - 1)
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('استراحة', style: TextStyle(fontSize: 11.5)),
                      value: breaks.contains(i + 1),
                      onChanged: (_) => setSheet(() {
                        breaks = breaks.contains(i + 1)
                            ? breaks.where((n) => n != i + 1).toList()
                            : ([...breaks, i + 1]..sort());
                      }),
                    ),
                  )
                else ...[
                  const Spacer(),
                  if (count > 1)
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.danger),
                      onPressed: () => setSheet(() => periods = periods.sublist(0, count - 1)),
                    ),
                ],
              ],
            ),
          ),
        if (count < 12)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 17),
              label: const Text('حصة'),
              onPressed: () => setSheet(() {
                final start = periods.isEmpty ? '07:30' : periods.last.end;
                periods = [...periods, BellPeriod(start, addMinutes(start, 45))];
              }),
            ),
          ),
        const Divider(),
        const Text('حصص اليوم', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            for (final d in f.days)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dayNames[d], style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  DropdownButton<int>(
                    isDense: true,
                    value: (dayPeriods['$d'] ?? count).clamp(1, count).toInt(),
                    items: [
                      for (var n = 1; n <= count; n++) DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (n) => setSheet(() {
                      if (n == null || n >= count) {
                        dayPeriods.remove('$d');
                      } else {
                        dayPeriods['$d'] = n;
                      }
                    }),
                  ),
                ],
              ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            const Expanded(child: Text('حد الاحتياط اليومي', style: TextStyle(fontSize: 13))),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: coverMax <= 0 ? null : () => setSheet(() => coverMax--),
            ),
            Text('$coverMax'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: coverMax >= 8 ? null : () => setSheet(() => coverMax++),
            ),
          ],
        ),
          ],
        ),
      ];
    },
    footer: (ctx, _) => [
      Expanded(
        child: PrimaryButton(
          label: 'حفظ',
          expand: true,
          onPressed: f.isPastYear
              ? null
              : () async {
                  final raw = TimetableSettings(
                    periods: periods,
                    breaksAfter: breaks,
                    dayPeriods: dayPeriods,
                    coverDailyMax: coverMax,
                  ).toJson();
                  try {
                    await f.saveBell(TimetableSettings.fromMap(raw));
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) showAppSnack(ctx, userMessage(e, 'تعذّر الحفظ'), error: true);
                  }
                },
        ),
      ),
    ],
  );
}
