import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/attendance_days.dart';
import '../data/balance.dart';
import '../data/followup.dart';
import '../data/phone.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/table_gate.dart';
import '../widgets/widgets.dart';
import 'student_detail_screen.dart';
import 'teacher_detail_screen.dart';

const _red = Color(0xFFBA1A1A);
const _green = Color(0xFF16A34A);

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

class _HomeData {
  const _HomeData({
    required this.marked,
    required this.present,
    required this.absentToday,
    required this.collectedMonth,
    required this.expectedMonth,
    required this.overdue,
    required this.alerts,
    required this.lateGrading,
    required this.financeRequests,
    required this.chronic,
    required this.birthdays,
  });

  final int marked;
  final int present;
  final int absentToday;
  final double collectedMonth;
  final double expectedMonth;
  final double overdue;
  final int alerts;
  final int lateGrading;
  final int financeRequests;
  final List<({Student student, int days})> chronic;
  final List<_Birthday> birthdays;
}

/// الرئيسية — مطابق لما في `Dashboard.tsx` مما يخص الجوال: حضور اليوم، والتحصيل بنسبة الشهر
/// من المتوقع، والمتأخرات، و«يحتاج تدخلاً»، و«شعب بلا معلم اليوم»، و«أعياد ميلاد اليوم»،
/// و«الأكثر غياباً» بعدد أيامه. الحساب عند الفتح ثم بتجميع ثانيتين، والسحابي يُجلب مرة.
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
  _HomeData? data;
  Timer? _debounce;
  List<_Uncovered> uncovered = const [];
  int leaveRequests = 0;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    widget.active.addListener(_onActive);
  }

  void _onActive() {
    if (!widget.active.value || !mounted) return;
    if (_stale) {
      _stale = false;
      setState(() => data = _compute(_store!));
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
    data = _compute(store);
    unawaited(_loadStaff(store));
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
      if (mounted) setState(() => data = _compute(_store!));
    });
  }

  /// المعلم الغائب أو المُجاز اليوم: شعبه بلا معلم، تحتاج بديلاً.
  Future<void> _loadStaff(AppStore store) async {
    if (!store.isAdminUser) return;
    final today = isoDate(DateTime.now());
    final r = await Future.wait([StaffService.days(today, today), StaffService.leaves()]);
    if (!mounted) return;
    final days = (r[0] as List<StaffDay>?) ?? const <StaffDay>[];
    final leaves = (r[1] as List<LeaveRequest>?) ?? const <LeaveRequest>[];
    final onLeave = [for (final l in leaves) if (l.status == 'approved' && l.fromDate.compareTo(today) <= 0 && l.toDate.compareTo(today) >= 0) l];
    final away = {for (final d in days) if (d.status == 'absent') d.teacherId, for (final l in onLeave) l.teacherId};
    setState(() {
      leaveRequests = leaves.where((l) => l.status == 'pending').length;
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

  _HomeData _compute(AppStore store) {
    final now = DateTime.now();
    final today = isoDate(now);
    final month = today.substring(0, 7);
    final active = store.students.where((s) => s.status == 'active').toList();

    // حضور اليوم ومن غاب في آخر 30 يوماً: يوم واحد لكل طالب
    final since = isoDate(now.subtract(const Duration(days: 30)));
    final sessions = store.sessions.where((s) => s.sessionDate.compareTo(since) >= 0 && s.sessionDate.compareTo(today) <= 0).toList();
    final ids = {for (final s in sessions) s.id};
    final byStudent = <String, List<AttendanceMark>>{};
    for (final a in store.attendance) {
      if (ids.contains(a.sessionId)) byStudent.putIfAbsent(a.studentId, () => []).add(a);
    }
    var marked = 0, present = 0, absentToday = 0;
    final chronicPct = store.settings.followup.chronicPercent;
    final chronic = <({Student student, int days})>[];
    for (final s in active) {
      final days = dailyAttendance(byStudent[s.id] ?? const [], sessions);
      final t = days.where((d) => d.date == today).firstOrNull;
      if (t != null) {
        marked++;
        if (t.status == 'present') present++;
        if (t.status == 'absent') absentToday++;
      }
      final absent = days.where((d) => d.status == 'absent').length;
      // الغياب المزمن: نسبة من الأيام المرصودة في آخر 30 يوماً
      if (days.length >= 5 && absent / days.length * 100 >= chronicPct) chronic.add((student: s, days: absent));
    }
    chronic.sort((a, b) => b.days - a.days);

    final collected = store.payments
        .where((p) => !p.cancelled && isoDate(p.date).startsWith(month))
        .fold<double>(0, (n, p) => n + p.amount);
    final expected = store.installments
        .where((i) => isoDate(i.dueDate).startsWith(month))
        .fold<double>(0, (n, i) => n + i.amount);
    final overdue = store.installments.where((i) => isInstallmentDue(i)).fold<double>(0, (n, i) => n + unpaidOf(i));

    final md = today.substring(5);
    final birthdays = [
      for (final s in active)
        if (s.birthDate.length >= 10 && s.birthDate.substring(5, 10) == md)
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

    final completion = loadCompletion(store).rows;
    return _HomeData(
      marked: marked,
      present: present,
      absentToday: absentToday,
      collectedMonth: collected,
      expectedMonth: expected,
      overdue: overdue,
      alerts: loadAbsenceAlerts(store).length,
      lateGrading: completion.fold<int>(0, (n, r) => n + r.late),
      financeRequests: store.pendingFinanceRequests.length,
      chronic: chronic,
      birthdays: birthdays,
    );
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = data!;
    final showFinance = store.can('finance');
    final rate = d.marked == 0 ? null : (d.present / d.marked * 100).round();
    final needs = <(String, String, VoidCallback)>[
      if (d.alerts > 0) ('إنذارات غياب لم تُرسل', '${d.alerts}', () => widget.onReport('alerts')),
      if (d.lateGrading > 0) ('رصد متأخر عن موعده', '${d.lateGrading}', () => widget.onReport('completion')),
      if (leaveRequests > 0) ('طلبات إجازة', '$leaveRequests', () => widget.onSection('attendance')),
      if (showFinance && d.financeRequests > 0) ('طلبات موافقة', '${d.financeRequests}', () => widget.onSection('finance')),
    ];

    Widget card(String title, List<Widget> children, {int? count, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Tooltip(
                      message: hint ?? '',
                      child: Text(title, style: NoonText.style(13, weight: FontWeight.w700)),
                    ),
                  ),
                  if (count != null) Text('$count', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
                ]),
                const SizedBox(height: 4),
                ...children,
              ],
            ),
          ),
        );
    Widget row(String label, String sub, String value, {Color? color, VoidCallback? onTap, Widget? trailing}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
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
    Widget tile(String label, String value, String sub, {Color? color, VoidCallback? onTap, String? hint}) => Expanded(
          child: Tooltip(
            message: hint ?? '',
            child: AppCard(
              onTap: onTap,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: NoonText.style(11.5, color: AdminNoon.muted)),
                  const SizedBox(height: 4),
                  FittedBox(child: Text(value, style: NoonText.style(17, weight: FontWeight.w700, color: color))),
                  if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(10.5, color: AdminNoon.muted)),
                ],
              ),
            ),
          ),
        );

    final institution = store.institutionName.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(children: [
          tile(
            'حضور اليوم',
            rate == null ? '—' : '$rate%',
            d.marked == 0 ? 'لم يُرصد بعد' : '${d.absentToday} غائب',
            color: rate == null ? null : (rate >= 90 ? _green : _red),
            onTap: () => widget.onSection('attendance'),
          ),
          if (showFinance) ...[
            const SizedBox(width: 8),
            tile(
              'التحصيل',
              money(d.collectedMonth),
              // نسبة ما حُصّل هذا الشهر من أقساطه المستحقة فيه
              d.expectedMonth > 0 ? 'الشهر ${(d.collectedMonth / d.expectedMonth * 100).round()}% من المتوقع' : 'هذا الشهر',
              color: _green,
              hint: d.expectedMonth > 0 ? 'حُصّل هذا الشهر ${money(d.collectedMonth)} من ${money(d.expectedMonth)} مستحقة فيه' : null,
              onTap: () => widget.onSection('finance'),
            ),
          ],
        ]),
        if (showFinance) ...[
          const SizedBox(height: 8),
          Row(children: [
            tile('المتأخرات', money(d.overdue), 'أقساط حلّ موعدها', color: d.overdue > 0 ? _red : null, onTap: () => widget.onReport('arrears')),
          ]),
        ],
        const SizedBox(height: 10),
        if (needs.isNotEmpty)
          card('يحتاج تدخلاً', [for (final n in needs) row(n.$1, '', n.$2, color: _red, onTap: n.$3)]),
        if (store.isAdminUser && uncovered.isNotEmpty)
          card(
            'شعب بلا معلم اليوم',
            [
              for (final u in uncovered)
                row(u.teacher.name, u.classes.join('، '), u.away, color: _red, onTap: () => _push(TeacherDetailScreen(teacherId: u.teacher.id))),
            ],
            count: uncovered.fold<int>(0, (n, u) => n + u.classes.length),
            hint: 'معلمها غائب أو في إجازة: تحتاج بديلاً',
          ),
        if (d.birthdays.isNotEmpty)
          card(
            'أعياد ميلاد اليوم',
            [
              for (final b in d.birthdays)
                row(
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
            count: d.birthdays.length,
          ),
        if (d.chronic.isNotEmpty)
          card(
            'الأكثر غياباً',
            [
              for (final c in d.chronic.take(5))
                row(
                  c.student.fullName,
                  [c.student.gradeLevel, c.student.section].where((x) => x.trim().isNotEmpty).join(' · '),
                  '${c.days} أيام',
                  color: _red,
                  onTap: () => _push(StudentDetailScreen(studentId: c.student.id)),
                ),
            ],
            count: d.chronic.length,
            hint: 'غاب ${store.settings.followup.chronicPercent.round()}% فأكثر من أيام آخر 30 يوماً',
          ),
        if (needs.isEmpty && uncovered.isEmpty && d.birthdays.isEmpty && d.chronic.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text('لا شيء يحتاج تدخلاً اليوم', textAlign: TextAlign.center, style: NoonText.style(12.5, color: AppColors.muted)),
          ),
      ],
    );
  }
}
