import '../widgets/empty_note.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/school_calendar.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

const _days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/// أيام الدوام والعطل والامتحانات — `CalendarSettings`: العطلة لا يُرصد فيها غياب،
/// والأهل يرون القريب من الاثنين في بوابتهم.
class CalendarSettingsTab extends StatefulWidget {
  const CalendarSettingsTab({super.key});

  @override
  State<CalendarSettingsTab> createState() => _CalendarSettingsTabState();
}

class _CalendarSettingsTabState extends State<CalendarSettingsTab> {
  final _title = TextEditingController();
  String kind = 'holiday';
  String from = isoDate(DateTime.now());
  String to = '';
  bool suggesting = false;
  final skip = <String>{};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<String?> _pick(String initial, {String? first}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseIsoDate(initial) ?? DateTime.now(),
      firstDate: parseIsoDate(first ?? '') ?? DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    return picked == null ? null : isoDate(picked);
  }

  Future<void> _write(AppStore store, List<CalendarEvent> events) =>
      store.writeSchoolOption({'calendar': [for (final e in events) e.toMap()]});

  Future<void> _add(AppStore store, List<CalendarEvent> calendar) async {
    final title = _title.text.trim();
    if (title.isEmpty || from.isEmpty) return;
    await _write(store, [
      ...calendar,
      CalendarEvent(
        id: const Uuid().v4(),
        kind: kind,
        title: title,
        from: from,
        to: to.isNotEmpty && to.compareTo(from) >= 0 ? to : from,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _title.clear();
      to = '';
    });
    showAppSnack(context, 'أُضيف');
  }

  Widget _dateChip(String label, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(6)),
          child: Text(label, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5)),
        ),
      );

  Widget _row(AppStore store, List<CalendarEvent> calendar, CalendarEvent e, bool done) {
    final isAdmin = store.isAdminUser;
    List<CalendarEvent> replaced(CalendarEvent next) => [for (final x in calendar) x.id == e.id ? next : x];
    return Opacity(
      opacity: done ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${calendarKindLabels[e.kind]} · ${e.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.heading),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      _dateChip(e.from, !isAdmin ? null : () async {
                        final v = await _pick(e.from);
                        if (v != null) await _write(store, replaced(e.withDates(from: v)));
                      }),
                      _dateChip(e.to, !isAdmin ? null : () async {
                        final v = await _pick(e.to, first: e.from);
                        if (v != null) await _write(store, replaced(e.withDates(to: v)));
                      }),
                    ],
                  ),
                ],
              ),
            ),
            if (isAdmin)
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.muted),
                onPressed: () => _write(store, calendar.where((x) => x.id != e.id).toList()),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final isAdmin = store.isAdminUser;
    final calendar = store.settings.calendar;
    final weekend = store.settings.weekend;
    final today = isoDate(DateTime.now());
    final upcoming = calendar.where((e) => e.to.compareTo(today) >= 0).toList()..sort((a, b) => a.from.compareTo(b.from));
    final past = calendar.where((e) => e.to.compareTo(today) < 0).toList()..sort((a, b) => b.from.compareTo(a.from));
    final now = DateTime.now();
    final suggestions = officialHolidays(today, isoDate(DateTime(now.year + 1, now.month, now.day)))
        .where((h) => !calendar.any((e) => e.kind == 'holiday' && e.title == h.title && e.from == h.from))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text('أيام الدوام', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var d = 0; d < _days.length; d++)
              FilterChip(
                label: Text(_days[d], style: const TextStyle(fontSize: 11.5)),
                selected: !weekend.contains(d),
                onSelected: !isAdmin
                    ? null
                    : (_) {
                        final next = weekend.contains(d) ? weekend.where((x) => x != d).toList() : ([...weekend, d]..sort());
                        if (next.length < 7) store.writeSchoolOption({'weekend': next});
                      },
              ),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'العطل والامتحانات (${calendar.length})',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
            ),
            if (suggestions.isNotEmpty && isAdmin)
              GhostButton(label: 'عطل رسمية', onPressed: () => setState(() => suggesting = !suggesting)),
          ],
        ),
        if (suggesting) ...[
          for (final h in suggestions)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: !skip.contains('${h.title}|${h.from}'),
              onChanged: (v) => setState(() {
                final key = '${h.title}|${h.from}';
                v == true ? skip.remove(key) : skip.add(key);
              }),
              title: Text(h.title, style: const TextStyle(fontSize: 12.5)),
              subtitle: Text(h.from == h.to ? h.from : '${h.from} ← ${h.to}', style: const TextStyle(fontSize: 11)),
            ),
          PrimaryButton(
            label: 'إضافة ${suggestions.where((h) => !skip.contains('${h.title}|${h.from}')).length}',
            expand: true,
            onPressed: () async {
              final picked = suggestions.where((h) => !skip.contains('${h.title}|${h.from}')).toList();
              if (picked.isEmpty) return;
              await _write(store, [
                ...calendar,
                for (final h in picked)
                  CalendarEvent(id: const Uuid().v4(), kind: 'holiday', title: h.title, from: h.from, to: h.to),
              ]);
              if (!mounted) return;
              setState(() {
                suggesting = false;
                skip.clear();
              });
              showAppSnack(this.context, 'أُضيفت ${picked.length}');
            },
          ),
          const SizedBox(height: 10),
        ],
        if (isAdmin) ...[
          Row(
            children: [
              DropdownButton<String>(
                value: kind,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'holiday', child: Text('عطلة', style: TextStyle(fontSize: 12.5))),
                  DropdownMenuItem(value: 'exam', child: Text('امتحان', style: TextStyle(fontSize: 12.5))),
                ],
                onChanged: (v) => setState(() => kind = v ?? 'holiday'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _title,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(isDense: true, hintText: 'العنوان'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _dateChip(from, () async {
                final v = await _pick(from);
                if (v != null) setState(() => from = v);
              }),
              const SizedBox(width: 6),
              _dateChip(to.isEmpty ? 'إلى (اختياري)' : to, () async {
                final v = await _pick(to.isEmpty ? from : to, first: from);
                if (v != null) setState(() => to = v);
              }),
              const Spacer(),
              PrimaryButton(
                label: 'إضافة',
                icon: Icons.add,
                onPressed: _title.text.trim().isEmpty ? null : () => _add(store, calendar),
              ),
            ],
          ),
          const Divider(height: 22),
        ],
        if (calendar.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: EmptyNote('لا عطل ولا امتحانات'),
          )
        else ...[
          for (final e in upcoming) _row(store, calendar, e, false),
          for (final e in past) _row(store, calendar, e, true),
        ],
      ],
    );
  }
}
