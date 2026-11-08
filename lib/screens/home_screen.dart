import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dashboard_stats.dart';
import '../data/followup.dart';
import '../data/phone.dart';
import '../data/portal_usage.dart';
import '../data/school_backups.dart';
import '../data/school_calendar.dart';
import '../data/school_options.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/table_gate.dart';
import '../widgets/widgets.dart';
import 'announcement_sheet.dart';
import 'finance_screen.dart' show financeAgingRequest;
import 'student_detail_screen.dart';
import 'teacher_detail_screen.dart';

/// ألوان الحالات نفسها في البطاقات والرسوم: حاضر أخضر، مأذون عنبري، غائب أحمر — `C`.
const _present = Color(0xFF16A34A);
const _excused = Color(0xFF475569);
const _absent = Color(0xFFBA1A1A);
const _empty = Color(0xFFE2E8F0);
const _spent = Color(0xFF475569);
const _tealC = Color(0xFF0F766E);
const _parent = Color(0xFF0F766E);
const _studentC = Color(0xFF7DD3C0);

const _periods = [('1', 'اليوم'), ('7', 'الأسبوع'), ('30', 'الشهر')];
const _vs = {'1': 'عن آخر يوم', '7': 'عن الأسبوع السابق', '30': 'عن الشهر السابق'};
const _chartLabels = {
  'attendance': 'الحضور',
  'absent': 'الغياب',
  'collected': 'التحصيل',
  'expenses': 'المصروفات',
  'enrolled': 'التسجيل',
  'usage': 'الدخول',
};
const _chartColors = {
  'attendance': _present,
  'absent': _absent,
  'collected': _present,
  'expenses': _spent,
  'enrolled': _tealC,
  'usage': _parent,
};
const _weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

String _dayTitle(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String _dm(String date) => '${int.parse(date.substring(8))}/${int.parse(date.substring(5, 7))}';

/// فرق بإشارة: «▲ 3%»، أو «بلا تغيير» — `delta`.
String? _delta(num? now, num? before, String unit) {
  if (now == null || before == null) return null;
  final d = (now - before).round();
  return d == 0 ? 'بلا تغيير' : '${d > 0 ? '▲' : '▼'} ${d.abs()}$unit';
}

class _Birthday {
  const _Birthday({required this.id, required this.student, required this.name, required this.sub, required this.age, required this.phone});

  final String id;
  final bool student;
  final String name;
  final String sub;
  final int age;
  final String phone;
}

class _Uncovered {
  const _Uncovered({required this.teacher, required this.away, required this.classes});

  final Teacher teacher;
  final String away;
  final List<String> classes;
}

/// سطر «يحتاج تدخلاً»: بتفاصيل ينفتح في مكانه، وبلا تفاصيل ينقل مباشرة — `PendingItem`.
class _Pending {
  const _Pending({required this.label, required this.value, this.onTap, this.details, this.open});

  final String label;
  final String value;
  final VoidCallback? onTap;
  final List<({String label, String sub, String value, VoidCallback onTap})>? details;
  final ({String label, VoidCallback onTap})? open;
}

/// الرئيسية — `Dashboard.tsx` بتصميم الجوال: بطاقة اليوم، والفترة والمرحلة، وبطاقات الأرقام،
/// و«يحتاج تدخلاً»، والرسم لآخر 30 يوماً وحلقة الحضور، ثم التفاصيل. الحساب عند الفتح ثم بتجميع ثانيتين.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onSection, required this.onReport, required this.active});

  /// الرئيسية ظاهرة الآن: وهي مخفية خلف قسم آخر لا تعيد حسابها مع كل مزامنة.
  final ValueListenable<bool> active;

  /// فتح قسم من الشريط السفلي (`finance`، `attendance`...).
  final ValueChanged<String> onSection;

  /// فتح تقرير بعينه (`alerts`، `completion`...).
  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context) => TableGate(
        tables: const ['sessions', 'attendance', 'payments', 'installments', 'student_evaluations', 'audit_log', 'finance_requests'],
        message: 'جارٍ تحميل الرئيسية...',
        child: _Home(onSection: onSection, onReport: onReport, active: active),
      );
}

class _Home extends StatefulWidget {
  const _Home({required this.onSection, required this.onReport, required this.active});

  final ValueListenable<bool> active;
  final ValueChanged<String> onSection;
  final ValueChanged<String> onReport;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  AppStore? _store;
  DashboardStats? stats;
  Timer? _debounce;
  bool _stale = false;

  // كل فتح يبدأ باليوم وبالمدرسة كلها: اللوحة للمتابعة اليومية
  String period = '1';
  String grade = '';
  String chart = 'attendance';
  bool allAbsent = false;
  bool allChronic = false;
  final _openPending = <String>{};

  List<_Uncovered> uncovered = const [];
  int leaveRequests = 0;
  ({int absent, int late, int onLeave}) staff = (absent: 0, late: 0, onLeave: 0);
  String? backupIssue;
  List<({String day, String role, int users})>? usage;

  @override
  void initState() {
    super.initState();
    widget.active.addListener(_onActive);
  }

  void _onActive() {
    if (!widget.active.value || !mounted) return;
    if (_stale) {
      _stale = false;
      setState(_recompute);
    }
    unawaited(_loadStaff(_store!));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (_store == store) return;
    _store?.removeListener(_onStore);
    _store = store..addListener(_onStore);
    _recompute();
    unawaited(_loadStaff(store));
    if (store.isAdminUser) {
      usageDaily(30).then((v) {
        if (mounted) setState(() => usage = v);
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _store?.removeListener(_onStore);
    widget.active.removeListener(_onActive);
    super.dispose();
  }

  void _onStore() {
    if (!widget.active.value) {
      _stale = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(_recompute);
    });
  }

  void _recompute() {
    final store = _store!;
    stats = buildDashboard(
      today: isoDate(DateTime.now()),
      students: store.students,
      rooms: store.roomsInViewedYear,
      sessions: store.sessions,
      attendance: store.attendance,
      installments: store.installments,
      payments: store.payments,
      expenses: store.can('finance.expenses') ? store.expenses : const [],
      calendar: store.settings.calendar,
      days: int.parse(period),
      grade: grade,
      chronicPercent: store.settings.followup.chronicPercent,
    );
  }

  void _update({String? period, String? grade}) {
    setState(() {
      if (period != null) this.period = period;
      if (grade != null) this.grade = grade;
      _recompute();
    });
  }

  /// المعلم الغائب أو المُجاز اليوم: شعبه بلا معلم، وأعداد الموظفين اليوم.
  Future<void> _loadStaff(AppStore store) async {
    if (!store.isAdminUser) return;
    final tenant = store.tenantId;
    if (tenant != null && !store.isStaffSession) {
      dailyBackupProblem(tenant).then((issue) {
        if (mounted) setState(() => backupIssue = issue);
      }).catchError((Object _) {});
    }
    final today = isoDate(DateTime.now());
    final r = await Future.wait([StaffService.days(today, today), StaffService.leaves()]);
    if (!mounted) return;
    final days = (r[0] as List<StaffDay>?) ?? const <StaffDay>[];
    final leaves = (r[1] as List<LeaveRequest>?) ?? const <LeaveRequest>[];
    final onLeave = [for (final l in leaves) if (l.status == 'approved' && l.fromDate.compareTo(today) <= 0 && l.toDate.compareTo(today) >= 0) l];
    final away = {for (final d in days) if (d.status == 'absent') d.teacherId, for (final l in onLeave) l.teacherId};
    setState(() {
      leaveRequests = leaves.where((l) => l.status == 'pending').length;
      staff = (
        absent: days.where((d) => d.status == 'absent').length,
        late: days.where((d) => d.status == 'late').length,
        onLeave: onLeave.length,
      );
      uncovered = [
        for (final t in store.teachersInViewedYear)
          if (away.contains(t.id))
            _Uncovered(
              teacher: t,
              away: onLeave.any((l) => l.teacherId == t.id) ? 'إجازة' : 'غائب',
              classes: [
                for (final g in store.groupsInViewedYear)
                  if (g.teacherId == t.id && g.status != 'archived')
                    for (final rid in g.allRoomIds)
                      if (store.roomById(rid) case final room?)
                        '${store.subjectById(g.subjectId)?.name ?? ''} ${[room.gradeLevel, room.name].where((s) => s.isNotEmpty).join(' ')}'.trim(),
              ],
            ),
      ].where((u) => u.classes.isNotEmpty).toList();
    });
  }

  List<_Birthday> _birthdays(AppStore store, DateTime now) {
    final md = isoDate(now).substring(5);
    return [
      for (final s in store.students)
        if (s.status == 'active' && s.birthDate.length >= 10 && s.birthDate.substring(5, 10) == md)
          _Birthday(
            id: s.id,
            student: true,
            name: s.fullName,
            sub: [s.gradeLevel, s.section].where((x) => x.trim().isNotEmpty).join(' · '),
            age: now.year - (int.tryParse(s.birthDate.substring(0, 4)) ?? now.year),
            phone: s.parentPhone,
          ),
      for (final t in store.teachersInViewedYear)
        if (t.birthDate.length >= 10 && t.birthDate.substring(5, 10) == md)
          _Birthday(id: t.id, student: false, name: t.name, sub: t.jobTitle.trim().isEmpty ? 'معلم' : t.jobTitle.trim(), age: 0, phone: t.phone),
    ];
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  // ── لبنات العرض ──

  Widget _card(String title, List<Widget> children, {int? count, String? hint, Widget? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: noonPanel(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Tooltip(
                  message: hint ?? '',
                  child: Text(title, style: NoonText.style(13.5, weight: FontWeight.w700)),
                ),
              ),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AdminNoon.band, borderRadius: BorderRadius.circular(20)),
                  child: Text('$count', style: NoonText.style(11.5, weight: FontWeight.w700, color: AdminNoon.muted)),
                ),
              ?trailing,
            ]),
            if (hint != null) Text(hint, style: NoonText.style(10.5, color: AdminNoon.muted)),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      );

  Widget _row(String label, String sub, String value, {Color? color, VoidCallback? onTap, Widget? leading, Widget? trailing}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12.5, weight: FontWeight.w700)),
                  if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: NoonText.style(11, color: AdminNoon.muted)),
                ],
              ),
            ),
            if (value.isNotEmpty) Text(value, style: NoonText.style(12, weight: FontWeight.w700, color: color)),
            ?trailing,
          ]),
        ),
      );

  Widget _more(bool open, int count, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        child: Text(open ? 'أقل' : '+$count', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.tealD)),
      );

  /// بطاقة رقم: عنوان صغير، ورقم كبير بلونه، وسطر تحته — `NKpiCards`.
  Widget _kpi(String label, String value, String sub, {Color? color, VoidCallback? onTap, String? hint}) => Tooltip(
        message: hint ?? '',
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: noonPanel(),
            child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AdminNoon.rPanel),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (color != null) ...[
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(11.5, color: AdminNoon.muted))),
                  ]),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value, style: NoonText.style(19, weight: FontWeight.w800, color: color ?? AdminNoon.text)),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(10.5, color: AdminNoon.muted)),
                ],
              ),
            ),
          ),
          ),
        ),
      );

  IconData _pendingIcon(String key) => switch (key) {
        'att' => Icons.event_busy_outlined,
        'alerts' => Icons.warning_amber_rounded,
        'grades' => Icons.pending_actions_outlined,
        'approvals' => Icons.fact_check_outlined,
        'requests' => Icons.request_quote_outlined,
        _ => Icons.error_outline_rounded,
      };

  /// بطاقة «يحتاج تدخلاً»: ما يطلب قراراً من المدير، فإطار وترويسة بلون التنبيه وأيقونة لكل بند وعدّاد بارز.
  Widget _attentionCard(Map<String, _Pending> pending) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AdminNoon.rPanel),
          border: Border.all(color: AdminNoon.ink.withValues(alpha: 0.22)),
          boxShadow: [BoxShadow(color: AdminNoon.ink.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              color: AdminNoon.ink,
              child: Row(children: [
                Icon(Icons.notifications_active_outlined, size: 20, color: AdminNoon.onInk),
                const SizedBox(width: 8),
                Expanded(child: Text('يحتاج تدخلاً', style: NoonText.style(14, weight: FontWeight.w700, color: AdminNoon.onInk))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AdminNoon.onInk, borderRadius: BorderRadius.circular(20)),
                  child: Text('${pending.length}', style: NoonText.style(12.5, weight: FontWeight.w700, color: AdminNoon.ink)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: Column(children: [for (final e in pending.entries) _pendingRow(e.key, e.value)]),
            ),
          ],
        ),
      );

  Widget _pendingRow(String key, _Pending p) {
    final open = _openPending.contains(key);
    final urgent = key == 'alerts';
    final tone = urgent ? AdminNoon.red600 : AdminNoon.ink;
    final badge = Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(20)),
      child: Text(p.value, textAlign: TextAlign.center, style: NoonText.style(12.5, weight: FontWeight.w700, color: Colors.white)),
    );
    final leading = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(_pendingIcon(key), size: 18, color: tone),
    );
    if (p.details == null) {
      return _row(
        p.label,
        '',
        '',
        onTap: p.onTap,
        leading: leading,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          badge,
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 20, color: AdminNoon.faint),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          p.label,
          '',
          '',
          onTap: () => setState(() => open ? _openPending.remove(key) : _openPending.add(key)),
          leading: leading,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            badge,
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AdminNoon.muted),
            ),
          ]),
        ),
        if (open)
          Container(
            margin: const EdgeInsetsDirectional.only(start: 6, bottom: 6),
            padding: const EdgeInsetsDirectional.only(start: 10),
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: AdminNoon.line, width: 2))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in p.details!) _row(d.label, d.sub, d.value, onTap: d.onTap, color: AdminNoon.muted),
                if (p.open != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: p.open!.onTap,
                      child: Text(p.open!.label, style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.tealD)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = stats!;
    final now = DateTime.now();
    final features = store.featureState;
    final showAttendance = store.isFeatureOn('attendance') && store.can('attendance');
    final showFinance = store.can('finance');
    final hidden = store.settings.dashboardHidden;
    bool shown(String id) => !hidden.contains(id);
    final canAnnounce = features['portal.notes'] == true && store.can('students') && store.settings.toolOn('announcements');
    final today1 = period == '1';
    final counts = today1 ? s.today : s.range;
    final rate = rateOf(counts);
    final prevRate = rateOf(s.previous);
    final month = isoDate(now).substring(0, 7);
    final expectedMonth = store.installments.where((i) => isoDate(i.dueDate).startsWith(month)).fold<double>(0, (n, i) => n + i.amount);
    final collectedDelta = s.collectedPrevious > 0 ? ((s.collectedRange - s.collectedPrevious) / s.collectedPrevious * 100).round() : null;

    final attendanceSub = rate == null
        ? (s.holiday != null ? 'عطلة' : 'لم يُرصد بعد')
        : today1
            ? (s.roomsMarked < s.roomsTotal
                ? 'رُصد ${s.roomsMarked} من ${s.roomsTotal} شعبة'
                : (prevRate == null ? '${counts.present} حاضر' : 'آخر يوم $prevRate%'))
            : (_delta(rate, prevRate, '%') == null ? '${counts.present} حاضر' : '${_delta(rate, prevRate, '%')} ${_vs[period]}');
    final collectedSub = today1
        ? 'أمس ${money(s.collectedPrevious)}'
        : (collectedDelta == null ? 'هذا الشهر ${money(s.collectedMonth)}' : '${_delta(collectedDelta, 0, '%')} ${_vs[period]}');
    final streaks = s.absentToday.where((a) => a.streak > 1).length;
    final periodLabel = switch (period) { '1' => 'اليوم', '7' => 'آخر 7 أيام', _ => 'آخر 30 يوماً' };

    // ما ينتظر قراراً اليوم: سطر لكل نوع بعدده، ومن له تفاصيل ينفتح في مكانه
    final alerts = showAttendance ? loadAbsenceAlerts(store) : const <AbsenceAlert>[];
    final completion = store.isFeatureOn('evaluations') && store.isAdminUser ? loadCompletion(store).rows : const <CompletionRow>[];
    final lateByTeacher = <String, List<CompletionRow>>{};
    for (final r in completion) {
      if (r.late > 0) (lateByTeacher[r.teacherId] ??= []).add(r);
    }
    String roomLabel(Classroom r) => [r.gradeLevel, r.name].where((x) => x.trim().isNotEmpty).join(' · ');
    final approvals = store.can('evaluations') ? store.pendingApprovals.length : 0;
    final requests = (showFinance ? store.pendingPaymentRequests.length : 0) + (store.can('finance.discount') ? store.pendingFinanceRequests.length : 0);
    final unmarked = showAttendance && s.holiday == null ? s.unmarkedRooms : const <({Classroom room, int students})>[];
    final pending = <String, _Pending>{
      if (unmarked.isNotEmpty)
        'att': _Pending(
          label: 'شعب لم تُرصد',
          value: '${unmarked.length}',
          details: [
            for (final u in unmarked) (label: roomLabel(u.room), sub: '', value: '${u.students} طالب', onTap: () => widget.onSection('attendance')),
          ],
          open: (label: 'رصد الحضور', onTap: () => widget.onSection('attendance')),
        ),
      if (alerts.isNotEmpty)
        'alerts': _Pending(
          label: 'إنذارات غياب',
          value: '${alerts.length}',
          details: [
            for (final a in alerts)
              (
                label: a.student.fullName,
                sub: '${[a.student.gradeLevel, a.student.section].where((x) => x.trim().isNotEmpty).join(' · ')} · ${a.days} يوم',
                value: a.levelName,
                onTap: () => _push(StudentDetailScreen(studentId: a.student.id)),
              ),
          ],
          open: (label: 'الإرسال للأهل', onTap: () => widget.onReport('alerts')),
        ),
      // سطر لكل معلم متأخر لا لكل مادة وشعبة: المدير يتابع أشخاصاً
      if (lateByTeacher.isNotEmpty)
        'grades': _Pending(
          label: 'رصد متأخر',
          value: '${lateByTeacher.length}',
          details: [
            for (final e in lateByTeacher.entries)
              (
                label: e.value.first.teacherName,
                sub: e.value.map((r) => '${r.subjectName} ${roomLabel(r.room)}').join('، '),
                value: '${e.value.length}',
                onTap: () => _push(TeacherDetailScreen(teacherId: e.key)),
              ),
          ],
          open: (label: 'تقرير الرصد', onTap: () => widget.onReport('completion')),
        ),
      if (showFinance && s.longOverdue > 0)
        'late': _Pending(
          label: 'متأخرون +60 يوم',
          value: '${s.longOverdue}',
          onTap: () {
            financeAgingRequest.value = '60';
            widget.onSection('finance');
          },
        ),
      if (approvals > 0) 'approve': _Pending(label: 'علامات بانتظار الاعتماد', value: '$approvals', onTap: () => widget.onSection('evaluations')),
      if (requests > 0) 'fin': _Pending(label: 'طلبات مالية', value: '$requests', onTap: () => widget.onSection('finance')),
      if (store.isAdminUser && leaveRequests > 0) 'leave': _Pending(label: 'طلبات إجازة', value: '$leaveRequests', onTap: () => widget.onSection('attendance')),
      if (backupIssue != null) 'backup': _Pending(label: 'النسخة اليومية', value: backupIssue!, onTap: () => widget.onSection('settings')),
      if (store.isAdminUser && staff.absent > 0) 'staff': _Pending(label: 'موظفون غائبون', value: '${staff.absent}', onTap: () => widget.onSection('attendance')),
    };

    // الرسم: الحضور خطاً، والبقية أعمدة يومية لآخر 30 يوماً
    final usageDays = [
      for (var i = 0; i < 30; i++)
        () {
          final d = isoDate(DateTime(now.year, now.month, now.day + i - 29));
          int of(String role) => usage?.where((r) => r.day == d && r.role == role).firstOrNull?.users ?? 0;
          return (date: d, parent: of('parent'), student: of('student'));
        }(),
    ];
    final chartKinds = [
      for (final k in _chartLabels.keys)
        if (k == 'usage'
            ? usage != null && usage!.isNotEmpty
            : (k == 'attendance' || k == 'absent')
                ? showAttendance
                : k == 'expenses'
                    ? store.can('finance.expenses')
                    : k == 'collected'
                        ? showFinance
                        : store.can('students'))
          k,
    ];
    final chartKind = chartKinds.contains(chart) ? chart : chartKinds.firstOrNull;
    final List<({String label, double value})> series = switch (chartKind) {
      'attendance' => [for (final t in s.trend) (label: _dm(t.date), value: t.rate.toDouble())],
      'absent' => [for (final t in s.trend) (label: _dm(t.date), value: t.absent.toDouble())],
      'collected' => [for (final t in s.collectedTrend) (label: _dm(t.date), value: t.amount)],
      'expenses' => [for (final t in s.expenseTrend) (label: _dm(t.date), value: t.amount)],
      'enrolled' => [for (final t in s.enrollTrend) (label: _dm(t.date), value: t.amount)],
      'usage' => [for (final d in usageDays) (label: _dm(d.date), value: (d.parent + d.student).toDouble())],
      _ => const [],
    };
    final seriesTotal = series.fold<double>(0, (n, p) => n + p.value);
    final isMoney = chartKind == 'collected' || chartKind == 'expenses';

    final birthdays = _birthdays(store, now);
    final institution = store.institutionName.trim();
    final absentList = allAbsent ? s.absentToday : s.absentToday.take(6).toList();
    final chronicList = allChronic ? s.chronic : s.chronic.take(6).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        AdminHero(
          icon: Icons.space_dashboard_outlined,
          label: s.holiday == null ? _dayTitle(now) : '${_dayTitle(now)} · عطلة: ${s.holiday!.title}',
          value: '${s.activeStudents}',
          unit: 'طالب نشط',
          chips: [
            '${s.roomsTotal} شعبة',
            if (s.newThisMonth > 0) '+${s.newThisMonth} هذا الشهر',
            if (grade.isNotEmpty) grade,
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: NoonSegment<String>(
              value: period,
              options: _periods,
              onChanged: (v) => _update(period: v),
            ),
          ),
          if (grade.isNotEmpty) ...[
            const SizedBox(width: 6),
            InputChip(
              label: Text(grade, style: NoonText.style(11.5, weight: FontWeight.w700)),
              onDeleted: () => _update(grade: ''),
              tooltip: 'كل المدرسة',
            ),
          ],
          if (canAnnounce) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => showAnnouncementSheet(context, grade: grade),
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: Text(grade.isEmpty ? 'إعلان' : 'إعلان لـ$grade'),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        // بطاقات الأرقام: عمودان
        LayoutBuilder(builder: (context, c) {
          final tiles = <Widget>[
            if (showAttendance) ...[
              _kpi(
                'الحضور · $periodLabel',
                rate == null ? '—' : '$rate%',
                attendanceSub,
                color: rate == null ? null : (rate < 85 ? _absent : _present),
                onTap: () => widget.onSection('attendance'),
              ),
              _kpi(
                'الغياب · $periodLabel',
                rate == null ? '—' : '${counts.absent}',
                '${counts.excused} مأذون${today1 && streaks > 0 ? ' · $streaks متتالٍ' : ''}',
                color: counts.absent > 0 ? _absent : null,
                onTap: () => widget.onReport('alerts'),
              ),
            ],
            if (showFinance) ...[
              _kpi(
                'التحصيل · $periodLabel',
                money(s.collectedRange),
                expectedMonth > 0 ? 'هذا الشهر ${(s.collectedMonth / expectedMonth * 100).round()}% من المتوقع' : collectedSub,
                color: _present,
                hint: expectedMonth > 0 ? 'حُصّل هذا الشهر ${money(s.collectedMonth)} من ${money(expectedMonth)} مستحقة فيه · $collectedSub' : null,
                onTap: () => widget.onSection('finance'),
              ),
              _kpi(
                'المتأخرات حتى اليوم',
                money(s.overdueTotal),
                '${s.debtors} طالب${s.dueSoonAmount > 0 ? ' · قريباً ${money(s.dueSoonAmount)}' : ''}',
                color: s.overdueTotal > 0 ? _absent : null,
                onTap: () => widget.onSection('finance'),
              ),
            ],
          ];
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
        const SizedBox(height: 12),
        if (pending.isEmpty)
          _card('يحتاج تدخلاً', [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('لا شيء معلّق', textAlign: TextAlign.center, style: NoonText.style(12, color: AdminNoon.muted)),
            ),
          ])
        else
          _attentionCard(pending),
        if (shown('uncovered') && store.isAdminUser && uncovered.isNotEmpty)
          _card(
            'شعب بلا معلم اليوم',
            [
              for (final u in uncovered)
                _row(u.teacher.name, u.classes.join('، '), u.away, color: _absent, onTap: () => _push(TeacherDetailScreen(teacherId: u.teacher.id))),
            ],
            count: uncovered.fold<int>(0, (n, u) => n + u.classes.length),
            hint: 'معلمها غائب أو في إجازة: تحتاج بديلاً',
          ),
        if (shown('chart') && chartKind != null)
          _card(
            _chartLabels[chartKind]!,
            [
              if (chartKinds.length > 1)
                NoonSegment<String>(
                  value: chartKind,
                  options: [for (final k in chartKinds) (k, _chartLabels[k]!)],
                  onChanged: (k) => setState(() => chart = k),
                ),
              const SizedBox(height: 10),
              if ((chartKind == 'attendance' || chartKind == 'absent') && s.trend.length < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('لا رصد بعد', textAlign: TextAlign.center, style: NoonText.style(12, color: AdminNoon.muted)),
                )
              else
                SizedBox(
                  height: 140,
                  child: _TrendChart(
                    points: series,
                    line: chartKind == 'attendance',
                    max: chartKind == 'attendance' ? 100 : null,
                    color: _chartColors[chartKind]!,
                    stacks: chartKind == 'usage' ? [for (final d in usageDays) [d.parent.toDouble(), d.student.toDouble()]] : null,
                  ),
                ),
              if (chartKind == 'usage')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    _legend('أهالي', _parent),
                    const SizedBox(width: 12),
                    _legend('طلاب', _studentC),
                  ]),
                ),
            ],
            hint: '30 يوماً',
            trailing: chartKind == 'attendance'
                ? null
                : Text(
                    isMoney ? money(seriesTotal) : trimNum(seriesTotal),
                    style: NoonText.style(12, weight: FontWeight.w700, color: _chartColors[chartKind]),
                  ),
          ),
        if (showAttendance)
          _card(
            today1 ? 'حضور اليوم' : 'توزيع الحضور',
            [
              _Donut(
                parts: [
                  ('حاضر', counts.present, _present),
                  ('مأذون', counts.excused, _excused),
                  ('غائب', counts.absent, _absent),
                  if (today1 && s.unmarkedToday > 0) ('لم يُرصد', s.unmarkedToday, _empty),
                ],
                center: rate == null ? '—' : '$rate%',
              ),
            ],
          ),
        if (shown('grades') && showAttendance && s.byGrade.isNotEmpty)
          _card('حسب المرحلة', [
            for (final g in s.byGrade)
              InkWell(
                onTap: () => _update(grade: grade == g.grade ? '' : g.grade),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: grade == g.grade ? AdminNoon.band : null,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Row(children: [
                    SizedBox(width: 74, child: Text(g.grade, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12.5, weight: FontWeight.w700))),
                    // شريط واحد بنسبة الحضور، والغائبون عدداً بجانبه
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: g.rate / 100,
                          minHeight: 8,
                          backgroundColor: AdminNoon.line,
                          valueColor: AlwaysStoppedAnimation(g.rate < 85 ? _absent : _present),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text('${g.rate}%', textAlign: TextAlign.end, style: NoonText.style(12, weight: FontWeight.w700, color: g.rate < 85 ? _absent : null)),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(g.absent > 0 ? '${g.absent} غائب' : '', textAlign: TextAlign.end, style: NoonText.style(10.5, color: AdminNoon.muted)),
                    ),
                  ]),
                ),
              ),
          ]),
        if (shown('absent') && showAttendance && s.absentToday.isNotEmpty)
          _card(
            'غائبون اليوم',
            [
              for (final a in absentList)
                _row(
                  a.student.fullName,
                  [a.student.gradeLevel, a.student.section].where((x) => x.trim().isNotEmpty).join(' · '),
                  a.streak > 1 ? '${a.streak} أيام' : '',
                  color: _absent,
                  onTap: () => _push(StudentDetailScreen(studentId: a.student.id)),
                ),
              if (s.absentToday.length > 6) _more(allAbsent, s.absentToday.length - 6, () => setState(() => allAbsent = !allAbsent)),
            ],
            count: s.absentToday.length,
          ),
        if (shown('chronic') && showAttendance && s.chronic.isNotEmpty)
          _card(
            'الأكثر غياباً',
            [
              for (final c in chronicList)
                _row(
                  c.student.fullName,
                  '${[c.student.gradeLevel, c.student.section].where((x) => x.trim().isNotEmpty).join(' · ')} · من ${c.marked} يوماً مرصوداً',
                  '${c.absent} ${c.absent > 10 ? 'يوماً' : 'أيام'}',
                  color: _absent,
                  leading: Tooltip(
                    message: 'آخر أسبوعين ${c.recent} · قبلهما ${c.before}',
                    child: c.trend == 'up'
                        ? const Icon(Icons.trending_up_rounded, size: 18, color: _absent)
                        : c.trend == 'down'
                            ? const Icon(Icons.trending_down_rounded, size: 18, color: _present)
                            : const SizedBox(width: 18),
                  ),
                  onTap: () => _push(StudentDetailScreen(studentId: c.student.id)),
                ),
              if (s.chronic.length > 6) _more(allChronic, s.chronic.length - 6, () => setState(() => allChronic = !allChronic)),
            ],
            count: s.chronic.length,
            hint: 'غاب ${store.settings.followup.chronicPercent.round()}% من الأيام فأكثر · آخر 30 يوماً',
          ),
        if (shown('staff') && store.isAdminUser && staff.late + staff.onLeave > 0)
          _card('الموظفون اليوم', [
            if (staff.late > 0) _row('متأخر', '', '${staff.late}', color: _excused, onTap: () => widget.onSection('attendance')),
            if (staff.onLeave > 0) _row('في إجازة', '', '${staff.onLeave}', onTap: () => widget.onSection('attendance')),
          ]),
        if (shown('birthdays') && birthdays.isNotEmpty)
          _card(
            'أعياد ميلاد اليوم',
            [
              for (final b in birthdays)
                _row(
                  b.name,
                  '${b.sub}${b.age > 0 ? ' · ${b.age} سنة' : ''}',
                  '',
                  onTap: () => _push(b.student ? StudentDetailScreen(studentId: b.id) : TeacherDetailScreen(teacherId: b.id)),
                  trailing: b.phone.trim().isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://wa.me/${getWhatsAppPhone(b.phone)}?text=${Uri.encodeComponent(b.student ? 'كل عام و${b.name} بخير، عيد ميلاد سعيد من أسرة $institution' : 'كل عام وأنت بخير أستاذ/ة ${b.name}، عيد ميلاد سعيد من أسرة $institution')}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text('تهنئة'),
                        ),
                ),
            ],
            count: birthdays.length,
          ),
        if (shown('upcoming') && s.upcoming.isNotEmpty)
          _card('قادم', [
            for (final e in s.upcoming)
              _row(
                e.title,
                calendarKindLabels[e.kind] ?? '',
                eventRange(e),
                leading: Icon(Icons.event_outlined, size: 18, color: e.kind == 'exam' ? _excused : AdminNoon.muted),
              ),
          ]),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: NoonText.style(11, color: AdminNoon.muted)),
      ]);
}

/// حلقة بنسب الحالات، والنسبة في وسطها، ومفتاح الألوان بأعدادها — `Donut`.
class _Donut extends StatelessWidget {
  const _Donut({required this.parts, required this.center});

  final List<(String, int, Color)> parts;
  final String center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 110,
          height: 110,
          child: CustomPaint(
            painter: _DonutPainter(parts),
            child: Center(child: Text(center, style: NoonText.style(18, weight: FontWeight.w800))),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [
            for (final (label, value, color) in parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: NoonText.style(12.5, color: AdminNoon.muted))),
                  Text('$value', style: NoonText.style(13, weight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts);

  final List<(String, int, Color)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = _empty;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final total = parts.fold<int>(0, (n, p) => n + p.$2);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (final (_, value, color) in parts) {
      final sweep = value / total * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, base..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.parts != parts;
}

/// رسم آخر 30 يوماً: النسبة خطاً، والبقية أعمدة يومية (والدخول عمودان متراكبان) — `TrendChart`.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points, required this.color, this.line = false, this.max, this.stacks});

  final List<({String label, double value})> points;
  final Color color;
  final bool line;
  final double? max;
  final List<List<double>>? stacks;

  @override
  Widget build(BuildContext context) {
    final top = max ?? points.fold<double>(0, (m, p) => math.max(m, p.value));
    return Column(children: [
      Expanded(
        child: Directionality(
          // الزمن من اليسار لليمين: الأقدم أولاً والأحدث آخراً كما في الويب
          textDirection: TextDirection.ltr,
          child: CustomPaint(
            size: Size.infinite,
            painter: _TrendPainter(points: points, color: color, line: line, top: top <= 0 ? 1 : top, stacks: stacks),
          ),
        ),
      ),
      if (points.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(points.first.label, style: NoonText.style(10, color: AdminNoon.muted)),
                Text(points.last.label, style: NoonText.style(10, color: AdminNoon.muted)),
              ],
            ),
          ),
        ),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.color, required this.line, required this.top, this.stacks});

  final List<({String label, double value})> points;
  final Color color;
  final bool line;
  final double top;
  final List<List<double>>? stacks;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = _empty
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.isEmpty) return;
    final n = points.length;
    if (line) {
      final path = Path();
      final fill = Path();
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
        final y = size.height - points[i].value / top * size.height;
        if (i == 0) {
          path.moveTo(x, y);
          fill.moveTo(x, size.height);
          fill.lineTo(x, y);
        } else {
          path.lineTo(x, y);
          fill.lineTo(x, y);
        }
        if (i == n - 1) fill.lineTo(x, size.height);
      }
      canvas.drawPath(fill..close(), Paint()..color = color.withValues(alpha: 0.10));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round,
      );
      final last = Offset(n == 1 ? size.width / 2 : size.width, size.height - points.last.value / top * size.height);
      canvas.drawCircle(last, 3.5, Paint()..color = color);
      return;
    }
    final slot = size.width / n;
    final w = math.max(2.0, slot * 0.62);
    for (var i = 0; i < n; i++) {
      final x = slot * i + (slot - w) / 2;
      final parts = stacks != null && i < stacks!.length ? stacks![i] : [points[i].value];
      var bottom = size.height;
      for (var p = 0; p < parts.length; p++) {
        final h = parts[p] / top * size.height;
        if (h <= 0) continue;
        final c = stacks == null ? color : (p == 0 ? _parent : _studentC);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, bottom - h, w, h),
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2),
          ),
          Paint()..color = c,
        );
        bottom -= h;
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => true;
}
