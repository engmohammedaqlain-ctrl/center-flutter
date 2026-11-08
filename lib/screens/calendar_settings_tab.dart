import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/school_calendar.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart' show NoonButton, NoonSegment, NoonTone, showNoonSheet;
import '../widgets/empty_note.dart';
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
  bool suggesting = false;
  final skip = <String>{};

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

  /// نافذة إضافة عطلة أو امتحان: النموذج لا يبقى مفتوحاً في الصفحة.
  Future<void> _openAdd(AppStore store, List<CalendarEvent> calendar) async {
    final title = TextEditingController();
    var kind = 'holiday';
    var from = isoDate(DateTime.now());
    var to = '';
    await showNoonSheet<void>(
      context,
      title: 'إضافة عطلة أو امتحان',
      body: (ctx, set) => [
        NoonSegment<String>(
          value: kind,
          options: const [('holiday', 'عطلة'), ('exam', 'امتحان')],
          onChanged: (v) => set(() => kind = v),
        ),
        TextField(
          controller: title,
          autofocus: true,
          onChanged: (_) => set(() {}),
          decoration: const InputDecoration(hintText: 'العنوان'),
        ),
        Row(
          children: [
            Expanded(
              child: _dateChip(from, () async {
                final v = await _pick(from);
                if (v != null) set(() => from = v);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dateChip(to.isEmpty ? 'إلى (اختياري)' : to, () async {
                final v = await _pick(to.isEmpty ? from : to, first: from);
                if (v != null) set(() => to = v);
              }),
            ),
          ],
        ),
      ],
      footer: (ctx, set) => [
        NoonButton(
          label: 'إضافة',
          icon: Icons.add,
          tone: NoonTone.ink,
          onPressed: title.text.trim().isEmpty
              ? null
              : () async {
                  await _write(store, [
                    ...calendar,
                    CalendarEvent(
                      id: const Uuid().v4(),
                      kind: kind,
                      title: title.text.trim(),
                      from: from,
                      to: to.isNotEmpty && to.compareTo(from) >= 0 ? to : from,
                    ),
                  ]);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) showAppSnack(context, 'أُضيف');
                },
        ),
      ],
    );
    title.dispose();
  }

  /// ترتيب الأسبوع كما يبدأ عندنا: السبت أولاً.
  static const _weekOrder = [6, 0, 1, 2, 3, 4, 5];

  Widget _dayCell(AppStore store, int d, List<int> weekend, bool isAdmin) {
    final on = !weekend.contains(d);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: !isAdmin
          ? null
          : () {
              final next = weekend.contains(d) ? weekend.where((x) => x != d).toList() : ([...weekend, d]..sort());
              if (next.length < 7) store.writeSchoolOption({'weekend': next});
            },
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? AppColors.navy : AppColors.line),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              _days[d],
              maxLines: 1,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateChip(String label, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(6)),
          child: Text(label, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
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
        Row(
          children: [
            for (var i = 0; i < _weekOrder.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: _dayCell(store, _weekOrder[i], weekend, isAdmin)),
            ],
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
          const SizedBox(height: 4),
          GhostButton(label: 'إضافة عطلة أو امتحان', icon: Icons.add, onPressed: () => _openAdd(store, calendar)),
          const SizedBox(height: 10),
          const Divider(height: 12),
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
