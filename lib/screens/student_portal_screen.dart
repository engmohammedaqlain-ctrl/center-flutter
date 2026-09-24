import 'dart:async';

import 'package:flutter/material.dart';

import '../data/features.dart';
import '../data/grading.dart';
import '../data/institution.dart';
import '../data/portal.dart';
import '../data/realtime.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'portal_chrome.dart';

/// بوابة الطالب وولي الأمر — تخطيط جوال بهوية AppColors وشريط سفلي.
class StudentPortalScreen extends StatefulWidget {
  const StudentPortalScreen({
    super.key,
    required this.user,
    required this.onExit,
    this.service = const PortalService(),
  });

  final PortalUser user;
  final VoidCallback onExit;

  /// قابلة للاستبدال في الاختبارات كي لا تمسّ السحابة.
  final PortalService service;

  @override
  State<StudentPortalScreen> createState() => _StudentPortalScreenState();
}

class _StudentPortalScreenState extends State<StudentPortalScreen> {
  StudentPortalData? data;
  String? error;
  bool loading = true;

  /// الحساب المفتوح الآن. وليّ أمر بعدة أبناء يبدّل بينهم، فيتغيّر داخل الشاشة
  /// بلا إعادة دخول — لذلك هو حالة لا خاصية ثابتة على الودجة.
  late PortalUser user = widget.user;

  /// ولي الأمر يتابع ملف ابنه بلا المودل.
  bool get isParent => user.isParent;

  /// الابن الذي يُفتح ملفه الآن، أثناء انتظار تبديله.
  String? switchingChildId;

  /// توسيع قائمة الأقساط — الافتراضي أول ثلاثة؛ الأهم ملخّص الدفع أعلاه.
  bool _feesExpanded = false;

  late String tab = isParent ? 'attendance' : 'moodle';

  String? moodleGroupId;
  String term = 'term_1';
  List<CourseSection> sections = const [];
  bool loadingMoodle = false;
  final closed = <String>{};
  int _moodleToken = 0;

  PortalService get _service => widget.service;

  /// فتح ملف ابن آخر: دخولٌ جديد بهويته، ثم إعادة تحميل الشاشة على ملفه.
  Future<void> _switchChild(PortalChild child) async {
    if (child.id == user.id || switchingChildId != null) return;
    setState(() => switchingChildId = child.id);

    final result = await _service.switchToChild(user, child.id);
    if (!mounted) return;

    if (!result.ok) {
      setState(() => switchingChildId = null);
      showAppSnack(context, result.error ?? 'تعذّر فتح ملف الابن', error: true);
      return;
    }

    final next = result.users.first;
    // الجلسة المحفوظة تتبع الابن المفتوح: إغلاق التطبيق وفتحه يعيده على ملفه
    unawaited(AppStore.instance.savePortalSession(
      nationalId: next.nationalId.isEmpty ? user.nationalId : next.nationalId,
      code: next.portalCode.isEmpty ? user.portalCode : next.portalCode,
      userId: next.id,
      user: next,
    ));
    setState(() {
      user = next;
      switchingChildId = null;
      loading = true;
      sections = const [];
    });
    await _load();
  }

  List<PortalNavItem> get _navItems {
    final state = resolveFeatures(data?.features);
    final ids = familyPortalTabs(state, isParent: isParent);
    PortalNavItem? item(String id) => switch (id) {
          'moodle' => const PortalNavItem(
              id: 'moodle',
              label: 'مودل',
              icon: Icons.menu_book_outlined,
              activeIcon: Icons.menu_book,
            ),
          'subjects' => const PortalNavItem(
              id: 'subjects',
              label: 'مواد',
              icon: Icons.school_outlined,
              activeIcon: Icons.school,
            ),
          'attendance' => const PortalNavItem(
              id: 'attendance',
              label: 'حضور',
              icon: Icons.event_available_outlined,
              activeIcon: Icons.event_available,
            ),
          'evaluations' => const PortalNavItem(
              id: 'evaluations',
              label: 'درجات',
              icon: Icons.workspace_premium_outlined,
              activeIcon: Icons.workspace_premium,
            ),
          'financial' => const PortalNavItem(
              id: 'financial',
              label: 'رسوم',
              icon: Icons.credit_card_outlined,
              activeIcon: Icons.credit_card,
            ),
          _ => null,
        };
    return [for (final id in ids) if (item(id) case final n?) n];
  }

  @override
  void initState() {
    super.initState();
    _load();
    _startPortalRealtime();
  }

  PortalRealtime? _portalRt;

  void _startPortalRealtime() {
    final tid = user.tenantId;
    if (tid.isEmpty) return;
    _portalRt = PortalRealtime(onChanged: (_) {
      if (!mounted) return;
      unawaited(_load());
    });
    unawaited(_portalRt!.connect(tid));
  }

  @override
  void dispose() {
    unawaited(_portalRt?.disconnect() ?? Future.value());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await _service.studentData(user);
      if (!mounted) return;
      if (result != null) {
        AppColors.apply(result.branding.colors);
      }
      setState(() {
        data = result;
        loading = false;
        if (result == null) {
          error = 'تعذّر جلب بيانات الطالب.';
        } else {
          if (moodleGroupId == null && result.subjects.isNotEmpty) {
            moodleGroupId = result.subjects.first.groupId;
          }
          final ids = _navItems.map((n) => n.id).toSet();
          if (!ids.contains(tab) && ids.isNotEmpty) tab = ids.first;
        }
      });
      if (tab == 'moodle' && !isParent) _loadMoodle();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذّر الاتصال بالسحابة.';
      });
    }
  }

  Future<void> _loadMoodle() async {
    final gid = moodleGroupId;
    if (gid == null || gid.isEmpty) return;
    final token = ++_moodleToken;
    setState(() => loadingMoodle = true);
    final roomId = data?.subjects.where((s) => s.groupId == gid).map((s) => s.roomId).firstOrNull ?? '';
    try {
      final list = await _service.groupSections(
        tenantId: user.tenantId,
        groupId: gid,
        term: term,
        includeHidden: false,
        roomId: roomId.isEmpty ? null : roomId,
      );
      if (!mounted || token != _moodleToken) return;
      setState(() {
        sections = list;
        closed.removeWhere((id) => list.every((s) => s.id != id));
        loadingMoodle = false;
      });
    } catch (_) {
      if (mounted && token == _moodleToken) setState(() => loadingMoodle = false);
    }
  }

  void _selectTab(String id) {
    setState(() => tab = id);
    if (id == 'moodle' && !isParent && sections.isEmpty) _loadMoodle();
  }

  @override
  Widget build(BuildContext context) {
    final branding = data?.branding ?? const PortalBranding();
    final student = data?.student;
    final displayName = isParent
        ? (user.studentName.isNotEmpty ? user.studentName : (student?.fullName ?? user.name))
        : user.name;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PortalChromeHeader(
            branding: branding,
            // بلا اسم وليّ الأمر: الترويسة تُعرض على شاشة يراها غير صاحبها
            displayName: displayName,
            gradeLine: portalGradeLine(user: user, student: student),
            onExit: widget.onExit,
          ),
          // أبناء وليّ الأمر: لمس اسم يفتح ملفه — دخولٌ بهويته وكلمة وليّ
          // الأمر نفسها، فلا تتغيّر صلاحية ولا يُطلب منه رمز من جديد
          if (isParent && user.children.length > 1)
            _ChildrenBar(
              children: user.children,
              currentId: user.id,
              busyId: switchingChildId,
              color: parseHexColor(branding.colors.activeItem) ?? AppColors.amber,
              onPick: _switchChild,
            ),
          Expanded(
            child: loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        'جارِ تحميل البيانات...',
                        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                : error != null
                    ? _ErrorBody(message: error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.accent,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                          children: switch (tab) {
                            'subjects' => _subjectsTab(),
                            'attendance' => _attendanceTab(),
                            'evaluations' => _evaluationsTab(),
                            'financial' => _financialTab(),
                            _ => _moodleTab(),
                          },
                        ),
                      ),
          ),
          PortalBottomNav(
            items: _navItems,
            activeId: tab,
            onSelect: _selectTab,
          ),
        ],
      ),
    );
  }

  // ── المودل ────────────────────────────────────────────────────────────────

  List<Widget> _moodleTab() {
    final subjects = data!.subjects;
    return [
      // المواد شرائح تُمرَّر، والفصل مفتاح مقسّم — بلا بطاقة ولا عناوين تشرح الظاهر
      if (subjects.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'لا توجد مواد مسجلة حالياً',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.faint, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        )
      else
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in subjects)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: _PortalPill(
                    label: s.subjectName,
                    selected: moodleGroupId == s.groupId,
                    onTap: () {
                      setState(() => moodleGroupId = s.groupId);
                      _loadMoodle();
                    },
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      _TermSwitch(
        value: term,
        onChanged: (t) {
          setState(() => term = t);
          _loadMoodle();
        },
      ),
      const SizedBox(height: Gap.lg),
      if (loadingMoodle)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.heading),
              ),
              const SizedBox(height: 8),
              const Text(
                'جارٍ تحميل المحتوى الدراسي...',
                style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        )
      else if (sections.isEmpty)
        EmptyState(message: 'لا توجد وحدات أو دروس منشورة لهذه المادة في هذا الفصل',
          icon: Icons.layers_outlined,
        )
      else
        for (final sec in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Corner.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(Corner.card),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _StudentSectionPage(
                      section: sec,
                      service: _service,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Corner.card),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.layers_outlined, size: 18, color: AppColors.heading),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sec.title,
                              style: TextStyle(
                                fontFamily: AppText.family,
                                color: AppColors.heading,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${sec.items.length} عنصر',
                              style: TextStyle(
                                fontFamily: AppText.family,
                                color: AppColors.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const AppChevron(color: AppColors.faint),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  // ── المواد ────────────────────────────────────────────────────────────────

  List<Widget> _subjectsTab() {
    final subjects = data!.subjects;
    return [
      Text(
        'المواد والمعلمون (${subjects.length}):',
        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: Gap.md),
      if (subjects.isEmpty)
        EmptyState(message: 'لا توجد مواد مسجلة حالياً')
      else
        for (final s in subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.subjectName,
                          style: TextStyle(color: AppColors.heading, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 13, color: AppColors.accent),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  text: 'المعلم: ',
                                  children: [
                                    TextSpan(
                                      text: s.teacherName,
                                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        if (s.roomName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text('القاعة: ${s.roomName}', style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
                        ],
                      ],
                    ),
                  ),
                  if (s.days.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusChip.amber(daysNames(s.days)),
                          if (s.startTime.length >= 5 && s.endTime.length >= 5) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule, size: 11, color: AppColors.muted),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    '${s.startTime.substring(0, 5)} - ${s.endTime.substring(0, 5)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
    ];
  }

  // ── الحضور ────────────────────────────────────────────────────────────────

  List<Widget> _attendanceTab() {
    final a = data!.attendance;
    final total = a.present + a.absent + a.excused;
    final rate = total == 0 ? 0.0 : a.present / total;

    // السجل مجموع بالشهر: صفٌّ واحد لكل يوم بحالته
    final byMonth = <String, List<AttendanceMark>>{};
    for (final r in a.records) {
      final d = parseIsoDate(r.date.length >= 10 ? r.date.substring(0, 10) : r.date);
      final key = d == null ? r.date : '${gregorianMonths[d.month - 1]} ${d.year}';
      byMonth.putIfAbsent(key, () => []).add(r);
    }

    return [
      _PortalSummary(
        label: 'نسبة الحضور',
        value: '${(rate * 100).round()}%',
        ratio: rate,
        parts: [
          (label: 'حاضر', value: '${a.present}', color: const Color(0xFF2E7D57)),
          (label: 'غائب', value: '${a.absent}', color: const Color(0xFFA5484A)),
          (label: 'مأذون', value: '${a.excused}', color: const Color(0xFF9A6700)),
        ],
      ),
      const SizedBox(height: Gap.lg),
      if (a.records.isEmpty)
        EmptyState(message: 'لا توجد سجلات حضور مسجلة بعد')
      else
        for (final entry in byMonth.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              entry.key,
              style: TextStyle(
                fontFamily: AppText.family,
                color: AppColors.heading,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Corner.card),
              border: Border.all(color: AppColors.line),
              boxShadow: cardShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++)
                  _PortalRow(
                    title: portalDayLabel(entry.value[i].date),
                    meta: entry.value[i].notes.trim(),
                    last: i == entry.value.length - 1,
                    trailing: switch (entry.value[i].status) {
                      'present' => const _PortalBadge('حاضر', Color(0xFF2E7D57)),
                      'excused' => const _PortalBadge('مأذون', Color(0xFF9A6700)),
                      _ => const _PortalBadge('غائب', Color(0xFFA5484A)),
                    },
                  ),
              ],
            ),
          ),
        ],
    ];
  }

  // ── الدرجات ───────────────────────────────────────────────────────────────

  List<Widget> _evaluationsTab() {
    final list = data!.evaluations;
    final scheme = data!.branding.gradingScheme;
    final summaries = subjectGradeSummaries(
      [for (final e in list) e.toEvaluation()],
      scheme,
      (id) {
        for (final e in list) {
          if (e.subjectId == id && e.subjectName.isNotEmpty) return e.subjectName;
        }
        return 'مادة';
      },
    );

    // التقييمات تتبع موادّها كما في ملف الطالب، لا قائمة واحدة طويلة بعد الملخص
    final bySubject = <String, List<StudentEvaluation>>{};
    for (final e in list) {
      bySubject.putIfAbsent(e.subjectName.trim().isEmpty ? 'غير محدد' : e.subjectName.trim(), () => []).add(e);
    }
    for (final rows in bySubject.values) {
      rows.sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
    }

    final names = <String>{
      for (final x in summaries) x.subjectName,
      ...bySubject.keys,
    }.toList()
      ..sort();

    if (names.isEmpty) {
      return [
        EmptyState(
          message: 'لم يتم رصد أي درجات أو تقييمات لك بعد',
          icon: Icons.workspace_premium_outlined,
        ),
      ];
    }

    return [
      for (final name in names)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SubjectGradesCard(
            name: name,
            summary: summaries.where((x) => x.subjectName == name).firstOrNull,
            rows: bySubject[name] ?? const [],
            scheme: scheme,
          ),
        ),
    ];
  }

  // ── الرسوم ────────────────────────────────────────────────────────────────

  List<Widget> _financialTab() {
    final f = data!.finance;
    final owes = f.currentDue > 0;
    const previewCount = 3;
    final all = f.installments;
    final showAll = _feesExpanded || all.length <= previewCount;
    final visible = showAll ? all : all.take(previewCount).toList();
    final hidden = all.length - visible.length;

    return [
      _PortalSummary(
        label: owes ? 'المستحق حالياً' : 'حالة الحساب',
        value: owes ? money(f.currentDue) : 'مسدد بالكامل',
        valueColor: owes ? const Color(0xFFA5484A) : const Color(0xFF2E7D57),
        parts: [
          (label: 'المقبوض', value: money(f.totalPaid), color: const Color(0xFF2E7D57)),
          if (f.scheduledRemaining > 0)
            (label: 'مجدول لاحقاً', value: money(f.scheduledRemaining), color: AppColors.muted),
        ],
      ),
      const SizedBox(height: Gap.lg),
      if (all.isEmpty)
        EmptyState(message: 'لا توجد أقساط مسجلة حالياً')
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'الرسوم (${all.length})',
            style: TextStyle(
              fontFamily: AppText.family,
              color: AppColors.heading,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Corner.card),
            border: Border.all(color: AppColors.line),
            boxShadow: cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++)
                _PortalRow(
                  title: visible[i].title,
                  meta: 'استحقاق ${portalDayLabel(visible[i].dueDate)}',
                  last: i == visible.length - 1 && hidden == 0,
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        money(visible[i].amount),
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: AppColors.heading,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _installmentChip(visible[i]),
                    ],
                  ),
                ),
              if (hidden > 0 || (_feesExpanded && all.length > previewCount))
                InkWell(
                  onTap: () => setState(() => _feesExpanded = !_feesExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _feesExpanded ? 'عرض أقل' : 'عرض المزيد ($hidden)',
                          style: TextStyle(
                            fontFamily: AppText.family,
                            color: AppColors.amberDark,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _feesExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: AppColors.amberDark,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: Gap.lg),
      const SizedBox(height: Gap.sm),
      Text(
        'سجل الدفعات وسندات القبض (${f.payments.length}):',
        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: Gap.sm),
      if (f.payments.isEmpty)
        EmptyState(message: 'لا توجد سندات قبض مسجلة بعد')
      else
        for (final p in f.payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showPortalReceipt(
                  context: context,
                  payment: p,
                  student: data!.student,
                  branding: data!.branding,
                ),
                borderRadius: BorderRadius.circular(Corner.card),
                child: AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'سند #${p.receiptNumber}',
                                  style: TextStyle(
                                    color: AppColors.heading,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                StatusChip.muted(data!.branding.methodLabel(p.method)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isoDate(p.date),
                              style: TextStyle(color: AppColors.faint, fontSize: 10.5, fontFamily: 'monospace'),
                            ),
                            if (p.purpose.isNotEmpty)
                              Text(
                                paymentPurposeNames[p.purpose] ?? p.purpose,
                                style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusChip.success('+ ${money(p.amount)}'),
                          const SizedBox(height: 6),
                          Text(
                            'عرض الوصل',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  Widget _installmentChip(PortalInstallment i) {
    if (i.status == 'unpaid') {
      return i.isScheduled ? StatusChip.muted('مجدول') : StatusChip.danger('مستحق');
    }
    if (i.status == 'partially_paid') {
      return i.isScheduled
          ? StatusChip.muted('مجدول (باقي ${money(i.remaining)})')
          : StatusChip.amber('باقي ${money(i.remaining)}');
    }
    return StatusChip.success('مسدد');
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 34, color: AppColors.faint),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('إعادة المحاولة'),
              style: TextButton.styleFrom(foregroundColor: AppColors.heading),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريحة اختيار في البوابة — المادة المختارة تمتلئ بلون الهوية.
class _PortalPill extends StatelessWidget {
  const _PortalPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.amber : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? AppColors.amber : AppColors.lineStrong),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.amber.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
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

/// مفتاح الفصل: خانتان متجاورتان بمؤشّر ينزلق.
class _TermSwitch extends StatelessWidget {
  const _TermSwitch({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _terms = [('term_1', 'الفصل الأول'), ('term_2', 'الفصل الثاني')];

  @override
  Widget build(BuildContext context) {
    final index = _terms.indexWhere((t) => t.$1 == value).clamp(0, _terms.length - 1);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / _terms.length;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                width: w,
                left: rtl ? box.maxWidth - w * (index + 1) : w * index,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (id, label) in _terms)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(id),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: id == value ? AppColors.heading : AppColors.muted,
                              fontSize: 12.5,
                              fontWeight: id == value ? FontWeight.w600 : FontWeight.w600,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// درجات مادة واحدة: اسمها ونسبتها، وفصلاها، ثم تقييماتها — كترتيب ملف الطالب.
class _SubjectGradesCard extends StatelessWidget {
  const _SubjectGradesCard({
    required this.name,
    required this.summary,
    required this.rows,
    required this.scheme,
  });

  final String name;
  final SubjectGradeSummary? summary;
  final List<StudentEvaluation> rows;
  final GradingScheme scheme;

  static Color _tone(double percent) {
    if (percent >= 85) return const Color(0xFF2E7D57);
    if (percent >= 60) return const Color(0xFF9A6700);
    return const Color(0xFFA5484A);
  }

  @override
  Widget build(BuildContext context) {
    final percent = summary?.yearAverage ??
        (rows.isEmpty ? null : rows.fold<double>(0, (a, e) => a + (e.percent ?? 0)) / rows.length);
    final tone = percent == null ? AppColors.muted : _tone(percent);

    String termLabel(TermGrade t) {
      if (t.components.isEmpty || t.currentAverage == null) return '—';
      return t.isComplete ? '${t.total.round()}%' : '${t.currentAverage!.round()}% حالي';
    }

    final terms = summary == null
        ? ''
        : [
            if (scheme.isConfigured('term_1')) 'الفصل الأول ${termLabel(summary!.term1)}',
            if (scheme.isConfigured('term_2')) 'الفصل الثاني ${termLabel(summary!.term2)}',
          ].join('  ·  ');

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
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              border: BorderDirectional(start: BorderSide(color: tone, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: AppColors.heading,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (percent != null)
                      Text(
                        '${percent.round()}%',
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: tone,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (terms.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(terms, style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
                ],
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text('لا تقييمات في هذه المادة بعد', style: TextStyle(color: AppColors.faint, fontSize: 11.5)),
            )
          else
            for (var i = 0; i < rows.length; i++)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                decoration: BoxDecoration(
                  border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.hover)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            rows[i].title.isEmpty ? 'تقييم دراسي' : rows[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rows[i].typeLabel,
                            style: const TextStyle(color: AppColors.faint, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${rows[i].score == null ? '—' : trimNum(rows[i].score!)} / ${trimNum(rows[i].maxScore)}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: AppText.family,
                        color: rows[i].passed ? AppColors.text : const Color(0xFFA5484A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
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

class _StudentSectionPage extends StatelessWidget {
  const _StudentSectionPage({required this.section, required this.service});

  final CourseSection section;
  final PortalService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          section.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          if (section.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'لا توجد مواد أو واجبات مضافة في هذه الوحدة',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AppText.family, color: AppColors.faint, fontSize: 12),
              ),
            )
          else
            for (final it in section.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ContentTile(
                  item: it,
                  service: service,
                  onOpen: it.contentUrl.isEmpty
                      ? null
                      : () => openPortalMaterial(
                            context,
                            it.contentUrl,
                            service: service,
                            fileName: it.fileName,
                          ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({required this.item, this.onOpen, this.service = const PortalService()});

  final CourseItem item;
  final VoidCallback? onOpen;
  final PortalService service;

  @override
  Widget build(BuildContext context) {
    final showImage = item.contentUrl.isNotEmpty &&
        item.type != 'link' &&
        portalLooksLikeImage(item.contentUrl, fileName: item.fileName);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Corner.card),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(Corner.card),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            color: AppColors.heading,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        StatusChip.muted(item.typeLabel),
                      ],
                    ),
                  ),
                  if (onOpen != null)
                    Icon(
                      item.type == 'file' ? Icons.download_rounded : Icons.open_in_new_rounded,
                      size: 18,
                      color: AppColors.amberDark,
                    ),
                ],
              ),
              if (item.description.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  item.description.trim(),
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: AppColors.text,
                    fontSize: 13,
                    height: 1.65,
                  ),
                ),
              ],
              if (item.type == 'assignment' && item.dueDate.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'تاريخ التسليم: ${portalDayLabel(item.dueDate)}${item.isOverdue() ? ' (منتهٍ)' : ''}',
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: item.isOverdue() ? AppColors.danger : const Color(0xFF2E7D57),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (showImage)
                PortalInlineImage(url: item.contentUrl, fileName: item.fileName, service: service),
            ],
          ),
        ),
      ),
    );
  }
}

/// عنوان يوم مقروء: «12 أكتوبر»، والسنة إن لم تكن الحالية.
String portalDayLabel(String raw) {
  final d = parseIsoDate(raw.length >= 10 ? raw.substring(0, 10) : raw);
  if (d == null) return raw;
  final base = '${d.day} ${gregorianMonths[d.month - 1]}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

/// ملخّص التبويب: رقمه الكبير، وشريط نسبته إن وُجدت، وتفاصيله تحته.
class _PortalSummary extends StatelessWidget {
  const _PortalSummary({
    required this.label,
    required this.value,
    required this.parts,
    this.ratio,
    this.valueColor,
  });

  final String label;
  final String value;
  final List<({String label, String value, Color color})> parts;

  /// نسبة تُرسم شريطاً تحت الرقم — للحضور.
  final double? ratio;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final accent = valueColor ?? AppColors.heading;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // العنوان فوق الرقم لا بجانبه: الرقم هو ما يُقرأ أولاً، وكان
                // يتزاحم مع عنوانه على سطر واحد فيصغر كلاهما
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppText.family,
                    color: AppColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: accent,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                ),
                if (ratio != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: ratio!.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppColors.sunken,
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (parts.isNotEmpty)
            // شريط مقسوم بعدد التفاصيل: يملأ عرض البطاقة بدل شرائح صغيرة
            // تترك نصفها فارغاً، وكل خانة تحمل رقمها فوق اسمها
            Container(
              decoration: const BoxDecoration(
                color: AppColors.sunken,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < parts.length; i++)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                        decoration: BoxDecoration(
                          border: i == parts.length - 1
                              ? null
                              : const BorderDirectional(end: BorderSide(color: AppColors.line)),
                        ),
                        child: Column(
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                parts[i].value,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: AppText.family,
                                  color: parts[i].color,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                parts[i].label,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
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
    );
  }
}

/// صف في قوائم البوابة: عنوانه وتفصيله، وحالته أو مبلغه في الطرف.
class _PortalRow extends StatelessWidget {
  const _PortalRow({required this.title, required this.trailing, this.meta = '', this.last = false});

  final String title;
  final Widget trailing;
  final String meta;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                if (meta.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.faint, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// شارة حالة ناعمة في البوابة.
class _PortalBadge extends StatelessWidget {
  const _PortalBadge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.family,
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// شريط أبناء وليّ الأمر — لمس اسم يفتح ملفه.
class _ChildrenBar extends StatelessWidget {
  const _ChildrenBar({
    required this.children,
    required this.currentId,
    required this.busyId,
    required this.color,
    required this.onPick,
  });

  final List<PortalChild> children;
  final String currentId;
  final String? busyId;
  final Color color;
  final ValueChanged<PortalChild> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final child = children[i];
          final current = child.id == currentId;
          final busy = busyId == child.id;
          return Material(
            color: current ? color : AppColors.sunken,
            borderRadius: BorderRadius.circular(Corner.field),
            child: InkWell(
              onTap: current || busyId != null ? null : () => onPick(child),
              borderRadius: BorderRadius.circular(Corner.field),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    busy ? 'جارٍ الفتح...' : child.shortName,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: current ? Colors.white : AppColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
