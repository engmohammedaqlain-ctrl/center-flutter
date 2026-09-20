import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/academic_matching.dart';
import '../data/balance.dart';
import '../data/class_tiers.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/due_status.dart';
import '../widgets/list_paging.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'attendance_print.dart';
import 'attendance_screen.dart';
import 'room_form_screen.dart';
import 'student_detail_screen.dart';
import 'section_students_sheet.dart';

/// الصفوف والشعب — المقابل لـ `pages/SchoolClasses.tsx`.
///
/// شريط المراحل أعلى الشاشة، ثم بطاقة لكل صف: الاسم والمرحلة والمربي والإشغال.
/// «صف جديد» زر ثابت في متناول الإبهام، والصف يُفتح صفحةً بعنوانه.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  String tier = 'all';

  static const _tierLabels = {
    'all': 'الكل',
    'secondary': 'الثانوية',
    'middle': 'الإعدادية',
    'primary': 'الابتدائية',
    'kindergarten': 'رياض الأطفال',
  };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('classes')) {
          return NoAccess(section: 'classes', roleName: store.roleName);
        }

        final canEdit = store.can('classes');
        final tiers = {for (final r in store.roomsInViewedYear) r.id: classTier(store, r)};
        int countOf(String id) => id == 'all' ? store.roomsInViewedYear.length : tiers.values.where((t) => t == id).length;
        // رياض الأطفال تظهر حين يوجد لها صف فقط، كما في Center
        final tabs = _tierLabels.keys.where((id) => id != 'kindergarten' || countOf(id) > 0).toList();
        if (!tabs.contains(tier)) tier = 'all';

        final rooms = store.roomsInViewedYear.where((r) => tier == 'all' || tiers[r.id] == tier).toList();

        // أقسام لكل مرحلة بترتيب الرسوم، والشعب داخلها أبجدياً
        final gradeOrder = store.gradeOptions;
        final byGrade = <String, List<Classroom>>{};
        for (final r in rooms) {
          final g = r.gradeLevel.trim().isEmpty ? 'مرحلة غير محددة' : r.gradeLevel.trim();
          (byGrade[g] ??= []).add(r);
        }
        for (final list in byGrade.values) {
          list.sort((a, b) => a.name.compareTo(b.name));
        }
        final orderedGrades = [
          ...gradeOrder.where(byGrade.containsKey),
          ...byGrade.keys.where((g) => !gradeOrder.contains(g)).toList()..sort(),
        ];
        final listItems = <Object>[];
        for (final g in orderedGrades) {
          listItems.add(g);
          listItems.addAll(byGrade[g]!);
        }

        return ThumbActionLayer(
          action: canEdit
              ? ThumbAction(label: 'صف جديد', icon: Icons.add, onPressed: () => _openRoomForm(context, null))
              : null,
          child: Column(
            children: [
              _tierBar(tabs, countOf),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, thumbActionClearance),
                  itemCount: rooms.isEmpty ? 1 : listItems.length,
                  itemBuilder: (context, i) {
                    if (rooms.isEmpty) {
                      return const SizedBox(
                        height: 220,
                        child: EmptyState(message: 'لا توجد شعب أو صفوف مسجلة في هذه المرحلة.'),
                      );
                    }
                    final item = listItems[i];
                    if (item is String) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(16, i > 0 ? 16 : 6, 16, 8),
                        child: _GradeSectionHeader(title: item),
                      );
                    }
                    final room = item as Classroom;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _RoomCard(
                        room: room,
                        teacher: store.teacherById(room.teacherId),
                        students: store.studentsOf(room),
                        canEdit: canEdit,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => _ClassDetailScreen(roomId: room.id)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// شريط المراحل: أزرار أفقية تتمرّر، المختار منها ممتلئ بلون الهوية.
  Widget _tierBar(List<String> tabs, int Function(String) countOf) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      // تمرير المراحل أفقياً ليس تمريراً للقائمة: لا يُخفي زر «صف جديد»
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final id = tabs[i];
            final on = tier == id;
            return InkWell(
              onTap: () => setState(() => tier = id),
              borderRadius: BorderRadius.circular(Corner.field),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? AppColors.amberSoft : Colors.white,
                  borderRadius: BorderRadius.circular(Corner.field),
                  border: Border.all(color: on ? AppColors.amberBorder : AppColors.line),
                ),
                child: Text(
                  '${_tierLabels[id]} (${countOf(id)})',
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: on ? AppColors.amberDark : AppColors.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══ إجراءات الصف — من بطاقته ومن صفحته ═════════════════════════════════════

Future<void> _openRoomForm(BuildContext context, Classroom? room) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomFormScreen(room: room)));
}

/// تعيين مربي الصف أو تغييره — «بدون مربي» خيار مشروع كما في Center.
Future<void> _assignTeacher(BuildContext context, Classroom room) async {
  final store = StoreScope.of(context);
  var teacherId = store.teacherById(room.teacherId) == null ? '' : room.teacherId;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.school_outlined, size: 18, color: AppColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'مربي الصف: ${room.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const FieldLabel('اختر المعلم المشرف'),
              AppDropdown<String>(
                value: teacherId,
                items: [
                  const DropdownMenuItem(value: '', child: Text('بدون مربي صف')),
                  for (final t in store.teachersInViewedYear)
                    DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setSheet(() => teacherId = v ?? ''),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: 'حفظ',
                      icon: Icons.check,
                      height: 44,
                      onPressed: () {
                        try {
                          store.upsertRoom(
                            Classroom(
                              id: room.id,
                              name: room.name,
                              gradeLevel: room.gradeLevel,
                              teacherId: teacherId,
                              capacity: room.capacity,
                              notes: room.notes,
                              tier: room.tier,
                            ),
                          );
                          Navigator.pop(ctx);
                          if (context.mounted) showAppSnack(context, 'تم تعيين المربي للصف');
                        } on StoreException catch (e) {
                          showAppSnack(ctx, e.message, error: true);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// «٣ معلمين» بصيغة عربية سليمة — الرقم وحده يقرأ ركيكاً في البطاقة.
String _teachersLabel(int n) => switch (n) {
      1 => 'معلم واحد',
      2 => 'معلمان',
      <= 10 => '$n معلمين',
      _ => '$n معلماً',
    };

/// إسناد معلمي مواد الشعبة — المقابل لـ `SectionSubjectTeachersModal`.
///
/// كل مادة في سطرها ومعلمها أمامها. المادة بلا معلم تُرفع عن الشعبة عند الحفظ،
/// والمسندة تُنشئ مجموعتها تلقائياً ويُربط بها طلاب الشعبة بلا رسوم.
Future<void> _assignSubjectTeachers(BuildContext context, Classroom room) async {
  final store = StoreScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (_) => _SubjectTeachersSheet(store: store, room: room),
  );
}

class _SubjectTeachersSheet extends StatefulWidget {
  const _SubjectTeachersSheet({required this.store, required this.room});

  final AppStore store;
  final Classroom room;

  @override
  State<_SubjectTeachersSheet> createState() => _SubjectTeachersSheetState();
}

class _SubjectTeachersSheetState extends State<_SubjectTeachersSheet> {
  /// معرّف المادة ← معرّف معلمها؛ الفارغ يعني «بلا معلم».
  late final Map<String, String> rows;
  String adding = '';
  bool showAllSubjects = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    final existing = store.sectionSubjectGroups(widget.room.id);
    if (existing.isNotEmpty) {
      rows = {for (final g in existing) g.subjectId: g.teacherId};
    } else {
      // شعبة جديدة: مواد شقيقة نفس المرحلة، وإلا مواد المرحلة
      final grade = widget.room.gradeLevel;
      var templateIds = <String>[];
      if (grade.trim().isNotEmpty) {
        for (final sr in store.roomsInViewedYear) {
          if (sr.id == widget.room.id || !isSameGrade(sr.gradeLevel, grade)) continue;
          final groups = store.sectionSubjectGroups(sr.id);
          if (groups.isEmpty) continue;
          templateIds = groups.map((g) => g.subjectId).toList();
          break;
        }
      }
      final fromSister = <String, String>{};
      for (final sid in templateIds) {
        final sub = store.subjectById(sid);
        if (sub == null || !subjectCoversGrade(sub, grade)) continue;
        fromSister[sid] = '';
      }
      rows = fromSister.isNotEmpty
          ? fromSister
          : {for (final s in store.gradeApplicableSubjects(grade)) s.id: ''};
    }
  }

  void _save() {
    try {
      widget.store.saveSectionSubjectAssignments(
        roomId: widget.room.id,
        gradeLevel: widget.room.gradeLevel,
        roomName: widget.room.name,
        assignments: rows,
      );
      Navigator.pop(context);
      showAppSnack(context, 'تم الحفظ');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final subjects = store.subjectsInViewedYear;
    final grade = widget.room.gradeLevel;
    final gradeSubjects = filterSubjectsForGrade(subjects, grade);
    final selectable = showAllSubjects ? subjects : gradeSubjects;
    final available = selectable.where((s) => !rows.containsKey(s.id)).toList();
    final missingGrade = gradeSubjects.where((s) => !rows.containsKey(s.id)).toList();
    final assigned = rows.values.where((t) => t.trim().isNotEmpty).length;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 18, color: AppColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'معلمو مواد ${widget.room.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.cardTitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'عدد المواد المسندة: $assigned من أصل ${rows.length} مادة',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  SquareIconButton(icon: Icons.close, onTap: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            if (subjects.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                child: Text(
                  'لا مواد — تُضاف من الإعدادات',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
                ),
              )
            else
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  shrinkWrap: true,
                  children: [
                    if (missingGrade.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => setState(() {
                            for (final s in missingGrade) {
                              rows[s.id] = '';
                            }
                          }),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.heading,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'إدراج مواد المرحلة (${missingGrade.length})',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                          ),
                        ),
                      ),
                    for (final entry in rows.entries) ...[
                      () {
                        final sub = store.subjectById(entry.key);
                        final offGrade = sub != null && !subjectCoversGrade(sub, grade);
                        final teachers = [...store.teachersInViewedYear]..sort((a, b) {
                          final aHas = a.subjectIds.contains(entry.key);
                          final bHas = b.subjectIds.contains(entry.key);
                          if (aHas != bHas) return aHas ? -1 : 1;
                          return a.name.compareTo(b.name);
                        });
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                            decoration: tileDecoration(),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 92,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        store.subjectName(entry.key),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                      ),
                                      if (offGrade)
                                        Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.amberSoft,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppColors.amberBorder),
                                          ),
                                          child: Text(
                                            'خارج المرحلة',
                                            style: TextStyle(
                                              color: AppColors.amberDark,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppDropdown<String>(
                                    value: store.teacherById(entry.value) == null ? '' : entry.value,
                                    items: [
                                      const DropdownMenuItem(value: '', child: Text('-- غير محدد --')),
                                      for (final t in teachers)
                                        DropdownMenuItem(
                                          value: t.id,
                                          child: Text(
                                            t.subjectIds.contains(entry.key) ? '${t.name} (تخصص)' : t.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) => setState(() => rows[entry.key] = v ?? ''),
                                  ),
                                ),
                                SquareIconButton(
                                  icon: Icons.close,
                                  color: AppColors.danger,
                                  onTap: () => setState(() => rows.remove(entry.key)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }(),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: AppDropdown<String>(
                            value: adding.isEmpty ? null : adding,
                            hint: available.isEmpty ? 'لا مواد متاحة للإضافة' : 'اختيار مادة إضافية...',
                            items: [
                              for (final s in available)
                                DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    '${s.name} (${subjectGradesLabel(s)})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => adding = v ?? ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PrimaryButton(
                          label: 'إضافة',
                          icon: Icons.add,
                          onPressed: adding.isEmpty
                              ? null
                              : () => setState(() {
                                    rows[adding] = '';
                                    adding = '';
                                  }),
                        ),
                      ],
                    ),
                    if (grade.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: Checkbox(
                                value: showAllSubjects,
                                activeColor: AppColors.amber,
                                onChanged: (v) => setState(() {
                                  showAllSubjects = v ?? false;
                                  adding = '';
                                }),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'مواد كل المراحل',
                              style: TextStyle(color: AppColors.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'التوزيع ينعكس فوراً في بوابة المعلم ورصد الدرجات.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: PrimaryButton(
                          label: 'حفظ التوزيع',
                          icon: Icons.check,
                          height: 44,
                          onPressed: subjects.isEmpty ? null : _save,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// إضافة طلاب إلى الشعبة، وإخبار المستخدم بعدد من انتقل إليها.
Future<void> _addStudents(BuildContext context, Classroom room) async {
  final added = await showSectionStudentsSheet(context, room);
  if (added > 0 && context.mounted) {
    showAppSnack(context, 'أُضيف $added ${added == 1 ? 'طالب' : 'طلاب'} إلى ${room.name}');
  }
}

Future<void> _confirmDeleteRoom(BuildContext context, Classroom room, {VoidCallback? onDeleted}) async {
  final store = StoreScope.of(context);
  final ok = await confirmSheet(
    context,
    title: 'تأكيد حذف الصف',
    message: 'يُحذف الصف «${room.name}»، ويبقى طلابه.',
    confirmLabel: 'حذف',
  );
  if (!ok || !context.mounted) return;
  try {
    store.deleteRoom(room.id);
    showAppSnack(context, 'تم حذف الصف');
    onDeleted?.call();
  } on StoreException catch (e) {
    showAppSnack(context, e.message, error: true);
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {bool danger = false}) {
  final color = danger ? AppColors.danger : AppColors.text;
  return PopupMenuItem<String>(
    value: value,
    height: 40,
    child: Row(
      children: [
        Icon(icon, size: 17, color: danger ? AppColors.danger : AppColors.muted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
      ],
    ),
  );
}

/// إدارة الصف: التعديل والتعيين والحذف لمن يملك تعديل الجداول وحده.
List<PopupMenuEntry<String>> _manageItems(Teacher? teacher) => [
      _menuItem('edit', Icons.edit_outlined, 'تعديل بيانات الصف'),
      _menuItem('assign', Icons.school_outlined, teacher == null ? 'تعيين مربي' : 'تغيير المربي'),
      _menuItem('subjects', Icons.menu_book_outlined, 'معلمو مواد الصف'),
      const PopupMenuDivider(height: 8),
      _menuItem('delete', Icons.delete_outline, 'حذف الصف', danger: true),
    ];

// ═══ بطاقة الصف ════════════════════════════════════════════════════════════

/// عنوان مرحلة رسمي بسيط: شريط هوية + الاسم + خط يمتد ليملأ السطر.
class _GradeSectionHeader extends StatelessWidget {
  const _GradeSectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.amber,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: AppColors.heading,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.lineStrong,
                  AppColors.line.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

TextStyle get _titleStyle => TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.heading);

const _metaStyle = TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.25);

/// إجراءات الصف — ورقة سفلية مثل خصم الأقساط (أوضح من القائمة المنبثقة).
Future<void> _showRoomActionsSheet(
  BuildContext context, {
  required AppStore store,
  required Classroom room,
  required List<Student> students,
  required Teacher? teacher,
  required bool canEdit,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              [
                room.name,
                if (room.gradeLevel.trim().isNotEmpty) room.gradeLevel.trim(),
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const Divider(height: 1),
          if (store.can('attendance'))
            ListTile(
              leading: const Icon(Icons.fact_check_outlined, color: AppColors.info),
              title: const Text('رصد الحضور'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'attendance'),
            ),
          ListTile(
            leading: Icon(Icons.download_outlined, color: AppColors.heading),
            title: const Text('تنزيل كشف الصف (PDF)'),
            dense: true,
            visualDensity: VisualDensity.compact,
            onTap: () => Navigator.pop(ctx, 'print'),
          ),
          ListTile(
            leading: Icon(Icons.vpn_key_outlined, color: AppColors.amberDark),
            title: const Text('رموز دخول الطلاب'),
            dense: true,
            visualDensity: VisualDensity.compact,
            onTap: () => Navigator.pop(ctx, 'codes'),
          ),
          if (canEdit) ...[
            ListTile(
              leading: Icon(Icons.group_add_outlined, color: AppColors.navy),
              title: const Text('إضافة طلاب للشعبة'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'add_students'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.muted),
              title: const Text('تعديل بيانات الصف'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined, color: AppColors.muted),
              title: Text(teacher == null ? 'تعيين مربي' : 'تغيير المربي'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'assign'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: AppColors.muted),
              title: const Text('معلمو مواد الصف'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'subjects'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('حذف الصف'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'attendance':
      openClassAttendance(context, room: room);
    case 'print':
      printClassRoster(context, store: store, room: room, students: students);
    case 'codes':
      showClassPortalCodes(context, room: room, students: students);
    case 'add_students':
      await _addStudents(context, room);
    case 'edit':
      await _openRoomForm(context, room);
    case 'assign':
      await _assignTeacher(context, room);
    case 'subjects':
      await _assignSubjectTeachers(context, room);
    case 'delete':
      await _confirmDeleteRoom(context, room);
  }
}

/// الصف: الاسم والمرحلة، ثم المربي والإشغال — بلا تنبيه مستحقات في القائمة.
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.teacher,
    required this.students,
    required this.canEdit,
    required this.onOpen,
  });

  final Classroom room;
  final Teacher? teacher;
  final List<Student> students;
  final bool canEdit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final teacherCount = store.sectionTeacherIds(room).length;
    final grade = [
      room.gradeLevel.trim().isEmpty ? 'مرحلة غير محددة' : room.gradeLevel.trim(),
      if (teacherCount > 0) _teachersLabel(teacherCount),
    ].join('  ·  ');

    final shape = BorderRadius.circular(Corner.card);
    return Material(
      color: Colors.transparent,
      borderRadius: shape,
      child: InkWell(
        borderRadius: shape,
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: shape,
            border: Border.all(color: AppColors.line),
            boxShadow: cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                          const SizedBox(height: 3),
                          Text(grade, maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'خيارات الصف',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.more_horiz, size: 22, color: AppColors.muted),
                      onPressed: () => _showRoomActionsSheet(
                        context,
                        store: store,
                        room: room,
                        students: students,
                        teacher: teacher,
                        canEdit: canEdit,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: AppColors.line),
                ),
                Row(
                  children: [
                    Icon(Icons.school_outlined, size: 15, color: teacher == null ? AppColors.faint : AppColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: teacher != null
                          ? Text(
                              teacher!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppText.family,
                                color: AppColors.text,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : canEdit
                              ? Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TileButton(
                                    label: 'تعيين مربي',
                                    icon: const Icon(Icons.add, size: 13),
                                    color: AppColors.amber,
                                    background: AppColors.amberSoft,
                                    border: AppColors.amberBorder,
                                    onTap: () => _assignTeacher(context, room),
                                  ),
                                )
                              : const Text('بدون مربي', style: TextStyle(color: AppColors.faint, fontSize: 12)),
                    ),
                    if (students.isEmpty && canEdit) ...[
                      const SizedBox(width: 8),
                      TileButton(
                        label: 'إضافة طلاب',
                        icon: const Icon(Icons.group_add_outlined, size: 13),
                        color: AppColors.navy,
                        background: Colors.white,
                        border: AppColors.lineStrong,
                        onTap: () => _addStudents(context, room),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══ صفحة الصف ═════════════════════════════════════════════════════════════

/// طلاب الصف مقاعدَ — اسم الصف عنوان الصفحة ومرحلته ومربيه تحته، والطباعة
/// والرموز والإدارة في شريطها. البحث ثابت أعلى المحتوى، والأرقام تُمرَّر معه.
class _ClassDetailScreen extends StatefulWidget {
  const _ClassDetailScreen({required this.roomId});
  final String roomId;

  @override
  State<_ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<_ClassDetailScreen> {
  final search = TextEditingController();
  int visibleCount = kListPageSize;

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
        final room = store.roomsInViewedYear.where((r) => r.id == widget.roomId).firstOrNull ?? store.roomById(widget.roomId);
        if (room == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('الصف')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('لم يتم العثور على الصف', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  GhostButton(label: 'العودة للصفوف', onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
          );
        }

        final teacher = store.teacherById(room.teacherId);
        final canEdit = store.can('classes');
        final roster = store.studentsOf(room);
        final q = search.text.trim();
        final list = q.isEmpty ? roster : roster.where((s) => s.fullName.contains(q) || s.phone.contains(q)).toList();
        final visible = listPage(list, visibleCount);
        final buckets = installmentBucketsByStudent(store.installments);
        final meta = [
          if (room.gradeLevel.trim().isNotEmpty) room.gradeLevel.trim(),
          teacher == null ? 'بدون مربي' : 'المربي: ${teacher.name}',
          '${roster.length} طالب',
        ].join('  ·  ');

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'تنزيل كشف الصف',
                icon: const Icon(Icons.download_outlined, size: 20),
                onPressed: () => printClassRoster(context, store: store, room: room, students: roster),
              ),
              IconButton(
                tooltip: 'رموز دخول الطلاب',
                icon: const Icon(Icons.vpn_key_outlined, size: 20),
                onPressed: () => showClassPortalCodes(context, room: room, students: roster),
              ),
              if (canEdit)
                PopupMenuButton<String>(
                  tooltip: 'إدارة الصف',
                  position: PopupMenuPosition.under,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  constraints: const BoxConstraints(minWidth: 190),
                  onSelected: (v) {
                    if (v == 'edit') _openRoomForm(context, room);
                    if (v == 'assign') _assignTeacher(context, room);
                    if (v == 'subjects') _assignSubjectTeachers(context, room);
                    if (v == 'delete') {
                      _confirmDeleteRoom(context, room, onDeleted: () => Navigator.pop(context));
                    }
                  },
                  itemBuilder: (_) => _manageItems(teacher),
                ),
            ],
          ),
          // الإجراءان اليوميان ثابتان أسفل الشاشة في متناول الإبهام
          bottomNavigationBar: (store.can('attendance') || canEdit)
              ? _ClassActionBar(
                  onAttendance: store.can('attendance') ? () => openClassAttendance(context, room: room) : null,
                  onAddStudent: canEdit ? () => _addStudents(context, room) : null,
                )
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: SearchField(
                  controller: search,
                  hint: 'ابحث باسم الطالب أو الهاتف...',
                  onChanged: (_) => setState(() => visibleCount = kListPageSize),
                  trailing: Text(
                    q.isEmpty ? '${roster.length}' : '${list.length}/${roster.length}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SubjectTeachersCard(room: room, canEdit: canEdit),
                            if (room.notes.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              InfoStrip(
                                child: Text(
                                  'ملاحظات: ${room.notes.trim()}',
                                  style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (list.isEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 220,
                          child: EmptyState(
                            message: q.isEmpty ? 'لا يوجد طلاب مسجلين في هذا الصف' : 'لا يوجد طلاب يطابقون البحث',
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        // كشف واحد بإطار رفيع، صف لكل طالب — يُقرأ كقائمة الصف الورقية
                        sliver: DecoratedSliver(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Corner.card),
                            border: Border.all(color: AppColors.line),
                          ),
                          sliver: SliverList.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, i) => _RosterRow(
                              seat: roster.indexOf(visible[i]) + 1,
                              student: visible[i],
                              due: buckets.due[visible[i].id] ?? 0,
                              scheduled: buckets.scheduled[visible[i].id] ?? 0,
                              hasPlan: (buckets.due.containsKey(visible[i].id) ||
                                  buckets.scheduled.containsKey(visible[i].id)),
                              showBalance: store.can('finance'),
                              last: i == visible.length - 1,
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          child: LoadMoreButton(
                            shown: visible.length,
                            total: list.length,
                            onMore: () => setState(() => visibleCount += kListPageSize),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// شريط إجراءات الصف السفلي: الرصد وإضافة طالب في منطقة الإبهام.
class _ClassActionBar extends StatelessWidget {
  const _ClassActionBar({required this.onAttendance, required this.onAddStudent});

  final VoidCallback? onAttendance;
  final VoidCallback? onAddStudent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(color: AppColors.navy.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              if (onAttendance != null)
                Expanded(
                  flex: 3,
                  child: PrimaryButton(
                    label: 'رصد الحضور',
                    icon: Icons.fact_check_outlined,
                    height: 48,
                    expand: true,
                    onPressed: onAttendance,
                  ),
                ),
              if (onAttendance != null && onAddStudent != null) const SizedBox(width: 8),
              if (onAddStudent != null)
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onAddStudent,
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                      label: const Text('إضافة طالب', maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.heading,
                        side: const BorderSide(color: AppColors.lineStrong),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
                        textStyle: const TextStyle(
                          fontFamily: AppText.family,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مواد الصف ومعلموها — بطاقة تُطوى: الرأس يلخّص العدد والمواد غير المسندة
/// وزر التعديل ظاهر فيه دائماً، والتفصيل يُفتح عند الحاجة.
class _SubjectTeachersCard extends StatefulWidget {
  const _SubjectTeachersCard({required this.room, required this.canEdit});

  final Classroom room;
  final bool canEdit;

  @override
  State<_SubjectTeachersCard> createState() => _SubjectTeachersCardState();
}

class _SubjectTeachersCardState extends State<_SubjectTeachersCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final assigned = store.sectionSubjectGroups(widget.room.id).where((g) => g.subjectId.isNotEmpty).toList()
      ..sort((a, b) => store.subjectName(a.subjectId).compareTo(store.subjectName(b.subjectId)));
    if (assigned.isEmpty && !widget.canEdit) return const SizedBox.shrink();

    final unassigned = assigned.where((g) => g.teacherId.trim().isEmpty).length;
    final canExpand = assigned.isNotEmpty;
    final shape = BorderRadius.circular(Corner.card);

    final Widget status;
    if (assigned.isEmpty) {
      status = const Text('لا توجد مواد', style: TextStyle(color: AppColors.faint, fontSize: 11.5));
    } else if (unassigned > 0) {
      status = _StatusDot(label: '$unassigned غير مسند', color: AppColors.warn);
    } else {
      status = const _StatusDot(label: 'كل المواد مسندة', color: AppColors.success);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: shape,
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canExpand ? () => setState(() => _open = !_open) : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.amberSoft,
                        borderRadius: BorderRadius.circular(Corner.field),
                        border: Border.all(color: AppColors.amberBorder),
                      ),
                      child: Icon(Icons.menu_book_rounded, size: 18, color: AppColors.amberDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'المواد والمعلمون',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppText.family,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: AppColors.heading,
                                  ),
                                ),
                              ),
                              if (assigned.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.hover,
                                    borderRadius: BorderRadius.circular(Corner.chip),
                                  ),
                                  child: Text(
                                    '${assigned.length}',
                                    style: const TextStyle(
                                      fontFamily: AppText.family,
                                      color: AppColors.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          status,
                        ],
                      ),
                    ),
                    if (widget.canEdit) ...[
                      const SizedBox(width: 8),
                      TileButton(
                        label: assigned.isEmpty ? 'إسناد' : 'تعديل',
                        icon: Icon(assigned.isEmpty ? Icons.add : Icons.edit_outlined, size: 13),
                        color: AppColors.amberDark,
                        background: AppColors.amberSoft,
                        border: AppColors.amberBorder,
                        onTap: () => _assignSubjectTeachers(context, widget.room),
                      ),
                    ],
                    if (canExpand)
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: const Padding(
                          padding: EdgeInsetsDirectional.only(start: 4),
                          child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.faint),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open || !canExpand
                ? const SizedBox(width: double.infinity)
                : Container(
                    decoration: const BoxDecoration(
                      color: AppColors.sunken,
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    padding: const EdgeInsets.all(10),
                    // شبكة بعمودين: كل مادة بلاطة بلونها ومعلمها تحتها
                    child: LayoutBuilder(
                      builder: (context, box) {
                        const gap = 8.0;
                        final w = (box.maxWidth - gap) / 2;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final g in assigned)
                              SizedBox(
                                width: w,
                                child: _SubjectTile(
                                  subject: store.subjectName(g.subjectId),
                                  teacher: g.teacherId.trim().isEmpty ? null : store.teacherName(g.teacherId),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// ألوان المواد: لون ثابت لكل مادة يُشتق من اسمها فلا يتبدّل بين فتحة وأخرى.
const _subjectHues = <Color>[
  Color(0xFF0055CC), // أزرق
  Color(0xFF1F845A), // أخضر
  Color(0xFF6E5DC6), // بنفسجي
  Color(0xFFB65C02), // برتقالي
  Color(0xFF206A83), // تركواز
  Color(0xFFAE2E24), // أحمر
];

Color _subjectHue(String name) =>
    _subjectHues[name.codeUnits.fold<int>(0, (a, c) => a + c) % _subjectHues.length];

/// بلاطة مادة: شريط بلونها، اسمها، ومعلمها بحرفه الأول — أو «غير مسند» بلون التنبيه.
class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.subject, required this.teacher});

  final String subject;
  final String? teacher;

  @override
  Widget build(BuildContext context) {
    final missing = teacher == null;
    final hue = _subjectHue(subject);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: missing ? AppColors.warnSoft : Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: missing ? AppColors.warn : hue),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(9, 9, 8, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppText.family,
              color: AppColors.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              if (missing) ...[
                const Icon(Icons.person_off_outlined, size: 13, color: AppColors.warn),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  teacher ?? 'غير مسند',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: missing ? AppColors.warn : AppColors.muted,
                    fontSize: 11.5,
                    fontWeight: missing ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// طالب في كشف الصف: رقم مقعده، واسمه وهاتفه، وحالته المالية في الطرف، وسهم يفتح ملفه.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.seat,
    required this.student,
    required this.due,
    required this.scheduled,
    required this.hasPlan,
    required this.showBalance,
    required this.last,
  });

  final int seat;
  final Student student;
  final double due;
  final double scheduled;
  final bool hasPlan;

  /// المبلغ المستحق لمن يملك عرض المالية، وكلمة الحالة لغيره.
  final bool showBalance;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final canOpen = store.can('students');
    final phone = student.phone.trim();
    final shown = hasPlan ? -due : student.balance;

    return InkWell(
      onTap: canOpen
          ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: student.id)),
              )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: tileDecoration(),
              child: Text(
                seat.toString().padLeft(2, '0'),
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.muted),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    student.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading),
                  ),
                  if (phone.isNotEmpty)
                    Text(phone, maxLines: 1, textDirection: TextDirection.ltr, style: _metaStyle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showBalance)
              DueStatus(
                kind: shown.abs() <= cent
                    ? DueStatusKind.clear
                    : shown < 0
                        ? DueStatusKind.due
                        : DueStatusKind.credit,
                amount: shown.abs(),
                scheduled: scheduled,
                clearLabel: hasPlan ? 'مسدد' : 'خالص',
                compact: true,
              )
            else
              Text(
                due > cent ? 'عليه مستحق' : 'مسدد',
                style: TextStyle(
                  color: due > cent ? AppColors.danger : AppColors.success,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (canOpen) ...[
              const SizedBox(width: 2),
              const AppChevron(size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// رموز دخول طلاب الصف إلى البوابة — المقابل لـ `ClassPortalCodesModal`.
///
/// يُظهر رمز كل طالب ويولّد الناقص دفعةً واحدة، فتوزيع الرموز على الصف
/// لا يحتاج فتح ملف كل طالب على حدة.
/// أنماط العرض: طلاب / أولياء / الاثنان — والنسخ TSV للصق في Excel.
Future<void> showClassPortalCodes(
  BuildContext context, {
  required Classroom room,
  required List<Student> students,
}) {
  final store = StoreScope.of(context);
  var mode = 'both'; // students | parents | both
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) {
          final missing = students.where((s) {
            if (mode == 'students') return s.portalCode.trim().isEmpty;
            if (mode == 'parents') return s.parentPortalCode.trim().isEmpty;
            return s.portalCode.trim().isEmpty || s.parentPortalCode.trim().isEmpty;
          }).length;
          final summary = students.isEmpty
              ? 'لا يوجد طلاب مسجلون في هذا الصف'
              : missing == 0
                  ? 'الطلاب: ${students.length}  ·  جميعهم لديهم رموز'
                  : 'الطلاب: ${students.length}  ·  بلا رمز: $missing';

          String tsv() {
            final buf = StringBuffer();
            if (mode == 'students') {
              buf.writeln('الاسم\tرمز الطالب');
              for (final s in students) {
                buf.writeln('${s.fullName}\t${s.portalCode}');
              }
            } else if (mode == 'parents') {
              buf.writeln('الاسم\tرمز ولي الأمر');
              for (final s in students) {
                buf.writeln('${s.fullName}\t${s.parentPortalCode}');
              }
            } else {
              buf.writeln('الاسم\tرمز الطالب\tرمز ولي الأمر');
              for (final s in students) {
                buf.writeln('${s.fullName}\t${s.portalCode}\t${s.parentPortalCode}');
              }
            }
            return buf.toString();
          }

          Widget modeChip(String id, String label) {
            final on = mode == id;
            return InkWell(
              onTap: () => setSheet(() => mode = id),
              borderRadius: BorderRadius.circular(Corner.field),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? AppColors.navy : Colors.white,
                  borderRadius: BorderRadius.circular(Corner.field),
                  border: Border.all(color: on ? AppColors.navy : AppColors.line),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: on ? Colors.white : AppColors.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.vpn_key_outlined, size: 18, color: AppColors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'رموز دخول البوابة — ${room.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.cardTitle,
                              ),
                              const SizedBox(height: 2),
                              Text(summary, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        if (missing > 0 && store.can('students'))
                          PrimaryButton(
                            label: 'توليد الناقص',
                            icon: Icons.autorenew,
                            onPressed: () {
                              final made = store.ensureStudentPortalCodes(students);
                              showAppSnack(ctx, 'تم توليد $made رمزاً');
                            },
                          ),
                      ],
                    ),
                  ),
                  if (students.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          modeChip('students', 'طلاب'),
                          const SizedBox(width: 6),
                          modeChip('parents', 'أولياء'),
                          const SizedBox(width: 6),
                          modeChip('both', 'الاثنان'),
                        ],
                      ),
                    ),
                  const Divider(height: 1, color: AppColors.line),
                  if (students.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                      child: Column(
                        children: [
                          Icon(Icons.groups_outlined, size: 30, color: AppColors.faint),
                          SizedBox(height: 8),
                          Text(
                            'لا يوجد طلاب في هذا الصف بعد',
                            style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'تظهر رموز الدخول هنا بعد تسجيل الطلاب في الصف.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: students.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (_, i) {
                          final student = students[i];
                          final code = student.portalCode.trim();
                          final parentCode = student.parentPortalCode.trim();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(width: 22, child: Text('${i + 1}', style: AppText.label)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    student.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.body,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (mode != 'parents') _codeLine('الطالب', code),
                                    if (mode == 'both') const SizedBox(height: 2),
                                    if (mode != 'students') _codeLine('ولي الأمر', parentCode),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1, color: AppColors.line),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        if (students.isNotEmpty)
                          Expanded(
                            child: GhostButton(
                              label: 'نسخ Excel',
                              icon: Icons.copy_all_outlined,
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: tsv()));
                                if (ctx.mounted) showAppSnack(ctx, 'تم نسخ الكشف (TSV)');
                              },
                            ),
                          ),
                        if (students.isNotEmpty) const SizedBox(width: 8),
                        Expanded(
                          child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// سطر كلمة مرور في كشف الرموز: صاحبها ثم الكلمة، أو «بلا رمز».
Widget _codeLine(String owner, String code) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$owner: ', style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
      if (code.isEmpty)
        const Text('بلا رمز', style: TextStyle(color: AppColors.faint, fontSize: 11.5))
      else
        SelectableText(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 1.2,
            color: AppColors.heading,
          ),
        ),
    ],
  );
}
