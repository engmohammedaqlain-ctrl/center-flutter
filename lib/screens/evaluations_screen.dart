import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/academic_matching.dart';
import '../data/grading.dart';
import '../data/monthly_averages.dart';
import '../data/store.dart';
import '../data/arabic_search.dart';
import '../models/models.dart';
import 'report_cards_sheet.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/animated_count.dart';
import '../widgets/list_paging.dart';
import '../widgets/table_gate.dart';
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
  int listVisible = kListPageSize;
  String roomFilter = 'all';
  String groupId = 'all';
  String type = 'all';
  /// فلتر الفصل الدراسي — مطابق لـ `selectedTerm` في الويب.
  String termFilter = 'all';

  /// ترتيب طلاب المادة: أبجدي افتراضياً، أو بالنتيجة من الأعلى.
  bool sortByResult = false;

  /// يُفتح على شعبة واحدة (أول صف وأول شعبة) وعلى الفصل الحالي مرة واحدة، لا على كل الكشوف.
  bool _scopeReady = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return TableGate(
      tables: const ['student_evaluations', 'rooms', 'students', 'groups'],
      message: 'جارٍ تحميل الدرجات...',
      child: ListenableBuilder(
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
      ),
    );
  }

  /// النمط الموزون: التقييمات مجموعة بموادها كجدول الويب، لكن بعمقٍ يناسب
  /// الجوال — المادة تُفتح فتُظهر طلابها بمعدل كلٍّ منهم، والطالب يُفتح فتظهر
  /// درجاته فيها. الجدول العريض لا يُقرأ على شاشة هاتف.
  Widget _weightedBody(AppStore store) {
    final q = search.text.trim().toLowerCase();
    final rooms = store.roomsInViewedYear;
    // الصفوف بترتيب الإعدادات، ثم ما في السجلات وليس فيها
    final options = store.gradeOptions;
    int gradeRank(String g) {
      final i = options.indexWhere((x) => isSameGrade(x, g));
      return i < 0 ? options.length : i;
    }

    final grades = <String>{
      for (final r in rooms)
        if (r.gradeLevel.trim().isNotEmpty) r.gradeLevel.trim(),
      for (final s in store.studentsInViewedYear)
        if (s.gradeLevel.trim().isNotEmpty) s.gradeLevel.trim(),
    }.toList()
      ..sort((a, b) {
        final byRank = gradeRank(a).compareTo(gradeRank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    List<Classroom> roomsOf(String grade) => rooms.where((r) => isSameGrade(r.gradeLevel, grade)).toList();

    if (!_scopeReady && grades.isNotEmpty) {
      _scopeReady = true;
      gradeFilter = grades.first;
      roomFilter = roomsOf(grades.first).firstOrNull?.id ?? 'all';
      termFilter = termForDate(isoDate(DateTime.now()), term2Start: store.viewedAcademicYear?.term2Start);
    }

    // شعبة كل طالب: طالب معروفة شعبته يُحكم بها، فلا يظهر طلاب شعبة أخرى من مادة مشتركة
    final roomOfStudent = <String, String>{
      for (final s in store.studentsInViewedYear)
        if (s.section.trim().isNotEmpty)
          if (rooms.where((r) => studentBelongsToRoom(s, r)).firstOrNull case final r?) s.id: r.id,
    };

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
        final studentRoom = roomOfStudent[e.studentId];
        if (studentRoom != null ? studentRoom != roomFilter : !(group != null && group.includesRoom(roomFilter))) {
          return false;
        }
      }
      if (groupId != 'all' && e.groupId != groupId) return false;
      if (type != 'all' && e.type != type) return false;
      // تقييم بلا فصل يبقى ظاهراً في كل الفصول
      if (termFilter != 'all' && e.term.isNotEmpty && e.term != termFilter) return false;
      if (q.isEmpty) return true;
      final name = (student?.fullName ?? '').toLowerCase();
      return name.contains(q) || e.title.toLowerCase().contains(q);
    }).toList();

    // المواد بترتيب أسمائها، وطلاب كل مادة بترتيب أسمائهم
    final byGroup = <String, List<Evaluation>>{};
    for (final e in list) {
      byGroup.putIfAbsent(e.groupId, () => []).add(e);
    }
    String groupTitle(String id) {
      final g = store.groupById(id);
      if (g == null) return 'بلا مادة';
      final subject = store.subjectName(g.subjectId);
      return subject.isNotEmpty && subject != 'غير محدد' ? subject : g.name;
    }

    // المواد بترتيب صفوفها كما في الإعدادات، ثم بأسمائها
    final groupIds = byGroup.keys.toList()
      ..sort((a, b) {
        final byGrade = gradeRank(store.groupById(a)?.gradeLevel ?? '').compareTo(gradeRank(store.groupById(b)?.gradeLevel ?? ''));
        return byGrade != 0 ? byGrade : compareArabicNames(groupTitle(a), groupTitle(b));
      });
    final classSelected = gradeFilter != 'all' || roomFilter != 'all';

    final activeFilters =
        [gradeFilter, roomFilter, groupId, termFilter, type].where((v) => v != 'all').length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الدرجات والتقييمات'),
        actions: [
          // شهادات الصف أو الشعبة المختارة دفعة واحدة، أو كشف نتائجها بالترتيب
          PopupMenuButton<bool>(
            tooltip: classSelected ? 'الشهادات' : 'اختر الصف أو الشعبة أولاً',
            enabled: classSelected,
            icon: const Icon(Icons.workspace_premium_outlined),
            onSelected: (summary) => openClassReportCards(
              context,
              store,
              roomId: roomFilter == 'all' ? null : roomFilter,
              grade: gradeFilter == 'all' ? '' : gradeFilter,
              summary: summary,
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('شهادات الصف')),
              PopupMenuItem(value: true, child: Text('كشف النتائج')),
            ],
          ),
          // إقفال العلامات بعد تسليم الشهادات: المدير يضبطه، وغيره يراه
          if (store.isAdminUser || store.settings.gradesLockedUntil.isNotEmpty)
            IconButton(
              tooltip: store.settings.gradesLockedUntil.isEmpty
                  ? 'إقفال العلامات'
                  : 'العلامات مقفلة حتى ${store.settings.gradesLockedUntil}',
              icon: Icon(
                store.settings.gradesLockedUntil.isEmpty ? Icons.lock_open_outlined : Icons.lock_outline,
                color: store.settings.gradesLockedUntil.isEmpty ? null : const Color(0xFFF2C14E),
              ),
              onPressed: store.isAdminUser ? () => _editGradesLock(context, store) : null,
            ),
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
      body: Material(
        color: AppColors.bg,
        child: ThumbActionLayer(
          action: store.can('evaluations')
              ? ThumbAction(
                  label: 'رصد درجات',
                  icon: Icons.add,
                  color: AppColors.navy,
                  noon: true,
                  onPressed: () => _record(context, store),
                )
              : null,
          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SearchField(
                            controller: search,
                            hint: 'اسم الطالب أو عنوان التقييم',
                            onChanged: (_) => setState(() => listVisible = kListPageSize),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterButton(
                          count: activeFilters,
                          onTap: () => _openFilters(
                            store,
                            grades: grades,
                            rooms: rooms,
                            groups: groups,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (store.settings.gradesLockedUntil.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFF8E6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    store.isAdminUser
                        ? 'العلامات حتى ${store.settings.gradesLockedUntil.split('-').reversed.join('/')} مقفلة على غير المدير'
                        : gradeLockMessage(store.settings.gradesLockedUntil),
                    style: const TextStyle(color: Color(0xFF6B4A00), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: AdminHero(
                    icon: Icons.workspace_premium_outlined,
                    label: 'معدل الكشوف',
                    value: '${(list.fold<int>(0, (a, e) => a + e.percent) / list.length).round()}',
                    unit: '%',
                    chips: ['${groupIds.length} كشف', '${list.length} علامة'],
                  ),
                ),
              Expanded(
                child: groupIds.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: EmptyState(message: 'لا توجد تقييمات مرصودة مطابقة للبحث.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, thumbActionClearance),
                        itemCount: listPage(groupIds, listVisible).length +
                            (listVisible < groupIds.length ? 1 : 0),
                        itemBuilder: (context, i) {
                          final page = listPage(groupIds, listVisible);
                          if (i >= page.length) {
                            return LoadMoreButton(
                              shown: page.length,
                              total: groupIds.length,
                              onMore: () => setState(() => listVisible += kListPageSize),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _GroupSection(
                              title: groupTitle(page[i]),
                              group: store.groupById(page[i]),
                              evaluations: byGroup[page[i]]!,
                              sortByResult: sortByResult,
                              onDelete: store.canEditGrades ? (e) => _delete(context, store, e) : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// فلاتر الشاشة في ورقة واحدة: المرحلة والشعبة والمادة والفصل والنوع.
  Future<void> _openFilters(
    AppStore store, {
    required List<String> grades,
    required List<Classroom> rooms,
    required List<Group> groups,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void pick(VoidCallback change) {
            setState(() {
              change();
              listVisible = kListPageSize;
            });
            setSheet(() {});
          }

          Widget group(String title, Map<String, String> options, String value, ValueChanged<String> onPick) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final e in options.entries)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: _ChoicePill(
                              label: e.value,
                              selected: e.key == value,
                              onTap: () => pick(() => onPick(e.key)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(child: Text('تصفية', style: AppText.cardTitle.copyWith(fontSize: 16))),
                        TextButton(
                          onPressed: () => pick(() {
                            gradeFilter = 'all';
                            roomFilter = 'all';
                            groupId = 'all';
                            type = 'all';
                            termFilter = 'all';
                          }),
                          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                          child: const Text('إعادة الضبط', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      children: [
                        // الصف والشعبة بقائمة واحدة: الشعبة تحت صفها
                        group(
                          'الصف',
                          {
                            'all': 'كل الصفوف',
                            for (final g in grades) ...{
                              if (rooms.where((r) => isSameGrade(r.gradeLevel, g)).length != 1)
                                'grade:$g': rooms.any((r) => isSameGrade(r.gradeLevel, g)) ? '$g - كل الشعب' : g,
                              for (final r in rooms.where((r) => isSameGrade(r.gradeLevel, g))) r.id: '$g - ${r.name}',
                            },
                            for (final r in rooms.where((r) => r.gradeLevel.trim().isEmpty)) r.id: r.name,
                          },
                          roomFilter != 'all' ? roomFilter : (gradeFilter != 'all' ? 'grade:$gradeFilter' : 'all'),
                          (v) {
                            final room = rooms.where((r) => r.id == v).firstOrNull;
                            gradeFilter = room != null
                                ? (room.gradeLevel.trim().isEmpty ? 'all' : room.gradeLevel.trim())
                                : (v.startsWith('grade:') ? v.substring(6) : 'all');
                            roomFilter = room?.id ?? 'all';
                            groupId = 'all';
                          },
                        ),
                        group(
                          'المادة',
                          {'all': 'الكل', for (final g in groups) g.id: g.name},
                          groups.any((g) => g.id == groupId) ? groupId : 'all',
                          (v) => groupId = v,
                        ),
                        group(
                          'الفصل',
                          {
                            'all': 'كل الفصول',
                            for (final e in gradingTermLabels.entries) e.key: e.value,
                          },
                          termFilter,
                          (v) => termFilter = v,
                        ),
                        group(
                          'النوع',
                          {'all': 'الكل', for (final e in evaluationTypeNames.entries) e.key: e.value},
                          type,
                          (v) => type = v,
                        ),
                        group(
                          'ترتيب الطلاب',
                          const {'name': 'أبجدي', 'result': 'حسب النتيجة'},
                          sortByResult ? 'result' : 'name',
                          (v) => sortByResult = v == 'result',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: PrimaryButton(label: 'تم', expand: true, height: 46, onPressed: () => Navigator.pop(ctx)),
                  ),
                ],
              ),
            ),
          );
        },
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
    try {
      store.deleteEvaluation(e.id);
    } on StoreException catch (err) {
      if (context.mounted) showAppSnack(context, err.message, error: true);
      return;
    }
    if (context.mounted) showAppSnack(context, 'تم حذف التقييم');
  }

  /// إقفال العلامات حتى تاريخ، أو فتحها — للمدير.
  Future<void> _editGradesLock(BuildContext context, AppStore store) async {
    final current = store.settings.gradesLockedUntil;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'كل علامة بتاريخ اختبار حتى اليوم المختار لا يرصدها ولا يعدّلها ولا يحذفها إلا المدير، ولا المعلم من بوابته.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(current.isEmpty ? 'إقفال العلامات حتى تاريخ…' : 'تغيير تاريخ الإقفال ($current)'),
              onTap: () => Navigator.pop(sheet, 'lock'),
            ),
            if (current.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: const Text('فتح التعديل'),
                onTap: () => Navigator.pop(sheet, 'open'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    var date = '';
    if (choice == 'lock') {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(current) ?? now,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 2),
        helpText: 'إقفال العلامات حتى',
      );
      if (picked == null) return;
      date = isoDate(picked);
    }
    try {
      await store.setGradesLockedUntil(date);
      if (context.mounted) showAppSnack(context, date.isEmpty ? 'فُتح تعديل العلامات' : 'أُقفلت العلامات حتى $date');
    } on StoreException catch (err) {
      if (context.mounted) showAppSnack(context, err.message, error: true);
    }
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
  int rosterVisible = kListPageSize;

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
      rosterVisible = kListPageSize;
    });
  }

  Future<void> _save(AppStore store, List<Student> students, Map<String, Evaluation> saved) async {
    if (busy) return;
    setState(() => busy = true);
    await yieldUi(2);
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
    await yieldUi(2);
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
              ..sort((a, b) => compareArabicNames(a.fullName, b.fullName)));

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
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.success),
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
                          rosterVisible = kListPageSize;
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
                    child: Text(busy ? '...' : 'حفظ', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      itemCount: listPage(rows, rosterVisible).length +
                          (rosterVisible < rows.length ? 1 : 0),
                      itemBuilder: (_, i) {
                        final page = listPage(rows, rosterVisible);
                        if (i >= page.length) {
                          return LoadMoreButton(
                            shown: page.length,
                            total: rows.length,
                            onMore: () => setState(() => rosterVisible += kListPageSize),
                          );
                        }
                        final r = page[i];
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
                                      fontWeight: FontWeight.w600,
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
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.heading),
                      ),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => _applyRewards(store, eligible),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
                      ),
                      child: const Text('تطبيق الخصم', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
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

/// مادة في كشف الدرجات: رأسها معدلها وعدد طلابها، وتُفتح فتُظهر طلابها.
class _GroupSection extends StatefulWidget {
  const _GroupSection({
    required this.title,
    required this.group,
    required this.evaluations,
    this.sortByResult = false,
    this.onDelete,
  });

  final String title;
  final Group? group;
  final List<Evaluation> evaluations;

  /// الطلاب بالنتيجة من الأعلى بدل الأبجدي.
  final bool sortByResult;
  final void Function(Evaluation)? onDelete;

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  bool open = false;
  int visibleCount = kListPageSize;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final g = widget.group;

    // طلاب المادة بترتيب أسمائهم، ولكلٍّ معدله فيها
    final byStudent = <String, List<Evaluation>>{};
    for (final e in widget.evaluations) {
      byStudent.putIfAbsent(e.studentId, () => []).add(e);
    }
    int averageOf(List<Evaluation> rows) =>
        rows.isEmpty ? 0 : (rows.fold<int>(0, (a, e) => a + e.percent) / rows.length).round();
    final students = byStudent.keys.toList()
      ..sort((a, b) {
        if (widget.sortByResult) {
          final byResult = averageOf(byStudent[b]!).compareTo(averageOf(byStudent[a]!));
          if (byResult != 0) return byResult;
        }
        return compareArabicNames(store.studentById(a)?.fullName, store.studentById(b)?.fullName);
      });
    final visibleStudents = listPage(students, visibleCount);
    final average = averageOf(widget.evaluations);

    final meta = [
      if (g != null && g.gradeLevel.trim().isNotEmpty) g.gradeLevel.trim(),
      if (g != null && g.teacherId.isNotEmpty) store.teacherName(g.teacherId),
      '${students.length} طالب',
    ].where((s) => s.isNotEmpty && s != 'غير محدد').join('  ·  ');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 8, 11),
              child: Row(
                children: [
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
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.faint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$average%',
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: _tierColor(average),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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
                    decoration: const BoxDecoration(
                      color: AppColors.sunken,
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < visibleStudents.length; i++)
                          _StudentRow(
                            name: store.studentById(visibleStudents[i])?.fullName ?? 'طالب محذوف',
                            rows: byStudent[visibleStudents[i]]!,
                            percent: averageOf(byStudent[visibleStudents[i]]!),
                            last: i == visibleStudents.length - 1 && visibleStudents.length >= students.length,
                            subject: widget.title,
                            onDelete: widget.onDelete,
                          ),
                        if (visibleStudents.length < students.length)
                          LoadMoreButton(
                            shown: visibleStudents.length,
                            total: students.length,
                            onMore: () => setState(() => visibleCount += kListPageSize),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// طالب داخل المادة: اسمه ومعدله، ولمسه يفتح درجاته فيها.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.name,
    required this.rows,
    required this.percent,
    required this.last,
    required this.subject,
    this.onDelete,
  });

  final String name;
  final List<Evaluation> rows;
  final int percent;
  final bool last;
  final String subject;
  final void Function(Evaluation)? onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showStudentGrades(context, name: name, subject: subject, rows: rows, onDelete: onDelete),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.hover)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text('${rows.length} تقييم', style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
                ],
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontFamily: AppText.family,
                color: _tierColor(percent),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

/// درجات طالب في مادة: لكل تقييم عنوانه ودرجته من أصلها ونسبته، ونوعه وتاريخه.
Future<void> _showStudentGrades(
  BuildContext context, {
  required String name,
  required String subject,
  required List<Evaluation> rows,
  void Function(Evaluation)? onDelete,
}) {
  final sorted = [...rows]..sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
  final store = StoreScope.of(context);
  final lock = store.myGradesLock;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subject, style: const TextStyle(color: AppColors.faint, fontSize: 11.5)),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sorted.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.hover, indent: 20, endIndent: 20),
                itemBuilder: (context, i) {
                  final e = sorted[i];
                  return Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [e.typeLabel, if (e.evaluationDate.isNotEmpty) e.evaluationDate]
                                    .where((s) => s.isNotEmpty)
                                    .join('  ·  '),
                                style: const TextStyle(color: AppColors.faint, fontSize: 10.5),
                              ),
                              // من رصد العلامة ومن عدّلها (العلامات قبل التحديث بلا اسم)
                              if (e.recordedBy.isNotEmpty || e.updatedBy.isNotEmpty)
                                Text(
                                  [
                                    if (e.recordedBy.isNotEmpty) 'رصدها ${e.recordedBy}',
                                    if (e.updatedBy.isNotEmpty && e.updatedBy != e.recordedBy) 'عدّلها ${e.updatedBy}',
                                  ].join('  ·  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.faint, fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          // تعديل العلامة بلمسها — كنقر الخلية في كشف الويب
                          onTap: store.canEditGrades && !isGradeLocked(e.evaluationDate, lock)
                              ? () async {
                                  final value = await _askScore(ctx, e);
                                  if (value == null || value == e.score) return;
                                  try {
                                    store.updateEvaluationScore(e.id, value);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (context.mounted) showAppSnack(context, 'عُدّلت العلامة');
                                  } on StoreException catch (err) {
                                    if (ctx.mounted) showAppSnack(ctx, err.message, error: true);
                                  }
                                }
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${trimNum(e.score)} / ${trimNum(e.maxScore)}',
                                style: TextStyle(
                                  fontFamily: AppText.family,
                                  color: _tierColor(e.percent),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text('${e.percent}%', style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
                            ],
                          ),
                        ),
                        if (onDelete != null && !isGradeLocked(e.evaluationDate, lock))
                          IconButton(
                            tooltip: 'حذف',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                            onPressed: () {
                              Navigator.pop(ctx);
                              onDelete(e);
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// زرّ التصفية الموحّد: أيقونة وعدد الفلاتر المفعّلة عليها.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    return Tooltip(
      message: 'تصفية',
      child: PressableScale(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: controlHeight,
              height: controlHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.amberSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(Corner.field),
                border: Border.all(color: on ? AppColors.amberBorder : AppColors.line),
              ),
              child: Icon(Icons.tune_rounded, size: 20, color: on ? AppColors.amberDark : AppColors.muted),
            ),
            if (on)
              PositionedDirectional(
                top: -5,
                end: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600, height: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
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

/// لون النسبة بثلاث درجات — مطابق لشارة النسبة في جدول Evaluations.tsx:
/// 85% فأكثر ممتاز، 50% فأكثر مقبول، وما دونها راسب.
Color _tierColor(int percent) {
  if (percent >= 85) return AppColors.success;
  if (percent >= 50) return AppColors.amber;
  return AppColors.danger;
}

/// نافذة إدخال علامة جديدة لتقييم مرصود.
Future<double?> _askScore(BuildContext context, Evaluation e) async {
  final ctl = TextEditingController(text: trimNum(e.score));
  final result = await showDialog<double>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: 'العلامة من ${trimNum(e.maxScore)}'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, double.tryParse(ctl.text.trim())),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  ctl.dispose();
  return result;
}
