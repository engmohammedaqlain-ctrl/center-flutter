import 'package:flutter/material.dart';

import '../data/followup.dart';
import '../data/grading.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// المتابعة في صفحة واحدة بسطور قصيرة — `FollowupSettings.tsx`: متى يُنذر الأهل بالغياب،
/// ومن يُعدّ «الأكثر غياباً»، وموعد رصد كل مكوّن. نص الرسالة خلف نقرة.
class FollowupSettingsTab extends StatefulWidget {
  const FollowupSettingsTab({super.key, this.onOpenGrading});

  /// «نظام العلامات»: مصدر المكوّنات.
  final VoidCallback? onOpenGrading;

  @override
  State<FollowupSettingsTab> createState() => _FollowupSettingsTabState();
}

class _FollowupSettingsTabState extends State<FollowupSettingsTab> {
  FollowupSettings? draft;
  bool messageOpen = false;
  String term = 'term_1';
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _edit(FollowupSettings next) => setState(() => draft = next);

  Future<void> _save(AppStore store, FollowupSettings f) async {
    final clean = ({for (final n in f.levels) if (n > 0) n}.toList()..sort());
    try {
      await store.writeSettingsPatch({'followup': f.copyWith(levels: clean).toMap()});
      if (!mounted) return;
      setState(() => draft = null);
      showAppSnack(context, 'تم الحفظ');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final f = draft ?? store.settings.followup;
    final levels = f.levels;
    if (!messageOpen && _message.text != f.message) _message.text = f.message;

    // أسماء مكوّنات الفصل (بوزن) من النظام العام وأنظمة المواد الخاصة، بلا تكرار
    final grading = store.gradingForViewedYear;
    final names = <String>{};
    for (final s in [defaultIfEmpty(grading.scheme, store.newId), for (final v in grading.subjects.values) ?v.scheme]) {
      for (final c in term == 'term_2' ? s.term2 : s.term1) {
        if (c.weight > 0 && c.name.trim().isNotEmpty) names.add(c.name.trim());
      }
    }
    String deadlineOf(String name) => f.gradeDeadlines.where((d) => d.term == term && d.name == name).firstOrNull?.date ?? '';
    void setDeadline(String name, String date) => _edit(f.copyWith(gradeDeadlines: [
          for (final d in f.gradeDeadlines)
            if (!(d.term == term && d.name == name)) d,
          if (date.isNotEmpty) GradeDeadline(term: term, name: name, date: date),
        ]));

    Widget line(Widget label, List<Widget> trailing, {bool last = false}) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(children: [Expanded(child: label), ...trailing]),
        );
    Widget number(int value, ValueChanged<int> onChanged) => SizedBox(
          width: 56,
          height: 36,
          child: TextFormField(
            key: ValueKey('${value}_${levels.length}'),
            initialValue: value > 0 ? '$value' : '',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
          ),
        );
    final muted = TextStyle(fontFamily: AppText.family, color: AppColors.muted, fontSize: 12);

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, draft != null ? 92 : 24),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(
                Tooltip(
                  message: 'يُرسل للأهل من التقارير ← الإنذارات، مرة لكل مستوى',
                  child: Row(children: [
                    Checkbox(value: f.absenceEnabled, onChanged: (v) => _edit(f.copyWith(absenceEnabled: v == true))),
                    Text('إنذار الأهل بالغياب', style: AppText.label),
                  ]),
                ),
                [
                  if (f.absenceEnabled)
                    TextButton(onPressed: () => setState(() => messageOpen = !messageOpen), child: const Text('نص الرسالة')),
                ],
              ),
              if (f.absenceEnabled) ...[
                for (var i = 0; i < levels.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 96, child: Text(alertLevelName(i, levels.length), style: AppText.label)),
                      Text('بعد ', style: muted),
                      number(levels[i], (n) => _edit(f.copyWith(levels: [for (var j = 0; j < levels.length; j++) j == i ? n : levels[j]]))),
                      Text(' أيام غياب', style: muted),
                      const Spacer(),
                      if (levels.length > 1)
                        IconButton(
                          tooltip: 'حذف هذا الإنذار',
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                          onPressed: () => _edit(f.copyWith(levels: [for (var j = 0; j < levels.length; j++) if (j != i) levels[j]])),
                        ),
                    ]),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => _edit(f.copyWith(levels: [...levels, (levels.isEmpty ? 0 : levels.last) + 5])),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('إنذار'),
                  ),
                ),
                if (messageOpen) ...[
                  Tooltip(
                    message: '{الطالب} {الأيام} {المستوى} تُستبدل عند الإرسال',
                    child: TextField(
                      controller: _message,
                      maxLines: 3,
                      maxLength: 400,
                      onChanged: (v) => _edit(f.copyWith(message: v)),
                    ),
                  ),
                  if (f.message != defaultAbsenceMessage)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () {
                          _message.text = defaultAbsenceMessage;
                          _edit(f.copyWith(message: defaultAbsenceMessage));
                        },
                        child: const Text('النص الافتراضي'),
                      ),
                    ),
                ],
                const Divider(height: 1, color: AppColors.line),
              ],
              line(
                Tooltip(message: 'في الرئيسية: من آخر 30 يوماً مرصوداً', child: Text('الأكثر غياباً', style: AppText.label)),
                [
                  Text('من غاب ', style: muted),
                  number(f.chronicPercent.round(), (n) => _edit(f.copyWith(chronicPercent: n > 0 && n < 100 ? n.toDouble() : f.chronicPercent))),
                  Text(' % فأكثر', style: muted),
                ],
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(
                Tooltip(message: 'بعد الموعد يظهر الرصد الناقص في الرئيسية', child: Text('موعد الرصد', style: AppText.label)),
                [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'term_1', label: Text('الفصل الأول', style: TextStyle(fontSize: 11.5))),
                      ButtonSegment(value: 'term_2', label: Text('الفصل الثاني', style: TextStyle(fontSize: 11.5))),
                    ],
                    selected: {term},
                    onSelectionChanged: (v) => setState(() => term = v.first),
                  ),
                ],
                last: true,
              ),
              Row(children: [
                Text('المكوّنات من ', style: muted),
                InkWell(
                  onTap: widget.onOpenGrading,
                  child: Text('نظام العلامات', style: muted.copyWith(color: AppColors.info, decoration: TextDecoration.underline)),
                ),
                Text('، وتتغيّر بتغييره', style: muted),
              ]),
              for (final name in names)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(name, style: AppText.label)),
                    OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final cur = DateTime.tryParse(deadlineOf(name));
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: cur ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 2),
                        );
                        if (picked != null) setDeadline(name, isoDate(picked));
                      },
                      child: Text(deadlineOf(name).isEmpty ? 'بلا موعد' : deadlineOf(name).split('-').reversed.join('/')),
                    ),
                    if (deadlineOf(name).isNotEmpty)
                      IconButton(
                        tooltip: 'بلا موعد',
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                        onPressed: () => setDeadline(name, ''),
                      ),
                  ]),
                ),
            ],
          ),
        ),
        if (draft != null) ...[
          const SizedBox(height: 12),
          ActionButtons(
            gap: 8,
            primary: PrimaryButton(label: 'حفظ', icon: Icons.check, expand: true, onPressed: () => _save(store, f)),
            secondary: GhostButton(label: 'تراجع', onPressed: () => setState(() => draft = null)),
          ),
        ],
      ],
    );
  }
}

/// نظام المدرسة بلا مكوّنات يُعرض بالنموذج الافتراضي — `withDefaultTerms`.
GradingScheme defaultIfEmpty(GradingScheme s, String Function() newId) {
  if (s.term1.isEmpty && s.term2.isEmpty) return defaultGradingScheme(newId);
  return GradingScheme(term1: s.term1.isEmpty ? defaultTermComponents(newId) : s.term1, term2: s.term2.isEmpty ? s.term1 : s.term2);
}
