import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/followup.dart';
import '../data/phone.dart';
import '../data/portal_usage.dart';
import '../data/reports_data.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sheet_export.dart';
import 'student_detail_screen.dart';
import 'teacher_detail_screen.dart';

const _red = Color(0xFFBA1A1A);
const _green = Color(0xFF16A34A);
const _amber = Color(0xFF92400E);
const _bandColors = [Color(0xFF15803D), Color(0xFF22C55E), Color(0xFF0EA5E9), Color(0xFFD97706), Color(0xFFBA1A1A)];
const _bandCells = [
  (bg: Color(0xFFDCFCE7), fg: Color(0xFF166534)),
  (bg: Color(0xFFECFCCB), fg: Color(0xFF3F6212)),
  (bg: Color(0xFFE0F2FE), fg: Color(0xFF075985)),
  (bg: Color(0xFFFEF3C7), fg: Color(0xFF92400E)),
  (bg: Color(0xFFFEE2E2), fg: Color(0xFF991B1B)),
];
const _monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

String _dm(String d) => d.length < 10 ? d : '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}';
String _num(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
bool _matches(String name, String q) => q.trim().isEmpty || name.contains(q.trim());

Widget reportView(String id) => switch (id) {
      'absence' => const _AbsenceReport(),
      'alerts' => const _AlertsReport(),
      'results' => const _ResultsReport(),
      'completion' => const _CompletionReport(),
      'decline' => const _DeclineReport(),
      'analysis' => const _AnalysisReport(),
      'compare' => const _CompareReport(),
      'students' => const _StudentsReport(),
      'arrears' => const _DuesReport(),
      'data' => const _DataReport(),
      'usage' => const _UsageReport(),
      'edits' => const _EditLogReport(),
      _ => const NoonEmpty('لا تقرير'),
    };

void _openStudent(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentDetailScreen(studentId: id)));
void _openTeacher(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeacherDetailScreen(teacherId: id)));
void _openSettings(BuildContext context, String tab) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(initialTab: tab)));

// ── أجزاء مشتركة — `ReportParts.tsx` ─────────────────────────────────────────

/// ورقة التقرير كما تُعرض: PDF أو Excel.
typedef _Sheet = ({String title, List<String> meta, List<String> headers, List<List<Object?>> rows, bool landscape});

SheetData _toSheet(AppStore store, _Sheet s) => SheetData(
      title: s.title,
      institution: store.institutionName,
      logo: store.institutionLogo,
      meta: s.meta,
      headers: s.headers,
      rows: [for (final r in s.rows) [for (final c in r) c == null ? '' : (c is num ? _num(c) : '$c')]],
      landscape: s.landscape,
      signatures: const [],
    );

/// شريط التقرير: الفلاتر، ثم تنزيل PDF وExcel بما يُعرض.
class _Bar extends StatelessWidget {
  const _Bar({required this.children, this.sheet});

  final List<Widget> children;
  final _Sheet Function()? sheet;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...children,
          if (sheet != null) ...[
            NoonButton(small: true, icon: Icons.download_outlined, label: 'PDF', onPressed: () => printSheet(context, _toSheet(store, sheet!()))),
            NoonButton(small: true, icon: Icons.table_view_outlined, label: 'Excel', onPressed: () => downloadSheetCsv(context, _toSheet(store, sheet!()))),
          ],
        ],
      ),
    );
  }
}

class _Pick<T> extends StatelessWidget {
  const _Pick({required this.value, required this.options, required this.onChanged});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.lineStrong)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: options.containsKey(value) ? value : options.keys.first,
            isDense: true,
            style: NoonText.style(12.5, weight: FontWeight.w700),
            items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}

/// الصف: «كل الصفوف» أو صف.
Widget _gradePick(AppStore store, String value, ValueChanged<String> onChanged) =>
    _Pick<String>(value: value, options: {'': 'كل الصفوف', for (final g in reportGrades(store)) g: g}, onChanged: onChanged);

/// الحد يُقرأ جملة: «غاب [3] أيام فأكثر» — `MinInput`.
class _NumLine extends StatelessWidget {
  const _NumLine({required this.label, required this.suffix, required this.value, required this.onChanged});

  final String label;
  final String suffix;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: NoonText.style(12, color: AdminNoon.muted)),
        SizedBox(
          width: 52,
          height: 36,
          child: TextFormField(
            initialValue: value > 0 ? '$value' : '',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
          ),
        ),
        Text(' $suffix', style: NoonText.style(12, color: AdminNoon.muted)),
      ]);
}

class _Search extends StatelessWidget {
  const _Search({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        height: 36,
        child: TextField(
          onChanged: onChanged,
          decoration: const InputDecoration(isDense: true, hintText: 'بحث بالاسم', prefixIcon: Icon(Icons.search, size: 18)),
        ),
      );
}

/// «الشعب / الطلاب» — `ViewToggle`.
Widget _viewToggle(String value, ValueChanged<String> onChanged, {String students = 'الطلاب'}) => SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [const ButtonSegment(value: 'sections', label: Text('الشعب')), ButtonSegment(value: 'students', label: Text(students))],
      selected: {value},
      onSelectionChanged: (v) => onChanged(v.first),
    );

typedef _Kpi = ({String label, String value, String sub, Color? color, VoidCallback? onTap});

Widget _kpis(List<_Kpi> items) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in items)
              SizedBox(
                width: (c.maxWidth - 8) / 2,
                child: AppCard(
                  onTap: k.onTap,
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.label, style: NoonText.style(11, color: AdminNoon.muted)),
                    FittedBox(child: Text(k.value, style: NoonText.style(16, weight: FontWeight.w700, color: k.color))),
                    if (k.sub.isNotEmpty) Text(k.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(10.5, color: AdminNoon.muted)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );

/// سطر قائمة: الاسم وتحته التفصيل، والقيم في طرفه.
Widget _row(String title, String sub, List<Widget> trailing, {VoidCallback? onTap, Widget? leading}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          ?leading,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(13, weight: FontWeight.w700)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: NoonText.style(11, color: AdminNoon.muted)),
            ]),
          ),
          for (final t in trailing) Padding(padding: const EdgeInsetsDirectional.only(start: 10), child: t),
        ]),
      ),
    );

Widget _list(List<Widget> rows) => AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: AdminNoon.line))),
            child: rows[i],
          ),
      ]),
    );

Widget _val(String v, {Color? color, String? hint}) {
  final t = Text(v, style: NoonText.style(12.5, weight: FontWeight.w700, color: color));
  return hint == null ? t : Tooltip(message: hint, child: t);
}

Widget _body(List<Widget> children, {Future<void> Function()? onRefresh}) {
  final list = ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 24), children: children);
  return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh, child: list);
}

/// حساب محفوظ حتى تتغير مدخلاته: التقرير يتحدث مع كل مزامنة ولا يعيد حسابه الثقيل.
class _Memo<T> {
  Object? _key;
  late T _value;

  T get(Object key, T Function() compute) {
    if (key != _key) {
      _value = compute();
      _key = key;
    }
    return _value;
  }

  void clear() => _key = null;
}

// ── الغياب ───────────────────────────────────────────────────────────────────

class _AbsenceReport extends StatefulWidget {
  const _AbsenceReport();

  @override
  State<_AbsenceReport> createState() => _AbsenceReportState();
}

class _AbsenceReportState extends State<_AbsenceReport> {
  int monthOffset = 0;
  String grade = '';
  String view = 'sections';
  String sectionId = '';
  int minAbsent = 0;
  int maxRate = 0;
  String q = '';
  final _memo = _Memo<List<SectionAttendance>>();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = DateTime.now();
    final m = DateTime(now.year, now.month + monthOffset, 1);
    final month = isoDate(m).substring(0, 7);
    final days = monthSchoolDays(month);
    final periodLabel = '${_monthNames[m.month - 1]} ${m.year}';
    final sections = _memo.get('$month|$grade', () => attendanceBySection(store, groupBySection(store, grade: grade), days.first, days.last));
    final scoped = [for (final s in sections) if (sectionId.isEmpty || s.group.room.id == sectionId) s];
    final studentRows = [
      for (final s in scoped)
        for (final r in s.rows)
          if (r.absent >= minAbsent && (maxRate == 0 || r.rate <= maxRate) && _matches(r.student.fullName, q)) (r: r, section: s.group.label),
    ]..sort((a, b) => b.r.absent != a.r.absent ? b.r.absent - a.r.absent : a.r.student.fullName.compareTo(b.r.student.fullName));
    final present = scoped.fold<int>(0, (n, s) => n + s.present);
    final absent = scoped.fold<int>(0, (n, s) => n + s.absent);
    final excused = scoped.fold<int>(0, (n, s) => n + s.excused);
    final students = scoped.fold<int>(0, (n, s) => n + s.rows.length);
    final marked = present + absent + excused;
    final rate = marked == 0 ? null : (present / marked * 100).round();

    _Sheet sheet() => (
          title: 'كشف حضور $periodLabel',
          meta: [grade.isEmpty ? 'المدرسة' : grade, 'ح حاضر • غ غائب • م مأذون'],
          headers: view == 'students' ? ['#', 'اسم الطالب', 'الشعبة', 'غياب', 'مأذون', 'حضور'] : ['الشعبة', 'الطلاب', 'غياب', 'مأذون', 'الحضور'],
          rows: view == 'students'
              ? [for (var i = 0; i < studentRows.length; i++) [i + 1, studentRows[i].r.student.fullName, studentRows[i].section, studentRows[i].r.absent, studentRows[i].r.excused, studentRows[i].r.present]]
              : [for (final s in scoped) [s.group.label, s.rows.length, s.absent, s.excused, s.rate == null ? '—' : '${s.rate}%']],
          landscape: false,
        );

    return _body([
      _Bar(sheet: sheet, children: [
        _viewToggle(view, (v) => setState(() => view = v)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'الشهر السابق', icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => monthOffset--)),
          Text(periodLabel, style: NoonText.style(12.5, weight: FontWeight.w700)),
          IconButton(tooltip: 'الشهر التالي', icon: const Icon(Icons.chevron_left), onPressed: monthOffset >= 0 ? null : () => setState(() => monthOffset++)),
        ]),
        _gradePick(store, grade, (g) => setState(() {
              grade = g;
              sectionId = '';
            })),
        if (sectionId.isNotEmpty)
          InputChip(
            label: Text(sections.where((s) => s.group.room.id == sectionId).firstOrNull?.group.label ?? ''),
            onDeleted: () => setState(() => sectionId = ''),
          ),
        if (view == 'students') ...[
          _NumLine(label: 'غاب', suffix: 'أيام فأكثر', value: minAbsent, onChanged: (v) => setState(() => minAbsent = v)),
          _NumLine(label: 'حضوره', suffix: '% فأقل', value: maxRate, onChanged: (v) => setState(() => maxRate = v.clamp(0, 100))),
          _Search(onChanged: (v) => setState(() => q = v)),
        ],
      ]),
      if (sections.isNotEmpty)
        _kpis([
          (label: 'الحضور', value: rate == null ? '—' : '$rate%', sub: '$present يوم حضور', color: rate == null ? null : (rate < 85 ? _red : _green), onTap: null),
          (label: 'غياب', value: '$absent', sub: '${scoped.fold<int>(0, (n, s) => n + s.rows.where((r) => r.absent > 0).length)} طالب غاب', color: absent > 0 ? _red : null, onTap: null),
          (label: 'مأذون', value: '$excused', sub: '${scoped.fold<int>(0, (n, s) => n + s.rows.where((r) => r.excused > 0).length)} طالب', color: excused > 0 ? _amber : null, onTap: null),
          (label: 'الطلاب', value: '$students', sub: '${scoped.length} شعبة · ${days.length} يوم دوام', color: null, onTap: null),
        ]),
      if (sections.isEmpty)
        const NoonEmpty('لا شعب')
      else if (view == 'students')
        studentRows.isEmpty
            ? const NoonEmpty('لا طلاب')
            : _list([
                for (final x in studentRows)
                  _row(x.r.student.fullName, x.section, [
                    _val('${x.r.absent}', color: x.r.absent > 0 ? _red : null, hint: 'غياب'),
                    _val('${x.r.excused}', color: AdminNoon.muted, hint: 'مأذون'),
                    _val('${x.r.present}', hint: 'حضور'),
                  ], onTap: () => _openStudent(context, x.r.student.id)),
              ])
      else
        _list([
          for (final s in scoped)
            _row(s.group.label, '${s.rows.length} طالب · ${s.absent} غياب · ${s.excused} مأذون', [
              _val(s.rate == null ? '—' : '${s.rate}%', color: s.rate != null && s.rate! < 85 ? _amber : null),
            ], onTap: () => setState(() {
                  sectionId = s.group.room.id;
                  view = 'students';
                })),
          _row('المدرسة', '$students طالب · $absent غياب · $excused مأذون', [_val(rate == null ? '—' : '$rate%')]),
        ]),
    ], onRefresh: () async => setState(_memo.clear));
  }
}

// ── إنذارات الغياب — `AbsenceAlertsView` ─────────────────────────────────────

class _AlertsReport extends StatefulWidget {
  const _AlertsReport();

  @override
  State<_AlertsReport> createState() => _AlertsReportState();
}

class _AlertsReportState extends State<_AlertsReport> {
  String grade = '';
  String q = '';
  final picked = <String>{};
  bool busy = false;
  int reload = 0;
  final _memo = _Memo<List<AbsenceAlert>>();

  static const _levelColors = [Color(0xFFD97706), Color(0xFFDC2626), Color(0xFFB91C1C), Color(0xFF7F1D1D)];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final f = store.settings.followup;
    if (!f.absenceEnabled) {
      return _body([
        const NoonEmpty('الإنذارات متوقفة'),
        Center(child: NoonButton(small: true, icon: Icons.tune_rounded, label: 'الإعدادات', onPressed: () => _openSettings(context, 'followup'))),
      ]);
    }
    final alerts = _memo.get(reload, () => loadAbsenceAlerts(store));
    final shown = [for (final a in alerts) if ((grade.isEmpty || a.student.gradeLevel.trim() == grade) && _matches(a.student.fullName, q)) a];
    final selected = [for (final a in shown) if (picked.contains(a.student.id)) a];
    final target = selected.isNotEmpty ? selected : shown;

    Future<void> send() async {
      if (target.isEmpty || busy) return;
      if (!await confirmSheet(context, title: 'إرسال', message: 'إرسال ${target.length} إنذار للأهل؟', confirmColor: AdminNoon.tealD)) return;
      setState(() => busy = true);
      final r = await sendAbsenceAlerts(store, target);
      if (!mounted || !context.mounted) return;
      showAppSnack(context, r.failed > 0 ? 'أُرسل ${r.sent}، وتعذّر ${r.failed}' : 'أُرسل ${r.sent}', error: r.failed > 0);
      setState(() {
        busy = false;
        picked.clear();
        reload++;
      });
    }

    _Sheet sheet() => (
          title: 'إنذارات الغياب',
          meta: [grade.isEmpty ? 'المدرسة' : grade, '${shown.length} طالب'],
          headers: ['#', 'اسم الطالب', 'الصف', 'الشعبة', 'أيام الغياب', 'الإنذار'],
          rows: [for (var i = 0; i < shown.length; i++) [i + 1, shown[i].student.fullName, shown[i].student.gradeLevel, shown[i].student.section, shown[i].days, shown[i].levelName]],
          landscape: false,
        );

    return _body([
      _Bar(sheet: sheet, children: [
        _gradePick(store, grade, (g) => setState(() => grade = g)),
        _Search(onChanged: (v) => setState(() => q = v)),
      ]),
      _kpis([
        for (var i = 0; i < f.levels.length; i++)
          () {
            final n = shown.where((a) => a.level == i).length;
            return (label: alertLevelName(i, f.levels.length), value: '$n', sub: '${f.levels[i]} يوم فأكثر', color: n > 0 ? _levelColors[i.clamp(0, 3)] : null, onTap: null);
          }(),
      ]),
      if (shown.isEmpty)
        const NoonEmpty('لا إنذارات مستحقة')
      else ...[
        Row(children: [
          Expanded(child: Text(selected.isNotEmpty ? '${selected.length} مختار' : '${shown.length} مستحق', style: NoonText.style(12, color: AdminNoon.muted))),
          NoonButton(small: true, tone: NoonTone.sun, icon: Icons.send_outlined, busy: busy, label: 'إرسال للأهل (${target.length})', onPressed: send),
        ]),
        const SizedBox(height: 8),
        _list([
          for (final a in shown)
            _row(
              a.student.fullName,
              [
                [a.student.gradeLevel, a.student.section].where((x) => x.trim().isNotEmpty).join(' · '),
                if (a.sentLevel >= 0) 'أُرسل: ${alertLevelName(a.sentLevel, f.levels.length)}',
              ].where((x) => x.isNotEmpty).join(' · '),
              [
                _val('${a.days}', hint: 'أيام الغياب'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _levelColors[a.level.clamp(0, 3)], borderRadius: BorderRadius.circular(999)),
                  child: Text(a.levelName, style: NoonText.style(11, weight: FontWeight.w700, color: Colors.white)),
                ),
              ],
              leading: Checkbox(
                value: picked.contains(a.student.id),
                onChanged: (v) => setState(() => v == true ? picked.add(a.student.id) : picked.remove(a.student.id)),
              ),
              onTap: () => _openStudent(context, a.student.id),
            ),
        ]),
      ],
    ]);
  }
}

// ── العلامات: مشترك ─────────────────────────────────────────────────────────

mixin _GradesState<T extends StatefulWidget> on State<T> {
  String period = 'term_1';
  String grade = '';
  final _cards = _Memo<List<SectionGrades>>();

  List<SectionGrades> sections(AppStore store) => _cards.get(grade, () => sectionGrades(store, grade: grade));

  Widget periodPick(ValueChanged<String> onChanged) => _Pick<String>(value: period, options: periodLabels, onChanged: onChanged);

  Widget? monthlyGuard(AppStore store) => store.gradingForViewedYear.mode == 'monthly' ? const NoonEmpty('غير متاح مع المعدل الشهري') : null;
}

// ── النتائج ─────────────────────────────────────────────────────────────────

class _ResultsReport extends StatefulWidget {
  const _ResultsReport();

  @override
  State<_ResultsReport> createState() => _ResultsReportState();
}

class _ResultsReportState extends State<_ResultsReport> with _GradesState {
  String view = 'sections';
  String metric = '';
  String order = 'top';
  int min = 0, max = 0, limit = 0;
  String q = '';
  String sectionId = '';
  final picked = <int>[];

  static const _orders = {'top': 'الأعلى أولاً', 'bottom': 'الأدنى أولاً', 'fail': 'دون النجاح'};

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (monthlyGuard(store) case final g?) return g;
    final pass = store.gradingForViewedYear.passPercent;
    final all = sections(store);
    final scoped = [for (final s in all) if (sectionId.isEmpty || s.id == sectionId) s];
    final prev = previousAverages(store);
    final subjects = subjectNames(all.expand((s) => s.cards));

    ({int graded, double? average, int failing, double sum}) summary(SectionGrades s) {
      final avgs = [for (final c in s.cards) if (studentAverage(c, period) case final a?) a];
      final sum = avgs.fold<double>(0, (a, b) => a + b);
      return (graded: avgs.length, average: avgs.isEmpty ? null : round1(sum / avgs.length), failing: avgs.where((a) => a < pass).length, sum: sum);
    }

    final parts = [for (final s in scoped) summary(s)];
    final graded = parts.fold<int>(0, (n, p) => n + p.graded);
    final average = graded == 0 ? null : round1(parts.fold<double>(0, (n, p) => n + p.sum) / graded);
    final failing = parts.fold<int>(0, (n, p) => n + p.failing);

    final ranked = rankStudents(
      [for (final s in scoped) SectionGrades(id: s.id, label: s.label, cards: [for (final c in s.cards) if (_matches(c.studentName, q)) c])],
      metric: metric,
      period: period,
      order: order,
      pass: pass,
      min: min,
      max: max,
      limit: limit,
      picked: picked,
      prev: prev,
    );
    final metricLabel = metric.isEmpty ? 'المعدل' : (metric == 'prev' ? 'السنة الماضية' : metric.substring(4));
    // عنوان يُقرأ جملة لا رموزاً
    final queryTitle = [
      limit > 0 ? 'أول $limit ${limit > 10 ? 'طالباً' : 'طلاب'}' : 'الطلاب',
      picked.isNotEmpty ? 'بتقدير ${picked.map((b) => bands[b]).join(' أو ')}' : (order == 'fail' ? 'دون علامة النجاح' : order == 'top' ? 'من الأعلى' : 'من الأدنى'),
      metric.isEmpty ? 'في المعدل العام' : (metric == 'prev' ? 'في معدل السنة الماضية' : 'في $metricLabel'),
      '— ${grade.isEmpty ? 'المدرسة كلها' : 'الصف $grade'}',
    ].join(' ');

    _Sheet sheet() => view == 'students'
        ? (
            title: queryTitle,
            meta: [metric == 'prev' ? 'معدل السنة الماضية' : periodLabels[period]!, '${ranked.length} طالب'],
            headers: ['#', 'اسم الطالب', 'الشعبة', metricLabel],
            rows: [for (var i = 0; i < ranked.length; i++) [i + 1, ranked[i].card.studentName, ranked[i].section, '${_num(ranked[i].value)}%']],
            landscape: false,
          )
        : (
            title: 'نتائج ${periodLabels[period]}',
            meta: [grade.isEmpty ? 'المدرسة' : grade, 'النجاح ${_num(pass)}%'],
            headers: ['الشعبة', 'مرصود', 'المعدل', 'دون النجاح'],
            rows: [
              for (var i = 0; i < scoped.length; i++) [scoped[i].label, parts[i].graded, parts[i].average == null ? '—' : '${_num(parts[i].average!)}%', parts[i].failing],
            ],
            landscape: false,
          );

    return _body([
      _Bar(sheet: sheet, children: [
        _viewToggle(view, (v) => setState(() => view = v)),
        if (metric != 'prev') periodPick((p) => setState(() => period = p)),
        _gradePick(store, grade, (g) => setState(() {
              grade = g;
              sectionId = '';
              metric = '';
            })),
        if (sectionId.isNotEmpty)
          InputChip(label: Text(all.where((s) => s.id == sectionId).firstOrNull?.label ?? ''), onDeleted: () => setState(() => sectionId = '')),
        if (view == 'students') ...[
          _Pick<String>(
            value: metric,
            options: {'': 'المعدل العام', for (final n in subjects) 'sub:$n': n, if (prev.isNotEmpty) 'prev': 'معدل السنة الماضية'},
            onChanged: (v) => setState(() => metric = v),
          ),
          _Pick<String>(value: order, options: _orders, onChanged: (v) => setState(() => order = v)),
          _NumLine(label: 'علامته من', suffix: '%', value: min, onChanged: (v) => setState(() => min = v)),
          _NumLine(label: 'إلى', suffix: '%', value: max, onChanged: (v) => setState(() => max = v)),
          _NumLine(label: 'أول', suffix: 'طالب', value: limit, onChanged: (v) => setState(() => limit = v)),
          _Search(onChanged: (v) => setState(() => q = v)),
        ],
      ]),
      if (view == 'students')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < bands.length; i++)
              FilterChip(
                label: Text(bands[i]),
                selected: picked.contains(i),
                selectedColor: _bandColors[i].withValues(alpha: 0.2),
                onSelected: (on) => setState(() => on ? (picked..add(i)..sort()) : picked.remove(i)),
              ),
            Text('${ranked.length} طالب', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
          ]),
        ),
      if (view == 'sections' && graded > 0)
        _kpis([
          (label: 'المعدل', value: average == null ? '—' : '${_num(average)}%', sub: 'النجاح ${_num(pass)}%', color: average != null && average < pass ? _red : null, onTap: null),
          (label: 'دون النجاح', value: '$failing', sub: '${(failing / graded * 100).round()}% من المرصودين', color: failing > 0 ? _red : null, onTap: null),
          (label: 'ناجح', value: '${graded - failing}', sub: '${((graded - failing) / graded * 100).round()}%', color: _green, onTap: null),
          (label: 'مرصود', value: '$graded', sub: '${scoped.length} شعبة', color: null, onTap: null),
        ]),
      if (all.isEmpty)
        const NoonEmpty('لا شعب')
      else if (view == 'students')
        ranked.isEmpty
            ? const NoonEmpty('لا طلاب')
            : _list([
                for (var i = 0; i < ranked.length; i++)
                  _row('${i + 1}. ${ranked[i].card.studentName}', ranked[i].section, [
                    _val('${_num(ranked[i].value)}%', color: ranked[i].value < pass ? _red : null),
                  ], onTap: () => _openStudent(context, ranked[i].card.id)),
              ])
      else
        _list([
          for (var i = 0; i < scoped.length; i++)
            _row(scoped[i].label, '${parts[i].graded} مرصود${parts[i].failing > 0 ? ' · ${parts[i].failing} دون النجاح' : ''}', [
              _val(parts[i].average == null ? '—' : '${_num(parts[i].average!)}%'),
            ], onTap: () => setState(() {
                  sectionId = scoped[i].id;
                  order = 'top';
                  view = 'students';
                })),
        ]),
    ], onRefresh: () async => setState(_cards.clear));
  }
}

// ── تحليل المواد ─────────────────────────────────────────────────────────────

class _AnalysisReport extends StatefulWidget {
  const _AnalysisReport();

  @override
  State<_AnalysisReport> createState() => _AnalysisReportState();
}

class _AnalysisReportState extends State<_AnalysisReport> with _GradesState {
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (monthlyGuard(store) case final g?) return g;
    final pass = store.gradingForViewedYear.passPercent;
    final a = analyzeSubjects(sections(store).expand((s) => s.cards).toList(), period, pass);
    final rows = [...a.subjects, ?a.overall];
    String pct(int n, int of) => '${of == 0 ? 0 : (n / of * 100).round()}%';

    _Sheet sheet() => (
          title: 'تحليل نتائج ${periodLabels[period]}',
          meta: [grade.isEmpty ? 'المدرسة' : grade, 'النجاح ${_num(pass)}%'],
          headers: ['المادة', 'الطلاب', ...bands, 'النجاح', 'المعدل'],
          rows: [
            for (final r in rows) [r.name, r.count, for (final n in r.bandCounts) '$n (${pct(n, r.count)})', '${r.passRate}%', '${_num(r.average)}%'],
          ],
          landscape: true,
        );

    // جدول تحليل النتائج المعتمد في المدارس: لكل مادة عدد كل تقدير ونسبته، ثم النجاح والمعدل
    return _body([
      _Bar(sheet: sheet, children: [
        periodPick((p) => setState(() => period = p)),
        _gradePick(store, grade, (g) => setState(() => grade = g)),
      ]),
      if (a.subjects.isEmpty)
        const NoonEmpty('لا علامات')
      else
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              color: r == a.overall ? const Color(0xFFF1F5F9) : null,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(r.name, style: NoonText.style(13.5, weight: FontWeight.w700))),
                  Text('${r.count} طالب', style: NoonText.style(11.5, color: AdminNoon.muted)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  for (var i = 0; i < bands.length; i++)
                    Expanded(
                      child: Column(children: [
                        Text(bands[i], style: NoonText.style(10, color: AdminNoon.muted)),
                        Text('${r.bandCounts[i]}', style: NoonText.style(13, weight: FontWeight.w700, color: i == 4 && r.bandCounts[i] > 0 ? _red : null)),
                        Text(pct(r.bandCounts[i], r.count), style: NoonText.style(10, color: AdminNoon.muted)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Text('النجاح ', style: NoonText.style(12, color: AdminNoon.muted)),
                  Text('${r.passRate}%', style: NoonText.style(12.5, weight: FontWeight.w700, color: r.passRate < 70 ? _red : null)),
                  const Spacer(),
                  Text('المعدل ', style: NoonText.style(12, color: AdminNoon.muted)),
                  Tooltip(
                    message: 'الأعلى ${_num(r.max)}% · الأدنى ${_num(r.min)}%',
                    child: Text('${_num(r.average)}%', style: NoonText.style(12.5, weight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ),
    ], onRefresh: () async => setState(_cards.clear));
  }
}

// ── مقارنة الشعب ─────────────────────────────────────────────────────────────

class _CompareReport extends StatefulWidget {
  const _CompareReport();

  @override
  State<_CompareReport> createState() => _CompareReportState();
}

class _CompareReportState extends State<_CompareReport> with _GradesState {
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (monthlyGuard(store) case final g?) return g;
    final pass = store.gradingForViewedYear.passPercent;
    final cols = [for (final s in sections(store)) if (s.cards.isNotEmpty) s];
    final m = compareMatrix(cols, period);

    _Sheet sheet() => (
          title: 'مقارنة الشعب',
          meta: ['النجاح ${_num(pass)}%'],
          headers: ['المادة', for (final s in cols) s.label],
          rows: [
            for (final r in m.rows) [r.name, for (final v in r.values) v == null ? '' : '${_num(v)}%'],
            ['المعدل العام', for (final v in m.overall) v == null ? '' : '${_num(v)}%'],
          ],
          landscape: cols.length > 5,
        );

    double? bestOf(List<double?> v) {
      final n = v.whereType<double>().toList();
      return n.length > 1 ? n.reduce((a, b) => a > b ? a : b) : null;
    }

    Widget cell(double? v, bool best) {
      if (v == null) return Text('—', textAlign: TextAlign.center, style: NoonText.style(12, color: AdminNoon.faint));
      final c = _bandCells[bandOf(v, pass)];
      return Tooltip(
        message: best ? 'الأعلى في المادة' : '',
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(4), border: best ? Border.all(color: _green, width: 2) : null),
          child: Text('${_num(v)}%', style: NoonText.style(12, weight: FontWeight.w700, color: c.fg)),
        ),
      );
    }

    Widget line(String name, List<double?> values, {bool total = false}) {
      final best = bestOf(values);
      return Container(
        color: total ? const Color(0xFFF1F5F9) : null,
        child: Row(children: [
          SizedBox(width: 120, child: Padding(padding: const EdgeInsets.all(6), child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12, weight: FontWeight.w700)))),
          for (final v in values) SizedBox(width: 76, child: cell(v, v != null && v == best)),
        ]),
      );
    }

    return _body([
      _Bar(sheet: sheet, children: [
        periodPick((p) => setState(() => period = p)),
        _gradePick(store, grade, (g) => setState(() => grade = g)),
      ]),
      if (cols.isEmpty || m.rows.isEmpty)
        const NoonEmpty('لا علامات')
      else
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                color: const Color(0xFFF1F5F9),
                child: Row(children: [
                  SizedBox(width: 120, child: Padding(padding: const EdgeInsets.all(6), child: Text('المادة', style: NoonText.style(11.5, weight: FontWeight.w700)))),
                  for (final s in cols)
                    SizedBox(width: 76, child: Text(s.label, textAlign: TextAlign.center, maxLines: 2, style: NoonText.style(10.5, weight: FontWeight.w700))),
                ]),
              ),
              for (final r in m.rows) line(r.name, r.values),
              line('المعدل العام', m.overall, total: true),
            ]),
          ),
        ),
    ], onRefresh: () async => setState(_cards.clear));
  }
}

// ── التراجع — `GradeDeclineView` ─────────────────────────────────────────────

class _DeclineReport extends StatefulWidget {
  const _DeclineReport();

  @override
  State<_DeclineReport> createState() => _DeclineReportState();
}

class _DeclineReportState extends State<_DeclineReport> {
  String grade = '';
  int minDrop = 10;
  String subjectId = '';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final pass = store.gradingForViewedYear.passPercent;
    final people = <String, ({String name, String section})>{
      for (final g in groupBySection(store, grade: grade))
        for (final s in g.students) s.id: (name: s.fullName, section: g.label),
    };
    final declines = examDeclines(store.evaluations.where((e) => people.containsKey(e.studentId)), minDrop < 1 ? 1 : minDrop.toDouble());
    String subjectName(String id) => store.subjectById(id)?.name ?? '—';
    final subjectsInList = {for (final d in declines) d.subjectId}.toList()..sort((a, b) => subjectName(a).compareTo(subjectName(b)));
    final rows = [for (final d in declines) if ((subjectId.isEmpty || d.subjectId == subjectId) && _matches(people[d.studentId]?.name ?? '', q)) d];
    final students = {for (final r in rows) r.studentId}.length;
    String band(double p) => bands[bandOf(p, pass)];

    _Sheet sheet() => (
          title: 'من نزلت علامته $minDrop% فأكثر بين آخر اختبارين',
          meta: ['$students طالب'],
          headers: ['#', 'اسم الطالب', 'الشعبة', 'المادة', 'السابق', 'الأخير', 'النزول', 'التقدير'],
          rows: [
            for (var i = 0; i < rows.length; i++)
              [
                i + 1,
                people[rows[i].studentId]?.name,
                people[rows[i].studentId]?.section,
                subjectName(rows[i].subjectId),
                '${_num(rows[i].before.percent)}%',
                '${_num(rows[i].after.percent)}%',
                '${_num(rows[i].diff.abs())}%',
                '${band(rows[i].before.percent)} ← ${band(rows[i].after.percent)}',
              ],
          ],
          landscape: true,
        );

    return _body([
      _Bar(sheet: sheet, children: [
        _NumLine(label: 'نزلت علامته', suffix: '% فأكثر بين آخر اختبارين', value: minDrop, onChanged: (v) => setState(() => minDrop = v)),
        _gradePick(store, grade, (g) => setState(() => grade = g)),
        if (subjectsInList.length > 1)
          _Pick<String>(value: subjectId, options: {'': 'كل المواد', for (final id in subjectsInList) id: subjectName(id)}, onChanged: (v) => setState(() => subjectId = v)),
        _Search(onChanged: (v) => setState(() => q = v)),
      ]),
      if (rows.isNotEmpty)
        _kpis([
          (label: 'طلاب تراجعوا', value: '$students', sub: '', color: _red, onTap: null),
          (label: 'تراجع في مادة', value: '${rows.length}', sub: '', color: _amber, onTap: null),
          (label: 'صاروا دون النجاح', value: '${rows.where((r) => r.after.percent < pass && r.before.percent >= pass).length}', sub: '', color: _red, onTap: null),
          (label: 'أشد نزول', value: '${_num(rows.first.diff.abs())}%', sub: people[rows.first.studentId]?.name ?? '', color: _red, onTap: null),
        ]),
      if (rows.isEmpty)
        const NoonEmpty('لا تراجع بهذا الحد')
      else
        _list([
          for (final r in rows)
            _row(
              people[r.studentId]?.name ?? '',
              '${subjectName(r.subjectId)}: ${_num(r.before.percent)}% ← ${_num(r.after.percent)}% · ${band(r.before.percent)} ← ${band(r.after.percent)}',
              [_val('▼ ${_num(r.diff.abs())}%', color: _red, hint: '${r.before.title} ${_dm(r.before.date)} ← ${r.after.title} ${_dm(r.after.date)}')],
              onTap: () => _openStudent(context, r.studentId),
            ),
        ]),
    ]);
  }
}

// ── اكتمال الرصد — `GradeCompletionView` ─────────────────────────────────────

class _CompletionReport extends StatefulWidget {
  const _CompletionReport();

  @override
  State<_CompletionReport> createState() => _CompletionReportState();
}

class _CompletionReportState extends State<_CompletionReport> {
  String grade = '';
  bool onlyMissing = false;
  final _memo = _Memo<({String term, List<CompletionRow> rows})>();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final data = _memo.get(0, () => loadCompletion(store));
    final term = periodLabels[data.term]!;
    final rows = [for (final r in data.rows) if (grade.isEmpty || r.room.gradeLevel.trim() == grade) r];
    final done = rows.fold<int>(0, (n, r) => n + r.done);
    final total = rows.fold<int>(0, (n, r) => n + r.total);
    final late = rows.fold<int>(0, (n, r) => n + r.late);
    final pct = total == 0 ? 0 : (done / total * 100).round();
    String label(CompletionRow r) => sectionLabel(r.room);

    final byTeacher = <String, List<CompletionRow>>{};
    for (final r in rows) {
      byTeacher.putIfAbsent(r.teacherId, () => []).add(r);
    }
    final teachers = [
      for (final e in byTeacher.entries)
        (
          id: e.key,
          name: e.value.first.teacherName,
          rows: [for (final r in e.value) if (!onlyMissing || r.done < r.total) r],
          missing: [for (final r in e.value) if (r.done < r.total) r],
          late: e.value.fold<int>(0, (n, r) => n + r.late),
        ),
    ].where((t) => t.rows.isNotEmpty).toList()
      ..sort((a, b) => b.late != a.late ? b.late - a.late : (b.missing.length != a.missing.length ? b.missing.length - a.missing.length : a.name.compareTo(b.name)));

    /// تذكير بالواتساب بما ينقص المعلم بالضبط
    void remind(String id, String name, List<CompletionRow> missing) {
      final phone = store.teacherById(id)?.phone.trim() ?? '';
      if (phone.isEmpty) return;
      final lines = missing.map((r) => '• ${r.subjectName} ${label(r)}: ${r.components.where((c) => !c.done).map((c) => c.name).join('، ')}').join('\n');
      final text = 'الأستاذ/ة $name، تحية طيبة.\nنرجو استكمال رصد العلامات ($term):\n$lines';
      launchUrl(Uri.parse('https://wa.me/${getWhatsAppPhone(phone)}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
    }

    _Sheet sheet() => (
          title: 'اكتمال الرصد · $term',
          meta: [grade.isEmpty ? 'المدرسة' : grade, '$done من $total'],
          headers: ['المادة', 'الشعبة', 'المعلم', 'المرصود', 'الناقص', 'المتأخر'],
          rows: [
            for (final r in rows)
              [
                r.subjectName,
                label(r),
                r.teacherName,
                '${r.done}/${r.total}',
                r.components.where((c) => !c.done).map((c) => c.name).join('، '),
                r.components.where((c) => c.late).map((c) => c.name).join('، '),
              ],
          ],
          landscape: true,
        );

    if (data.rows.isEmpty) return const NoonEmpty('لا مواد مسندة لمعلمين');
    return _body([
      _Bar(sheet: sheet, children: [
        _gradePick(store, grade, (g) => setState(() => grade = g)),
        FilterChip(label: const Text('الناقص فقط'), selected: onlyMissing, onSelected: (v) => setState(() => onlyMissing = v)),
        if (store.settings.followup.gradeDeadlines.isEmpty)
          Tooltip(
            message: 'ليظهر المتأخر عن موعده',
            child: NoonButton(small: true, icon: Icons.tune_rounded, label: 'حدّد مواعيد الرصد', onPressed: () => _openSettings(context, 'followup')),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(TextSpan(children: [
          const TextSpan(text: 'رُصد '),
          TextSpan(text: '$pct%', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' ($done من $total · $term)', style: TextStyle(color: AdminNoon.muted, fontSize: 11.5)),
          if (late > 0) TextSpan(text: '   متأخر عن موعده $late', style: const TextStyle(color: _red, fontWeight: FontWeight.w700)),
        ]), style: NoonText.style(13)),
      ),
      if (teachers.isEmpty)
        const NoonEmpty('كل الرصد مكتمل')
      else
        for (final t in teachers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _openTeacher(context, t.id),
                      child: Text(t.name, style: NoonText.style(13.5, weight: FontWeight.w700)),
                    ),
                  ),
                  if (t.missing.isNotEmpty && (store.teacherById(t.id)?.phone.trim() ?? '').isNotEmpty)
                    TextButton(onPressed: () => remind(t.id, t.name, t.missing), child: const Text('تذكير بالواتساب')),
                ]),
                for (final r in t.rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: r.subjectName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' · ${label(r)}', style: TextStyle(color: AdminNoon.muted)),
                      ]), style: NoonText.style(12)),
                      if (r.unlinked > 0)
                        Tooltip(message: 'لا تدخل المعدل', child: Text('${r.unlinked} علامة بلا مكوّن', style: NoonText.style(11, color: _amber))),
                      const SizedBox(height: 4),
                      Wrap(spacing: 4, runSpacing: 4, children: [
                        for (final c in r.components)
                          Tooltip(
                            message: c.done ? 'رُصد${c.entries > 1 ? ' (${c.entries})' : ''}' : (c.due.isNotEmpty ? 'موعده ${_dm(c.due)}' : 'لم يُرصد'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: c.done ? const Color(0xFFDCFCE7) : (c.late ? const Color(0xFFFEF2F2) : Colors.white),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: c.done ? const Color(0xFF86EFAC) : (c.late ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0))),
                              ),
                              child: Text(
                                '${c.name} ${c.done ? '✓' : (c.late ? 'متأخر' : '—')}',
                                style: NoonText.style(10.5, weight: FontWeight.w700, color: c.done ? _green : (c.late ? _red : AdminNoon.faint)),
                              ),
                            ),
                          ),
                      ]),
                    ]),
                  ),
              ]),
            ),
          ),
    ], onRefresh: () async => setState(_memo.clear));
  }
}

// ── قوائم الطلاب — `StudentsReport` ──────────────────────────────────────────

const _traits = {
  'sick': 'حالة صحية',
  'male': 'ذكور',
  'female': 'إناث',
  'app_parent_never': 'ولي أمر لم يدخل البوابة',
  'app_student_never': 'طالب لم يدخل البوابة',
  'app_week_none': 'لا دخول منذ أسبوع',
};
const _numLabels = {'absent': 'غياب', 'due': 'متأخر', 'prev': 'السنة الماضية'};
const _numSuffix = {'absent': 'أيام فأكثر', 'due': 'فأكثر', 'prev': '% فأكثر'};
const _numDefault = {'absent': 5, 'due': 100, 'prev': 90};

bool _recent(AccountUsage? u) =>
    u != null &&
    (u.today || u.yesterday || u.days7 > 0 || (u.lastSeen != null && DateTime.now().difference(DateTime.tryParse(u.lastSeen!) ?? DateTime(2000)).inDays < 7));

class _StudentsReport extends StatefulWidget {
  const _StudentsReport();

  @override
  State<_StudentsReport> createState() => _StudentsReportState();
}

class _StudentsReportState extends State<_StudentsReport> {
  String grade = '';
  final traits = <String>[];
  final nums = <String, int>{};
  String q = '';
  Map<String, AccountUsage>? usage;
  bool usageAsked = false;
  final _facts = _Memo<({Map<String, int> absent, Map<String, double> due, Map<String, double> prev})>();

  bool _sick(Student s) => s.healthStatus == 'مريض' || s.medicalCondition.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final appTraits = [for (final t in traits) if (t.startsWith('app_')) t];
    // دخول البوابة سحابي: يُجلب حين تُطلب صفة منه فقط
    if (appTraits.isNotEmpty && !usageAsked) {
      usageAsked = true;
      accountUsage().then((u) {
        if (mounted) setState(() => usage = u);
      });
    }
    // الأرقام تُحسب حين يُطلب شرط منها فقط: غياب العام يمرّ على سجل الحضور كله
    final facts = nums.isEmpty ? null : _facts.get(0, () => (absent: absentDaysThisYear(store), due: duesByStudent(store), prev: previousAverages(store)));
    num? factOf(Student s, String k) => switch (k) {
          'absent' => facts?.absent[s.id] ?? 0,
          'due' => facts?.due[s.id],
          _ => facts?.prev[s.id],
        };
    bool appMatch(Student s, String t) {
      final u = usage;
      if (u == null) return false;
      final parent = u['parent:${s.id}'], student = u['student:${s.id}'];
      if (t == 'app_parent_never') return parent?.lastSeen == null;
      if (t == 'app_student_never') return student?.lastSeen == null;
      return !_recent(parent) && !_recent(student);
    }

    bool hasTrait(Student s, String t) => switch (t) {
          'male' => s.gender == 'ذكر',
          'female' => s.gender == 'أنثى',
          'sick' => _sick(s),
          _ => appMatch(s, t),
        };
    final groups = [
      for (final g in groupBySection(store, grade: grade))
        (
          label: g.label,
          students: [
            for (final s in g.students)
              if (traits.every((t) => hasTrait(s, t)) &&
                  nums.entries.every((e) => (factOf(s, e.key) ?? -1) >= e.value) &&
                  _matches(s.fullName, q))
                s,
          ],
        ),
    ].where((g) => g.students.isNotEmpty).toList();
    final total = groups.fold<int>(0, (n, g) => n + g.students.length);
    final title = [...traits.map((t) => _traits[t]!), for (final e in nums.entries) '${_numLabels[e.key]} ${e.value}'].join(' + ');
    String factText(Student s, String k) {
      final v = factOf(s, k);
      return v == null ? '' : (k == 'due' ? money(v) : k == 'prev' ? '${_num(v)}%' : '$v');
    }

    String seenText(Student s) =>
        'ولي الأمر: ${lastSeenLabel(usage?['parent:${s.id}'])} · الطالب: ${lastSeenLabel(usage?['student:${s.id}'])}';

    _Sheet sheet() => (
          title: title.isEmpty ? 'كل الطلاب' : title,
          meta: [grade.isEmpty ? 'المدرسة' : grade, '$total طالب'],
          headers: ['#', 'اسم الطالب', 'الشعبة', 'الهوية', 'الجنس', 'الميلاد', 'ولي الأمر', 'جوال ولي الأمر', 'الحالة الصحية', ...nums.keys.map((k) => _numLabels[k]!), if (appTraits.isNotEmpty) 'آخر دخول'],
          rows: [
            for (final g in groups)
              for (final s in g.students)
                [
                  '',
                  s.fullName,
                  g.label,
                  s.nationalId,
                  s.gender,
                  s.birthDate,
                  s.parentName,
                  formatPhoneDisplay(s.parentPhone, s.parentPhonePrefix),
                  s.medicalCondition.trim().isNotEmpty ? s.medicalCondition : (s.healthStatus == 'مريض' ? 'مريض' : ''),
                  ...nums.keys.map((k) => factText(s, k)),
                  if (appTraits.isNotEmpty) seenText(s),
                ],
          ].indexed.map((e) => [e.$1 + 1, ...e.$2.skip(1)]).toList(),
          landscape: true,
        );

    // الغياب والمتأخرات والدخول لها تقاريرها المفصلة: رابط إليها بدل تكرار تفصيلها هنا
    final related = [
      if (nums.containsKey('absent')) ('تقرير الغياب', 'absence'),
      if (nums.containsKey('due')) ('تقرير المتأخرات', 'arrears'),
      if (appTraits.isNotEmpty) ('تقرير استخدام النظام', 'usage'),
    ];

    return _body([
      _Bar(sheet: sheet, children: [
        PopupMenuButton<String>(
          tooltip: 'الصفات المختارة تجتمع',
          onSelected: (v) => setState(() {
            if (v.startsWith('num:')) {
              nums[v.substring(4)] = _numDefault[v.substring(4)]!;
            } else {
              traits.add(v);
            }
          }),
          itemBuilder: (_) => [
            for (final e in _traits.entries)
              if (!traits.contains(e.key)) PopupMenuItem(value: e.key, child: Text(e.value)),
            for (final e in _numLabels.entries)
              if (!nums.containsKey(e.key)) PopupMenuItem(value: 'num:${e.key}', child: Text('${e.value}…')),
          ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.lineStrong)),
            child: Text('+ صفة', style: NoonText.style(12.5, weight: FontWeight.w700)),
          ),
        ),
        for (final e in nums.entries)
          Container(
            padding: const EdgeInsetsDirectional.only(start: 10),
            decoration: BoxDecoration(color: AdminNoon.mist, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _NumLine(label: _numLabels[e.key]!, suffix: _numSuffix[e.key]!, value: e.value, onChanged: (v) => setState(() => nums[e.key] = v)),
              IconButton(tooltip: 'إزالة', icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => nums.remove(e.key))),
            ]),
          ),
        for (final t in traits) InputChip(label: Text(_traits[t]!), onDeleted: () => setState(() => traits.remove(t))),
        _gradePick(store, grade, (g) => setState(() => grade = g)),
        _Search(onChanged: (v) => setState(() => q = v)),
        Text('$total', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
      ]),
      if (related.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('للتفصيل:', style: NoonText.style(12, color: AdminNoon.muted)),
            for (final r in related) TextButton(onPressed: () => openReport(context, r.$2), child: Text('${r.$1} ←')),
          ]),
        ),
      if (total == 0)
        const NoonEmpty('لا طلاب')
      else
        _list([
          for (final g in groups)
            for (final s in g.students)
              _row(
                s.fullName,
                [
                  g.label,
                  if (traits.contains('sick')) (s.medicalCondition.trim().isNotEmpty ? s.medicalCondition.trim() : 'مريض') else formatPhoneDisplay(s.parentPhone, s.parentPhonePrefix),
                  if (appTraits.isNotEmpty) seenText(s),
                ].join(' · '),
                [for (final k in nums.keys) _val(factText(s, k), hint: _numLabels[k])],
                onTap: () => _openStudent(context, s.id),
              ),
        ]),
    ]);
  }
}

// ── المتأخرات — `DuesReport` ────────────────────────────────────────────────

class _DuesReport extends StatefulWidget {
  const _DuesReport();

  @override
  State<_DuesReport> createState() => _DuesReportState();
}

class _DuesReportState extends State<_DuesReport> {
  String grade = '';
  String view = 'sections';
  int minDue = 0;
  String q = '';
  String sectionId = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final due = duesByStudent(store);
    final all = [
      for (final g in groupBySection(store, grade: grade, activeOnly: true))
        (
          group: g,
          rows: [
            for (final s in g.students)
              if ((due[s.id] ?? 0) > 0 && (due[s.id] ?? 0) >= minDue && _matches(s.fullName, q)) (student: s, due: due[s.id]!),
          ]..sort((a, b) => b.due.compareTo(a.due)),
        ),
    ].where((s) => s.rows.isNotEmpty).toList();
    final shown = [for (final s in all) if (sectionId.isEmpty || s.group.room.id == sectionId) s];
    double sum(Iterable<({Student student, double due})> r) => r.fold(0, (n, x) => n + x.due);
    final total = shown.fold<double>(0, (n, s) => n + sum(s.rows));
    final debtors = [for (final s in shown) for (final r in s.rows) (r: r, section: s.group.label)]..sort((a, b) => b.r.due.compareTo(a.r.due));

    _Sheet sheet() => (
          title: 'المتأخرات',
          meta: [grade.isEmpty ? 'المدرسة' : grade, '${debtors.length} طالب', money(total)],
          headers: ['#', 'اسم الطالب', 'الشعبة', 'ولي الأمر', 'الجوال', 'المتأخر'],
          rows: [
            for (var i = 0; i < debtors.length; i++)
              [i + 1, debtors[i].r.student.fullName, debtors[i].section, debtors[i].r.student.parentName, formatPhoneDisplay(debtors[i].r.student.parentPhone, debtors[i].r.student.parentPhonePrefix), money(debtors[i].r.due)],
          ],
          landscape: false,
        );

    return _body([
      _Bar(sheet: sheet, children: [
        _viewToggle(view, (v) => setState(() => view = v), students: 'المدينون'),
        _gradePick(store, grade, (g) => setState(() {
              grade = g;
              sectionId = '';
            })),
        if (sectionId.isNotEmpty)
          InputChip(label: Text(all.where((s) => s.group.room.id == sectionId).firstOrNull?.group.label ?? ''), onDeleted: () => setState(() => sectionId = '')),
        _NumLine(label: 'متأخر عليه', suffix: 'فأكثر', value: minDue, onChanged: (v) => setState(() => minDue = v)),
        if (view == 'students') _Search(onChanged: (v) => setState(() => q = v)),
      ]),
      if (debtors.isNotEmpty)
        _kpis([
          (label: 'المتأخر', value: money(total), sub: '${shown.length} شعبة', color: _red, onTap: null),
          (label: 'المدينون', value: '${debtors.length}', sub: 'متوسط ${money((total / debtors.length).round())}', color: _amber, onTap: null),
          (label: 'الأعلى', value: money(debtors.first.r.due), sub: debtors.first.r.student.fullName, color: null, onTap: () => _openStudent(context, debtors.first.r.student.id)),
        ]),
      if (shown.isEmpty)
        const NoonEmpty('لا متأخرات')
      else if (view == 'students')
        _list([
          for (final d in debtors)
            _row(d.r.student.fullName, '${d.section} · ${formatPhoneDisplay(d.r.student.parentPhone, d.r.student.parentPhonePrefix)}', [_val(money(d.r.due), color: _amber)],
                onTap: () => _openStudent(context, d.r.student.id)),
        ])
      else
        _list([
          for (final s in shown)
            _row(s.group.label, '${s.rows.length} طالب', [_val(money(sum(s.rows)), color: _amber)], onTap: () => setState(() {
                  sectionId = s.group.room.id;
                  view = 'students';
                })),
          _row('المدرسة', '${debtors.length} طالب', [_val(money(total), color: _amber)]),
        ]),
    ]);
  }
}

// ── بيانات ناقصة أو خاطئة — `DataQualityReport` ─────────────────────────────

const _issues = {
  'parent_phone': 'جوال ولي الأمر',
  'parent_id': 'هوية ولي الأمر',
  'student_id': 'هوية الطالب',
  'parent_name': 'اسم ولي الأمر',
  'student_phone': 'جوال الطالب',
  'birth': 'تاريخ الميلاد',
};
final _idRe = RegExp(r'^\d{9}$');

/// `isValidStudentPhone`: 05 ثم 8 أرقام، أو 970/972 ثم 9، أو 20 ثم 10.
bool _phoneOk(String phone, [String prefix = '']) {
  final d = combinePhoneAndPrefix(phone, prefix).replaceAll(RegExp(r'\D'), '');
  return RegExp(r'^05\d{8}$').hasMatch(d) || RegExp(r'^97[02]\d{9}$').hasMatch(d) || RegExp(r'^20\d{10}$').hasMatch(d);
}

class _DataReport extends StatefulWidget {
  const _DataReport();

  @override
  State<_DataReport> createState() => _DataReportState();
}

class _DataReportState extends State<_DataReport> {
  String grade = '';
  String issue = '';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final groups = groupBySection(store, grade: grade, activeOnly: true);
    // الهوية المكررة بين الطلاب خطأ إدخال غالباً
    final idCount = <String, int>{};
    for (final s in store.students.where((s) => s.status == 'active')) {
      final id = s.nationalId.trim();
      if (id.isNotEmpty) idCount[id] = (idCount[id] ?? 0) + 1;
    }
    final thisYear = DateTime.now().year;
    final all = [
      for (final g in groups)
        for (final s in g.students)
          () {
            final p = <(String, String)>[];
            final sid = s.nationalId.trim(), pid = s.parentNationalId.trim();
            if (s.parentPhone.trim().isEmpty) {
              p.add(('parent_phone', 'ناقص'));
            } else if (!_phoneOk(s.parentPhone, s.parentPhonePrefix)) {
              p.add(('parent_phone', 'صيغة خاطئة'));
            }
            if (pid.isEmpty) {
              p.add(('parent_id', 'ناقص'));
            } else if (!_idRe.hasMatch(pid)) {
              p.add(('parent_id', 'ليست 9 أرقام'));
            }
            if (sid.isEmpty) {
              p.add(('student_id', 'ناقص'));
            } else if (!_idRe.hasMatch(sid)) {
              p.add(('student_id', 'ليست 9 أرقام'));
            } else if ((idCount[sid] ?? 0) > 1) {
              p.add(('student_id', 'مكررة'));
            }
            if (s.parentName.trim().isEmpty) p.add(('parent_name', 'ناقص'));
            if (s.phone.trim().isNotEmpty && !_phoneOk(s.phone, s.phonePrefix)) p.add(('student_phone', 'صيغة خاطئة'));
            final year = int.tryParse(s.birthDate.length >= 4 ? s.birthDate.substring(0, 4) : '') ?? 0;
            if (s.birthDate.isEmpty) {
              p.add(('birth', 'ناقص'));
            } else if (year == 0 || thisYear - year < 3 || thisYear - year > 22) {
              p.add(('birth', 'غير معقول'));
            }
            return (student: s, section: g.label, problems: p);
          }(),
    ].where((r) => r.problems.isNotEmpty).toList();
    final staff = grade.isNotEmpty
        ? const <({Teacher t, List<String> problems})>[]
        : [
            for (final t in store.teachersInViewedYear)
              (
                t: t,
                problems: [
                  if (t.phone.trim().isEmpty) 'الجوال ناقص' else if (!_phoneOk(t.phone)) 'الجوال بصيغة خاطئة',
                  if (t.nationalId.trim().isNotEmpty && !_idRe.hasMatch(t.nationalId.trim())) 'الهوية ليست 9 أرقام',
                ],
              ),
          ].where((x) => x.problems.isNotEmpty).toList();
    final rows = [for (final r in all) if ((issue.isEmpty || r.problems.any((p) => p.$1 == issue)) && _matches(r.student.fullName, q)) r];
    int countOf(String k) => all.where((r) => r.problems.any((p) => p.$1 == k)).length;
    String problems(List<(String, String)> list) => [for (final p in list) if (issue.isEmpty || p.$1 == issue) '${_issues[p.$1]}: ${p.$2}'].join('، ');

    _Sheet sheet() => (
          title: issue.isNotEmpty ? '${_issues[issue]}: ناقص أو خاطئ' : 'البيانات الناقصة أو الخاطئة',
          meta: [grade.isEmpty ? 'المدرسة' : grade, '${rows.length} طالب'],
          headers: ['#', 'الاسم', 'الشعبة', 'المشكلة'],
          rows: [
            for (var i = 0; i < rows.length; i++) [i + 1, rows[i].student.fullName, rows[i].section, problems(rows[i].problems)],
            if (issue.isEmpty)
              for (final s in staff) ['', s.t.name, 'معلم', s.problems.join('، ')],
          ],
          landscape: false,
        );

    return _body([
      _Bar(sheet: sheet, children: [
        _gradePick(store, grade, (g) => setState(() => grade = g)),
        _Pick<String>(value: issue, options: {'': 'كل المشكلات', ..._issues}, onChanged: (v) => setState(() => issue = v)),
        _Search(onChanged: (v) => setState(() => q = v)),
      ]),
      if (all.isNotEmpty)
        _kpis([
          for (final k in ['parent_phone', 'parent_id', 'student_id'])
            (label: _issues[k]!, value: '${countOf(k)}', sub: '', color: countOf(k) > 0 ? _red : null, onTap: () => setState(() => issue = issue == k ? '' : k)),
        ]),
      if (rows.isEmpty && staff.isEmpty)
        const NoonEmpty('البيانات مكتملة')
      else ...[
        if (rows.isNotEmpty)
          _list([
            for (final r in rows)
              _row(r.student.fullName, r.section, [
                Flexible(
                  child: Text(problems(r.problems), textAlign: TextAlign.end, style: NoonText.style(11, weight: FontWeight.w700, color: _red)),
                ),
              ], onTap: () => _openStudent(context, r.student.id)),
          ]),
        if (issue.isEmpty && staff.isNotEmpty) ...[
          const SizedBox(height: 10),
          _list([
            for (final s in staff)
              _row(s.t.name, 'معلم', [Text(s.problems.join('، '), style: NoonText.style(11, weight: FontWeight.w700, color: _red))],
                  onTap: () => _openTeacher(context, s.t.id)),
          ]),
        ],
      ],
    ]);
  }
}

// ── استخدام النظام — `UsageReport` ──────────────────────────────────────────

const _whoLabels = {
  'parent_never': 'ولي الأمر لم يدخل',
  'student_never': 'الطالب لم يدخل',
  'week_none': 'لا دخول منذ أسبوع',
  'today': 'دخل اليوم',
  'all': 'كل الطلاب',
};
const _parentColor = Color(0xFF0EA5E9);
const _studentColor = Color(0xFF10B981);

class _UsageReport extends StatefulWidget {
  const _UsageReport();

  @override
  State<_UsageReport> createState() => _UsageReportState();
}

class _UsageReportState extends State<_UsageReport> {
  String grade = '';
  String view = 'sections';
  String who = 'parent_never';
  String q = '';
  late Future<(Map<String, AccountUsage>?, List<({String day, String role, int users})>?)> _load = _fetch();

  Future<(Map<String, AccountUsage>?, List<({String day, String role, int users})>?)> _fetch() async =>
      (await accountUsage(), await usageDaily(30));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return FutureBuilder(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final usage = snap.data?.$1;
        if (usage == null) {
          return _body([const NoonEmpty('يحتاج اتصالاً بالإنترنت')], onRefresh: () async => setState(() => _load = _fetch()));
        }
        final daily = snap.data?.$2;
        final groups = groupBySection(store, grade: grade, activeOnly: true);
        final all = groups.expand((g) => g.students).toList();
        AccountUsage? parentOf(Student s) => usage['parent:${s.id}'];
        AccountUsage? studentOf(Student s) => usage['student:${s.id}'];
        ({String label, String? whoKey, int today, int yesterday, int week, int ever, int never, int total}) roleRow(
            String label, List<AccountUsage?> list, int total, String? whoKey) {
          final seen = list.where((u) => u?.lastSeen != null).length;
          return (
            label: label,
            whoKey: whoKey,
            today: list.where((u) => u?.today ?? false).length,
            yesterday: list.where((u) => u?.yesterday ?? false).length,
            week: list.where(_recent).length,
            ever: seen,
            never: (total - seen).clamp(0, total),
            total: total,
          );
        }

        final teacherUsage = [for (final u in usage.values) if (u.role == 'teacher') u];
        final summary = [
          roleRow('الأهالي', all.map(parentOf).toList(), all.length, 'parent_never'),
          roleRow('الطلاب', all.map(studentOf).toList(), all.length, 'student_never'),
          if (grade.isEmpty)
            roleRow('المعلمون', teacherUsage, store.teachersInViewedYear.length > teacherUsage.length ? store.teachersInViewedYear.length : teacherUsage.length, null),
        ];
        bool matchWho(Student s) => switch (who) {
              'parent_never' => parentOf(s)?.lastSeen == null,
              'student_never' => studentOf(s)?.lastSeen == null,
              'week_none' => !_recent(parentOf(s)) && !_recent(studentOf(s)),
              'today' => (parentOf(s)?.today ?? false) || (studentOf(s)?.today ?? false),
              _ => true,
            };
        final listed = [
          for (final g in groups) (label: g.label, students: [for (final s in g.students) if (matchWho(s) && _matches(s.fullName, q)) s]),
        ].where((g) => g.students.isNotEmpty).toList();
        final count = listed.fold<int>(0, (n, g) => n + g.students.length);
        int pctOf(int n, int of) => of == 0 ? 0 : (n / of * 100).round();
        final sectionStats = [
          for (final g in groups)
            (
              g: g,
              paP: pctOf(g.students.where((s) => parentOf(s)?.lastSeen != null).length, g.students.length),
              stP: pctOf(g.students.where((s) => studentOf(s)?.lastSeen != null).length, g.students.length),
              wkP: pctOf(g.students.where((s) => _recent(parentOf(s)) || _recent(studentOf(s))).length, g.students.length),
            ),
        ];
        // ثلاثون يوماً متصلة: اليوم بلا دخول صفر لا فجوة
        final byDay = <String, (int, int)>{};
        for (final r in daily ?? const <({String day, String role, int users})>[]) {
          if (r.role == 'teacher') continue;
          final d = byDay[r.day] ?? (0, 0);
          byDay[r.day] = r.role == 'parent' ? (d.$1 + r.users, d.$2) : (d.$1, d.$2 + r.users);
        }
        final points = [
          for (var i = 29; i >= 0; i--)
            () {
              final day = DateTime.now().subtract(Duration(days: i));
              final v = byDay[isoDate(day)] ?? (0, 0);
              return (label: '${day.day}/${day.month}', parent: v.$1, student: v.$2);
            }(),
        ];
        final maxDay = points.fold<int>(1, (m, p) => p.parent + p.student > m ? p.parent + p.student : m);

        _Sheet sheet() => view == 'students'
            ? (
                title: _whoLabels[who]!,
                meta: [grade.isEmpty ? 'المدرسة' : grade, '$count طالب'],
                headers: ['#', 'اسم الطالب', 'الشعبة', 'ولي الأمر', 'جوال ولي الأمر', 'دخول ولي الأمر', 'دخول الطالب'],
                rows: [
                  for (final (i, s) in [for (final g in listed) for (final s in g.students) (g.label, s)].indexed)
                    [i + 1, s.$2.fullName, s.$1, s.$2.parentName, formatPhoneDisplay(s.$2.parentPhone, s.$2.parentPhonePrefix), lastSeenLabel(parentOf(s.$2)), lastSeenLabel(studentOf(s.$2))],
                ],
                landscape: true,
              )
            : (
                title: 'استخدام النظام',
                meta: [grade.isEmpty ? 'المدرسة' : grade],
                headers: ['الشعبة', 'الطلاب', 'دخل الطالب', 'دخل ولي الأمر', 'نشط هذا الأسبوع'],
                rows: [for (final r in sectionStats) [r.g.label, r.g.students.length, '${r.stP}%', '${r.paP}%', '${r.wkP}%']],
                landscape: false,
              );

        Color pctColor(int p) => p >= 70 ? _green : (p >= 40 ? const Color(0xFFD97706) : _red);
        Widget bar(int pct, Color color) => Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: pct / 100, minHeight: 5, color: color, backgroundColor: const Color(0xFFE2E8F0)),
                ),
              ),
              SizedBox(width: 34, child: Text('$pct%', textAlign: TextAlign.end, style: NoonText.style(10, weight: FontWeight.w700, color: AdminNoon.muted))),
            ]);

        return _body([
          _Bar(sheet: sheet, children: [
            _gradePick(store, grade, (g) => setState(() => grade = g)),
            if (view == 'students') ...[
              _Pick<String>(value: who, options: _whoLabels, onChanged: (v) => setState(() => who = v)),
              _Search(onChanged: (v) => setState(() => q = v)),
              Text('$count', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
            ],
          ]),
          if (view == 'students') ...[
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => setState(() => view = 'sections'), child: const Text('→ الملخص'))),
            if (count == 0)
              const NoonEmpty('لا طلاب')
            else
              _list([
                for (final g in listed)
                  for (final s in g.students)
                    _row(s.fullName, g.label, [
                      _val(lastSeenLabel(parentOf(s)), color: parentOf(s)?.lastSeen == null ? _red : null, hint: 'ولي الأمر'),
                      _val(lastSeenLabel(studentOf(s)), color: studentOf(s)?.lastSeen == null ? _red : null, hint: 'الطالب'),
                    ], onTap: () => _openStudent(context, s.id)),
              ]),
          ] else ...[
            // بطاقة لكل دور: نسبة من دخل، ونشاطه القريب، ومن لم يدخل يفتح قائمته
            for (final r in summary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: r.total == 0 ? 0 : r.ever / r.total,
                          strokeWidth: 6,
                          color: pctColor(pctOf(r.ever, r.total)),
                          backgroundColor: const Color(0xFFE2E8F0),
                        ),
                        Text('${pctOf(r.ever, r.total)}%', style: NoonText.style(12, weight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.label, style: NoonText.style(13, weight: FontWeight.w700)),
                        Text('دخل ${r.ever} من ${r.total}', style: NoonText.style(11, color: AdminNoon.muted)),
                        Text('اليوم ${r.today} · أمس ${r.yesterday} · الأسبوع ${r.week}', style: NoonText.style(11, color: AdminNoon.muted)),
                        if (r.never > 0)
                          InkWell(
                            onTap: r.whoKey == null
                                ? null
                                : () => setState(() {
                                      who = r.whoKey!;
                                      view = 'students';
                                    }),
                            child: Text('${r.never} لم يدخلوا', style: NoonText.style(11, weight: FontWeight.w700, color: _red)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
            // الدخول اليومي: أعمدة متراكبة للأهالي والطلاب
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('الدخول اليومي${grade.isNotEmpty ? ' · المدرسة كلها' : ''}', style: NoonText.style(13, weight: FontWeight.w700))),
                  Text('■ ', style: TextStyle(color: _parentColor, fontSize: 11)),
                  Text('أهالي  ', style: NoonText.style(11, color: AdminNoon.muted)),
                  Text('■ ', style: TextStyle(color: _studentColor, fontSize: 11)),
                  Text('طلاب', style: NoonText.style(11, color: AdminNoon.muted)),
                ]),
                const SizedBox(height: 8),
                if (points.every((p) => p.parent + p.student == 0))
                  Padding(padding: const EdgeInsets.all(24), child: Text('لا دخول مسجّل بعد', textAlign: TextAlign.center, style: NoonText.style(12, color: AdminNoon.muted)))
                else
                  SizedBox(
                    height: 110,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (final p in points)
                        Expanded(
                          child: Tooltip(
                            message: '${p.label}: أهالي ${p.parent} · طلاب ${p.student}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                Container(height: 100 * p.student / maxDay, color: _studentColor),
                                Container(height: 100 * p.parent / maxDay, color: _parentColor),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            // الشعب: خانات صغيرة بشريطين
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('الشعب', style: NoonText.style(13, weight: FontWeight.w700))),
                  Text('من دخل يوماً', style: NoonText.style(11, color: AdminNoon.muted)),
                ]),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, c) => Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final r in sectionStats)
                      SizedBox(
                        width: (c.maxWidth - 6) / 2,
                        child: Tooltip(
                          message: '${r.g.students.length} طالب · أهالي ${r.paP}% · طلاب ${r.stP}% · نشط هذا الأسبوع ${r.wkP}%',
                          child: InkWell(
                            onTap: () => setState(() {
                              grade = r.g.room.gradeLevel.trim();
                              who = 'all';
                              view = 'students';
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: AdminNoon.line)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r.g.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(11.5, weight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                bar(r.paP, _parentColor),
                                const SizedBox(height: 3),
                                bar(r.stP, _studentColor),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ],
        ], onRefresh: () async => setState(() => _load = _fetch()));
      },
    );
  }
}

// ── سجل التعديلات — `EditLogReport` ─────────────────────────────────────────

const _editLabels = {'grade_edit': 'تعديل علامة', 'grade_delete': 'حذف علامة', 'student_edit': 'بيانات طالب'};

class _EditLogReport extends StatefulWidget {
  const _EditLogReport();

  @override
  State<_EditLogReport> createState() => _EditLogReportState();
}

class _EditLogReportState extends State<_EditLogReport> {
  String kind = '';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    String stamp(String iso) {
      final d = DateTime.tryParse(iso)?.toLocal();
      return d == null ? '' : '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    final entries = [
      for (final e in store.financeAudit)
        if (_editLabels.containsKey(e.action) &&
            (kind.isEmpty || (kind == 'students' ? e.action == 'student_edit' : e.action != 'student_edit')) &&
            (q.trim().isEmpty || e.studentName.contains(q.trim()) || e.userName.contains(q.trim())))
          e,
    ]..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final shown = entries.take(200).toList();

    return _body([
      _Bar(children: [
        _Pick<String>(value: kind, options: const {'': 'الكل', 'grades': 'العلامات', 'students': 'بيانات الطلاب'}, onChanged: (v) => setState(() => kind = v)),
        SizedBox(
          width: 180,
          height: 36,
          child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(isDense: true, hintText: 'طالب أو مستخدم')),
        ),
      ]),
      if (shown.isEmpty)
        const NoonEmpty('لا تعديلات')
      else
        _list([
          for (final e in shown)
            _row(
              e.studentName.isEmpty ? '—' : e.studentName,
              '${_editLabels[e.action]} · ${e.summary} · ${e.userName}',
              [Text(stamp(e.createdAt ?? ''), textDirection: TextDirection.ltr, style: NoonText.style(11, color: AdminNoon.muted))],
              onTap: e.studentId.isEmpty ? null : () => _openStudent(context, e.studentId),
            ),
        ]),
    ]);
  }
}
