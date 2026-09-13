import 'package:flutter/material.dart';

import '../data/class_tiers.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'attendance_print.dart';
import 'attendance_screen.dart';
import 'room_form_screen.dart';
import 'student_detail_screen.dart';

/// الصفوف والشعب — المقابل لـ `pages/SchoolClasses.tsx`.
///
/// بتنسيق المالية: شريط المراحل أعلى الشاشة، ثم بطاقات أرقام، ثم بطاقة لكل صف —
/// الاسم ومرحلته مقابل الخيارات، وخط رفيع، ثم المربي والإشغال بشريط سعة.
/// «صف جديد» زر ثابت في متناول الإبهام، والصف يُفتح صفحةً بعنوانه.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  String tier = 'all';

  static const _tierLabels = {
    'all': 'جميع الصفوف',
    'secondary': 'الثانوية (10-12)',
    'middle': 'الإعدادية (5-9)',
    'primary': 'الابتدائية (1-4)',
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

        final canEdit = store.can('schedule.edit');
        final tiers = {for (final r in store.rooms) r.id: classTier(store, r)};
        int countOf(String id) => id == 'all' ? store.rooms.length : tiers.values.where((t) => t == id).length;
        // رياض الأطفال تظهر حين يوجد لها صف فقط، كما في Center
        final tabs = _tierLabels.keys.where((id) => id != 'kindergarten' || countOf(id) > 0).toList();
        if (!tabs.contains(tier)) tier = 'all';

        final rooms = store.rooms.where((r) => tier == 'all' || tiers[r.id] == tier).toList();
        final rosters = {for (final r in rooms) r.id: store.studentsOf(r)};
        final enrolled = rosters.values.fold<int>(0, (a, l) => a + l.length);
        final debtors = rosters.values.fold<int>(0, (a, l) => a + l.where((s) => s.isDebtor).length);

        return ThumbActionLayer(
          action: canEdit
              ? ThumbAction(label: 'صف جديد', icon: Icons.add, onPressed: () => _openRoomForm(context, null))
              : null,
          child: Column(
            children: [
              _tierBar(tabs, countOf),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, thumbActionClearance),
                  itemCount: 1 + (rooms.isEmpty ? 1 : rooms.length),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: StatRow(
                          children: [
                            StatCard(
                              label: 'الصفوف',
                              value: '${rooms.length}',
                              color: AppColors.heading,
                            ),
                            StatCard(
                              label: 'الطلاب',
                              value: '$enrolled',
                              color: AppColors.heading,
                            ),
                            StatCard(
                              label: 'عليهم مستحقات',
                              value: '$debtors',
                              color: debtors > 0 ? AppColors.danger : AppColors.success,
                            ),
                          ],
                        ),
                      );
                    }
                    if (rooms.isEmpty) {
                      return const SizedBox(
                        height: 220,
                        child: EmptyState(message: 'لا توجد شعب أو صفوف مسجلة في هذه المرحلة.'),
                      );
                    }
                    final room = rooms[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RoomCard(
                        room: room,
                        teacher: store.teacherById(room.teacherId),
                        students: rosters[room.id]!,
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
                  color: on ? AppColors.navy : Colors.white,
                  borderRadius: BorderRadius.circular(Corner.field),
                  border: Border.all(color: on ? AppColors.navy : AppColors.line),
                ),
                child: Text(
                  '${_tierLabels[id]} (${countOf(id)})',
                  style: TextStyle(
                    color: on ? Colors.white : AppColors.muted,
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

int _seatsOf(Classroom room) => room.capacity > 0 ? room.capacity : 30;

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
                  for (final t in store.teachers)
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

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    final existing = store.sectionSubjectGroups(widget.room.id);
    if (existing.isNotEmpty) {
      rows = {for (final g in existing) g.subjectId: g.teacherId};
    } else {
      // شعبة جديدة: تُبدأ بمواد مرحلتها، فلا يُبنى الجدول من الصفر كل مرة
      rows = {for (final s in store.gradeApplicableSubjects(widget.room.gradeLevel)) s.id: ''};
    }
  }

  void _save() {
    try {
      final count = widget.store.saveSectionSubjectAssignments(
        roomId: widget.room.id,
        gradeLevel: widget.room.gradeLevel,
        roomName: widget.room.name,
        assignments: rows,
      );
      Navigator.pop(context);
      showAppSnack(context, count == 0 ? 'تم رفع إسناد جميع المواد' : 'تم إسناد $count مادة لمعلميها');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final subjects = store.subjects;
    final available = subjects.where((s) => !rows.containsKey(s.id)).toList();
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
                          'المواد: ${rows.length}  ·  المسندة: $assigned',
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
                  'لا توجد مواد دراسية بعد. تُضاف من «الإعدادات ← المواد».',
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
                    for (final entry in rows.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                          decoration: tileDecoration(),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 92,
                                child: Text(
                                  store.subjectName(entry.key),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppDropdown<String>(
                                  value: store.teacherById(entry.value) == null ? '' : entry.value,
                                  items: [
                                    const DropdownMenuItem(value: '', child: Text('بلا معلم')),
                                    for (final t in store.teachers)
                                      DropdownMenuItem(
                                        value: t.id,
                                        child: Text(t.name, overflow: TextOverflow.ellipsis),
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
                      ),
                    if (available.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: AppDropdown<String>(
                              value: adding.isEmpty ? null : adding,
                              hint: 'إضافة مادة للشعبة',
                              items: [
                                for (final s in available)
                                  DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
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
                  ],
                ),
              ),
            const Divider(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: 'حفظ الإسناد',
                      icon: Icons.check,
                      height: 44,
                      onPressed: subjects.isEmpty ? null : _save,
                    ),
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

Future<void> _confirmDeleteRoom(BuildContext context, Classroom room, {VoidCallback? onDeleted}) async {
  final store = StoreScope.of(context);
  final ok = await confirmSheet(
    context,
    title: 'تأكيد حذف الصف',
    message: 'هل تريد حذف الصف "${room.name}"؟ لن يتم حذف الطلاب المسجلين فيه.',
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

TextStyle get _titleStyle => TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.heading);

const _metaStyle = TextStyle(color: AppColors.muted, fontSize: 11);

/// الصف: الاسم ومرحلته مقابل الخيارات، ثم خط رفيع، ثم المربي مقابل عدد الطلاب،
/// وشريط السعة، وتنبيه المستحقات إن وُجدت.
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
    final seats = _seatsOf(room);
    final full = students.length >= seats;
    final debtors = students.where((s) => s.isDebtor).length;
    final teacherCount = store.sectionTeacherIds(room).length;
    final grade = [
      room.gradeLevel.trim().isEmpty ? 'مرحلة غير محددة' : room.gradeLevel.trim(),
      if (teacherCount > 0) _teachersLabel(teacherCount),
    ].join('  ·  ');

    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 2, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                      const SizedBox(height: 2),
                      Text(grade, maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات الصف',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
                constraints: const BoxConstraints(minWidth: 190),
                onSelected: (v) {
                  if (v == 'attendance') openClassAttendance(context, room: room);
                  if (v == 'print') printClassRoster(context, store: store, room: room, students: students);
                  if (v == 'codes') showClassPortalCodes(context, room: room, students: students);
                  if (v == 'edit') _openRoomForm(context, room);
                  if (v == 'assign') _assignTeacher(context, room);
                  if (v == 'subjects') _assignSubjectTeachers(context, room);
                  if (v == 'delete') _confirmDeleteRoom(context, room);
                },
                itemBuilder: (_) => [
                  if (store.can('attendance.view'))
                    _menuItem('attendance', Icons.fact_check_outlined, 'رصد الحضور'),
                  _menuItem('print', Icons.download_outlined, 'تنزيل كشف الصف (PDF)'),
                  _menuItem('codes', Icons.vpn_key_outlined, 'رموز دخول الطلاب'),
                  if (canEdit) ...[const PopupMenuDivider(height: 8), ..._manageItems(teacher)],
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 10),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
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
                              style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700),
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
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${students.length}',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.heading),
                          ),
                          TextSpan(text: ' / $seats طالب'),
                        ],
                      ),
                      style: _metaStyle,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // الإشغال بلمحة: أحمر حين يمتلئ الصف
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (students.length / seats).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: const Color(0xFFF1F5F9),
                    color: full ? AppColors.danger : AppColors.success,
                  ),
                ),
                if (debtors > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: AppColors.danger),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '$debtors طلاب عليهم مستحقات',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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
        final room = store.rooms.where((r) => r.id == widget.roomId).firstOrNull;
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
        final canEdit = store.can('schedule.edit');
        final roster = store.studentsOf(room);
        final q = search.text.trim();
        final list = q.isEmpty ? roster : roster.where((s) => s.fullName.contains(q) || s.phone.contains(q)).toList();
        final debtors = roster.where((s) => s.isDebtor).length;
        final meta = [
          if (room.gradeLevel.trim().isNotEmpty) room.gradeLevel.trim(),
          teacher == null ? 'بدون مربي' : 'المربي: ${teacher.name}',
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
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: SearchField(
                  controller: search,
                  hint: 'ابحث باسم الطالب أو الهاتف...',
                  onChanged: (_) => setState(() {}),
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
                            StatRow(
                              children: [
                                StatCard(
                                  label: 'الطلاب',
                                  value: '${roster.length}',
                                  color: AppColors.heading,
                                ),
                                StatCard(label: 'مسددون', value: '${roster.length - debtors}', color: AppColors.success),
                                StatCard(
                                  label: 'عليهم مستحقات',
                                  value: '$debtors',
                                  color: debtors > 0 ? AppColors.danger : AppColors.heading,
                                ),
                                StatCard(
                                  label: 'المعلمون',
                                  value: '${store.sectionTeacherIds(room).length}',
                                  color: AppColors.heading,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // الرصد أول ما يُطلب من صفحة الصف، فيكون أول زر فيها
                            Row(
                              children: [
                                if (store.can('attendance.view'))
                                  Expanded(
                                    child: PrimaryButton(
                                      label: 'رصد الحضور',
                                      icon: Icons.fact_check_outlined,
                                      height: 40,
                                      expand: true,
                                      onPressed: () => openClassAttendance(context, room: room),
                                    ),
                                  ),
                                if (store.can('attendance.view') && canEdit) const SizedBox(width: 8),
                                if (canEdit)
                                  Expanded(
                                    child: GhostButton(
                                      label: 'معلمو المواد',
                                      icon: Icons.menu_book_outlined,
                                      onPressed: () => _assignSubjectTeachers(context, room),
                                    ),
                                  ),
                              ],
                            ),
                            _SubjectTeachersCard(room: room),
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
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        // كشف واحد بإطار رفيع، صف لكل طالب — يُقرأ كقائمة الصف الورقية
                        sliver: DecoratedSliver(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Corner.card),
                            border: Border.all(color: AppColors.line),
                          ),
                          sliver: SliverList.builder(
                            itemCount: list.length,
                            itemBuilder: (context, i) => _RosterRow(
                              seat: roster.indexOf(list[i]) + 1,
                              student: list[i],
                              showBalance: store.can('finance.view'),
                              last: i == list.length - 1,
                            ),
                          ),
                        ),
                      ),
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

/// مواد الصف ومعلموها — سطر لكل مادة. لا تظهر قبل أن يُسند شيء.
class _SubjectTeachersCard extends StatelessWidget {
  const _SubjectTeachersCard({required this.room});

  final Classroom room;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final assigned = store.sectionSubjectGroups(room.id).where((g) => g.teacherId.trim().isNotEmpty).toList()
      ..sort((a, b) => store.subjectName(a.subjectId).compareTo(store.subjectName(b.subjectId)));
    if (assigned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle('مواد الصف ومعلموها (${assigned.length})'),
            for (final g in assigned)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 14, color: AppColors.faint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        store.subjectName(g.subjectId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        store.teacherName(g.teacherId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
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

/// طالب في كشف الصف: رقم مقعده، واسمه وهاتفه، وحالته المالية في الطرف، وسهم يفتح ملفه.
class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.seat, required this.student, required this.showBalance, required this.last});

  final int seat;
  final Student student;

  /// المبلغ المستحق لمن يملك عرض المالية، وكلمة الحالة لغيره.
  final bool showBalance;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final canOpen = store.can('students.view');
    final debt = student.isDebtor;
    final phone = student.phone.trim();

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
            Text(
              debt ? (showBalance ? 'عليه ${money(student.balance)}' : 'عليه مستحق') : 'مسدد',
              style: TextStyle(
                color: debt ? AppColors.danger : AppColors.success,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (canOpen) ...[
              const SizedBox(width: 2),
              // «التالي» ينعكس مع الاتجاه فيُرسم «<»
              const Icon(Icons.chevron_right, size: 18, color: AppColors.faint),
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
Future<void> showClassPortalCodes(
  BuildContext context, {
  required Classroom room,
  required List<Student> students,
}) {
  final store = StoreScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final missing = students
            .where((s) => s.portalCode.trim().isEmpty || s.parentPortalCode.trim().isEmpty)
            .length;
        final summary = students.isEmpty
            ? 'لا يوجد طلاب مسجلون في هذا الصف'
            : missing == 0
                ? 'الطلاب: ${students.length}  ·  جميعهم لديهم رموز'
                : 'الطلاب: ${students.length}  ·  بلا رمز: $missing';

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                      if (missing > 0 && store.can('students.edit'))
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
                const Divider(height: 1, color: AppColors.line),
                if (students.isEmpty)
                  // لا قائمة فارغة تحجز نصف الشاشة: رسالة قصيرة بحجمها
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
                              // كلمة الطالب ثم كلمة ولي أمره
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _codeLine('الطالب', code),
                                  const SizedBox(height: 2),
                                  _codeLine('ولي الأمر', parentCode),
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
                  child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
                ),
              ],
            ),
          ),
        );
      },
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
