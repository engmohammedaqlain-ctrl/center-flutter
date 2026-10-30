import 'package:flutter/material.dart';

import '../data/phone.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'attendance_screen.dart';

String _dm(String d) => '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}';
String _range(LeaveRequest l) => l.fromDate == l.toDate ? _dm(l.fromDate) : '${_dm(l.fromDate)} - ${_dm(l.toDate)}';

const _dayNames = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// عطلة من تقويم المدرسة (`settings.calendar`، يضبطه الويب) — `holidayOn`.
String? holidayOn(AppStore store, String date) {
  final raw = store.settings.extra['calendar'];
  if (raw is! List) return null;
  for (final e in raw) {
    if (e is Map && e['kind'] == 'holiday' && '${e['from']}'.compareTo(date) <= 0 && date.compareTo('${e['to'] ?? e['from']}') <= 0) {
      return '${e['title'] ?? 'عطلة'}';
    }
  }
  return null;
}

/// أيام دوام شهر بإزاحة أشهر: بلا الجمعة — `getSchoolMonthDates`.
List<SchoolDay> _schoolMonth(int offset) {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month + offset, 1);
  final last = DateTime(first.year, first.month + 1, 0);
  final today = isoDate(now);
  return [
    for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1)))
      if (d.weekday != DateTime.friday)
        SchoolDay(date: d, dateStr: isoDate(d), dayName: _dayNames[d.weekday - 1], shortDate: '${d.day}/${d.month}', isToday: isoDate(d) == today),
  ];
}

const _monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// النقر على الخانة يدور بالحالات كما في كشف الطلاب: حاضر ← غائب ← متأخر ← بلا رصد.
const _next = {'none': 'present', 'present': 'absent', 'absent': 'late', 'late': null};

/// دوام الموظفين — `StaffAttendance.tsx`: يوم واحد بأزرار الحالة (عرض الجوال في الويب)،
/// أو كشف أسبوعي أو شهري كالطلاب بخانة لكل يوم تُرصد بالنقر، والإجازة والعطلة في مكانها،
/// ومجموع الغياب والتأخر. طلبات الإجازة المعلّقة فوق الكشف.
class StaffAttendanceView extends StatefulWidget {
  const StaffAttendanceView({super.key});

  @override
  State<StaffAttendanceView> createState() => _StaffAttendanceViewState();
}

class _StaffAttendanceViewState extends State<StaffAttendanceView> {
  String period = 'day';
  int weekOffset = 0;
  int monthOffset = 0;
  String date = isoDate(DateTime.now());

  List<StaffDay>? records;
  List<StaffDay> monthRecords = const [];
  List<LeaveRequest> leaves = const [];
  bool loading = true;
  bool offline = false;

  List<SchoolDay> get days => period == 'month' ? _schoolMonth(monthOffset) : AppStore.schoolWeek(weekOffset);
  String get from => period == 'day' ? date : days.first.dateStr;
  String get to => period == 'day' ? date : days.last.dateStr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => loading = true);
    final month = (period == 'day' ? date : to).substring(0, 7);
    final results = await Future.wait([
      StaffService.days(from, to, force: force),
      StaffService.days('$month-01', '$month-31', force: force),
      StaffService.leaves(force: force),
    ]);
    if (!mounted) return;
    setState(() {
      loading = false;
      offline = results[0] == null;
      records = results[0] as List<StaffDay>?;
      monthRecords = (results[1] as List<StaffDay>?) ?? const [];
      leaves = (results[2] as List<LeaveRequest>?) ?? const [];
    });
  }

  String? statusOf(String id, String day) => records?.where((d) => d.teacherId == id && d.date == day).firstOrNull?.status;

  int countIn(String id, String status, List<StaffDay> list) =>
      list.where((d) => d.teacherId == id && d.status == status && approvedLeaveOn(leaves, id, d.date) == null).length;

  Future<void> _save(AppStore store, String teacherId, String day, String? status) async {
    if (day.compareTo(isoDate(DateTime.now())) > 0) return showAppSnack(context, 'يوم لم يأتِ بعد', error: true);
    try {
      await StaffService.setDay(store.tenantId ?? '', teacherId, day, status);
      await _load();
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر الحفظ', error: true);
    }
  }

  Future<void> _allPresent(AppStore store, List<Teacher> teachers, String day) async {
    try {
      for (final t in teachers) {
        if (statusOf(t.id, day) == null && approvedLeaveOn(leaves, t.id, day) == null) {
          await StaffService.setDay(store.tenantId ?? '', t.id, day, 'present');
        }
      }
      await _load();
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر الحفظ', error: true);
    }
  }

  Future<void> _decide(AppStore store, String id, bool approve, {bool paid = false}) async {
    try {
      await StaffService.decideLeave(id, approve: approve, paid: paid, decidedBy: store.deviceUser?.name ?? 'الإدارة');
      await _load(force: true);
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر الحفظ', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final teachers = [...store.teachersInViewedYear]..sort((a, b) => a.name.compareTo(b.name));
    final pending = leaves.where((l) => l.status == 'pending').toList()..sort((a, b) => a.fromDate.compareTo(b.fromDate));
    String nameOf(String id) => store.teacherById(id)?.name ?? 'موظف';

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (pending.isNotEmpty) ...[
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('طلبات إجازة (${pending.length})', style: NoonText.style(13, weight: FontWeight.w700)),
                  for (final l in pending)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(nameOf(l.teacherId), style: NoonText.style(13, weight: FontWeight.w700)),
                          Text('${_range(l)}${l.reason.isNotEmpty ? ' · ${l.reason}' : ''}', style: NoonText.style(11, color: AdminNoon.muted)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            NoonButton(small: true, tone: NoonTone.ink, label: 'مدفوعة', tooltip: 'موافقة بلا خصم', onPressed: () => _decide(store, l.id, true, paid: true)),
                            NoonButton(small: true, label: 'غير مدفوعة', tooltip: 'موافقة مع خصم أيامها', onPressed: () => _decide(store, l.id, true)),
                            NoonButton(small: true, tone: NoonTone.danger, label: 'رفض', onPressed: () => _decide(store, l.id, false)),
                          ]),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'day', label: Text('يوم')),
              ButtonSegment(value: 'week', label: Text('أسبوعي')),
              ButtonSegment(value: 'month', label: Text('شهري')),
            ],
            selected: {period},
            onSelectionChanged: (v) {
              setState(() => period = v.first);
              _load();
            },
          ),
          const SizedBox(height: 8),
          _navigator(store, teachers),
          const SizedBox(height: 8),
          if (loading && records == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (offline && records == null)
            const NoonEmpty('تعذّر الاتصال، اسحب للتحديث')
          else if (teachers.isEmpty)
            const NoonEmpty('لا موظفين')
          else if (period == 'day')
            _dayList(store, teachers)
          else
            _sheet(store, teachers),
        ],
      ),
    );
  }

  Widget _navigator(AppStore store, List<Teacher> teachers) {
    final today = isoDate(DateTime.now());
    String label;
    VoidCallback prev, next;
    bool atEnd;
    if (period == 'day') {
      final d = DateTime.parse(date);
      label = '${_dayNames[d.weekday - 1]} ${_dm(date)}';
      DateTime shift(int by) {
        var x = d.add(Duration(days: by));
        if (x.weekday == DateTime.friday) x = x.add(Duration(days: by)); // لا دوام الجمعة
        return x;
      }

      prev = () => date = isoDate(shift(-1));
      next = () => date = isoDate(shift(1));
      atEnd = date.compareTo(today) >= 0;
    } else if (period == 'month') {
      final m = DateTime(DateTime.now().year, DateTime.now().month + monthOffset, 1);
      label = '${_monthNames[m.month - 1]} ${m.year}';
      prev = () => monthOffset--;
      next = () => monthOffset++;
      atEnd = monthOffset >= 0;
    } else {
      label = '${days.first.shortDate} — ${days.last.shortDate}';
      prev = () => weekOffset--;
      next = () => weekOffset++;
      atEnd = weekOffset >= 0;
    }
    final workDay = period == 'day' ? (holidayOn(store, date) == null ? date : null) : days.where((d) => d.isToday && holidayOn(store, d.dateStr) == null).firstOrNull?.dateStr;
    return Row(
      children: [
        IconButton(
          tooltip: 'السابق',
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(prev);
            _load();
          },
        ),
        Text(label, style: NoonText.style(13, weight: FontWeight.w700)),
        IconButton(
          tooltip: 'التالي',
          icon: const Icon(Icons.chevron_left),
          onPressed: atEnd
              ? null
              : () {
                  setState(next);
                  _load();
                },
        ),
        const Spacer(),
        if (workDay != null && teachers.isNotEmpty && records != null)
          NoonButton(
            small: true,
            tone: NoonTone.sun,
            icon: Icons.done_all_rounded,
            label: 'الكل حاضر',
            tooltip: 'لمن لم يُرصد',
            onPressed: () => _allPresent(store, teachers, workDay),
          ),
      ],
    );
  }

  /// الجوال في الويب: يوم واحد بأزرار الحالة.
  Widget _dayList(AppStore store, List<Teacher> teachers) {
    final holiday = holidayOn(store, date);
    if (holiday != null) return NoonEmpty('عطلة: $holiday');
    const tone = {'present': Color(0xFF059669), 'absent': Color(0xFFE11D48), 'late': Color(0xFFF59E0B)};
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < teachers.length; i++)
            () {
              final t = teachers[i];
              final leave = approvedLeaveOn(leaves, t.id, date);
              final status = statusOf(t.id, date);
              final absent = countIn(t.id, 'absent', monthRecords);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(13, weight: FontWeight.w700)),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: t.jobTitle.trim().isEmpty ? 'معلم' : t.jobTitle.trim()),
                              if (absent > 0) TextSpan(text: ' · غياب الشهر $absent', style: const TextStyle(color: Color(0xFFBE123C))),
                            ]),
                            style: NoonText.style(11, color: AdminNoon.muted),
                          ),
                        ],
                      ),
                    ),
                    if (leave != null)
                      NoonBadge('إجازة ${leave.paid == true ? 'مدفوعة' : 'غير مدفوعة'}')
                    else
                      for (final s in staffDayLabels.keys)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _save(store, t.id, date, status == s ? null : s),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: status == s ? tone[s] : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: status == s ? tone[s]! : AppColors.lineStrong),
                              ),
                              child: Text(
                                staffDayLabels[s]!,
                                style: NoonText.style(11.5, weight: FontWeight.w700, color: status == s ? Colors.white : AdminNoon.muted),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }

  /// كشف أسبوعي أو شهري كالطلاب: سطر لكل موظف وخانة لكل يوم.
  Widget _sheet(AppStore store, List<Teacher> teachers) {
    final list = days;
    final month = period == 'month';
    final today = isoDate(DateTime.now());
    final cellW = month ? 30.0 : 44.0;
    const line = BorderSide(color: Color(0xFFE2E8F0));
    Widget cell(Widget child, {Color? bg, double? w}) => Container(
          width: w ?? cellW,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, border: const Border(left: line, bottom: line)),
          child: child,
        );
    final head = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AdminNoon.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  cell(Text('الموظف', style: head), w: 120, bg: const Color(0xFFF1F5F9)),
                  for (final d in list)
                    cell(
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(month ? '${d.date.day}' : d.dayName, style: head, maxLines: 1, overflow: TextOverflow.clip),
                        if (!month) Text(d.shortDate, style: head.copyWith(fontSize: 9, fontWeight: FontWeight.w500)),
                      ]),
                      bg: d.isToday ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                    ),
                  cell(Text('الغياب', style: head.copyWith(color: const Color(0xFFDC2626))), w: 48, bg: const Color(0xFFF1F5F9)),
                  cell(Text('التأخر', style: head.copyWith(color: const Color(0xFF92400E))), w: 48, bg: const Color(0xFFF1F5F9)),
                  if (!month) cell(Text('الجوال', style: head), w: 110, bg: const Color(0xFFF1F5F9)),
                ]),
                for (final t in teachers)
                  () {
                    final absent = countIn(t.id, 'absent', records ?? const []);
                    final late = countIn(t.id, 'late', records ?? const []);
                    return Row(children: [
                      cell(
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(11.5, weight: FontWeight.w600)),
                          ),
                        ),
                        w: 120,
                        bg: absent > 0 ? const Color(0x4DFEF2F2) : null,
                      ),
                      for (final d in list)
                        () {
                          final holiday = holidayOn(store, d.dateStr);
                          if (holiday != null) {
                            return Tooltip(message: holiday, child: cell(Text('ع', style: head.copyWith(color: const Color(0xFF94A3B8))), bg: const Color(0xFFF1F5F9)));
                          }
                          final leave = approvedLeaveOn(leaves, t.id, d.dateStr);
                          if (leave != null) {
                            return Tooltip(
                              message: 'إجازة ${leave.paid == true ? 'مدفوعة' : 'غير مدفوعة'}',
                              child: cell(Text('إ', style: head.copyWith(color: const Color(0xFF475569))), bg: const Color(0xFFF1F5F9)),
                            );
                          }
                          final status = statusOf(t.id, d.dateStr);
                          final future = d.dateStr.compareTo(today) > 0;
                          final (Color? bg, Widget mark) = switch (status) {
                            'present' => (const Color(0xFFDCFCE7), const Icon(Icons.check, size: 15, color: Color(0xFF166534))),
                            'absent' => (const Color(0xFFFEE2E2), const Icon(Icons.close, size: 15, color: Color(0xFF991B1B))),
                            'late' => (const Color(0xFFFEF3C7), const Text('ت', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF92400E)))),
                            _ => (null, const Text('—', style: TextStyle(color: Color(0xFFD1D5DB)))),
                          };
                          return InkWell(
                            onTap: future ? null : () => _save(store, t.id, d.dateStr, _next[status ?? 'none']),
                            child: cell(Opacity(opacity: future ? 0.3 : 1, child: mark), bg: bg ?? (d.isToday ? const Color(0xFFF0F9FF) : null)),
                          );
                        }(),
                      cell(Text('$absent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: absent > 0 ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF))), w: 48),
                      cell(Text('$late', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: late > 0 ? const Color(0xFF92400E) : const Color(0xFF9CA3AF))), w: 48),
                      if (!month)
                        cell(
                          t.phone.trim().isEmpty
                              ? const Text('—', style: TextStyle(color: Color(0xFFD1D5DB)))
                              : InkWell(
                                  onTap: () => launchTel(t.phone.trim()),
                                  child: Text(formatPhoneDisplay(t.phone.trim()), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                                ),
                          w: 110,
                        ),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 14, children: [
          for (final (k, v) in const [('✓', 'حاضر'), ('✕', 'غائب'), ('ت', 'متأخر'), ('إ', 'إجازة'), ('ع', 'عطلة')])
            Text('$k $v', style: NoonText.style(11, color: AdminNoon.muted)),
        ]),
      ],
    );
  }
}

/// الحضور: الطلاب للجميع، ودوام الموظفين وإجازاتهم للمدير وحده — `AttendancePage.tsx`.
class AttendanceHub extends StatefulWidget {
  const AttendanceHub({super.key});

  @override
  State<AttendanceHub> createState() => _AttendanceHubState();
}

class _AttendanceHubState extends State<AttendanceHub> {
  String who = 'students';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.isAdminUser) return const AttendanceScreen();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'students', label: Text('الطلاب')),
              ButtonSegment(value: 'staff', label: Text('الموظفون')),
            ],
            selected: {who},
            onSelectionChanged: (v) => setState(() => who = v.first),
          ),
        ),
        Expanded(child: who == 'students' ? const AttendanceScreen() : const StaffAttendanceView()),
      ],
    );
  }
}
