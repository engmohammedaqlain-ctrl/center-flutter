import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
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

        final filtered = store.rooms.where((r) => tier == 'all' || r.tier == tier).toList();
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
                    child: const Icon(Icons.apartment, color: AppColors.heading, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('صفوف وشعب المدرسة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
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
                  _chip('secondary', 'الثانوية (10-12)', store.rooms.where((r) => r.tier == 'secondary').length),
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
    String grade = room?.gradeLevel ?? gradeLevelsFilter.first;
    String teacherId = room?.teacherId ?? (store.teachers.isNotEmpty ? store.teachers.first.id : '');
    final cap = TextEditingController(text: '${room?.capacity ?? 25}');
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
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room == null ? 'إضافة صف / شعبة جديدة' : 'تعديل: ${room.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
                  const SizedBox(height: 12),
                  const FieldLabel('اسم الصف / الشعبة *'),
                  TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: الشعبة (أ)...')),
                  const SizedBox(height: 10),
                  const FieldLabel('المرحلة الدراسية *'),
                  AppDropdown<String>(
                    value: grade,
                    items: gradeLevelsFilter.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (v) => setSt(() => grade = v ?? grade),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('المربي'),
                  AppDropdown<String>(
                    value: teacherId.isEmpty ? null : teacherId,
                    items: store.teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                    onChanged: (v) => setSt(() => teacherId = v ?? teacherId),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('السعة'),
                  TextField(controller: cap, keyboardType: TextInputType.number),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    expand: true,
                    label: 'حفظ',
                    onPressed: () {
                      try {
                        store.upsertRoom(
                          Classroom(
                            id: room?.id ?? store.newId(),
                            name: name.text.trim(),
                            gradeLevel: grade,
                            teacherId: teacherId,
                            capacity: int.tryParse(cap.text) ?? 25,
                            notes: room?.notes ?? '',
                          ),
                        );
                        Navigator.pop(ctx);
                      } on StoreException catch (e) {
                        showAppSnack(context, e.message, error: true);
                      }
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
                  const Text('تعيين المربي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
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
                    Text(room.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
                    const SizedBox(height: 4),
                    StatusChip.amber(room.gradeLevel),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'assign') onAssign();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('تعديل بيانات الصف')),
                  PopupMenuItem(value: 'assign', child: Text('تعيين مربي')),
                  PopupMenuItem(value: 'delete', child: Text('حذف الصف')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(teacher == null ? '+ تعيين مربي' : 'المربي: ${teacher!.name}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text('الطلاب: ${students.length} / ${room.capacity}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          if (debtors > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('$debtors طلاب عليهم مستحقات', style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
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
                  GhostButton(label: 'العودة للصفوف', icon: Icons.arrow_forward, onPressed: widget.onBack),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.room.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
                        if (teacher != null) Text('المربي: ${teacher.name}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  SquareIconButton(icon: Icons.edit_outlined, onTap: widget.onEdit),
                  const SizedBox(width: 6),
                  StatusChip.muted('${list.length} / ${widget.room.capacity}'),
                ],
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
                          Text((i + 1).toString().padLeft(2, '0'), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 12)),
                          const Spacer(),
                          s.isDebtor ? StatusChip.danger('عليه مستحق') : StatusChip.success('مسدد'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(s.fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
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
