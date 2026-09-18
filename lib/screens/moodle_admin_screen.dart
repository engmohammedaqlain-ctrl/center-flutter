import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/academic_matching.dart';
import '../data/portal.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

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
    try {
      await _service.setSectionVisible(sec.id, !sec.isVisible);
      if (!mounted) return;
      setState(() {
        sections = [
          for (final s in sections) s.id == sec.id ? s.copyWith(isVisible: !sec.isVisible) : s,
        ];
      });
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
    try {
      final url = await _service.materialOpenUrl(item.contentUrl) ?? item.contentUrl;
      final uri = Uri.tryParse(url);
      if (uri == null || !await canLaunchUrl(uri)) {
        if (mounted) showAppSnack(context, 'تعذّر فتح الرابط', error: true);
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر فتح الملف', error: true);
    }
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

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('المودل'),
            titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
            actions: [
              if (groupId != null)
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'ابحث بشعبة أو مادة أو معلم...',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AppDropdown<String>(
                            value: gradeFilter,
                            hint: 'المرحلة',
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('كل المراحل')),
                              for (final g in grades) DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => gradeFilter = v ?? 'all'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppDropdown<String>(
                            value: subjectFilter,
                            hint: 'المادة',
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('كل المواد')),
                              for (final s in subjects)
                                DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => subjectFilter = v ?? 'all'),
                          ),
                        ),
                      ],
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
                        onBack: () => setState(() {
                          groupId = null;
                          sections = const [];
                        }),
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
        );
      },
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
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
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
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
                  const Icon(Icons.chevron_left, color: AppColors.muted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GroupDetail extends StatelessWidget {
  const _GroupDetail({
    required this.store,
    required this.group,
    required this.term,
    required this.sections,
    required this.loading,
    required this.onBack,
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
  final VoidCallback onBack;
  final ValueChanged<String> onTerm;
  final ValueChanged<CourseSection> onToggle;
  final ValueChanged<CourseItem> onOpen;
  final void Function(CourseSection, CourseItem) onDeleteItem;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('الشعب'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amber,
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                cleanGroupName(group.name, group.gradeLevel),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final e in const [
              ('term_1', 'الفصل الأول'),
              ('term_2', 'الفصل الثاني'),
              ('other', 'أخرى'),
            ])
              ChoiceChip(
                label: Text(e.$2, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                selected: term == e.$1,
                onSelected: (_) => onTerm(e.$1),
                selectedColor: AppColors.amberSoft,
                side: BorderSide(color: term == e.$1 ? AppColors.amber : AppColors.lineStrong),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (sections.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'لا وحدات مضافة لهذه المادة في هذا الفصل',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
          )
        else
          for (final sec in sections) ...[
            _SectionCard(
              section: sec,
              onToggle: () => onToggle(sec),
              onOpen: onOpen,
              onDeleteItem: (it) => onDeleteItem(sec, it),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${section.items.length} مادة  ·  ${section.isVisible ? 'ظاهرة للطلاب' : 'مخفية'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: section.isVisible ? AppColors.success : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: section.isVisible ? 'إخفاء' : 'إظهار',
                  onPressed: onToggle,
                  icon: Icon(
                    section.isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.amber,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          if (section.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('لا مواد في هذه الوحدة', textAlign: TextAlign.center, style: TextStyle(color: AppColors.faint, fontSize: 11.5)),
            )
          else
            for (final it in section.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                          const SizedBox(height: 2),
                          Text(it.typeLabel, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                        ],
                      ),
                    ),
                    if (it.contentUrl.isNotEmpty)
                      IconButton(
                        tooltip: 'فتح',
                        onPressed: () => onOpen(it),
                        icon: Icon(Icons.open_in_new, size: 17, color: AppColors.navy),
                      ),
                    IconButton(
                      tooltip: 'حذف',
                      onPressed: () => onDeleteItem(it),
                      icon: const Icon(Icons.delete_outline, size: 17, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
