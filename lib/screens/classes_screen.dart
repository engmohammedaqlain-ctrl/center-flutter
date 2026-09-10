import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'attendance_print.dart';
import 'student_detail_screen.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  String? selectedId;
  String tier = 'all';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('classes')) {
          return NoAccess(section: 'classes', roleName: store.roleName);
        }
        if (selectedId != null) {
          final room = store.rooms.where((r) => r.id == selectedId).firstOrNull;
          if (room != null) {
            return _ClassDetail(
              room: room,
              onBack: () => setState(() => selectedId = null),
              onEdit: () => _editRoom(context, room),
            );
          }
        }

        final filtered = store.rooms.where((r) => tier == 'all' || _roomTier(store, r) == tier).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    color: AppColors.amberSoft,
                    child: Icon(Icons.apartment, color: AppColors.heading, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('صفوف وشعب المدرسة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
                        Text('المعروض: ${filtered.length} من أصل ${store.rooms.length} صف', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  PrimaryButton(label: 'صف جديد', icon: Icons.add, onPressed: () => _editRoom(context, null)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('all', 'جميع الصفوف', store.rooms.length),
                  _chip('secondary', 'الثانوية (10-12)', store.rooms.where((r) => _roomTier(store, r) == 'secondary').length),
                  _chip('middle', 'الإعدادية (5-9)', store.rooms.where((r) => _roomTier(store, r) == 'middle').length),
                  _chip('primary', 'الابتدائية (1-4)', store.rooms.where((r) => _roomTier(store, r) == 'primary').length),
                  _chip('kindergarten', 'رياض الأطفال', store.rooms.where((r) => _roomTier(store, r) == 'kindergarten').length),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (filtered.isEmpty)
              const EmptyState(message: 'لا توجد شعب أو صفوف مسجلة في هذه المرحلة.')
            else
              for (final room in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RoomCard(
                    room: room,
                    teacher: store.teacherById(room.teacherId),
                    students: store.studentsOf(room),
                    onOpen: () => setState(() => selectedId = room.id),
                    onEdit: () => _editRoom(context, room),
                    onAssign: () => _assignTeacher(context, room),
                    onDelete: () async {
                      final ok = await confirmSheet(context, title: 'حذف الصف', message: 'سيتم حذف "${room.name}".', confirmLabel: 'حذف');
                      if (ok) store.deleteRoom(room.id);
                    },
                  ),
                ),
          ],
        );
      },
    );
  }

  String _roomTier(AppStore store, Classroom room) {
    if (room.tier.isNotEmpty && educationalStageTiers.containsKey(room.tier)) return room.tier;
    final matched = store.gradeFees.where((f) => f.gradeName.trim().toLowerCase() == room.gradeLevel.trim().toLowerCase()).firstOrNull;
    if (matched != null && educationalStageTiers.containsKey(matched.tier)) return matched.tier;
    final g = room.gradeLevel.toLowerCase();
    if (g.contains('ثاني عشر') || g.contains('حادي عشر') || g.contains('عاشر') || g.contains('ثانوي')) return 'secondary';
    if (g.contains('تاسع') || g.contains('ثامن') || g.contains('سابع') || g.contains('سادس') || g.contains('خامس') || g.contains('إعداد')) return 'middle';
    if (g.contains('روضة') || g.contains('رياض') || g.contains('تمهيدي') || g.contains('بستان')) return 'kindergarten';
    return 'other';
  }

  Widget _chip(String id, String label, int count) {
    final on = tier == id;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: () => setState(() => tier = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: on ? AppColors.navy : const Color(0xFFF3F4F6),
          child: Text('$label ($count)', style: TextStyle(color: on ? Colors.white : AppColors.muted, fontWeight: FontWeight.w800, fontSize: 11)),
        ),
      ),
    );
  }

  Future<void> _editRoom(BuildContext context, Classroom? room) async {
    final store = StoreScope.of(context);
    final name = TextEditingController(text: room?.name ?? '');
    String grade = room?.gradeLevel ?? (store.gradeFees.isNotEmpty ? store.gradeFees.first.gradeName : gradeLevelsFilter.first);
    String teacherId = room?.teacherId ?? (store.teachers.isNotEmpty ? store.teachers.first.id : '');
    String stageTier = room?.tier.isNotEmpty == true ? room!.tier : (store.gradeFees.where((g) => g.gradeName == grade).firstOrNull?.tier ?? 'secondary');
    final cap = TextEditingController(text: '${room?.capacity ?? 30}');
    final notes = TextEditingController(text: room?.notes ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              return SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room == null ? 'إضافة صف / شعبة جديدة' : 'تعديل: ${room.name}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
                  const SizedBox(height: 12),
                  const FieldLabel('اسم الصف / الشعبة', requiredField: true),
                  TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: شعبة 1، شعبة أ، عاشر أ...')),
                  const SizedBox(height: 10),
                  const FieldLabel('المرحلة التعليمية الكبرى', requiredField: true),
                  AppDropdown<String>(
                    value: educationalStageTiers.containsKey(stageTier) ? stageTier : 'secondary',
                    items: educationalStageTiers.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setSt(() => stageTier = v ?? stageTier),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('المرحلة الدراسية التابعة لها', requiredField: true),
                  AppDropdown<String>(
                    value: store.gradeFees.any((g) => g.gradeName == grade) ? grade : (store.gradeFees.isNotEmpty ? store.gradeFees.first.gradeName : grade),
                    items: (store.gradeFees.isEmpty ? gradeLevelsFilter : store.gradeFees.map((g) => g.gradeName).toList())
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setSt(() {
                      grade = v ?? grade;
                      final match = store.gradeFees.where((g) => g.gradeName == grade).firstOrNull;
                      if (match != null) stageTier = match.tier;
                    }),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('المربي / مشرف الصف'),
                  AppDropdown<String>(
                    value: teacherId.isEmpty ? null : teacherId,
                    items: store.teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                    onChanged: (v) => setSt(() => teacherId = v ?? teacherId),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('السعة الاستيعابية (طالب)', requiredField: true),
                  TextField(controller: cap, keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  const FieldLabel('ملاحظات حول الصف'),
                  TextField(controller: notes, decoration: const InputDecoration(hintText: 'ملاحظات اختيارية...')),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    expand: true,
                    label: room == null ? 'إضافة الشعبة' : 'حفظ التعديلات',
                    onPressed: () {
                      if (grade.trim().isEmpty) {
                        showAppSnack(context, 'يرجى تحديد المرحلة الدراسية التابعة لها هذه الشعبة', error: true);
                        return;
                      }
                      try {
                        store.upsertRoom(
                          Classroom(
                            id: room?.id ?? store.newId(),
                            name: name.text.trim(),
                            gradeLevel: grade,
                            teacherId: teacherId,
                            capacity: int.tryParse(cap.text) ?? 30,
                            notes: notes.text.trim(),
                            tier: stageTier,
                          ),
                        );
                        Navigator.pop(ctx);
                      } on StoreException catch (e) {
                        showAppSnack(context, e.message, error: true);
                      }
                    },
                  ),
                ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _assignTeacher(BuildContext context, Classroom room) async {
    final store = StoreScope.of(context);
    String teacherId = room.teacherId;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تعيين المربي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
                  const SizedBox(height: 12),
                  AppDropdown<String>(
                    value: teacherId.isEmpty ? null : teacherId,
                    items: store.teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                    onChanged: (v) => setSt(() => teacherId = v ?? teacherId),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    expand: true,
                    label: 'حفظ',
                    onPressed: () {
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
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.teacher,
    required this.students,
    required this.onOpen,
    required this.onEdit,
    required this.onAssign,
    required this.onDelete,
  });

  final Classroom room;
  final Teacher? teacher;
  final List<Student> students;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onAssign;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final debtors = students.where((s) => s.isDebtor).length;
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(Gap.lg),
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
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle,
                    ),
                    const SizedBox(height: Gap.xs),
                    StatusChip.amber(room.gradeLevel),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'خيارات الصف',
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
                constraints: const BoxConstraints(minWidth: 180),
                onSelected: (v) {
                  if (v == 'print') {
                    printClassRoster(context, store: StoreScope.of(context), room: room, students: students);
                  }
                  if (v == 'codes') {
                    showClassPortalCodes(context, room: room, students: students);
                  }
                  if (v == 'edit') onEdit();
                  if (v == 'assign') onAssign();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'print', child: Text('طباعة كشف الصف')),
                  PopupMenuItem(value: 'codes', child: Text('رموز دخول البوابة')),
                  PopupMenuItem(value: 'edit', child: Text('تعديل بيانات الصف')),
                  PopupMenuItem(value: 'assign', child: Text('تعيين مربي')),
                  PopupMenuItem(value: 'delete', child: Text('حذف الصف')),
                ],
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: Gap.md),
          // سطر لكل معلومة بأيقونتها، فتُقرأ البطاقة بلمحة واحدة
          _line(
            Icons.school_outlined,
            teacher == null ? 'تعيين مربي الصف' : teacher!.name,
            faded: teacher == null,
          ),
          const SizedBox(height: Gap.sm),
          _line(Icons.groups_outlined, 'الطلاب: ${students.length} / ${room.capacity}'),
          if (debtors > 0) ...[
            const SizedBox(height: Gap.sm),
            _line(Icons.error_outline, '$debtors طلاب عليهم مستحقات', color: AppColors.danger),
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text, {Color? color, bool faded = false}) {
    final fg = color ?? (faded ? AppColors.faint : AppColors.muted);
    return Row(
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              height: 1.4,
              fontWeight: color != null ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClassDetail extends StatefulWidget {
  const _ClassDetail({required this.room, required this.onBack, required this.onEdit});
  final Classroom room;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  @override
  State<_ClassDetail> createState() => _ClassDetailState();
}

class _ClassDetailState extends State<_ClassDetail> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final teacher = store.teacherById(widget.room.teacherId);
    final q = search.text.trim();
    final list = store.studentsOf(widget.room).where((s) {
      if (q.isEmpty) return true;
      return s.fullName.contains(q) || s.phone.contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        AppCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  GhostButton(label: 'العودة للصفوف', icon: Icons.arrow_back, onPressed: widget.onBack),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.room.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
                        if (teacher != null) Text('المربي: ${teacher.name}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  SquareIconButton(
                    icon: Icons.print_outlined,
                    onTap: () => printClassRoster(
                      context,
                      store: StoreScope.of(context),
                      room: widget.room,
                      students: list,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SquareIconButton(icon: Icons.edit_outlined, onTap: widget.onEdit),
                  const SizedBox(width: 6),
                  StatusChip.muted('${list.length} / ${widget.room.capacity}'),
                ],
              ),
              if (widget.room.notes.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ملاحظات: ${widget.room.notes}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SearchField(controller: search, hint: 'ابحث باسم الطالب أو الهاتف...', onChanged: (_) => setState(() {})),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const EmptyState(message: 'لا يوجد طلاب مسجلين في هذا الصف')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.5,
            ),
            itemBuilder: (_, i) {
              final s = list[i];
              return AppCard(
                padding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: s.id)));
                },
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      color: AppColors.amberSoft,
                      child: Row(
                        children: [
                          Text((i + 1).toString().padLeft(2, '0'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 12)),
                          const Spacer(),
                          s.isDebtor ? StatusChip.danger('عليه مستحق') : StatusChip.success('مسدد'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(s.fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
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
        final missing = students.where((s) => s.portalCode.trim().isEmpty).length;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Row(
                    children: [
                      Icon(Icons.vpn_key_outlined, size: 18, color: AppColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('رموز دخول البوابة — ${room.name}', style: AppText.cardTitle),
                            Text('${students.length} طالب · بلا رمز: $missing', style: AppText.label),
                          ],
                        ),
                      ),
                      if (missing > 0)
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
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: students.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (_, i) {
                      final student = students[i];
                      final code = student.portalCode.trim();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Text('${i + 1}', style: AppText.label),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                student.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body,
                              ),
                            ),
                            if (code.isEmpty)
                              const Text('—', style: TextStyle(color: AppColors.faint, fontSize: 13))
                            else
                              SelectableText(
                                code,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 1.5,
                                  color: AppColors.heading,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
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
