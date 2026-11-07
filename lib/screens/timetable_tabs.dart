import '../widgets/empty_note.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/doc_export.dart';
import '../data/school_calendar.dart';
import '../data/staff.dart';
import '../data/timetable_model.dart';
import '../data/timetable_print.dart';
import '../data/timetable_service.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'classes_screen.dart' show assignSubjectTeachers;
import 'timetable_screen.dart';

const _emerald = Color(0xFFECFDF5);
const _rose = Color(0xFFFFE4E6);

BoxDecoration _panel() => BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(8),
    );

/// الجدول: شعبة أو معلم، صف لكل يوم وعمود لكل حصة. النقر يختار حصة ثم ينقلها أو يبدّلها — `GridTab`.
class GridTab extends StatelessWidget {
  const GridTab({super.key, required this.f});

  final TimetableState f;

  Future<void> _run(BuildContext context, Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (context.mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRoom = f.view == 'room';
    final list = isRoom
        ? [for (final r in f.rooms) (id: r.id, name: f.roomName(r.id))]
        : [for (final t in f.teachers) (id: t.id, name: t.name)];
    final currentId = f.currentId;
    final shown = f.entries.where((e) => isRoom ? e.roomId == currentId : f.teacherOfGroup(e.groupId) == currentId).toList();
    final selected = f.selectedEntry;
    final lesson = f.selectedLesson;
    final max = f.settings.periods.length;
    final pending = f.unplaced.where((l) => isRoom ? l.roomId == currentId : l.teacherId == currentId).toList();

    Widget cell(int day, int period) {
      if (period > f.settings.periodsOn(day)) return Container(height: 56, color: AppColors.sunken);
      final entry = shown.where((e) => e.day == day && e.period == period).firstOrNull;
      final sel = entry != null && selected != null && entry.same(selected);
      final off = isRoom ? f.rules.roomOff(currentId, day, period) : f.rules.teacherOff(currentId, day, period);
      final target = f.hasSelection && !sel ? f.moveConflicts(day, period) : null;
      final ok = target != null && target.conflicts.isEmpty;
      final Color color = sel
          ? const Color(0xFFD7EFEF)
          : target != null
              ? (ok ? _emerald : Colors.white)
              : off
                  ? AppColors.sunken
                  : Colors.white;
      return InkWell(
        onTap: f.isPastYear
            ? null
            : () {
                if (!f.hasSelection) {
                  if (entry != null) f.selectEntry(entry);
                  return;
                }
                if (sel) {
                  f.clearSelection();
                  return;
                }
                _run(context, () async {
                  final why = await f.dropAt(day, period);
                  if (why != null && context.mounted) showAppSnack(context, why, error: true);
                });
              },
        child: Container(
          height: 56,
          padding: const EdgeInsets.all(3),
          color: color,
          alignment: Alignment.center,
          child: Opacity(
            opacity: target != null && !ok ? 0.55 : 1,
            child: entry == null
                ? const SizedBox.shrink()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (entry.locked) const Icon(Icons.lock, size: 10, color: AppColors.muted),
                          Flexible(
                            child: Text(
                              f.subjectOf(entry.groupId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.heading),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        isRoom ? f.teacherName(f.teacherOfGroup(entry.groupId)) : f.roomCode(entry.roomId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: _panel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoonSegment<String>(
                value: f.view,
                options: const [('room', 'شعبة'), ('teacher', 'معلم')],
                onChanged: f.switchView,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: list.isEmpty
                        ? Text(isRoom ? 'لا شعب' : 'لا معلمون', style: const TextStyle(color: AppColors.muted, fontSize: 13))
                        : AppDropdown<String>(
                            value: list.any((x) => x.id == currentId) ? currentId : null,
                            items: [for (final x in list) DropdownMenuItem(value: x.id, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                            onChanged: (v) {
                              if (v != null) f.setViewId(v);
                            },
                          ),
                  ),
                  IconButton(
                    tooltip: 'تراجع',
                    icon: const Icon(Icons.undo_rounded),
                    onPressed: f.canUndo ? () => _run(context, f.undo) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (f.hasSelection) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: _panel(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected != null
                            ? '${f.subjectOf(selected.groupId)} · ${isRoom ? f.teacherName(f.teacherOfGroup(selected.groupId)) : f.roomName(selected.roomId)}'
                            : '${f.subjectOf(lesson!.groupId)} · ${f.roomName(lesson.roomId)}',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.heading),
                      ),
                      const Text('اختر الخانة', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ),
                if (selected != null) ...[
                  IconButton(
                    tooltip: selected.locked ? 'فك التثبيت' : 'تثبيت',
                    icon: Icon(selected.locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded, size: 20),
                    onPressed: () => _run(context, () => f.toggleLock(selected)),
                  ),
                  IconButton(
                    tooltip: 'إزالة',
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                    onPressed: () => _run(context, () => f.removeEntry(selected)),
                  ),
                ],
                IconButton(tooltip: 'إلغاء', icon: const Icon(Icons.close, size: 20), onPressed: f.clearSelection),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (list.isNotEmpty)
          Container(
            decoration: _panel(),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(86),
                columnWidths: const {0: FixedColumnWidth(64)},
                border: TableBorder.all(color: AppColors.line),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: AppColors.sunken),
                    children: [
                      const SizedBox(height: 40),
                      for (var i = 0; i < max; i++)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            Text(f.settings.periods[i].start, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                          ],
                        ),
                    ],
                  ),
                  for (final d in f.days)
                    TableRow(
                      children: [
                        Container(
                          height: 56,
                          color: AppColors.sunken,
                          alignment: Alignment.center,
                          child: Text(dayNames[d], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ),
                        for (var i = 0; i < max; i++) cell(d, i + 1),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('غير موضوعة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in pending)
                ChoiceChip(
                  label: Text(
                    '${f.subjectOf(l.groupId)}${isRoom ? '' : ' · ${f.roomName(l.roomId)}'}  ${f.remaining(l)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  selected: lesson != null && lesson.groupId == l.groupId && lesson.roomId == l.roomId,
                  onSelected: f.isPastYear
                      ? null
                      : (on) => f.selectLesson(on ? l : null),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// خانة رقم تُحفظ عند مغادرتها.
class _NumBox extends StatefulWidget {
  const _NumBox({super.key, required this.value, required this.onSave, this.enabled = true, this.width = 58});

  final int value;
  final ValueChanged<int> onSave;
  final bool enabled;
  final double width;

  @override
  State<_NumBox> createState() => _NumBoxState();
}

class _NumBoxState extends State<_NumBox> {
  late final controller = TextEditingController(text: widget.value == 0 ? '' : '${widget.value}');
  final focus = FocusNode();

  void _commit() {
    final parsed = int.tryParse(controller.text.trim()) ?? 0;
    final n = parsed < 0 ? 0 : parsed;
    if (n != widget.value) widget.onSave(n);
  }

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        child: TextField(
          controller: controller,
          focusNode: focus,
          enabled: widget.enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (_) => focus.unfocus(),
        ),
      );
}

/// الحصص: حصص كل مادة في كل شعبة، ومجموع الشعبة والمعلم أمام المتاح — `LoadTab`.
class LoadTab extends StatefulWidget {
  const LoadTab({super.key, required this.f});

  final TimetableState f;

  @override
  State<LoadTab> createState() => _LoadTabState();
}

class _LoadTabState extends State<LoadTab> {
  String mode = 'rooms';

  int _roomSlots(String id) => slotsFor(widget.f.days, widget.f.settings, (d, p) => widget.f.rules.roomOff(id, d, p));
  int _teacherSlots(String id) => slotsFor(widget.f.days, widget.f.settings, (d, p) => widget.f.rules.teacherOff(id, d, p));

  void _set(String groupId, int? n) {
    try {
      widget.f.setPeriods(groupId, n);
    } catch (e) {
      showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  void _copyFrom(Classroom target, String sourceId) {
    final f = widget.f;
    final source = f.lessons.where((l) => l.roomId == sourceId).toList();
    for (final l in f.lessons.where((x) => x.roomId == target.id).toList()) {
      final match = source.where((s) => s.subjectId == l.subjectId).firstOrNull;
      if (match != null) _set(l.groupId, match.count == 0 ? null : match.count);
    }
  }

  Widget _roomCard(Classroom room, Map<String, int> byRoom) {
    final f = widget.f;
    final mine = f.lessons.where((l) => l.roomId == room.id).toList()
      ..sort((a, b) => f.subjectOf(a.groupId).compareTo(f.subjectOf(b.groupId)));
    final total = byRoom[room.id] ?? 0;
    final slots = _roomSlots(room.id);
    final others = f.rooms.where((x) => x.id != room.id && x.gradeLevel == room.gradeLevel).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 2, top: 4, bottom: 4),
            child: Row(
              children: [
                Expanded(child: Text(f.roomName(room.id), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading))),
                Text(
                  '$total / $slots',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: total > slots ? FontWeight.w700 : FontWeight.w500,
                    color: total > slots ? AppColors.danger : (total == slots ? AppColors.success : AppColors.muted),
                  ),
                ),
                IconButton(
                  tooltip: 'الإسناد',
                  icon: const Icon(Icons.menu_book_outlined, size: 19),
                  onPressed: f.isPastYear ? null : () => assignSubjectTeachers(context, room),
                ),
                if (others.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'نسخ الحصص',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onSelected: (id) => _copyFrom(room, id),
                    itemBuilder: (_) => [
                      for (final o in others) PopupMenuItem(value: o.id, child: Text('نسخ من ${f.roomName(o.id)}')),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (mine.isEmpty)
            const Padding(
              padding: EdgeInsets.all(10),
              child: EmptyNote('لا مواد مسندة'),
            ),
          for (final l in mine)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 10, end: 2, top: 4, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${f.subjectOf(l.groupId)}${f.rules.lessonOf(l.groupId)['double'] == true ? ' · مزدوجة' : ''}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          f.teacherName(l.teacherId),
                          style: TextStyle(fontSize: 11, color: l.teacherId.isEmpty ? AppColors.danger : AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  _NumBox(
                    key: ValueKey('${l.groupId}-${l.roomId}-${l.count}'),
                    value: l.count,
                    enabled: !f.isPastYear,
                    onSave: (n) => _set(l.groupId, n == 0 ? null : n),
                  ),
                  IconButton(
                    tooltip: 'خيارات',
                    icon: const Icon(Icons.tune_rounded, size: 19),
                    onPressed: f.isPastYear ? null : () => _lessonRule(context, f, l.groupId),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final byRoom = roomLoads(f.lessons);
    final byTeacher = teacherLoads(f.lessons);
    final issues = [
      for (final r in f.rooms)
        if ((byRoom[r.id] ?? 0) > _roomSlots(r.id)) '${f.roomName(r.id)}: ${byRoom[r.id]} > ${_roomSlots(r.id)}',
      for (final t in f.teachers)
        if ((byTeacher[t.id] ?? 0) > _teacherSlots(t.id)) '${t.name}: ${byTeacher[t.id]} > ${_teacherSlots(t.id)}',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        NoonSegment<String>(
          value: mode,
          options: const [('rooms', 'الشعب'), ('teachers', 'المعلمون')],
          onChanged: (v) => setState(() => mode = v),
        ),
        const SizedBox(height: 8),
        if (issues.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حصص أكثر من المتاح', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                for (final s in issues) Text(s, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (mode == 'rooms') ...[
          if (f.rooms.isEmpty) const EmptyState(message: 'لا شعب'),
          for (final room in f.rooms) _roomCard(room, byRoom),
        ] else
          Container(
            decoration: _panel(),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('المعلم', style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                      SizedBox(width: 44, child: Text('الحصص', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                      SizedBox(width: 44, child: Text('النصاب', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                      SizedBox(width: 44, child: Text('المتاح', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (final t in f.teachers)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        Expanded(child: Text(t.name, style: const TextStyle(fontSize: 12.5))),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${byTeacher[t.id] ?? 0}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, color: (byTeacher[t.id] ?? 0) > _teacherSlots(t.id) ? AppColors.danger : null),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            t.weeklyPeriods == null ? '—' : trimNum(t.weeklyPeriods!),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: t.weeklyPeriods != null && t.weeklyPeriods != (byTeacher[t.id] ?? 0) ? const Color(0xFFB45309) : AppColors.muted,
                            ),
                          ),
                        ),
                        SizedBox(width: 44, child: Text('${_teacherSlots(t.id)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// خيارات الإسناد في الجدول: الحصص المزدوجة، حد اليوم، المرفق — `LessonRuleModal`.
Future<void> _lessonRule(BuildContext context, TimetableState f, String groupId) async {
  final current = f.rules.lessonOf(groupId);
  var isDouble = current['double'] == true;
  var maxPerDay = current['max_per_day'] is num ? (current['max_per_day'] as num).toInt() : 0;
  var facilityId = '${current['facility_id'] ?? ''}';
  final facilities = f.rules.facilities;
  final w = f.groupMap[groupId]?.weeklyPeriods;
  final count = w == null ? 0 : w.floor();

  await showNoonSheet<void>(
    context,
    title: f.subjectOf(groupId),
    body: (ctx, setSheet) => [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('مزدوجة', style: TextStyle(fontSize: 13)),
        subtitle: const Text('كل حصتين متتاليتين معاً', style: TextStyle(fontSize: 11.5)),
        value: isDouble,
        onChanged: count < 2 ? null : (v) => setSheet(() => isDouble = v),
      ),
      Row(
        children: [
          const Expanded(child: Text('حد اليوم', style: TextStyle(fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: maxPerDay <= 0 ? null : () => setSheet(() => maxPerDay--),
          ),
          Text('$maxPerDay'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: maxPerDay >= 8 ? null : () => setSheet(() => maxPerDay++),
          ),
        ],
      ),
      const SizedBox(height: 6),
      const Text('المرفق', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 4),
      AppDropdown<String>(
        value: facilityId,
        items: [
          const DropdownMenuItem(value: '', child: Text('بلا')),
          for (final x in facilities) DropdownMenuItem(value: '${x['id']}', child: Text('${x['name'] ?? ''}')),
        ],
        onChanged: (v) => setSheet(() => facilityId = v ?? ''),
      ),
    ],
    footer: (ctx, _) => [
      Expanded(
        child: PrimaryButton(
          label: 'حفظ',
          expand: true,
          onPressed: () async {
            final clean = <String, dynamic>{
              if (isDouble && count >= 2) 'double': true,
              if (maxPerDay > 0) 'max_per_day': maxPerDay,
              if (facilityId.isNotEmpty) 'facility_id': facilityId,
            };
            try {
              await f.saveRules(f.rules.withEntry('lessons', groupId, clean.isEmpty ? null : clean));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) showAppSnack(ctx, userMessage(e, 'تعذّر الحفظ'), error: true);
            }
          },
        ),
      ),
    ],
  );
}

/// القيود: خانات المعلم غير المتاحة، دوام الشعبة، المرافق، وخيارات عامة — `RulesTab`.
class RulesTab extends StatefulWidget {
  const RulesTab({super.key, required this.f});

  final TimetableState f;

  @override
  State<RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<RulesTab> {
  String part = 'teachers';
  String teacherId = '';
  String roomId = '';
  final facilityName = TextEditingController();

  @override
  void dispose() {
    facilityName.dispose();
    super.dispose();
  }

  Future<void> _save(TimetableRules next) async {
    try {
      await widget.f.saveRules(next);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  void _setOff(String key, String id, List<String> slots) {
    _save(widget.f.rules.withEntry(key, id, slots.isEmpty ? null : slots));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final tId = teacherId.isNotEmpty ? teacherId : (f.teachers.firstOrNull?.id ?? '');
    final rId = roomId.isNotEmpty ? roomId : (f.rooms.firstOrNull?.id ?? '');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        NoonSegment<String>(
          value: part,
          options: const [('teachers', 'المعلمون'), ('rooms', 'الدوام'), ('facilities', 'المرافق'), ('general', 'عام')],
          onChanged: (v) => setState(() => part = v),
        ),
        const SizedBox(height: 8),
        if (part == 'teachers')
          if (f.teachers.isEmpty)
            const EmptyState(message: 'لا معلمون')
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _panel(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDropdown<String>(
                    value: tId,
                    items: [for (final t in f.teachers) DropdownMenuItem(value: t.id, child: Text(t.name))],
                    onChanged: (v) => setState(() => teacherId = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('حد اليوم (أقصى حصص المعلم)', style: TextStyle(fontSize: 12.5))),
                      _NumBox(
                        key: ValueKey('max_$tId'),
                        value: f.rules.teacherMaxOf(tId),
                        enabled: !f.isPastYear,
                        onSave: (n) => _save(f.rules.withEntry('teacher_max_per_day', tId, n == 0 ? null : n)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _OffGrid(f: f, value: f.rules.teacherOffOf(tId), onChanged: (s) => _setOff('teacher_off', tId, s)),
                ],
              ),
            ),
        if (part == 'rooms')
          if (f.rooms.isEmpty)
            const EmptyState(message: 'لا شعب')
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _panel(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDropdown<String>(
                    value: rId,
                    items: [for (final r in f.rooms) DropdownMenuItem(value: r.id, child: Text(f.roomName(r.id)))],
                    onChanged: (v) => setState(() => roomId = v ?? ''),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('نفس الدوام لكل شعب المرحلة', style: TextStyle(fontSize: 12)),
                      onPressed: f.isPastYear
                          ? null
                          : () {
                              final grade = f.rooms.where((r) => r.id == rId).firstOrNull?.gradeLevel;
                              final slots = f.rules.roomOffOf(rId);
                              var next = f.rules;
                              for (final r in f.rooms.where((x) => x.gradeLevel == grade)) {
                                next = next.withEntry('room_off', r.id, slots.isEmpty ? null : slots);
                              }
                              _save(next);
                            },
                    ),
                  ),
                  _OffGrid(f: f, value: f.rules.roomOffOf(rId), onChanged: (s) => _setOff('room_off', rId, s)),
                ],
              ),
            ),
        if (part == 'facilities')
          Container(
            padding: const EdgeInsets.all(10),
            decoration: _panel(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final x in f.rules.facilities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text('${x['name'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        const Text('السعة', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        const SizedBox(width: 6),
                        _NumBox(
                          key: ValueKey('cap_${x['id']}'),
                          value: x['capacity'] is num ? (x['capacity'] as num).toInt() : 1,
                          enabled: !f.isPastYear,
                          onSave: (n) => _save(f.rules.withKey('facilities', [
                            for (final y in f.rules.facilities)
                              y['id'] == x['id'] ? {...y, 'capacity': n < 1 ? 1 : n} : y,
                          ])),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.danger),
                          onPressed: f.isPastYear
                              ? null
                              : () => _save(f.rules.withKey('facilities', [
                                    for (final y in f.rules.facilities)
                                      if (y['id'] != x['id']) y,
                                  ])),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: facilityName,
                        enabled: !f.isPastYear,
                        decoration: const InputDecoration(isDense: true, hintText: 'مختبر، حاسوب، ساحة'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GhostButton(
                      label: 'إضافة',
                      icon: Icons.add,
                      onPressed: f.isPastYear
                          ? null
                          : () {
                              final name = facilityName.text.trim();
                              if (name.isEmpty) return;
                              _save(f.rules.withKey('facilities', [
                                ...f.rules.facilities,
                                {'id': const Uuid().v4(), 'name': name, 'capacity': 1},
                              ]));
                              facilityName.clear();
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (part == 'general')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: _panel(),
            child: Column(
              children: [
                for (final (key, label) in const [
                  ('homeroom_first', 'مربي الصف في الحصة الأولى'),
                  ('no_double_across_break', 'المزدوجة لا تقطعها الاستراحة'),
                ])
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label, style: const TextStyle(fontSize: 13)),
                    value: f.rules.raw[key] == true,
                    onChanged: f.isPastYear ? null : (v) => _save(f.rules.withKey(key, v ? true : null)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// شبكة الأيام والحصص: النقر يغلق الخانة أو يفتحها، والنقر على اليوم يغلقه كله — `OffGrid`.
class _OffGrid extends StatelessWidget {
  const _OffGrid({required this.f, required this.value, required this.onChanged});

  final TimetableState f;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final max = f.settings.periods.length;
    final set = value.toSet();
    bool dayOff(int d) => set.contains(slotKey(d, '*'));
    void toggle(String k) {
      final next = {...set};
      if (!next.remove(k)) next.add(k);
      onChanged(next.toList());
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(38),
        columnWidths: const {0: FixedColumnWidth(72)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const SizedBox(height: 22),
              for (var i = 0; i < max; i++)
                Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted))),
            ],
          ),
          for (final d in f.days)
            TableRow(
              children: [
                InkWell(
                  onTap: f.isPastYear ? null : () => toggle(slotKey(d, '*')),
                  child: Container(
                    height: 34,
                    alignment: AlignmentDirectional.centerStart,
                    color: dayOff(d) ? _rose : null,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(dayNames[d], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                ),
                for (var i = 0; i < max; i++)
                  i + 1 > f.settings.periodsOn(d)
                      ? const SizedBox(height: 34)
                      : Padding(
                          padding: const EdgeInsets.all(2),
                          child: InkWell(
                            onTap: f.isPastYear || dayOff(d) ? null : () => toggle(slotKey(d, i + 1)),
                            child: Container(
                              height: 30,
                              decoration: BoxDecoration(
                                color: dayOff(d) || set.contains(slotKey(d, i + 1)) ? _rose : _emerald,
                                border: Border.all(color: AppColors.line),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
              ],
            ),
        ],
      ),
    );
  }
}

/// الاحتياط: حصص الغائبين في يوم من الجدول المعتمد، وبديل لكل حصة — `CoversTab`.
class CoversTab extends StatefulWidget {
  const CoversTab({super.key, required this.f});

  final TimetableState f;

  @override
  State<CoversTab> createState() => _CoversTabState();
}

class _CoversTabState extends State<CoversTab> {
  DateTime date = DateTime.now();
  List<StaffDay>? attendance;
  List<LeaveRequest> leaves = const [];
  List<TimetableCover>? monthCovers;
  var failed = false;
  var busy = false;

  String get day => isoDate(date);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = day;
    final results = await Future.wait<Object?>([
      StaffService.days(d, d, force: true),
      StaffService.leaves(force: true),
      TimetableService.coversOfMonth(d.substring(0, 7)),
    ]);
    if (!mounted || d != day) return;
    setState(() {
      attendance = results[0] as List<StaffDay>?;
      leaves = results[1] as List<LeaveRequest>? ?? const [];
      monthCovers = results[2] as List<TimetableCover>?;
      failed = attendance == null || monthCovers == null;
    });
  }

  void _shift(int by) {
    var next = date.add(Duration(days: by));
    final weekend = widget.f.store.settings.weekend;
    for (var i = 0; i < 6 && isWeekendDay(next, weekend); i++) {
      next = next.add(Duration(days: by));
    }
    setState(() {
      date = next;
      attendance = null;
    });
    _load();
  }

  Future<void> _save(CoverSlot s, String coverTeacher) async {
    final f = widget.f;
    f.store.requireSection('timetable');
    await TimetableService.saveCover(
      tenantId: f.store.tenantId ?? '',
      yearId: f.store.viewedAcademicYearId,
      cover: TimetableCover(
        date: day,
        period: s.period,
        roomId: s.roomId,
        groupId: s.groupId,
        absentTeacherId: s.absentTeacherId,
        coverTeacherId: coverTeacher,
      ),
    );
  }

  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final timetable = f.live;
    if (timetable == null) {
      return const Padding(padding: EdgeInsets.all(12), child: EmptyState(message: 'اعتمد الجدول أولاً'));
    }
    final att = attendance;
    final month = monthCovers;
    if (failed) {
      return Center(child: TextButton(onPressed: _load, child: const Text('تعذّر الجلب، إعادة المحاولة')));
    }
    if (att == null || month == null) return const Center(child: AppLoader(compact: true));

    final d = day;
    final dayNumber = jsDay(date);
    final covers = month.where((c) => c.date == d).toList();
    bool attendedAbsent(String id) => att.any((a) => a.teacherId == id && a.status == 'absent');
    final absent = <String>{
      for (final a in att)
        if (a.status == 'absent') a.teacherId,
      for (final t in f.teachers)
        if (approvedLeaveOn(leaves, t.id, d) != null) t.id,
      for (final c in covers) c.absentTeacherId,
    };
    final slots = absentSlots(dayNumber, timetable.entries, f.groupMap, absent);
    final monthCount = <String, int>{};
    for (final c in month) {
      if (c.coverTeacherId.isNotEmpty && c.date != d) monthCount[c.coverTeacherId] = (monthCount[c.coverTeacherId] ?? 0) + 1;
    }
    final input = CoverInput(
      day: dayNumber,
      entries: timetable.entries,
      groups: f.groupMap,
      teachers: f.teachers,
      rules: timetable.rules,
      absent: absent,
      today: [for (final c in covers) (period: c.period, roomId: c.roomId, coverId: c.coverTeacherId)],
      monthCount: monthCount,
      dailyMax: f.settings.coverDailyMax,
    );
    TimetableCover? coverOf(CoverSlot s) => covers.where((c) => c.period == s.period && c.roomId == s.roomId).firstOrNull;
    final totals = {...monthCount};
    for (final c in covers) {
      if (c.coverTeacherId.isNotEmpty) totals[c.coverTeacherId] = (totals[c.coverTeacherId] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: _panel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(tooltip: 'السابق', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(-1)),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(DateTime.now().year + 2),
                        );
                        if (picked == null || !mounted) return;
                        setState(() {
                          date = picked;
                          attendance = null;
                        });
                        _load();
                      },
                      child: Text('${dayNames[dayNumber]} $d'),
                    ),
                  ),
                  IconButton(tooltip: 'التالي', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(1)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      value: null,
                      hint: 'غائب آخر',
                      items: [
                        for (final t in f.teachers)
                          if (!absent.contains(t.id)) DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: f.isPastYear
                          ? (_) {}
                          : (id) {
                              if (id == null) return;
                              final mine = absentSlots(dayNumber, timetable.entries, f.groupMap, {id});
                              if (mine.isEmpty) {
                                showAppSnack(context, 'لا حصص له في هذا اليوم', error: true);
                                return;
                              }
                              _guard(() async {
                                for (final s in mine) {
                                  if (coverOf(s) == null) await _save(s, '');
                                }
                              });
                            },
                    ),
                  ),
                  IconButton(
                    tooltip: 'طباعة',
                    icon: const Icon(Icons.print_outlined),
                    onPressed: slots.isEmpty
                        ? null
                        : () async {
                            final bytes = await buildCoversPdf(
                              institution: f.store.institutionName,
                              logo: f.store.institutionLogo,
                              title: '${dayNames[dayNumber]} $d',
                              rows: [
                                for (final s in slots)
                                  [
                                    '${s.period}',
                                    f.roomName(s.roomId),
                                    f.subjectOf(s.groupId),
                                    f.teacherName(s.absentTeacherId),
                                    (coverOf(s)?.coverTeacherId ?? '').isEmpty ? '—' : f.teacherName(coverOf(s)!.coverTeacherId),
                                  ],
                              ],
                            );
                            if (!context.mounted) return;
                            if (bytes == null) {
                              showAppSnack(context, 'تعذّر إعداد الورقة', error: true);
                              return;
                            }
                            DocExport.showActions(context, bytes, 'الاحتياط $d');
                          },
                  ),
                  const SizedBox(width: 2),
                  PrimaryButton(
                    label: 'توزيع',
                    busy: busy,
                    onPressed: f.isPastYear || slots.isEmpty || busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            final picks = autoAssign(input, slots);
                            await _guard(() async {
                              for (final s in slots) {
                                final pick = picks[s.key];
                                if (pick != null) await _save(s, pick);
                              }
                            });
                            if (!mounted) return;
                            setState(() => busy = false);
                            final left = slots.where((s) => (coverOf(s)?.coverTeacherId ?? '').isEmpty && !picks.containsKey(s.key)).length;
                            if (left > 0) showAppSnack(context, '$left بلا بديل متفرغ', error: true);
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (absent.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in absent)
                InputChip(
                  backgroundColor: _rose,
                  label: Text(f.teacherName(id), style: const TextStyle(fontSize: 12)),
                  // الغائب المضاف يدوياً يُزال؛ غياب الدوام والإجازة من مصدرهما
                  onDeleted: !attendedAbsent(id) && approvedLeaveOn(leaves, id, d) == null && !f.isPastYear
                      ? () => _guard(() async {
                            for (final c in covers.where((x) => x.absentTeacherId == id)) {
                              await TimetableService.removeCover(c);
                            }
                          })
                      : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (slots.isEmpty)
          const EmptyState(message: 'لا حصص غائبين')
        else
          for (final s in slots)
            () {
              final current = coverOf(s)?.coverTeacherId ?? '';
              final options = coverCandidates(input, s);
              if (current.isNotEmpty && !options.contains(current)) options.insert(0, current);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: _panel(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'الحصة ${s.period} · ${f.roomName(s.roomId)} · ${f.subjectOf(s.groupId)}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.heading),
                    ),
                    Text('الغائب: ${f.teacherName(s.absentTeacherId)}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    const SizedBox(height: 6),
                    AppDropdown<String>(
                      value: current,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('بلا بديل')),
                        for (final id in options)
                          DropdownMenuItem(value: id, child: Text('${f.teacherName(id)} (${totals[id] ?? 0})')),
                      ],
                      onChanged: f.isPastYear
                          ? (_) {}
                          : (v) {
                              if (v != null && v != current) _guard(() => _save(s, v));
                            },
                    ),
                  ],
                ),
              );
            }(),
      ],
    );
  }
}
