import 'package:flutter/material.dart';

import '../data/academic_matching.dart';
import '../data/portal.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';
import 'portal_chrome.dart';

/// إدارة مواد المودل للموظف — المقابل لـ `pages/MoodleAdminPage.tsx`.
///
/// اعتدال لا تأليف: اختيار شعبة، إظهار/إخفاء الوحدات، فتح المواد وحذفها.
/// إنشاء الوحدات والمواد يبقى في بوابة المعلم.
class MoodleAdminScreen extends StatefulWidget {
  const MoodleAdminScreen({super.key});

  @override
  State<MoodleAdminScreen> createState() => _MoodleAdminScreenState();
}

class _MoodleAdminScreenState extends State<MoodleAdminScreen> {
  final _service = PortalService();
  final search = TextEditingController();
  String? groupId;
  String term = 'term_1';
  String gradeFilter = 'all';
  String subjectFilter = 'all';
  List<CourseSection> sections = const [];
  bool loading = false;
  int _token = 0;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<Group> _groups(AppStore store) {
    final q = search.text.trim().toLowerCase();
    return [
      for (final g in store.groupsInViewedYear.where((g) => g.isActive))
        if (_matches(store, g, q)) g,
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  bool _matches(AppStore store, Group g, String q) {
    if (gradeFilter != 'all' && !isSameGrade(g.gradeLevel, gradeFilter)) return false;
    if (subjectFilter != 'all' && g.subjectId != subjectFilter) return false;
    if (q.isEmpty) return true;
    final subject = store.subjectName(g.subjectId).toLowerCase();
    final teacher = (store.teacherById(g.teacherId)?.name ?? '').toLowerCase();
    final name = cleanGroupName(g.name, g.gradeLevel).toLowerCase();
    return name.contains(q) ||
        subject.contains(q) ||
        teacher.contains(q) ||
        g.gradeLevel.toLowerCase().contains(q);
  }

  Future<void> _load() async {
    final store = StoreScope.of(context);
    final tid = store.tenantId;
    final gid = groupId;
    if (tid == null || gid == null) {
      setState(() => sections = const []);
      return;
    }
    final token = ++_token;
    setState(() => loading = true);
    try {
      final list = await _service.groupSections(
        tenantId: tid,
        groupId: gid,
        term: term,
        includeHidden: true,
      );
      if (!mounted || token != _token) return;
      setState(() {
        sections = list;
        loading = false;
      });
    } catch (_) {
      if (mounted && token == _token) {
        setState(() => loading = false);
        showAppSnack(context, 'تعذّر تحميل وحدات الشعبة', error: true);
      }
    }
  }

  Future<void> _selectGroup(String id) async {
    setState(() => groupId = id);
    await _load();
  }

  Future<void> _toggle(CourseSection sec) async {
    final next = !sec.isVisible;
    try {
      await _service.setSectionVisible(sec.id, next);
      if (!mounted) return;
      setState(() {
        sections = [
          for (final s in sections) s.id == sec.id ? s.copyWith(isVisible: next) : s,
        ];
      });
      showAppSnack(context, next ? 'الوحدة ظاهرة للطلاب' : 'الوحدة مخفية عن الطلاب');
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر تغيير الإظهار', error: true);
    }
  }

  Future<void> _deleteItem(CourseSection sec, CourseItem item) async {
    final store = StoreScope.of(context);
    final tid = store.tenantId;
    if (tid == null) return;
    final ok = await confirmSheet(
      context,
      title: 'حذف المادة',
      message: 'هل تريد حذف «${item.title}» نهائياً؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      await _service.deleteItem(item, tid);
      if (!mounted) return;
      setState(() {
        sections = [
          for (final s in sections)
            s.id == sec.id ? s.copyWith(items: [for (final i in s.items) if (i.id != item.id) i]) : s,
        ];
      });
      showAppSnack(context, 'تم حذف المادة');
    } catch (_) {
      if (mounted) showAppSnack(context, 'فشل حذف المادة', error: true);
    }
  }

  Future<void> _openItem(CourseItem item) async {
    if (item.contentUrl.isEmpty) return;
    await openPortalMaterial(
      context,
      item.contentUrl,
      service: _service,
      fileName: item.fileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.can('moodle')) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('المودل')),
            body: NoAccess(section: 'moodle', roleName: store.roleName),
          );
        }

        final groups = _groups(store);
        final grades = <String>{
          for (final g in store.groupsInViewedYear.where((g) => g.isActive))
            if (g.gradeLevel.trim().isNotEmpty) g.gradeLevel.trim(),
        }.toList()
          ..sort();
        final subjects = store.subjectsInViewedYear.toList()..sort((a, b) => a.name.compareTo(b.name));
        final selected = groupId == null ? null : store.groupById(groupId!);

        final activeFilters = [gradeFilter, subjectFilter].where((v) => v != 'all').length;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            // داخل شعبة: عنوانها ورجوعٌ في الترويسة، بلا زر رجوع داخل الصفحة
            title: Text(
              selected == null ? 'المودل' : _groupTitle(store, selected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            leading: selected == null
                ? null
                : IconButton(
                    tooltip: 'الشعب',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
                    onPressed: () => setState(() {
                      groupId = null;
                      sections = const [];
                    }),
                  ),
            actions: [
              if (groupId != null)
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          body: Material(
            color: AppColors.bg,
            child: Column(
              children: [
                if (selected == null)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: SearchField(
                            controller: search,
                            hint: 'شعبة أو مادة أو معلم',
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterButton(
                          count: activeFilters,
                          onTap: () => _openFilters(grades: grades, subjects: subjects),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: selected == null
                      ? _GroupList(groups: groups, store: store, onSelect: _selectGroup)
                      : _GroupDetail(
                          store: store,
                          group: selected,
                          term: term,
                          sections: sections,
                          loading: loading,
                          onTerm: (t) {
                            setState(() => term = t);
                            _load();
                          },
                          onToggle: _toggle,
                          onOpen: _openItem,
                          onDeleteItem: _deleteItem,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// عنوان الشعبة في سطر واحد: اسمها، ويُضاف إليه ما ليس فيه أصلاً — فاسمٌ
  /// يحمل المادة والمعلم لا يُعاد ذكرهما تحته.
  String _groupTitle(AppStore store, Group g) {
    final name = cleanGroupName(g.name, g.gradeLevel);
    final subject = store.subjectName(g.subjectId);
    final teacher = store.teacherById(g.teacherId)?.name ?? '';
    final extras = [
      g.gradeLevel.trim(),
      if (subject != 'غير محدد') subject,
      teacher,
    ].where((p) => p.isNotEmpty && !name.contains(p));
    return [...extras, name].join('  ·  ');
  }

  /// المرحلة والمادة في ورقة واحدة بدل قائمتين دائمتين فوق القائمة.
  Future<void> _openFilters({required List<String> grades, required List<SubjectItem> subjects}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void pick(VoidCallback change) {
            setState(change);
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
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
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
                            subjectFilter = 'all';
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
                        group('المرحلة', {'all': 'الكل', for (final g in grades) g: g}, gradeFilter,
                            (v) => gradeFilter = v),
                        group('المادة', {'all': 'الكل', for (final x in subjects) x.id: x.name}, subjectFilter,
                            (v) => subjectFilter = v),
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
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.groups, required this.store, required this.onSelect});

  final List<Group> groups;
  final AppStore store;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(
        child: Text('لا شعب مطابقة', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final g = groups[i];
        final subject = store.subjectName(g.subjectId);
        final teacher = store.teacherById(g.teacherId)?.name ?? 'بلا معلم';
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corner.box),
            side: const BorderSide(color: AppColors.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Corner.box),
            onTap: () => onSelect(g.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cleanGroupName(g.name, g.gradeLevel),
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.heading),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (g.gradeLevel.trim().isNotEmpty) g.gradeLevel.trim(),
                            if (subject.isNotEmpty && subject != 'غير محدد') subject,
                            teacher,
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const AppChevron(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// محتوى الشعبة: مفتاح الفصل، ثم وحداتها بطاقةً لكل وحدة تُطوى وتُفتح.
class _GroupDetail extends StatelessWidget {
  const _GroupDetail({
    required this.store,
    required this.group,
    required this.term,
    required this.sections,
    required this.loading,
    required this.onTerm,
    required this.onToggle,
    required this.onOpen,
    required this.onDeleteItem,
  });

  final AppStore store;
  final Group group;
  final String term;
  final List<CourseSection> sections;
  final bool loading;
  final ValueChanged<String> onTerm;
  final ValueChanged<CourseSection> onToggle;
  final ValueChanged<CourseItem> onOpen;
  final void Function(CourseSection, CourseItem) onDeleteItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _TermSwitch(term: term, onTerm: onTerm),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : sections.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      child: Text(
                        'لا وحدات مضافة لهذه المادة في هذا الفصل',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: sections.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SectionCard(
                          section: sections[i],
                          onToggle: () => onToggle(sections[i]),
                          onOpen: onOpen,
                          onDeleteItem: (it) => onDeleteItem(sections[i], it),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

/// مفتاح الفصل: ثلاث خانات متجاورة بدل ثلاث شرائح منفصلة.
class _TermSwitch extends StatelessWidget {
  const _TermSwitch({required this.term, required this.onTerm});

  final String term;
  final ValueChanged<String> onTerm;

  static const _terms = [
    ('term_1', 'الفصل الأول'),
    ('term_2', 'الفصل الثاني'),
    ('other', 'أخرى'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = _terms.indexWhere((t) => t.$1 == term).clamp(0, _terms.length - 1);
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
              // مؤشّر ينزلق إلى الفصل المختار بدل أن يقفز إليه
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
                  for (final (value, label) in _terms)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTerm(value),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                style: TextStyle(
                                  fontFamily: AppText.family,
                                  color: value == term ? AppColors.heading : AppColors.muted,
                                  fontSize: 12.5,
                                  fontWeight: value == term ? FontWeight.w600 : FontWeight.w600,
                                ),
                                child: Text(label, maxLines: 1),
                              ),
                            ),
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

/// وحدة في المادة: رأسها اسمها وعدد موادها وحالة ظهورها — والحالة نفسها زرّ
/// يُظهرها أو يخفيها. تُطوى وتُفتح باللمس، ومادتها تُفتح بلمسها وتُحذف بسحبها.
class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.section,
    required this.onToggle,
    required this.onOpen,
    required this.onDeleteItem,
  });

  final CourseSection section;
  final VoidCallback onToggle;
  final ValueChanged<CourseItem> onOpen;
  final ValueChanged<CourseItem> onDeleteItem;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool open = true;

  @override
  Widget build(BuildContext context) {
    final sec = widget.section;
    final visible = sec.isVisible;

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
            onTap: sec.items.isEmpty ? null : () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 8, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sec.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${sec.items.length} مادة',
                          style: const TextStyle(color: AppColors.faint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // حالة الظهور شارة تُضغط فتتبدّل — لا أيقونة منفصلة
                  PressableScale(
                    onTap: widget.onToggle,
                    child: Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                      decoration: BoxDecoration(
                        color: visible ? const Color(0xFFE8F3EE) : AppColors.hover,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 13,
                            color: visible ? const Color(0xFF2E7D57) : AppColors.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            visible ? 'ظاهرة' : 'مخفية',
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: visible ? const Color(0xFF2E7D57) : AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (sec.items.isNotEmpty)
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Padding(
                        padding: EdgeInsetsDirectional.only(start: 2),
                        child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.faint),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !open || sec.items.isEmpty
                ? const SizedBox(width: double.infinity)
                : Container(
                    decoration: const BoxDecoration(
                      color: AppColors.sunken,
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < sec.items.length; i++)
                          Dismissible(
                            key: ValueKey(sec.items[i].id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: AppColors.dangerSoft,
                              alignment: AlignmentDirectional.centerEnd,
                              padding: const EdgeInsetsDirectional.only(end: 18),
                              child: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                            ),
                            // الحذف يُسحب ويُؤكَّد، فلا زرّ حذف في كل سطر
                            confirmDismiss: (_) async {
                              widget.onDeleteItem(sec.items[i]);
                              return false;
                            },
                            child: _ItemRow(
                              item: sec.items[i],
                              last: i == sec.items.length - 1,
                              onOpen: () => widget.onOpen(sec.items[i]),
                            ),
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

/// مادة داخل وحدة: نوعها أيقونةً، واسمها، ولمسها يفتحها.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.last, required this.onOpen});

  final CourseItem item;
  final bool last;
  final VoidCallback onOpen;

  IconData get _icon => switch (item.type) {
        'url' => Icons.link_rounded,
        'page' => Icons.article_outlined,
        'assign' => Icons.assignment_outlined,
        'quiz' => Icons.quiz_outlined,
        'video' => Icons.play_circle_outline,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final openable = item.contentUrl.isNotEmpty;
    return InkWell(
      onTap: openable ? onOpen : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.sunken,
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.hover)),
        ),
        child: Row(
          children: [
            Icon(_icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(item.typeLabel, style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
                ],
              ),
            ),
            if (openable) const Icon(Icons.open_in_new, size: 15, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

/// زرّ التصفية: أيقونة وعدد الفلاتر المفعّلة عليها.
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
