import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/balance.dart';
import '../data/followup.dart';
import '../data/phone.dart';
import '../data/portal_usage.dart';
import '../data/reports_data.dart';
import '../data/school_calendar.dart';
import '../data/staff.dart';
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
const _amber = Color(0xFF475569);
const _bandColors = [Color(0xFF15803D), Color(0xFF22C55E), Color(0xFF0EA5E9), Color(0xFF64748B), Color(0xFFBA1A1A)];
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
      'absence' => const _AbsenceHub(),
      'alerts' => const _AbsenceHub(alerts: true),
      'results' => const _ResultsReport(),
      'completion' => const _CompletionReport(),
      'analysis' => const _AnalysisHub(),
      'decline' => const _AnalysisHub(initial: 'decline'),
      'compare' => const _AnalysisHub(initial: 'compare'),
      'students' => const _StudentsReport(),
      'arrears' => const _DuesReport(),
      'staff' => const _StaffReport(),
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

/// شريط التقرير: الفلاتر في شبكة منتظمة (المنتقيات بنصف العرض، والبحث والشروط بعرض كامل)،
/// وقائمة «تصدير» واحدة في طرف أول صف.
class _Bar extends StatelessWidget {
  const _Bar({required this.children, this.sheet});

  final List<Widget> children;
  final _Sheet Function()? sheet;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final half = (c.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final w in children)
                      if (w is _Search || w is _NumLine)
                        SizedBox(width: c.maxWidth, child: w)
                      else if (w is _Pick || w is _MonthNav || w is _AdvToggle || w is PopupMenuButton)
                        SizedBox(width: half, child: w)
                      else
                        w,
                  ],
                );
              },
            ),
          ),
          if (sheet != null)
            PopupMenuButton<String>(
              tooltip: 'تصدير',
              icon: Icon(Icons.file_download_outlined, color: AdminNoon.ink),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                final data = _toSheet(store, sheet!());
                if (v == 'pdf') {
                  printSheet(context, data);
                } else {
                  downloadSheetXlsx(context, data);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('تنزيل PDF')),
                PopupMenuItem(value: 'xlsx', child: Text('تنزيل Excel')),
              ],
            ),
        ],
      ),
    );
  }
}

/// منتقي الشهر: السابق يميناً والتالي يساراً (معطّل بعد الحالي)، بإطار المنتقيات نفسه.
class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.label, required this.onPrev, required this.onNext});

  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AdminNoon.line)),
        child: Row(
          children: [
            IconButton(
              tooltip: 'الشهر السابق',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left, size: 22),
              onPressed: onPrev,
            ),
            Expanded(child: Text(label, textAlign: TextAlign.center, style: NoonText.style(13, weight: FontWeight.w700))),
            IconButton(
              tooltip: 'الشهر التالي',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right, size: 22),
              onPressed: onNext,
            ),
          ],
        ),
      );
}

/// زر يفتح الفلاتر المتقدمة أو يطويها؛ نقطة صغيرة تدل أن فيها شرطاً مفعّلاً وهي مطوية.
class _AdvToggle extends StatelessWidget {
  const _AdvToggle({required this.open, required this.active, required this.onTap});

  final bool open;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: open ? AdminNoon.mist : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: open ? AdminNoon.ink : AdminNoon.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 17, color: AdminNoon.ink),
              const SizedBox(width: 6),
              Text('تصفية متقدمة', style: NoonText.style(12.5, weight: FontWeight.w700)),
              if (active && !open) ...[
                const SizedBox(width: 6),
                Container(width: 7, height: 7, decoration: BoxDecoration(color: AdminNoon.ink, shape: BoxShape.circle)),
              ],
              Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: AdminNoon.muted),
            ],
          ),
        ),
      );
}

class _Pick<T> extends StatelessWidget {
  const _Pick({required this.value, required this.options, required this.onChanged});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AdminNoon.line)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: options.containsKey(value) ? value : options.keys.first,
            isDense: true,
            isExpanded: true,
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
    _Pick<String>(value: value, options: {'': 'كل المدرسة', for (final g in reportGrades(store)) g: g}, onChanged: onChanged);

/// النطاق باختيار واحد — `ScopeSelect`: كل المدرسة، صف، أو شعبة تحت صفها. الشعبة تفتح
/// طلابها، والمدرسة والصف ملخص شعبهما، و«طلاب الصف» خيار يظهر حين يُفتح من سطر المجموع.
/// يعيد (الصف، الشعبة، العرض).
Widget _scopePick(
  AppStore store, {
  required String grade,
  required String sectionId,
  required String view,
  required void Function(String grade, String sectionId, String view) onChanged,
  bool rooms = true,
}) {
  final current = sectionId.isNotEmpty ? 's:$sectionId' : (view == 'students' ? 'st:$grade' : (grade.isEmpty ? '' : 'g:$grade'));
  final all = store.roomsInViewedYear;
  final options = <String, String>{
    '': 'كل المدرسة',
    if (current == 'st:') 'st:': 'طلاب المدرسة',
    for (final g in reportGrades(store)) ...{
      'g:$g': g,
      if (current == 'st:$g') 'st:$g': 'طلاب $g',
      if (rooms)
        for (final r in all.where((r) => r.gradeLevel.trim() == g)) 's:${r.id}': '    ${r.name}',
    },
  };
  return _Pick<String>(
    value: current,
    options: options,
    onChanged: (v) {
      if (v.startsWith('s:')) {
        final room = all.where((r) => r.id == v.substring(2)).firstOrNull;
        onChanged(room?.gradeLevel.trim() ?? '', v.substring(2), 'students');
      } else if (v.startsWith('st:')) {
        onChanged(v.substring(3), '', 'students');
      } else {
        onChanged(v.isEmpty ? '' : v.substring(2), '', 'sections');
      }
    },
  );
}

/// الحد يُقرأ جملة: «غاب [3] أيام فأكثر» — `MinInput`. صف بعرض كامل بإطار الحقول، والخانة في طرفه.
class _NumLine extends StatelessWidget {
  const _NumLine({required this.label, required this.suffix, required this.value, required this.onChanged});

  final String label;
  final String suffix;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 6, 0),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AdminNoon.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label ', style: NoonText.style(12.5, color: AdminNoon.muted)),
          SizedBox(
            width: 64,
            height: 32,
            child: TextFormField(
              initialValue: value > 0 ? '$value' : '',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: NoonText.style(13.5, weight: FontWeight.w700),
              decoration: const InputDecoration(isDense: true, hintText: '0', contentPadding: EdgeInsets.symmetric(vertical: 6)),
              onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
            ),
          ),
          Text(' $suffix', style: NoonText.style(12.5, color: AdminNoon.muted)),
        ]),
      );
}

class _Search extends StatelessWidget {
  const _Search({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 180,
        height: 40,
        child: TextField(
          onChanged: onChanged,
          decoration: const InputDecoration(isDense: true, hintText: 'بحث بالاسم', prefixIcon: Icon(Icons.search, size: 18), filled: true, fillColor: Colors.white),
        ),
      );
}


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
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.label, style: NoonText.style(11.5, color: AdminNoon.muted)),
                    const SizedBox(height: 2),
                    FittedBox(child: Text(k.value, style: NoonText.style(19, weight: FontWeight.w700, color: k.color))),
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
          if (onTap != null) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.chevron_right_rounded, size: 18, color: AdminNoon.faint)),
        ]),
      ),
    );

Widget _list(List<Widget> rows) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: noonPanel(),
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
  bool showAdv = false;
  final _memo = _Memo<List<SectionAttendance>>();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = DateTime.now();
    final m = DateTime(now.year, now.month + monthOffset, 1);
    final month = isoDate(m).substring(0, 7);
    final days = monthSchoolDays(month, weekend: store.settings.weekend);
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
        _MonthNav(
          label: periodLabel,
          onPrev: () => setState(() => monthOffset--),
          onNext: monthOffset >= 0 ? null : () => setState(() => monthOffset++),
        ),
        _scopePick(store, grade: grade, sectionId: sectionId, view: view, onChanged: (g, s, v) => setState(() {
              grade = g;
              sectionId = s;
              view = v;
              if (v == 'sections') {
                q = '';
                minAbsent = 0;
                maxRate = 0;
              }
            })),
        _Search(onChanged: (v) => setState(() {
              q = v;
              if (v.isNotEmpty) view = 'students';
            })),
        if (view == 'students')
          _AdvToggle(open: showAdv, active: minAbsent > 0 || maxRate > 0, onTap: () => setState(() => showAdv = !showAdv)),
        if (view == 'students' && showAdv) ...[
          _NumLine(label: 'غاب', suffix: 'أيام فأكثر', value: minAbsent, onChanged: (v) => setState(() => minAbsent = v)),
          _NumLine(label: 'حضوره', suffix: '% فأقل', value: maxRate, onChanged: (v) => setState(() => maxRate = v.clamp(0, 100))),
        ],
      ]),
      if (sections.isNotEmpty)
        _kpis([
          (label: 'الحضور', value: rate == null ? '—' : '$rate%', sub: '$present يوم حضور', color: rate == null ? null : (rate < 85 ? _red : _green), onTap: null),
          (label: 'غياب', value: '$absent', sub: '${scoped.fold<int>(0, (n, s) => n + s.rows.where((r) => r.absent > 0).length)} طالب غاب', color: absent > 0 ? _red : null, onTap: null),
          (label: 'مأذون', value: '$excused', sub: '${scoped.fold<int>(0, (n, s) => n + s.rows.where((r) => r.excused > 0).length)} طالب', color: excused > 0 ? _amber : null, onTap: null),
          (label: 'الطلاب', value: '$students', sub: '${scoped.length} شعبة · ${days.where((d) => d.compareTo(isoDate(now)) <= 0).length} يوم دوام', color: null, onTap: null),
        ]),
      if (sections.isEmpty)
        const NoonEmpty('لا شعب')
      else if (view == 'students')
        studentRows.isEmpty
            ? const NoonEmpty('لا طلاب')
            : _list([
                // الحضور نسبة كما في ملخص الشعب، و«—» لمن لم يُرصد
                for (final x in studentRows)
                  _row(x.r.student.fullName, sectionId.isEmpty ? x.section : '', [
                    _val('${x.r.absent}', color: x.r.absent > 0 ? _red : null, hint: 'غياب'),
                    _val('${x.r.excused}', color: AdminNoon.muted, hint: 'مأذون'),
                    _val(x.r.present + x.r.absent + x.r.excused == 0 ? '—' : '${x.r.rate}%', color: x.r.rate < 85 ? _amber : null, hint: 'الحضور'),
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
          _row(grade.isEmpty ? 'المدرسة' : grade, '$students طالب · $absent غياب · $excused مأذون', [_val(rate == null ? '—' : '$rate%')],
              onTap: () => setState(() => view = 'students')),
        ]),
    ], onRefresh: () async => setState(_memo.clear));
  }
}

/// تقرير بعروض لنفس البيانات: شريط «الغياب | الإنذارات» أو «المواد | الشعب | التراجع» فوق
/// العرض المختار، فلا يكون كل عرض سطراً وحده في الفهرس.
class _Views extends StatefulWidget {
  const _Views({required this.views, required this.initial});

  final Map<String, ({String label, Widget view})> views;
  final String initial;

  @override
  State<_Views> createState() => _ViewsState();
}

class _ViewsState extends State<_Views> {
  late String current = widget.views.containsKey(widget.initial) ? widget.initial : widget.views.keys.first;

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: NoonSegment<String>(
            value: current,
            options: [for (final e in widget.views.entries) (e.key, e.value.label)],
            onChanged: (v) => setState(() => current = v),
          ),
        ),
        Expanded(child: KeyedSubtree(key: ValueKey(current), child: widget.views[current]!.view)),
      ]);
}

/// «الغياب» و«الإنذارات» تقرير واحد — كالويب.
class _AbsenceHub extends StatelessWidget {
  const _AbsenceHub({this.alerts = false});

  final bool alerts;

  @override
  Widget build(BuildContext context) => _Views(initial: alerts ? 'alerts' : 'absence', views: const {
        'absence': (label: 'الغياب', view: _AbsenceReport()),
        'alerts': (label: 'الإنذارات', view: _AlertsReport()),
      });
}

/// «التحليل»: المواد ومقارنة الشعب والتراجع — كالويب.
class _AnalysisHub extends StatelessWidget {
  const _AnalysisHub({this.initial = 'analysis'});

  final String initial;

  @override
  Widget build(BuildContext context) => _Views(initial: initial, views: const {
        'analysis': (label: 'المواد', view: _AnalysisReport()),
        'compare': (label: 'الشعب', view: _CompareReport()),
        'decline': (label: 'التراجع', view: _DeclineReport()),
      });
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

  static final _levelColors = [AdminNoon.ink, const Color(0xFFDC2626), const Color(0xFFB91C1C), const Color(0xFF7F1D1D)];

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
        NoonButton(tone: NoonTone.ink, expand: true, busy: busy, label: 'إرسال للأهل (${target.length})', onPressed: send),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(selected.isNotEmpty ? '${selected.length} مختار من ${shown.length}' : '${shown.length} مستحق', style: NoonText.style(12, color: AdminNoon.muted))),
          TextButton(
            onPressed: () => setState(() {
              if (selected.length == shown.length) {
                picked.clear();
              } else {
                picked.addAll([for (final a in shown) a.student.id]);
              }
            }),
            child: Text(selected.length == shown.length ? 'إلغاء التحديد' : 'تحديد الكل', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.ink)),
          ),
        ]),
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
  bool showAdv = false;

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
        if (metric != 'prev') periodPick((p) => setState(() => period = p)),
        _scopePick(store, grade: grade, sectionId: sectionId, view: view, onChanged: (g, s, v) => setState(() {
              if (g != grade) metric = '';
              grade = g;
              sectionId = s;
              view = v;
              if (v == 'sections') {
                q = '';
                limit = 0;
                picked.clear();
              }
            })),
        // الأوائل: أول عشرة بالمعدل في النطاق؛ النقر ثانية يلغيها
        FilterChip(
          avatar: Icon(
            Icons.emoji_events_outlined,
            size: 16,
            color: view == 'students' && limit > 0 && order == 'top' && metric.isEmpty ? Colors.white : AdminNoon.text,
          ),
          label: const Text('الأوائل'),
          selected: view == 'students' && limit > 0 && order == 'top' && metric.isEmpty,
          onSelected: (on) => setState(() {
            if (!on) {
              limit = 0;
              return;
            }
            metric = '';
            order = 'top';
            picked.clear();
            limit = 10;
            view = 'students';
          }),
        ),
        _Search(onChanged: (v) => setState(() {
              q = v;
              if (v.isNotEmpty) view = 'students';
            })),
        if (view == 'students')
          _AdvToggle(
            open: showAdv,
            active: metric.isNotEmpty || order != 'top' || min > 0 || max > 0 || limit > 0,
            onTap: () => setState(() => showAdv = !showAdv),
          ),
        if (view == 'students' && showAdv) ...[
          _Pick<String>(
            value: metric,
            options: {'': 'المعدل العام', for (final n in subjects) 'sub:$n': n, if (prev.isNotEmpty) 'prev': 'معدل السنة الماضية'},
            onChanged: (v) => setState(() => metric = v),
          ),
          _Pick<String>(value: order, options: _orders, onChanged: (v) => setState(() => order = v)),
          _NumLine(label: 'علامته من', suffix: '%', value: min, onChanged: (v) => setState(() => min = v)),
          _NumLine(label: 'إلى', suffix: '%', value: max, onChanged: (v) => setState(() => max = v)),
          _NumLine(label: 'أول', suffix: 'طالب', value: limit, onChanged: (v) => setState(() => limit = v)),
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
                onSelected: (on) => setState(() => on ? (picked..add(i)..sort()) : picked.remove(i)),
              ),
            Text('${ranked.length} طالب', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
          ]),
        ),
      if (view == 'sections' && graded > 0)
        _kpis([
          (label: 'المعدل', value: average == null ? '—' : '${_num(average)}%', sub: '$graded طالب', color: average != null && average < pass ? _red : null, onTap: null),
          (label: 'دون النجاح', value: '$failing', sub: 'تحت ${_num(pass)}%', color: failing > 0 ? _red : null, onTap: null),
        ]),
      if (all.isEmpty)
        const NoonEmpty('لا شعب')
      else if (view == 'students')
        ranked.isEmpty
            ? const NoonEmpty('لا طلاب')
            : _list([
                for (var i = 0; i < ranked.length; i++)
                  _row('${i + 1}. ${ranked[i].card.studentName}', sectionId.isEmpty ? ranked[i].section : '', [
                    _val('${_num(ranked[i].value)}%', color: ranked[i].value < pass ? _red : null),
                  ], onTap: () => _openStudent(context, ranked[i].card.id)),
              ])
      else
        _list([
          for (var i = 0; i < scoped.length; i++)
            _row(scoped[i].label, '${parts[i].graded} طالب${parts[i].failing > 0 ? ' · ${parts[i].failing} دون النجاح' : ''}', [
              _val(parts[i].average == null ? '—' : '${_num(parts[i].average!)}%'),
            ], onTap: () => setState(() {
                  sectionId = scoped[i].id;
                  order = 'top';
                  view = 'students';
                })),
          _row(grade.isEmpty ? 'المدرسة' : grade, '$graded طالب${failing > 0 ? ' · $failing دون النجاح' : ''}', [
            _val(average == null ? '—' : '${_num(average)}%'),
          ], onTap: () => setState(() {
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
                const SizedBox(height: 10),
                // توزيع التقديرات بنظرة: شريط بحصة كل تقدير بلونه
                if (r.count > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(children: [
                        for (var i = 0; i < bands.length; i++)
                          if (r.bandCounts[i] > 0) Expanded(flex: r.bandCounts[i], child: ColoredBox(color: _bandColors[i % _bandColors.length])),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
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

    // مادة (أو المعدل العام): شعبها صفوف بشريط نسبة لكل شعبة، فلا مصفوفة أفقية تحتاج تمريراً
    Widget subjectCard(String name, List<double?> values, {bool total = false}) {
      final best = bestOf(values);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: total ? const Color(0xFFF1F5F9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminNoon.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: NoonText.style(14, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (var i = 0; i < cols.length; i++)
              Builder(builder: (_) {
                final v = values[i];
                final isBest = v != null && v == best;
                final c = v == null ? null : _bandCells[bandOf(v, pass)];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(
                      width: 104,
                      child: Text(cols[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12.5, color: AdminNoon.muted)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(children: [
                          Container(height: 8, color: AdminNoon.band),
                          if (v != null)
                            FractionallySizedBox(
                              widthFactor: (v / 100).clamp(0.0, 1.0),
                              child: Container(height: 8, color: c!.fg),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 62,
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (isBest) ...[Icon(Icons.star_rounded, size: 14, color: _green), const SizedBox(width: 2)],
                        Text(v == null ? '—' : '${_num(v)}%', style: NoonText.style(12.5, weight: FontWeight.w700, color: v == null ? AdminNoon.faint : c!.fg)),
                      ]),
                    ),
                  ]),
                );
              }),
          ],
        ),
      );
    }

    return _body([
      _Bar(sheet: sheet, children: [
        periodPick((p) => setState(() => period = p)),
        _gradePick(store, grade, (g) => setState(() => grade = g)),
      ]),
      if (cols.isEmpty || m.rows.isEmpty)
        const NoonEmpty('لا علامات')
      else ...[
        for (final r in m.rows) subjectCard(r.name, r.values),
        subjectCard('المعدل العام', m.overall, total: true),
      ],
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
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: noonPanel(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$pct%', style: NoonText.style(28, weight: FontWeight.w700, height: 1.1)),
                const SizedBox(width: 8),
                Expanded(child: Text('من الرصد مكتمل', style: NoonText.style(13, color: AdminNoon.muted))),
                if (late > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: _red.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                    child: Text('متأخر $late', style: NoonText.style(11.5, weight: FontWeight.w700, color: _red)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 7,
                backgroundColor: AdminNoon.band,
                valueColor: AlwaysStoppedAnimation(pct >= 100 ? AdminNoon.green700 : AdminNoon.ink),
              ),
            ),
            const SizedBox(height: 6),
            Text('$done من $total · $term', style: NoonText.style(11.5, color: AdminNoon.muted)),
          ],
        ),
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
                      child: Text(t.name, style: NoonText.style(14, weight: FontWeight.w700)),
                    ),
                  ),
                  if (t.missing.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AdminNoon.band, borderRadius: BorderRadius.circular(20)),
                      child: Text('${t.missing.length} ناقص', style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.muted)),
                    ),
                ]),
                if (t.missing.isNotEmpty && (store.teacherById(t.id)?.phone.trim() ?? '').isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => remind(t.id, t.name, t.missing),
                      icon: const Icon(Icons.chat_outlined, size: 16),
                      label: const Text('تذكير بالواتساب'),
                      style: TextButton.styleFrom(foregroundColor: AdminNoon.ink, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                    ),
                  ),
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
  'withdrawn': 'منسحبون',
  'male': 'ذكور',
  'female': 'إناث',
  'app_parent_never': 'ولي أمر لم يدخل البوابة',
  'app_student_never': 'طالب لم يدخل البوابة',
  'app_week_none': 'لا دخول منذ أسبوع',
};
const _numLabels = {'absent': 'غياب', 'due': 'متأخر', 'prev': 'السنة الماضية'};

/// صفات شائعة تظهر أزراراً حين لا صفة مختارة: نقرة واحدة بدل فتح القائمة.
const _quick = {
  'sick': 'حالة صحية',
  'num:absent': 'كثيرو الغياب',
  'num:due': 'عليهم متأخرات',
  'app_parent_never': 'لم يدخل ولي الأمر',
  'withdrawn': 'منسحبون',
};
const _quickIcons = <String, IconData>{
  'sick': Icons.medical_services_outlined,
  'num:absent': Icons.event_busy_outlined,
  'num:due': Icons.account_balance_wallet_outlined,
  'app_parent_never': Icons.phone_android_outlined,
  'withdrawn': Icons.person_off_outlined,
};
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
          'withdrawn' => s.status == 'withdrawn',
          _ => appMatch(s, t),
        };
    // يبدأ بلا قائمة: كل الطلاب في صفحة الطلاب، وهنا ما يُسأل عنه بصفة
    final asked = traits.isNotEmpty || nums.isNotEmpty || q.trim().isNotEmpty;
    void add(String v) => setState(() {
          if (v.startsWith('num:')) {
            nums[v.substring(4)] = _numDefault[v.substring(4)]!;
          } else if (!traits.contains(v)) {
            traits.add(v);
          }
        });
    final groups = [
      for (final g in groupBySection(store, grade: grade, withWithdrawn: true))
        (
          label: g.label,
          students: [
            for (final s in g.students)
              if (asked &&
                  (traits.contains('withdrawn') || s.status != 'withdrawn') &&
                  traits.every((t) => hasTrait(s, t)) &&
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
      if (nums.containsKey('due')) ('تقرير التحصيل', 'arrears'),
      if (appTraits.isNotEmpty) ('تقرير استخدام النظام', 'usage'),
    ];

    return _body([
      _Bar(sheet: sheet, children: [
        PopupMenuButton<String>(
          tooltip: 'الصفات المختارة تجتمع',
          onSelected: add,
          itemBuilder: (_) => [
            for (final e in _traits.entries)
              if (!traits.contains(e.key)) PopupMenuItem(value: e.key, child: Text(e.value)),
            for (final e in _numLabels.entries)
              if (!nums.containsKey(e.key)) PopupMenuItem(value: 'num:${e.key}', child: Text('${e.value}…')),
          ],
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AdminNoon.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 18, color: AdminNoon.ink),
              const SizedBox(width: 4),
              Text('إضافة صفة', style: NoonText.style(12.5, weight: FontWeight.w700)),
            ]),
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
        if (asked) Text('$total', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
      ]),
      if (!asked) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text('اسأل بسؤال جاهز أو أضف صفة وابحث', style: NoonText.style(12.5, weight: FontWeight.w600, color: AdminNoon.muted)),
        ),
        _list([
          for (final e in _quick.entries)
            _row(
              e.value,
              '',
              const [],
              onTap: () => add(e.key),
              leading: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AdminNoon.mist, borderRadius: BorderRadius.circular(10)),
                  child: Icon(_quickIcons[e.key] ?? Icons.person_search_outlined, size: 19, color: AdminNoon.ink),
                ),
              ),
            ),
        ]),
      ],
      if (related.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('للتفصيل:', style: NoonText.style(12, color: AdminNoon.muted)),
            for (final r in related) TextButton(onPressed: () => openReport(context, r.$2), child: Text('${r.$1} ←')),
          ]),
        ),
      if (!asked)
        const SizedBox.shrink()
      else if (total == 0)
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

/// التحصيل بالشعب — `DuesReport.tsx`: المطلوب والمدفوع والمتأخر ونسبة التحصيل، واختيار
/// شعبة (أو النقر عليها، أو على سطر المدرسة) يفتح مدينيها بأرقام أهاليهم.
class _DuesReportState extends State<_DuesReport> {
  String grade = '';
  String view = 'sections';
  int minDue = 0;
  String q = '';
  String sectionId = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    // مطلوب كل طالب ومدفوعه ومتأخره من أقساطه
    final required = <String, double>{}, paid = <String, double>{}, due = <String, double>{};
    for (final i in store.installments) {
      final charge = chargeableAmount(i);
      required[i.studentId] = (required[i.studentId] ?? 0) + charge;
      paid[i.studentId] = (paid[i.studentId] ?? 0) + (i.paidAmount < charge ? i.paidAmount : charge);
      if (isInstallmentDue(i)) due[i.studentId] = (due[i.studentId] ?? 0) + unpaidOf(i);
    }
    final all = [
      for (final g in groupBySection(store, grade: grade, activeOnly: true))
        (
          group: g,
          students: [for (final s in g.students) if ((required[s.id] ?? 0) > 0) s],
        ),
    ].where((s) => s.students.isNotEmpty).toList();
    double sumOf(Map<String, double> m, Iterable<Student> list) => list.fold(0, (n, s) => n + (m[s.id] ?? 0));
    final everyone = [for (final s in all) ...s.students];
    final totalRequired = sumOf(required, everyone), totalPaid = sumOf(paid, everyone), totalDue = sumOf(due, everyone);
    int? rateOf(double p, double r) => r <= 0 ? null : (p / r * 100).round();
    final rate = rateOf(totalPaid, totalRequired);
    final debtorCount = everyone.where((s) => (due[s.id] ?? 0) > 0.005).length;
    // المدينون: من حلّ عليه ولم يدفع، بالحد والبحث والشعبة
    final debtors = [
      for (final s in all)
        if (sectionId.isEmpty || s.group.room.id == sectionId)
          for (final st in s.students)
            if ((due[st.id] ?? 0) > 0.005 && (due[st.id] ?? 0) >= minDue && _matches(st.fullName, q)) (student: st, due: due[st.id]!, paid: paid[st.id] ?? 0, section: s.group.label),
    ]..sort((a, b) => b.due.compareTo(a.due));
    final debtorsDue = debtors.fold<double>(0, (n, d) => n + d.due);

    _Sheet sheet() => view == 'students'
        ? (
            title: 'المدينون',
            meta: [grade.isEmpty ? 'المدرسة' : grade, '${debtors.length} طالب', money(debtorsDue)],
            headers: ['#', 'اسم الطالب', 'الشعبة', 'ولي الأمر', 'الجوال', 'المدفوع', 'المتأخر'],
            rows: [
              for (var i = 0; i < debtors.length; i++)
                [i + 1, debtors[i].student.fullName, debtors[i].section, debtors[i].student.parentName, formatPhoneDisplay(debtors[i].student.parentPhone, debtors[i].student.parentPhonePrefix), money(debtors[i].paid), money(debtors[i].due)],
            ],
            landscape: false,
          )
        : (
            title: 'التحصيل',
            meta: [grade.isEmpty ? 'المدرسة' : grade, if (rate != null) 'التحصيل $rate%'],
            headers: ['الشعبة', 'الطلاب', 'المطلوب', 'المدفوع', 'المتأخر', 'التحصيل'],
            rows: [
              for (final s in all)
                [s.group.label, s.students.length, money(sumOf(required, s.students)), money(sumOf(paid, s.students)), money(sumOf(due, s.students)), '${rateOf(sumOf(paid, s.students), sumOf(required, s.students)) ?? 0}%'],
              ['المدرسة', everyone.length, money(totalRequired), money(totalPaid), money(totalDue), '${rate ?? 0}%'],
            ],
            landscape: false,
          );

    return _body([
      _Bar(sheet: sheet, children: [
        _scopePick(store, grade: grade, sectionId: sectionId, view: view, onChanged: (g, s, v) => setState(() {
              grade = g;
              sectionId = s;
              view = v;
              if (v == 'sections') {
                q = '';
                minDue = 0;
              }
            })),
        _Search(onChanged: (v) => setState(() {
              q = v;
              if (v.isNotEmpty) view = 'students';
            })),
        if (view == 'students') _NumLine(label: 'متأخر عليه', suffix: 'فأكثر', value: minDue, onChanged: (v) => setState(() => minDue = v)),
      ]),
      if (all.isNotEmpty)
        _kpis([
          (label: 'المدفوع', value: money(totalPaid), sub: 'من ${money(totalRequired)}', color: _green, onTap: null),
          (label: 'التحصيل', value: rate == null ? '—' : '$rate%', sub: '', color: rate != null && rate < 70 ? _red : null, onTap: null),
          (label: 'المتأخر', value: money(totalDue), sub: '$debtorCount طالب', color: totalDue > 0 ? _red : null, onTap: debtorCount > 0 ? () => setState(() => view = 'students') : null),
        ]),
      if (all.isEmpty)
        const NoonEmpty('لا أقساط')
      else if (view == 'students')
        debtors.isEmpty
            ? const NoonEmpty('لا متأخرات')
            : _list([
                for (final d in debtors)
                  _row(d.student.fullName, [if (sectionId.isEmpty) d.section, formatPhoneDisplay(d.student.parentPhone, d.student.parentPhonePrefix)].where((x) => x.trim().isNotEmpty).join(' · '),
                      [_val(money(d.due), color: _amber, hint: 'المتأخر')],
                      onTap: () => _openStudent(context, d.student.id)),
              ])
      else
        _list([
          for (final s in all)
            () {
              final r = rateOf(sumOf(paid, s.students), sumOf(required, s.students));
              return _row(s.group.label, 'المدفوع ${money(sumOf(paid, s.students))} · المتأخر ${money(sumOf(due, s.students))}', [
                _val(r == null ? '—' : '$r%', color: r != null && r < 70 ? _amber : null, hint: 'التحصيل'),
              ], onTap: () => setState(() {
                    sectionId = s.group.room.id;
                    view = 'students';
                  }));
            }(),
          _row(grade.isEmpty ? 'المدرسة' : grade, 'المدفوع ${money(totalPaid)} · المتأخر ${money(totalDue)}', [_val(rate == null ? '—' : '$rate%')],
              onTap: () => setState(() => view = 'students')),
        ]),
    ]);
  }
}

// ── دوام الموظفين — `StaffReport.tsx` ────────────────────────────────────────

/// دوام الموظفين في شهر: سطر لكل موظف بحضوره وغيابه وتأخيره وإجازاته، حتى اليوم.
/// يوم الإجازة الموافق عليها إجازة لا غياب، كما في الرواتب.
class _StaffReport extends StatefulWidget {
  const _StaffReport();

  @override
  State<_StaffReport> createState() => _StaffReportState();
}

class _StaffReportState extends State<_StaffReport> {
  int monthOffset = 0;
  String q = '';
  ({List<StaffDay> days, List<LeaveRequest> leaves})? data;
  bool failed = false;
  String _loaded = '';

  String get _month {
    final now = DateTime.now();
    return isoDate(DateTime(now.year, now.month + monthOffset, 1)).substring(0, 7);
  }

  Future<void> _load({bool force = false}) async {
    final month = _month;
    _loaded = month;
    final days = await StaffService.days('$month-01', '$month-31', force: force);
    final leaves = await StaffService.leaves(force: force);
    if (!mounted || _loaded != month) return;
    setState(() {
      failed = days == null || leaves == null;
      data = failed ? null : (days: days!, leaves: leaves!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (_loaded != _month) {
      data = null;
      failed = false;
      _load();
    }
    final month = _month;
    final m = DateTime.parse('$month-01');
    final label = '${_monthNames[m.month - 1]} ${m.year}';
    final today = isoDate(DateTime.now());
    final schoolDays = [for (final d in monthSchoolDays(month)) if (d.compareTo(today) <= 0) d];
    final d = data;
    final rows = d == null
        ? const <({Teacher teacher, int present, int absent, int late, int leave, int unmarked})>[]
        : ([
            for (final t in store.teachersInViewedYear)
              if (_matches(t.name, q))
                () {
                  final marked = {for (final x in d.days) if (x.teacherId == t.id) x.date: x.status};
                  var present = 0, absent = 0, late = 0, leave = 0, unmarked = 0;
                  for (final day in schoolDays) {
                    if (approvedLeaveOn(d.leaves, t.id, day) != null) {
                      leave++;
                    } else {
                      switch (marked[day]) {
                        case 'present':
                          present++;
                        case 'absent':
                          absent++;
                        case 'late':
                          late++;
                        default:
                          unmarked++;
                      }
                    }
                  }
                  return (teacher: t, present: present, absent: absent, late: late, leave: leave, unmarked: unmarked);
                }(),
          ]..sort((a, b) => a.teacher.name.compareTo(b.teacher.name)));

    _Sheet sheet() => (
          title: 'دوام الموظفين',
          meta: [label, '${schoolDays.length} يوم دوام'],
          headers: ['#', 'الموظف', 'الوظيفة', 'حاضر', 'غائب', 'متأخر', 'إجازة', 'بلا رصد'],
          rows: [
            for (var i = 0; i < rows.length; i++)
              [i + 1, rows[i].teacher.name, rows[i].teacher.jobTitle.isEmpty ? 'معلم' : rows[i].teacher.jobTitle, rows[i].present, rows[i].absent, rows[i].late, rows[i].leave, rows[i].unmarked],
          ],
          landscape: false,
        );

    return _body([
      _Bar(sheet: sheet, children: [
        _MonthNav(
          label: label,
          onPrev: () => setState(() => monthOffset--),
          onNext: monthOffset >= 0 ? null : () => setState(() => monthOffset++),
        ),
        _Search(onChanged: (v) => setState(() => q = v)),
      ]),
      if (failed)
        const NoonEmpty('يحتاج اتصالاً بالإنترنت')
      else if (d == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (rows.isEmpty)
        const NoonEmpty('لا موظفين')
      else
        _list([
          for (final r in rows)
            _row(r.teacher.name, [if (r.teacher.jobTitle.isNotEmpty) r.teacher.jobTitle, if (r.leave > 0) 'إجازة ${r.leave}', if (r.unmarked > 0) 'بلا رصد ${r.unmarked}'].join(' · '), [
              _val('${r.present}', hint: 'حاضر'),
              _val('${r.absent}', color: r.absent > 0 ? _red : AdminNoon.muted, hint: 'غائب'),
              _val('${r.late}', color: r.late > 0 ? _amber : AdminNoon.muted, hint: 'متأخر'),
            ], onTap: () => _openTeacher(context, r.teacher.id)),
        ]),
    ], onRefresh: () => _load(force: true));
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
