import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// الجداول والمجموعات — المقابل لـ `pages/Schedule.tsx` وملفات `features/schedule`.
///
/// يظهر في نظام «مركز تعليمي»؛ نظام المدرسة يستعمل شاشة الصفوف بدلاً منه.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int tab = 0;
  final search = TextEditingController();
  String status = 'active';

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
        if (!store.canOpenSection('schedule')) {
          return NoAccess(section: 'schedule', roleName: store.roleName);
        }
        final canEdit = store.can('schedule.edit');
        final q = search.text.trim();
        final list = store.groups.where((g) {
          if (status.isNotEmpty && g.status != status) return false;
          if (q.isEmpty) return true;
          return g.name.contains(q) ||
              store.subjectName(g.subjectId).contains(q) ||
              store.teacherName(g.teacherId).contains(q);
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: Colors.white, border: Border.all(color: AppColors.line)),
              child: Row(
                children: [
                  Expanded(child: _tab('المجموعات', Icons.groups_2_outlined, 0, '${store.groups.length}')),
                  Expanded(child: _tab('الجدول الأسبوعي', Icons.calendar_month_outlined, 1, '')),
                  if (canEdit)
                    PrimaryButton(
                      label: 'مجموعة',
                      icon: Icons.add,
                      onPressed: () => _editGroup(context, null),
                    ),
                ],
              ),
            ),
            if (tab == 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SearchField(
                        controller: search,
                        hint: 'ابحث باسم المجموعة أو المادة أو المدرّس...',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: AppDropdown<String>(
                        value: status,
                        items: const [
                          DropdownMenuItem(value: '', child: Text('الكل')),
                          DropdownMenuItem(value: 'active', child: Text('نشطة')),
                          DropdownMenuItem(value: 'pending', child: Text('معلّقة')),
                          DropdownMenuItem(value: 'archived', child: Text('مؤرشفة')),
                        ],
                        onChanged: (v) => setState(() => status = v ?? ''),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: EmptyState(message: 'لا توجد مجموعات دراسية مطابقة'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: list.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _GroupCard(
                            group: list[i],
                            canEdit: canEdit,
                            onEdit: () => _editGroup(context, list[i]),
                            onEnroll: () => _enroll(context, list[i]),
                            onDelete: () => _deleteGroup(context, list[i]),
                          ),
                        ),
                      ),
              ),
            ] else
              Expanded(child: _WeeklyView(onPrint: () => _printSchedule(context))),
          ],
        );
      },
    );
  }

  Widget _tab(String label, IconData icon, int i, String count) {
    final on = tab == i;
    return InkWell(
      onTap: () => setState(() => tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? AppColors.amber : Colors.transparent, width: 2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: on ? AppColors.heading : AppColors.muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? AppColors.heading : AppColors.muted),
              ),
            ),
            if (count.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                color: const Color(0xFFF3F4F6),
                child: Text(count, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGroup(BuildContext context, Group g) async {
    final store = StoreScope.of(context);
    final ok = await confirmSheet(
      context,
      title: 'حذف المجموعة',
      message: 'هل تريد حذف مجموعة «${g.name}» نهائياً؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !context.mounted) return;
    try {
      store.deleteGroup(g.id);
      showAppSnack(context, 'تم حذف المجموعة');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _printSchedule(BuildContext context) async {
    final store = StoreScope.of(context);
    final active = store.groups.where((g) => g.isActive).toList();
    final bytes = await PdfKit.build(
      title: 'الجدول الأسبوعي للمجموعات',
      institutionName: store.institutionName,
      logoBase64: store.institutionLogo,
      landscape: true,
      body: (ctx) => [
        for (var d = 0; d < 7; d++)
          if (active.any((g) => g.days.contains(d))) ...[
            pw.Text(daysOfWeek[d], style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            PdfKit.table(
              headers: ['المجموعة', 'المادة', 'المدرّس', 'القاعة', 'الوقت', 'الطلاب'],
              rows: [
                for (final g in active.where((g) => g.days.contains(d)).toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime)))
                  [
                    g.name,
                    store.subjectName(g.subjectId),
                    store.teacherName(g.teacherId),
                    store.roomName(g.roomId),
                    g.timeLabel,
                    '${store.enrollmentCount(g.id)}',
                  ],
              ],
              flex: [4, 3, 4, 3, 3, 2],
            ),
            pw.SizedBox(height: 12),
          ],
      ],
    );
    if (!context.mounted) return;
    await PdfKit.preview(bytes, 'الجدول الأسبوعي');
  }

  Future<void> _editGroup(BuildContext context, Group? existing) async {
    final store = StoreScope.of(context);
    if (store.subjects.isEmpty || store.teachers.isEmpty) {
      showAppSnack(context, 'أضف مادة دراسية ومدرّساً أولاً من الإعدادات', error: true);
      return;
    }

    final name = TextEditingController(text: existing?.name ?? '');
    final price = TextEditingController(text: '${existing?.pricePerMonth ?? 0}');
    final maxStudents = TextEditingController(text: existing?.maxStudents?.toString() ?? '');
    var subjectId = existing?.subjectId ?? store.subjects.first.id;
    var teacherId = existing?.teacherId ?? store.teachers.first.id;
    var roomId = existing?.roomId ?? '';
    var gradeLevel = existing?.gradeLevel ?? '';
    var days = [...(existing?.days ?? <int>[])];
    var startTime = existing?.startTime ?? '16:00';
    var endTime = existing?.endTime ?? '18:00';
    var groupStatus = existing?.status ?? 'active';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? 'إضافة مجموعة دراسية' : 'تعديل: ${existing.name}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                ),
                const SizedBox(height: 10),
                const FieldLabel('اسم المجموعة', requiredField: true),
                TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: رياضيات — توجيهي (أ)')),
                const SizedBox(height: 8),
                const FieldLabel('المادة الدراسية', requiredField: true),
                AppDropdown<String>(
                  value: subjectId,
                  items: store.subjects.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (v) => setSt(() => subjectId = v ?? subjectId),
                ),
                const SizedBox(height: 8),
                const FieldLabel('المدرّس', requiredField: true),
                AppDropdown<String>(
                  value: teacherId,
                  items: store.teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (v) => setSt(() => teacherId = v ?? teacherId),
                ),
                const SizedBox(height: 8),
                const FieldLabel('القاعة'),
                AppDropdown<String>(
                  value: roomId,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('-- بدون قاعة محددة --')),
                    ...store.rooms.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))),
                  ],
                  onChanged: (v) => setSt(() => roomId = v ?? ''),
                ),
                const SizedBox(height: 8),
                const FieldLabel('المرحلة الدراسية'),
                AppDropdown<String>(
                  value: gradeLevel,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('-- كل المراحل --')),
                    ...gradeLevelsFilter.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                  ],
                  onChanged: (v) => setSt(() => gradeLevel = v ?? ''),
                ),
                const SizedBox(height: 8),
                const FieldLabel('أيام الدوام', requiredField: true),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 0; d < 7; d++)
                      InkWell(
                        onTap: () => setSt(() => days.contains(d) ? days.remove(d) : days.add(d)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Corner.box),
                            color: days.contains(d) ? AppColors.amber : Colors.white,
                            border: Border.all(color: days.contains(d) ? AppColors.amber : AppColors.line),
                          ),
                          child: Text(
                            daysOfWeek[d],
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: days.contains(d) ? Colors.white : AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('من الساعة'),
                          _TimeField(value: startTime, onChanged: (v) => setSt(() => startTime = v)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('إلى الساعة'),
                          _TimeField(value: endTime, onChanged: (v) => setSt(() => endTime = v)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('السعر الشهري (₪)'),
                          TextField(controller: price, keyboardType: TextInputType.number),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('الحد الأقصى للطلاب'),
                          TextField(
                            controller: maxStudents,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: 'بلا حد'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const FieldLabel('الحالة'),
                AppDropdown<String>(
                  value: groupStatus,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('نشطة')),
                    DropdownMenuItem(value: 'pending', child: Text('معلّقة')),
                    DropdownMenuItem(value: 'archived', child: Text('مؤرشفة')),
                  ],
                  onChanged: (v) => setSt(() => groupStatus = v ?? 'active'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        label: existing == null ? 'إضافة المجموعة' : 'حفظ التعديلات',
                        onPressed: () {
                          try {
                            store.upsertGroup(
                              Group(
                                id: existing?.id ?? store.newId(),
                                name: name.text.trim(),
                                subjectId: subjectId,
                                teacherId: teacherId,
                                roomId: roomId,
                                gradeLevel: gradeLevel,
                                pricePerMonth: double.tryParse(price.text.trim()) ?? 0,
                                maxStudents: int.tryParse(maxStudents.text.trim()),
                                days: days,
                                startTime: startTime,
                                endTime: endTime,
                                status: groupStatus,
                                createdAt: existing?.createdAt,
                              ),
                            );
                            Navigator.pop(ctx);
                            if (context.mounted) showAppSnack(context, 'تم حفظ المجموعة');
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
    name.dispose();
    price.dispose();
    maxStudents.dispose();
  }

  Future<void> _enroll(BuildContext context, Group group) async {
    final store = StoreScope.of(context);
    final query = TextEditingController();
    final customPrice = TextEditingController();
    final reason = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final enrolled = store.enrollmentsInGroup(group.id);
          final enrolledIds = enrolled.map((e) => e.studentId).toSet();
          final q = query.text.trim();
          final candidates = store.students
              .where((s) => !enrolledIds.contains(s.id))
              .where((s) => q.isEmpty || s.fullName.contains(q) || s.phone.contains(q))
              .take(25)
              .toList();

          return Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تسجيل الطلاب — ${group.name}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                  ),
                  Text(
                    'المسجّلون: ${enrolled.length}${group.maxStudents != null ? ' / ${group.maxStudents}' : ''}'
                    '   ·   السعر: ${money(group.pricePerMonth)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  if (enrolled.isNotEmpty) ...[
                    const SectionTitle('الطلاب المسجّلون'),
                    for (final e in enrolled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                store.studentById(e.studentId)?.fullName ?? '—',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(money(e.appliedPrice ?? group.pricePerMonth),
                                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            const SizedBox(width: 8),
                            SquareIconButton(
                              icon: Icons.person_remove_outlined,
                              color: AppColors.danger,
                              onTap: () {
                                try {
                                  store.deleteEnrollment(e.id);
                                  setSt(() {});
                                } on StoreException catch (err) {
                                  showAppSnack(ctx, err.message, error: true);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  const SectionTitle('إضافة طالب'),
                  SearchField(
                    controller: query,
                    hint: 'ابحث بالاسم أو الهاتف...',
                    onChanged: (_) => setSt(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'سعر مخصص (اختياري)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: reason,
                          decoration: const InputDecoration(hintText: 'سبب الخصم'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('لا يوجد طلاب مطابقون', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    )
                  else
                    for (final s in candidates)
                      InkWell(
                        onTap: () {
                          try {
                            store.enrollStudent(
                              studentId: s.id,
                              groupId: group.id,
                              customPrice: double.tryParse(customPrice.text.trim()),
                              discountReason: reason.text,
                            );
                            customPrice.clear();
                            reason.clear();
                            setSt(() {});
                          } on StoreException catch (err) {
                            showAppSnack(ctx, err.message, error: true);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: AppColors.bg, border: Border.all(color: AppColors.line)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${s.fullName}  (${s.gradeLevel})',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              ),
                              Icon(Icons.add_circle_outline, size: 16, color: AppColors.amber),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
          );
        },
      ),
    );
    query.dispose();
    customPrice.dispose();
    reason.dispose();
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final parts = value.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: int.tryParse(parts.first) ?? 16,
            minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
          ),
        );
        if (picked != null) {
          onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: Colors.white, border: Border.all(color: AppColors.lineStrong)),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.canEdit,
    required this.onEdit,
    required this.onEnroll,
    required this.onDelete,
  });

  final Group group;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onEnroll;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final count = store.enrollmentCount(group.id);
    final full = group.maxStudents != null && count >= group.maxStudents!;

    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: canEdit ? onEnroll : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
                    Text(
                      '${store.subjectName(group.subjectId)} · ${store.teacherName(group.teacherId)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              switch (group.status) {
                'active' => StatusChip.success('نشطة'),
                'pending' => StatusChip.amber('معلّقة'),
                _ => StatusChip.muted('مؤرشفة'),
              },
              if (canEdit)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 18, color: AppColors.muted),
                  onSelected: (v) => switch (v) {
                    'edit' => onEdit(),
                    'enroll' => onEnroll(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل المجموعة')),
                    PopupMenuItem(value: 'enroll', child: Text('تسجيل الطلاب')),
                    PopupMenuItem(value: 'delete', child: Text('حذف المجموعة')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event_repeat, size: 13, color: AppColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text('${group.daysLabel}  ·  ${group.timeLabel}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined, size: 13, color: AppColors.muted),
              const SizedBox(width: 4),
              Text(store.roomName(group.roomId), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              const Spacer(),
              Text(
                'الطلاب: $count${group.maxStudents != null ? ' / ${group.maxStudents}' : ''}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: full ? AppColors.danger : AppColors.heading,
                ),
              ),
              const SizedBox(width: 8),
              Text(money(group.pricePerMonth),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.amber)),
            ],
          ),
        ],
      ),
    );
  }
}

/// الجدول الأسبوعي — المقابل لـ `WeeklyScheduleView.tsx`.
class _WeeklyView extends StatelessWidget {
  const _WeeklyView({required this.onPrint});
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final active = store.groups.where((g) => g.isActive).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        GhostButton(label: 'تصدير الجدول PDF', icon: Icons.picture_as_pdf_outlined, onPressed: onPrint),
        const SizedBox(height: 10),
        for (var d = 0; d < 7; d++)
          () {
            final ofDay = active.where((g) => g.days.contains(d)).toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));
            if (ofDay.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle('${daysOfWeek[d]} (${ofDay.length})'),
                    for (final g in ofDay)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(width: 3, height: 30, color: AppColors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                                  Text(
                                    '${store.subjectName(g.subjectId)} · ${store.teacherName(g.teacherId)} · ${store.roomName(g.roomId)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            Text(g.timeLabel,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.heading)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          }(),
        if (active.isEmpty) const EmptyState(message: 'لا توجد مجموعات نشطة في الجدول'),
      ],
    );
  }
}

/// بطاقة المجموعات في ملف الطالب.
class StudentGroupsCard extends StatelessWidget {
  const StudentGroupsCard({super.key, required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final mine = store.enrollmentsOf(student.id);
    if (mine.isEmpty && store.groups.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'المجموعات المسجّل بها (${mine.length})',
            trailing: store.can('schedule.edit')
                ? GhostButton(
                    label: 'تسجيل',
                    icon: Icons.add,
                    onPressed: () => _enrollHere(context, store),
                  )
                : null,
          ),
          if (mine.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('الطالب غير مسجّل في أي مجموعة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else
            for (final e in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(store.groupById(e.groupId)?.name ?? 'مجموعة محذوفة',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                          Text(
                            [
                              if (store.groupById(e.groupId) != null) store.groupById(e.groupId)!.daysLabel,
                              if (e.discountReason.isNotEmpty) 'خصم: ${e.discountReason}',
                            ].join('  ·  '),
                            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    Text(money(e.appliedPrice ?? 0),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.heading)),
                    if (store.can('schedule.edit')) ...[
                      const SizedBox(width: 6),
                      SquareIconButton(
                        icon: Icons.link_off,
                        color: AppColors.danger,
                        onTap: () async {
                          final ok = await confirmSheet(
                            context,
                            title: 'إلغاء التسجيل',
                            message: 'هل أنت متأكد من إلغاء اشتراك الطالب من هذه المجموعة؟',
                            confirmLabel: 'إلغاء التسجيل',
                          );
                          if (!ok || !context.mounted) return;
                          try {
                            store.deleteEnrollment(e.id);
                          } on StoreException catch (err) {
                            showAppSnack(context, err.message, error: true);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _enrollHere(BuildContext context, AppStore store) async {
    final mine = store.enrollmentsOf(student.id).map((e) => e.groupId).toSet();
    final available = store.groups.where((g) => g.isActive && !mine.contains(g.id)).toList();
    if (available.isEmpty) {
      showAppSnack(context, 'لا توجد مجموعات متاحة للتسجيل', error: true);
      return;
    }
    final price = TextEditingController();
    final reason = TextEditingController();
    var groupId = available.first.id;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تسجيل ${student.fullName} في مجموعة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading)),
              const SizedBox(height: 10),
              const FieldLabel('المجموعة', requiredField: true),
              AppDropdown<String>(
                value: groupId,
                items: available
                    .map((g) => DropdownMenuItem(
                          value: g.id,
                          child: Text('${g.name} — ${money(g.pricePerMonth)}'),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => groupId = v ?? groupId),
              ),
              const SizedBox(height: 8),
              const FieldLabel('سعر مخصص (اختياري)'),
              TextField(controller: price, keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              const FieldLabel('سبب الخصم'),
              TextField(controller: reason),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: 'تسجيل',
                      onPressed: () {
                        try {
                          store.enrollStudent(
                            studentId: student.id,
                            groupId: groupId,
                            customPrice: double.tryParse(price.text.trim()),
                            discountReason: reason.text,
                          );
                          Navigator.pop(ctx);
                        } on StoreException catch (err) {
                          showAppSnack(ctx, err.message, error: true);
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
    );
    price.dispose();
    reason.dispose();
  }
}
