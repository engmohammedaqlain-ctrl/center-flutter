import 'dart:async';

import 'package:flutter/material.dart';

import '../data/features.dart';
import '../data/grading.dart';
import '../data/notes.dart';
import '../data/portal.dart';
import '../data/push.dart';
import '../data/realtime.dart';
import '../data/share_inbox.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/moodle_style.dart';
import '../widgets/noon_moodle.dart';
import '../widgets/noon_ui.dart';
import '../widgets/subject_style.dart';
import '../widgets/widgets.dart';
import 'notes_parts.dart';
import 'parent_payments.dart';
import 'portal_chrome.dart';

/// بوابة الطالب وولي الأمر بهوية نون — المقابل لـ `pages/StudentPortal.tsx` و`FamilyPortalParts.tsx`.
class StudentPortalScreen extends StatefulWidget {
  const StudentPortalScreen({
    super.key,
    required this.user,
    required this.onExit,
    this.service = const PortalService(),
    this.notes = const NotesService(),
  });

  final PortalUser user;
  final VoidCallback onExit;

  /// قابلة للاستبدال في الاختبارات كي لا تمسّ السحابة.
  final PortalService service;
  final NotesService notes;

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

  /// توسيع قائمة الأقساط — الافتراضي أول أربعة؛ الأهم ملخّص الدفع أعلاه.
  bool _feesExpanded = false;

  late String tab = isParent ? 'attendance' : 'moodle';

  String? moodleGroupId;
  String term = 'term_1';
  List<CourseSection> sections = const [];
  bool loadingMoodle = false;
  final closed = <String>{};
  int _moodleToken = 0;

  PortalService get _service => widget.service;

  // ── الملاحظات والإعلانات ──────────────────────────────────────────────────

  /// ملاحظات المدرسة لهذا الطالب بردودها: محادثة كل معلم على بطاقة مادته.
  List<NoteThread> noteThreads = const [];

  /// يزيد ليُعاد جلب الإعلانات (إشعار إعلان وصل).
  int _announceTick = 0;

  /// محادثة يطلبها إشعار لُمس قبل أن تجهز البيانات.
  String? _pendingNoteId;

  bool get _notesOn => data != null && resolveFeatures(data!.features)['portal.notes'] == true;

  Future<void> _loadNotes() async {
    if (!_notesOn) return;
    final id = user.id;
    try {
      final list = await widget.notes.family();
      if (mounted && user.id == id) setState(() => noteThreads = list);
    } catch (_) {
      // بلا شبكة تبقى المعروضة: الملاحظات ليست شرطاً للبوابة
    }
  }

  Future<void> _openChat(Conversation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FamilyChatPage(conv: c, canReply: isParent, service: widget.notes),
      ),
    );
    if (mounted) await _loadNotes();
  }

  /// المحادثة التي فيها ملاحظة الإشعار، أو أحدث ما لم يُقرأ.
  Future<void> _openPendingNote() async {
    final noteId = _pendingNoteId;
    if (noteId == null || data == null) return;
    _pendingNoteId = null;
    await _loadNotes();
    if (!mounted) return;
    final c = familyConversationOf(byAuthor(noteThreads), noteId: noteId);
    if (c != null) await _openChat(c);
  }

  /// فوق محتوى كل تبويب: إعلان المدرسة، وشريط «ملاحظة جديدة» يفتح محادثتها.
  List<Widget> _familyTop() {
    if (!_notesOn) return const [];
    return [
      // لكل ابن إعلانات نطاقه (مرحلته وشعبته)
      FamilyAnnouncementsCard(key: ValueKey(user.id), service: widget.notes, reloadTick: _announceTick),
      NewNotesBanner(
        threads: noteThreads,
        onOpen: () {
          final c = familyConversationOf(byAuthor(noteThreads));
          if (c != null) _openChat(c);
        },
      ),
    ];
  }

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
      noteThreads = const [];
    });
    // الجلسة الآن على هذا الابن: الجهاز يُسجَّل معه
    unawaited(ParentPush.instance.register());
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

  /// إشعار تحويل شورك من تطبيق البنك: يُفتح به نموذج الدفع في تبويب الرسوم.
  List<String> sharedReceipts = const [];
  bool _readingShare = false;

  Future<void> _onShared() async {
    final inbox = ShareInbox.instance;
    if (!mounted || _readingShare || !inbox.hasFiles || data == null) return;
    if (!isParent) {
      inbox.take();
      showAppSnack(context, 'المشاركة لولي الأمر', error: true);
      return;
    }
    if (!_navItems.any((n) => n.id == 'financial')) {
      inbox.take();
      showAppSnack(context, 'الدفع غير مفعّل لمدرستك', error: true);
      return;
    }
    _readingShare = true;
    final got = await receiptsFromShared(inbox.take());
    _readingShare = false;
    if (!mounted) return;
    if (got.images.isEmpty) {
      showAppSnack(context, 'الإشعار صورة أو PDF', error: true);
    } else {
      // أكثر من ابن: الدفعة لمن؟
      final child = await _pickChildForPayment();
      if (!mounted) return;
      if (child == null) {
        if (inbox.hasFiles) unawaited(_onShared());
        return;
      }
      if (child.id != user.id) {
        await _switchChild(child);
        if (!mounted) return;
        if (user.id != child.id) return;
      }
      if (got.skipped > 0) showAppSnack(context, 'أُرفق ${got.images.length} من ${got.images.length + got.skipped}');
      setState(() {
        tab = 'financial';
        sharedReceipts = got.images;
      });
    }
    if (inbox.hasFiles) unawaited(_onShared());
  }

  /// الابن الذي يخصه إشعار التحويل: الحالي إن كان وحده، وإلا يختاره ولي الأمر.
  Future<PortalChild?> _pickChildForPayment() async {
    final kids = user.children;
    final current = kids.where((c) => c.id == user.id).firstOrNull ??
        PortalChild(id: user.id, name: user.name, gradeLevel: user.gradeLevel);
    if (kids.length <= 1) return current;
    return showModalBottomSheet<PortalChild>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'الدفعة لمين؟',
                style: TextStyle(fontFamily: AppText.family, color: AppColors.heading, fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            for (final c in [current, ...kids.where((k) => k.id != current.id)])
              ListTile(
                leading: const Icon(Icons.person_outline, color: AppColors.muted),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: c.gradeLevel.trim().isEmpty
                    ? null
                    : Text(c.gradeLevel.trim(), style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    ShareInbox.instance.addListener(_onShared);
    _load();
    _startPortalRealtime();
    // ولي الأمر والطالب: الخادم يقرر ما يصل كلاً منهما
    _pushSubs = [
      ParentPush.instance.opened.listen(_openNotice),
      ParentPush.instance.received.listen(_showNotice),
    ];
    unawaited(ParentPush.instance.register());
  }

  List<StreamSubscription<PushNotice>> _pushSubs = const [];

  /// إشعار لُمس: ملف الطالب الذي يخصه، على تبويبه.
  Future<void> _openNotice(PushNotice notice) async {
    if (!mounted) return;
    if (notice.studentId.isNotEmpty && notice.studentId != user.id) {
      final child = user.children.where((c) => c.id == notice.studentId).firstOrNull;
      if (child == null) return;
      await _switchChild(child);
      if (!mounted || user.id != notice.studentId) return;
    }
    final tab = notice.tab;
    if (tab != null && _navItems.any((n) => n.id == tab)) _selectTab(tab);
    // الملاحظة: محادثتها مباشرة. الإعلان: البوابة نفسها، وبطاقته فوقها
    if (notice.kind == 'note') {
      _pendingNoteId = notice.noteId;
      await _openPendingNote();
    } else if (notice.kind == 'announcement') {
      setState(() => _announceTick++);
    }
  }

  /// إشعار وصل والبوابة مفتوحة: أندرويد لا يعرضه، فيظهر هنا ويُحدَّث الملف.
  void _showNotice(PushNotice notice) {
    if (!mounted || notice.body.isEmpty) return;
    showAppSnack(context, notice.body);
    if (notice.studentId == user.id) unawaited(_load(silent: true));
    if (notice.kind == 'announcement') setState(() => _announceTick++);
  }

  PortalRealtime? _portalRt;

  /// يزيد مع كل إشارة «تغيّر»: طلبات دفع ولي الأمر تُعاد فيظهر قرار المالية.
  int _realtimeTick = 0;

  void _startPortalRealtime() {
    final tid = user.tenantId;
    if (tid.isEmpty) return;
    _portalRt = PortalRealtime(onChanged: (tables) {
      if (!mounted) return;
      // المودل يُحدَّث بتغيّر المودل وحده وبصمت: كان كل حضور أو دفعة يعيد تحميله
      // فتختفي الوحدات وتعود أمام الطالب. وبقية البيانات تُحدَّث بلا شاشة تحميل.
      const moodle = {'course_sections', 'course_items'};
      final known = tables != null && tables.isNotEmpty;
      if ((!known || tables.any(moodle.contains)) && tab == 'moodle' && !isParent) {
        unawaited(_loadMoodle(silent: true));
      }
      if (!known || !tables.every(moodle.contains)) {
        setState(() => _realtimeTick++);
        unawaited(_load(silent: true));
      }
    });
    unawaited(_portalRt!.connect(tid));
  }

  @override
  void dispose() {
    ShareInbox.instance.removeListener(_onShared);
    for (final sub in _pushSubs) {
      unawaited(sub.cancel());
    }
    unawaited(_portalRt?.disconnect() ?? Future.value());
    super.dispose();
  }

  /// [silent] تحديث لحظي: البيانات المعروضة تبقى حتى يصل الجديد.
  Future<void> _load({bool silent = false}) async {
    if (!silent || data == null) {
      setState(() {
        loading = true;
        error = null;
      });
    }
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
      // مشاركة وصلت قبل أن تجهز البيانات
      if (result != null && ShareInbox.instance.hasFiles) unawaited(_onShared());
      if (result != null) {
        unawaited(_pendingNoteId != null ? _openPendingNote() : _loadNotes());
      }
      if (!silent && tab == 'moodle' && !isParent) _loadMoodle();
    } catch (_) {
      if (!mounted || (silent && data != null)) return;
      setState(() {
        loading = false;
        error = 'تعذّر الاتصال بالسحابة.';
      });
    }
  }

  /// [silent] تحديث لحظي: الوحدات تبقى ظاهرة حتى تصل الجديدة، لا مؤشر تحميل مكانها.
  /// ردّ طلب أقدم (مادة بُدّلت بسرعة) لا يغطي على الأحدث.
  Future<void> _loadMoodle({bool silent = false}) async {
    final gid = moodleGroupId;
    if (gid == null || gid.isEmpty) return;
    final token = ++_moodleToken;
    if (!silent) setState(() => loadingMoodle = true);
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
    final studentName = isParent
        ? (user.studentName.isNotEmpty ? user.studentName : (student?.fullName ?? user.name))
        : user.name;
    final details = portalGradeLine(user: user, student: student);
    final parentName = user.name.trim().isNotEmpty ? user.name.trim() : 'ولي الأمر';

    return Scaffold(
      backgroundColor: Noon.paper,
      body: DefaultTextStyle.merge(
        style: nText(14),
        child: Column(
          children: [
            PortalChromeHeader(
              branding: branding,
              // رقم الهوية لا يُعرض: الشاشة قد تكون مفتوحة أمام الآخرين
              sub: isParent ? 'ولي الأمر: $parentName' : [studentName, details].where((s) => s.isNotEmpty).join(' · '),
              onExit: widget.onExit,
            ),
            // ولي الأمر: الابن المعروض وأشقاؤه للتبديل — دخولٌ بهويته وكلمة وليّ الأمر نفسها
            if (isParent)
              _ChildBand(
                studentName: studentName,
                details: details,
                kids: user.children,
                currentId: user.id,
                busyId: switchingChildId,
                onPick: _switchChild,
              ),
            Expanded(
              child: loading
                  ? ListView(children: const [NLoading(text: 'جارٍ تحميل البيانات')])
                  : error != null
                      ? _ErrorBody(message: error!, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: Noon.teal,
                          child: ListView(
                            padding: const EdgeInsets.all(NoonSize.page),
                            children: [
                              // الإعلان وشريط الملاحظة الجديدة يحملان فراغهما: لا فراغ حين يغيبان
                              ..._familyTop(),
                              NColumn(
                                children: [
                                  ...switch (tab) {
                                    'subjects' => _subjectsTab(),
                                    'attendance' => _attendanceTab(),
                                    'evaluations' => _evaluationsTab(),
                                    'financial' => _financialTab(),
                                    _ => _moodleTab(),
                                  },
                                ],
                              ),
                            ],
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
      ),
    );
  }

  // ── المودل ────────────────────────────────────────────────────────────────

  List<Widget> _moodleTab() {
    final subjects = data!.subjects;
    return [
      // مواد الطالب كبسولات قابلة للتمرير، والفصل تحتها
      NPanel(
        padding: const EdgeInsets.all(16),
        child: NColumn(
          gap: 12,
          children: [
            if (subjects.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('لا مواد مسجلة', textAlign: TextAlign.center, style: nText(14, weight: FontWeight.w500, color: Noon.muted)),
              )
            else
              NSubjectPills<String>(
                items: [for (final s in subjects) (s.groupId, s.subjectName)],
                selected: moodleGroupId,
                onSelect: (id) {
                  setState(() => moodleGroupId = id);
                  _loadMoodle();
                },
              ),
            NSegment<String>(
              value: term,
              options: noonTermOptions,
              onChanged: (t) {
                setState(() => term = t);
                _loadMoodle();
              },
            ),
          ],
        ),
      ),
      if (loadingMoodle)
        const NLoading(text: 'جارٍ تحميل الوحدات')
      else if (sections.isEmpty)
        const NEmpty(text: 'لا وحدات منشورة', icon: Icons.layers_outlined)
      else
        NColumn(
          gap: 10,
          children: [
            for (final (i, sec) in sections.indexed)
              NUnitRow(
                section: sec,
                index: i,
                color: unitColor(sec, i),
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _StudentSectionPage(section: sec, service: _service),
                  ),
                ),
              ),
          ],
        ),
    ];
  }

  // ── المواد ────────────────────────────────────────────────────────────────

  List<Widget> _subjectsTab() {
    final subjects = data!.subjects;
    // محادثة كل معلم على بطاقة مادته، وما سواها (الإدارة، مربي الصف) صفوف فوق البطاقات
    final chats = byAuthor(noteThreads);
    final subjectKeys = {for (final s in subjects) teacherChatKey(s.teacherName, s.subjectName)};
    Conversation? chatOf(PortalSubject s) =>
        chats.where((c) => c.key == teacherChatKey(s.teacherName, s.subjectName)).firstOrNull;
    final others = [for (final c in chats) if (!subjectKeys.contains(c.key)) c];
    return [
      if (others.isNotEmpty) FamilyOtherChats(convs: others, onOpen: _openChat),
      NSectionTitle(title: 'المواد والمعلمون', count: subjects.length),
      if (subjects.isEmpty)
        const NEmpty(text: 'لا مواد مسجلة', icon: Icons.school_outlined)
      else
        // عمودان على الجوال
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final s in subjects)
                  SizedBox(
                    width: w,
                    child: _SubjectTile(
                      subject: s,
                      chat: chatOf(s),
                      onChat: chatOf(s) == null ? null : () => _openChat(chatOf(s)!),
                    ),
                  ),
              ],
            );
          },
        ),
    ];
  }

  // ── الحضور ────────────────────────────────────────────────────────────────

  List<Widget> _attendanceTab() {
    final a = data!.attendance;
    final total = a.present + a.absent + a.excused;
    final percent = total == 0 ? 0 : (a.present / total * 100).round();
    final tone = _percentTone(percent);

    // السجل مجموع بالشهر بترتيبه الوارد (الأحدث أولاً)
    final byMonth = <String, List<AttendanceMark>>{};
    for (final r in a.records) {
      byMonth.putIfAbsent(nMonthLabel(r.date), () => []).add(r);
    }

    return [
      NHeroCard(
        label: 'نسبة الحضور',
        icon: Icons.event_available_rounded,
        value: '$percent',
        unit: '%',
        tone: tone == NTone.green ? NoonHeroTone.paid : (tone == NTone.red ? NoonHeroTone.due : NoonHeroTone.theme),
        chips: ['حاضر ${a.present}', 'غائب ${a.absent}', 'مأذون ${a.excused}'],
        child: NHeroBar(percent: percent),
      ),
      if (a.records.isEmpty)
        const NEmpty(text: 'لا سجل حضور', icon: Icons.event_available_rounded)
      else ...[
        NSectionTitle(title: 'سجل الحضور', count: a.records.length),
        for (final entry in byMonth.entries)
          NColumn(
            gap: 8,
            children: [
              NSectionTitle(title: entry.key, count: entry.value.length),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: nPanelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NTableHead(cells: [('اليوم', 1), ('الحالة', -112)]),
                    NDivided(
                      children: [
                        for (final r in entry.value)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(nWeekdayLabel(r.date), style: nText(14, weight: FontWeight.w700)),
                                      if (r.notes.trim().isNotEmpty)
                                        Text(r.notes.trim(), style: nText(11, weight: FontWeight.w500, color: Noon.muted)),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 112, child: Align(alignment: AlignmentDirectional.centerStart, child: _attendanceBadge(r.status))),
                              ],
                            ),
                          ),
                      ],
                    ),
                    NFootRow(label: 'عدد الأيام', value: '${entry.value.length}'),
                  ],
                ),
              ),
            ],
          ),
      ],
    ];
  }

  static Widget _attendanceBadge(String status) => switch (status) {
        'present' => const NBadge('حاضر', tone: NTone.green, icon: Icons.check_rounded),
        'excused' => const NBadge('مأذون', tone: NTone.sun, icon: Icons.schedule_rounded),
        _ => const NBadge('غائب', tone: NTone.red, icon: Icons.close_rounded),
      };

  // ── الدرجات ───────────────────────────────────────────────────────────────

  /// المادة المفتوحة في الدرجات؛ الوحيدة مفتوحة افتراضياً.
  final _openSubjects = <String, bool>{};

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

    // التقييمات تتبع موادّها، لا قائمة واحدة طويلة
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

    if (names.isEmpty) return const [NEmpty(text: 'لا درجات بعد', icon: Icons.workspace_premium_outlined)];

    // المتوسط البسيط لا يُعرض حين يتوفر معدل موزون: يساوي بين واجب ونهائي
    final average = summaries.isEmpty ? _averagePercent(list)?.round() : null;
    final best = list.isEmpty ? 0 : list.map(_pct).reduce((a, b) => a > b ? a : b).round();
    bool isOpen(String name) => _openSubjects[name] ?? names.length == 1;

    return [
      if (list.isNotEmpty)
        NHeroCard(
          label: average != null ? 'المعدل' : 'الاختبارات',
          icon: Icons.workspace_premium_rounded,
          value: '${average ?? list.length}',
          unit: average != null ? '%' : null,
          chips: [if (average != null) 'الاختبارات ${list.length}', 'أعلى علامة $best%'],
        ),
      NSectionTitle(title: 'كشف الدرجات والتقييمات', count: list.length),
      NColumn(
        gap: 12,
        children: [
          for (final name in names)
            _SubjectGradesCard(
              key: ValueKey('grades:$name'),
              name: name,
              summary: summaries.where((x) => x.subjectName == name).firstOrNull,
              rows: bySubject[name] ?? const [],
              open: isOpen(name),
              onToggle: () => setState(() => _openSubjects[name] = !isOpen(name)),
            ),
        ],
      ),
    ];
  }

  // ── الرسوم ────────────────────────────────────────────────────────────────

  List<Widget> _financialTab() {
    final f = data!.finance;
    final owes = f.currentDue > 0;
    const preview = 4;
    final all = f.installments;
    final visible = !_feesExpanded && all.length > preview ? all.take(preview).toList() : all;
    final hidden = all.length - visible.length;
    final totalAmount = all.fold<double>(0, (s, i) => s + i.amount);
    final remaining = f.currentDue + f.scheduledRemaining;
    final paidInFull = !owes && remaining <= 0;

    // أقرب قسط غير مسدد بتاريخ استحقاقه
    final open = [for (final i in all) if (!_isPaid(i)) i]
      ..sort((a, b) => (a.dueDate.isEmpty ? '9999' : a.dueDate).compareTo(b.dueDate.isEmpty ? '9999' : b.dueDate));
    final next = open.firstOrNull;
    final nextLeft = next?.remaining ?? 0;
    final nextParts = next == null
        ? const <String>[]
        : [if (next.dueDate.isNotEmpty) nDayLabel(next.dueDate), if (nextLeft > 0) nMoney(nextLeft)];
    // لا رقم صفري يُعرض: المدفوع والقسط القادم حين لهما قيمة فقط
    final chips = [
      if (f.totalPaid > 0) '${paidInFull ? 'إجمالي المسدد' : 'المدفوع'} ${nMoney(f.totalPaid)}',
      if (!paidInFull && nextParts.isNotEmpty) 'القسط القادم ${nextParts.join(' · ')}',
    ];

    // الأحدث أولاً
    final payments = [...f.payments]..sort((a, b) => b.date.compareTo(a.date));

    return [
      // ولي الأمر: زر «تسديد دفعة» وطلباته أعلى التبويب
      if (isParent)
        ParentPaymentsSection(
          user: user,
          suggestedAmount: f.currentDue,
          accent: Noon.action,
          refreshTick: _realtimeTick,
          sharedReceipts: sharedReceipts,
          onSharedReceiptsUsed: () => sharedReceipts = const [],
        ),
      const NSectionTitle(title: 'الرسوم'),
      NHeroCard(
        label: owes ? 'مستحق الآن' : 'كشف الحساب',
        icon: Icons.credit_card_rounded,
        value: paidInFull ? 'مسدد بالكامل' : (owes ? nAmount(f.currentDue) : 'مسدد حتى الآن'),
        unit: owes ? 'شيكل' : null,
        tone: owes ? NoonHeroTone.due : NoonHeroTone.paid,
        chips: chips,
      ),
      NColumn(
        gap: 8,
        children: [
          NSubTitle('الأقساط (${all.length})'),
          if (all.isEmpty)
            const NEmpty(text: 'لا رسوم', icon: Icons.credit_card_rounded, dashed: false)
          else
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: nPanelDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NDivided(
                    children: [
                      for (final inst in visible)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(inst.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(14, weight: FontWeight.w700)),
                                    if (inst.dueDate.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Tooltip(
                                        message: 'الاستحقاق',
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.schedule_rounded, size: 12, color: Noon.muted),
                                            const SizedBox(width: 4),
                                            Text(nDayLabel(inst.dueDate), style: nText(11, weight: FontWeight.w500, color: Noon.muted)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(nMoney(inst.amount), style: nText(14, weight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  _installmentBadge(inst),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (all.length > preview)
                    NShowAll(
                      label: _feesExpanded ? 'عرض أقل' : 'عرض الكل ($hidden)',
                      onTap: () => setState(() => _feesExpanded = !_feesExpanded),
                    ),
                  NFootRow(label: 'إجمالي الرسوم', value: nMoney(totalAmount), horizontal: 16),
                ],
              ),
            ),
        ],
      ),
      if (payments.isEmpty)
        const NColumn(
          gap: 8,
          children: [
            NSubTitle('سندات القبض (0)'),
            NEmpty(text: 'لا سندات قبض', icon: Icons.receipt_long_outlined, dashed: false),
          ],
        )
      else
        NFold(
          title: 'سندات القبض',
          count: payments.length,
          summary: 'آخرها ${nFullDayLabel(isoDate(payments.first.date))}',
          rows: [for (final p in payments) _receiptRow(p)],
        ),
    ];
  }

  /// سند القبض صف يُلمس كله لفتح الوصل، وزر أيقونة «معاينة الوصل» في طرفه.
  Widget _receiptRow(Payment p) {
    final branding = data!.branding;
    final how = [
      branding.methodLabel(p.method),
      if (p.purpose.isNotEmpty) paymentPurposeNames[p.purpose] ?? '',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    void open() => showPortalReceipt(context: context, payment: p, student: data!.student, branding: branding);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: open,
        highlightColor: Noon.mist,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: 'سند ',
                        children: [
                          TextSpan(text: p.receiptNumber),
                        ],
                      ),
                      style: nText(14, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [nFullDayLabel(isoDate(p.date)), how].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nText(11, color: Noon.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(nMoney(p.amount), style: nText(14, weight: FontWeight.w700, color: Noon.green700)),
              const SizedBox(width: 4),
              NBtn(tone: NBtnTone.ghost, small: true, icon: Icons.description_outlined, tooltip: 'معاينة الوصل', fg: Noon.teal, onTap: open),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isPaid(PortalInstallment i) => i.status == 'paid' || i.paidAmount >= i.amount;

  /// «قادم» بدل «مجدول»: الكلمة المحاسبية لا يفهمها الأهل.
  static Widget _installmentBadge(PortalInstallment i) {
    if (_isPaid(i)) return const NBadge('مسدد', tone: NTone.green);
    if (i.isScheduled) return const NBadge('قادم');
    if (i.status == 'unpaid') return const NBadge('مستحق', tone: NTone.red);
    return NBadge('باقي ${nMoney(i.remaining)}', tone: NTone.sun);
  }
}

/// لون النسبة: أخضر من 85، وكهرماني من 60، وأحمر دونها.
NTone _percentTone(num percent) => percent >= 85 ? NTone.green : (percent >= 60 ? NTone.sun : NTone.red);

/// نسبة التقييم؛ بلا علامة صفر.
double _pct(StudentEvaluation e) => e.maxScore > 0 ? (e.score ?? 0) / e.maxScore * 100 : 0;

double? _averagePercent(List<StudentEvaluation> list) =>
    list.isEmpty ? null : list.fold<double>(0, (s, e) => s + _pct(e)) / list.length;

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(NoonSize.page),
      children: [
        NEmpty(
          text: message,
          icon: Icons.cloud_off_rounded,
          dashed: false,
          action: 'إعادة المحاولة',
          actionIcon: Icons.refresh_rounded,
          onAction: onRetry,
        ),
      ],
    );
  }
}

/// ولي الأمر: الابن المعروض ملفه دائماً ظاهر تحت الترويسة، ومعه أشقاؤه أزراراً للتبديل بلمسة.
class _ChildBand extends StatelessWidget {
  const _ChildBand({
    required this.studentName,
    required this.details,
    required this.kids,
    required this.currentId,
    required this.busyId,
    required this.onPick,
  });

  final String studentName;
  final String details;
  final List<PortalChild> kids;
  final String currentId;
  final String? busyId;
  final ValueChanged<PortalChild> onPick;

  @override
  Widget build(BuildContext context) {
    final many = kids.length > 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Noon.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (many)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kids.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final child = kids[i];
                  final current = child.id == currentId;
                  final radius = BorderRadius.circular(NoonRadius.btn);
                  return Opacity(
                    opacity: !current && busyId != null ? 0.6 : 1,
                    child: Material(
                      color: current ? Noon.mist : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: current ? Noon.teal : Noon.line)),
                      child: InkWell(
                        borderRadius: radius,
                        onTap: current || busyId != null ? null : () => onPick(child),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NInitial(name: child.name, on: current),
                              const SizedBox(width: 8),
                              Text(
                                busyId == child.id ? 'جارٍ الفتح' : child.shortName,
                                style: nText(14, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Row(
              children: [
                NInitial(name: studentName, size: 36, fontSize: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(studentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(14, weight: FontWeight.w700)),
                ),
              ],
            ),
          if (many || details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  if (many) TextSpan(text: studentName, style: TextStyle(color: Noon.text)),
                  if (many && details.isNotEmpty) const TextSpan(text: ' · '),
                  TextSpan(text: details),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nText(12, weight: FontWeight.w500, color: Noon.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// بطاقة مادة: بلاطة بأيقونة المادة ولونها الثابت، واسمها، وتحتها المعلم بحرفه الأول،
/// والشعبة خافتة، و«رسائل» حين كتب معلمها.
class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.subject, this.chat, this.onChat});

  final PortalSubject subject;
  final Conversation? chat;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    final s = subject;
    final tone = subjectTone(s.subjectName);
    final icon = subjectIcon(s.subjectName);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: nPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: noonMix(tone, 0.14), borderRadius: BorderRadius.circular(NoonRadius.tile)),
                child: icon != null
                    ? Icon(icon, size: 20, color: tone)
                    : Text(subjectInitial(s.subjectName), style: nText(16, weight: FontWeight.w700, color: tone, height: 1)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.subjectName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: nText(15, weight: FontWeight.w700, height: 1.375),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Tooltip(
            message: 'المعلم',
            child: Row(
              children: [
                NInitial(name: s.teacherName, size: 18, fontSize: 10),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(s.teacherName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(12, weight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          if (s.roomName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Tooltip(
              message: 'الشعبة',
              child: Text(s.roomName, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(11, color: Noon.muted)),
            ),
          ],
          if (chat != null) ...[
            const SizedBox(height: 10),
            SubjectChatButton(unread: chat!.unread, onTap: onChat!),
          ],
        ],
      ),
    );
  }
}

/// المادة الواحدة في الدرجات: ترويستها تُطوى، وفيها مفتاح الفصلين فمكوّنات الفصل المختار
/// وتقييمات كل مكوّن تحته (مطوية افتراضياً).
class _SubjectGradesCard extends StatefulWidget {
  const _SubjectGradesCard({
    super.key,
    required this.name,
    required this.summary,
    required this.rows,
    required this.open,
    required this.onToggle,
  });

  final String name;
  final SubjectGradeSummary? summary;
  final List<StudentEvaluation> rows;
  final bool open;
  final VoidCallback onToggle;

  @override
  State<_SubjectGradesCard> createState() => _SubjectGradesCardState();
}

class _SubjectGradesCardState extends State<_SubjectGradesCard> {
  final _expanded = <String, bool>{};

  static bool _hasMarks(TermGrade t) => t.components.any((c) => c.achievedScore != null);

  // الفصل الافتراضي: آخر فصل فيه علامات
  late String term = widget.summary != null && _hasMarks(widget.summary!.term2) ? 'term_2' : 'term_1';

  static Color _pctText(NTone t) => switch (t) {
        NTone.green => Noon.green700,
        NTone.red => Noon.red700,
        _ => Noon.warn,
      };

  /// علامة الفصل: كاملة، أو «حالي» ما دام فيه مكوّنات لم تُعقد.
  static String _termScoreText(TermGrade t) {
    if (t.components.isEmpty || t.currentAverage == null) return '—';
    final full = trimNum(t.fullMark);
    return t.isComplete ? '${t.termScore.round()} / $full' : '${(t.currentScore ?? 0).round()} / $full حالي';
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final rows = widget.rows;
    final percent = summary?.yearGrade?.percent ?? _averagePercent(rows);
    final rowsAverage = _averagePercent(rows)?.round();
    final weighted = summary != null && (summary.term1.components.isNotEmpty || summary.term2.components.isNotEmpty);
    final grade = summary == null ? null : (term == 'term_1' ? summary.term1 : summary.term2);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: nPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggle,
              highlightColor: Noon.mist2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(16, weight: FontWeight.w700)),
                          if (summary != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              summary.yearGrade != null
                                  ? 'السنة ${summary.yearGrade!.score.round()} / ${trimNum(summary.yearGrade!.yearFullMark)}'
                                  : 'من ${trimNum(summary.fullMark)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nText(11, weight: FontWeight.w500, color: Noon.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (percent != null) ...[
                      const SizedBox(width: 12),
                      NBadge('${percent.round()}%', tone: _percentTone(percent), height: 24, fontSize: 14),
                    ],
                    const SizedBox(width: 12),
                    NFoldArrow(open: widget.open, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (widget.open)
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Noon.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: weighted && grade != null
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: NSegment<String>(
                            value: term,
                            options: const [('term_1', 'الفصل الأول'), ('term_2', 'الفصل الثاني')],
                            onChanged: (t) => setState(() => term = t),
                          ),
                        ),
                        if (_hasMarks(grade)) ...[
                          _TotalRow(
                            label: 'المجموع',
                            value: _termScoreText(grade),
                            tone: grade.currentAverage == null ? null : _pctText(_percentTone(grade.currentAverage!.round())),
                          ),
                          for (final c in grade.components) _componentGroup(c, rows),
                          ..._othersGroup(grade, rows),
                        ] else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text('لا علامات بعد', style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
                          ),
                      ]
                    : rows.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text('لا تقييمات', style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
                            ),
                          ]
                        : [
                            if (rowsAverage != null)
                              _TotalRow(label: 'المعدل', value: '$rowsAverage%', tone: _pctText(_percentTone(rowsAverage))),
                            for (final (i, e) in rows.indexed) _EvaluationRow(e: e, first: i == 0 && rowsAverage == null),
                          ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _componentGroup(ComponentResult c, List<StudentEvaluation> rows) {
    final own = [for (final e in rows) if (e.term == term && e.componentId == c.component.id) e];
    final key = '$term:${c.component.id}';
    final graded = c.achievedScore != null;
    return _CollapsibleGroup(
      open: _expanded[key] ?? false,
      onToggle: own.isEmpty ? null : () => setState(() => _expanded[key] = !(_expanded[key] ?? false)),
      title: Text.rich(
        TextSpan(
          text: c.component.name,
          children: [
            TextSpan(text: ' (${trimNum(c.component.weight)}%)', style: nText(12, color: Noon.muted)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      end: Text(
        graded ? '${c.achievedScore!.round()} / ${c.maxScore.round()}' : 'لم تُرصد بعد',
        style: nText(14, weight: graded ? FontWeight.w700 : FontWeight.w400, color: graded ? Noon.text : Noon.muted),
      ),
      children: [for (final (i, e) in own.indexed) _EvaluationRow(e: e, first: i == 0)],
    );
  }

  List<Widget> _othersGroup(TermGrade grade, List<StudentEvaluation> rows) {
    final ids = {for (final c in grade.components) c.component.id};
    final others = [for (final e in rows) if (e.term.isEmpty || (e.term == term && !ids.contains(e.componentId))) e];
    if (others.isEmpty) return const [];
    final key = '$term:others';
    return [
      _CollapsibleGroup(
        open: _expanded[key] ?? false,
        onToggle: () => setState(() => _expanded[key] = !(_expanded[key] ?? false)),
        title: const Text('تقييمات أخرى'),
        end: Text('${others.length}', style: nText(12, color: Noon.muted)),
        children: [for (final (i, e) in others.indexed) _EvaluationRow(e: e, first: i == 0)],
      ),
    ];
  }
}

/// سطر المجموع: تظليل محايد خفيف، والرقم وحده بلون حالته.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Noon.band,
        border: Border.symmetric(horizontal: BorderSide(color: Noon.line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: nText(12, weight: FontWeight.w700))),
          Text(value, style: nText(14, weight: FontWeight.w700, color: tone ?? Noon.text)),
        ],
      ),
    );
  }
}

/// جزء من الفصل (مكوّن أو «تقييمات أخرى»): سطر أبيض بعنوانه ومجموعه وسهم، يُفتح بلمسة على
/// تقييماته مزاحةً. بلا [onToggle] (لم يُرصد) سطر خافت لا يُلمس.
class _CollapsibleGroup extends StatelessWidget {
  const _CollapsibleGroup({required this.title, required this.end, required this.open, this.onToggle, this.children = const []});

  final Widget title;
  final Widget end;
  final bool open;
  final VoidCallback? onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tappable = onToggle != null;
    final head = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style: nText(14, weight: tappable ? FontWeight.w500 : FontWeight.w400, color: tappable ? Noon.text : Noon.muted),
              child: title,
            ),
          ),
          const SizedBox(width: 8),
          end,
          if (tappable) ...[const SizedBox(width: 8), NFoldArrow(open: open)],
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Noon.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tappable)
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: onToggle, highlightColor: Noon.mist2, child: head),
            )
          else
            head,
          if (open && tappable)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
        ],
      ),
    );
  }
}

/// سطر تقييم: العنوان، وتحته «التاريخ · المعلم» خافتاً، والملاحظة، والعلامة في الطرف بخط
/// عريض وتحتها نسبتها صغيرة.
class _EvaluationRow extends StatelessWidget {
  const _EvaluationRow({required this.e, this.first = false});

  final StudentEvaluation e;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = _pct(e);
    final small = nText(10.5, color: Noon.muted);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 10, 16, 10),
      decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: Noon.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.title.isEmpty ? 'تقييم دراسي' : e.title, style: nText(14, weight: FontWeight.w500)),
                Text([nDayLabel(e.evaluationDate), e.teacherName].where((s) => s.trim().isNotEmpty).join(' · '), style: small),
                if (e.notes.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(e.notes.trim(), style: small)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  text: e.score == null ? '—' : trimNum(e.score!),
                  children: [
                    TextSpan(text: ' / ${trimNum(e.maxScore)}', style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
                  ],
                ),
                textDirection: TextDirection.ltr,
                style: nText(16, weight: FontWeight.w700, color: p >= 50 ? Noon.text : Noon.red600, height: 1),
              ),
              const SizedBox(height: 4),
              Text('${p.round()}%', textDirection: TextDirection.ltr, style: small),
            ],
          ),
        ],
      ),
    );
  }
}

/// وحدة المودل في صفحتها: دروسها بطاقات بلون نوعها، كل درس يُفتح بلمسة.
class _StudentSectionPage extends StatelessWidget {
  const _StudentSectionPage({required this.section, required this.service});

  final CourseSection section;
  final PortalService service;

  @override
  Widget build(BuildContext context) {
    return NPageScaffold(
      title: section.title,
      children: [
        NLessonsList(
          children: [
            for (final it in section.items)
              NLessonRow(
                item: it,
                dueLabel: nDayLabel,
                onOpen: it.contentUrl.isEmpty
                    ? null
                    : () => openPortalMaterial(context, it.contentUrl, service: service, fileName: it.fileName),
              ),
          ],
        ),
      ],
    );
  }
}

/// عنوان يوم مقروء: «12 أكتوبر»، والسنة إن لم تكن الحالية.
String portalDayLabel(String raw) => nDayLabel(raw);
