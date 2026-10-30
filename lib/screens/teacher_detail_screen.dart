import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/academic_matching.dart';
import '../data/followup.dart';
import '../data/grading.dart';
import '../data/phone.dart';
import '../data/portal_usage.dart';
import '../data/report_cards.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../data/supabase.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/table_gate.dart';
import '../widgets/widgets.dart';
import 'settings_forms.dart';

String _dm(String d) => d.length < 10 ? d : '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}';
String _dmy(String d) => d.length < 10 ? '—' : d.substring(0, 10).split('-').reversed.join('/');
String _roomLabel(Classroom r) => [r.gradeLevel, r.name].where((s) => s.trim().isNotEmpty).join(' - ');

const _green = Color(0xFF16A34A);
const _amber = Color(0xFF92400E);
const _red = Color(0xFFBA1A1A);

Color _rateColor(int? n) => n == null
    ? AdminNoon.muted
    : n >= 85
        ? _green
        : n >= 70
            ? _amber
            : _red;

/// سطر لكل مادة وشعبة يدرّسها: طلابها وحضورهم في حصصه ومعدلهم في مادته ورصده — `ClassLine`.
class _ClassLine {
  const _ClassLine({required this.groupId, required this.subject, required this.room, required this.students, this.attendance, this.average, this.completion});

  final String groupId;
  final String subject;
  final Classroom room;
  final int students;
  final int? attendance;
  final double? average;
  final CompletionRow? completion;
}

class _PageData {
  const _PageData({required this.lines, required this.sessions, required this.graded});

  final List<_ClassLine> lines;
  final int sessions;
  final int graded;
}

/// صفحة المعلم للإدارة كملف الطالب — مطابق لـ `TeacherDetail.tsx`: رأس بالاسم والوظيفة،
/// شريط عمله، مواده وشعبه بأدائها، ثم التواصل والدوام والمالية والإجازات والبيانات والتحضير.
///
/// الحسابات الثقيلة (شهادات كل شعبة وحضورها) تُحسب عند الفتح، ثم عند تغيّر المخزن بتجميع
/// ثانيتين (dc075f6)، لا مع كل إعادة رسم. والسحابي (الدوام والإجازات وآخر دخول) يُجلب مرة.
class TeacherDetailScreen extends StatelessWidget {
  const TeacherDetailScreen({super.key, required this.teacherId});

  final String teacherId;

  @override
  Widget build(BuildContext context) {
    return TableGate(
      tables: const ['sessions', 'attendance', 'student_evaluations', 'teacher_payouts'],
      message: 'جارٍ تحميل صفحة المعلم...',
      child: _TeacherPage(teacherId: teacherId),
    );
  }
}

class _TeacherPage extends StatefulWidget {
  const _TeacherPage({required this.teacherId});

  final String teacherId;

  @override
  State<_TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<_TeacherPage> {
  AppStore? _store;
  _PageData? data;
  Timer? _debounce;
  List<StaffDay> monthDays = const [];
  List<LeaveRequest> leaves = const [];
  String? lastSeen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (_store == store) return;
    _store?.removeListener(_onStore);
    _store = store..addListener(_onStore);
    data = _compute(store);
    unawaited(_loadCloud());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _store?.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => data = _compute(_store!));
    });
  }

  Future<void> _loadCloud() async {
    final id = widget.teacherId;
    final month = isoDate(DateTime.now()).substring(0, 7);
    final r = await Future.wait([
      StaffService.days('$month-01', '$month-31'),
      StaffService.leaves(),
      accountUsage(),
    ]);
    if (!mounted) return;
    setState(() {
      monthDays = [for (final d in (r[0] as List<StaffDay>?) ?? const <StaffDay>[]) if (d.teacherId == id) d]..sort((a, b) => b.date.compareTo(a.date));
      leaves = [for (final l in (r[1] as List<LeaveRequest>?) ?? const <LeaveRequest>[]) if (l.teacherId == id) l]..sort((a, b) => b.fromDate.compareTo(a.fromDate));
      final usage = r[2] as Map<String, AccountUsage>?;
      lastSeen = usage == null ? null : lastSeenLabel(usage['teacher:$id']);
    });
  }

  _PageData _compute(AppStore store) {
    final now = DateTime.now();
    final since = isoDate(now.subtract(const Duration(days: 30)));
    final term = termForDate(isoDate(now), term2Start: store.viewedAcademicYear?.term2Start);
    final completion = loadCompletion(store).rows;
    final groups = store.groupsInViewedYear.where((g) => g.teacherId == widget.teacherId && g.status != 'archived').toList();
    final groupIds = {for (final g in groups) g.id};
    // حضور حصصه في آخر 30 يوماً: سجلات جلسات مجموعاته
    final mine = store.sessions.where((s) => groupIds.contains(s.groupId) && s.sessionDate.compareTo(since) >= 0).toList();
    final mineIds = {for (final s in mine) s.id};
    final records = mineIds.isEmpty ? const <AttendanceMark>[] : store.attendance.where((a) => mineIds.contains(a.sessionId)).toList();
    final evalsByStudent = <String, List<Evaluation>>{};
    for (final e in store.evaluations) {
      evalsByStudent.putIfAbsent(e.studentId, () => []).add(e);
    }
    final grading = store.gradingForViewedYear;

    final lines = <_ClassLine>[];
    for (final g in groups) {
      for (final roomId in g.allRoomIds) {
        final room = store.roomById(roomId);
        if (room == null) continue;
        final members = store.studentsOf(room).where((s) => s.status == 'active').toList();
        final ids = {for (final s in members) s.id};
        final recs = records.where((r) => ids.contains(r.studentId)).toList();
        final present = recs.where((r) => r.status == 'present').length;
        // معدل طلابه في مادته: علامة الفصل الحالي الجارية من الشهادة
        final avgs = <double>[];
        for (final s in members) {
          final rows = buildReportCardRows(
            evalsByStudent[s.id] ?? const [],
            grading,
            s.gradeLevel,
            (id) => store.subjectById(id)?.name ?? '',
            year: store.viewedAcademicYear,
          );
          final row = rows.where((r) => r.subjectId == g.subjectId).firstOrNull;
          final v = row == null ? null : (term == 'term_2' ? row.term2 : row.term1).currentAverage;
          if (v != null) avgs.add(v);
        }
        lines.add(_ClassLine(
          groupId: g.id,
          subject: store.subjectById(g.subjectId)?.name ?? '—',
          room: room,
          students: members.length,
          attendance: recs.isEmpty ? null : (present / recs.length * 100).round(),
          average: avgs.isEmpty ? null : (avgs.reduce((a, b) => a + b) / avgs.length * 10).round() / 10,
          completion: completion.where((c) => c.groupId == g.id && c.room.id == roomId).firstOrNull,
        ));
      }
    }
    final order = store.gradeOptions;
    int rank(String grade) {
      final i = order.indexWhere((x) => isSameGrade(x, grade));
      return i < 0 ? order.length : i;
    }

    lines.sort((a, b) {
      final byGrade = rank(a.room.gradeLevel).compareTo(rank(b.room.gradeLevel));
      if (byGrade != 0) return byGrade;
      final byRoom = a.room.name.compareTo(b.room.name);
      return byRoom != 0 ? byRoom : a.subject.compareTo(b.subject);
    });
    return _PageData(
      lines: lines,
      sessions: mine.length,
      graded: store.evaluations.where((e) => e.teacherId == widget.teacherId).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = store.teacherById(widget.teacherId);
    if (t == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('المعلمون')),
        body: const NoonEmpty('المعلم غير موجود'),
      );
    }
    final d = data!;
    final lines = d.lines;
    final month = isoDate(DateTime.now()).substring(0, 7);

    int? meanOf(Iterable<num?> vals) {
      final v = vals.whereType<num>().toList();
      return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
    }

    final done = lines.fold<int>(0, (n, l) => n + (l.completion?.done ?? 0));
    final total = lines.fold<int>(0, (n, l) => n + (l.completion?.total ?? 0));
    final late = lines.fold<int>(0, (n, l) => n + (l.completion?.late ?? 0));
    final completionPct = total == 0 ? null : (done / total * 100).round();
    final average = meanOf(lines.map((l) => l.average));
    // الطالب في أكثر من مادة للمعلم يُعدّ مرة لكل شعبة، لا لكل مادة
    final studentsCount = {for (final l in lines) l.room.id: l.students}.values.fold<int>(0, (a, b) => a + b);
    final roomsCount = {for (final l in lines) l.room.id}.length;
    final subjectsCount = {for (final l in lines) l.subject}.length;
    final hasAttendance = lines.any((l) => l.attendance != null);

    final canSeePay = store.can('finance.expenses');
    // المالية في العام المعروض: من بدايته إلى نهايته
    final year = store.viewedAcademicYear;
    final payouts = store.teacherPayouts
        .where((p) => p.teacherId == t.id)
        .where((p) => year == null || year.startsOn.isEmpty || (p.paymentDate.compareTo(year.startsOn) >= 0 && p.paymentDate.compareTo(year.endsOn) <= 0))
        .toList();
    bool isAdvance(TeacherPayout p) => p.payoutType == 'advance';
    double sum(Iterable<TeacherPayout> list) => list.fold<double>(0, (n, p) => n + p.amount);
    final paidMonth = sum(payouts.where((p) => p.paymentDate.startsWith(month) && !isAdvance(p)));
    final advancesMonth = sum(payouts.where((p) => p.paymentDate.startsWith(month) && isAdvance(p)));
    final advancesYear = sum(payouts.where(isAdvance));
    final rateLabel = t.contractType == 'sessions' ? 'أجر الحصة' : 'الراتب';
    final phone = t.phone.trim();
    final contract = teacherContractLabels[t.contractType];

    int count(String s) => monthDays.where((x) => x.status == s).length;
    final absentDays = count('absent');
    final lateDays = count('late');
    final offDays = monthDays.where((x) => x.status != 'present').toList();
    final dutyLabel = absentDays > 0
        ? '$absentDays غياب'
        : lateDays > 0
            ? '$lateDays تأخر'
            : count('present') > 0
                ? 'منتظم'
                : '';
    final dutyColor = absentDays > 0 ? _red : (lateDays > 0 ? _amber : _green);

    Widget sec(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 10), child: child);
    Widget value(String? v, {bool ltr = false}) => (v == null || v.trim().isEmpty)
        ? Text('—', style: NoonText.style(12, color: AdminNoon.faint))
        : Text(v, textDirection: ltr ? TextDirection.ltr : null, style: NoonText.style(12, weight: FontWeight.w700));
    Widget sep() => Container(width: 1, height: 14, color: const Color(0xFFCBD5E1), margin: const EdgeInsets.symmetric(horizontal: 8));
    Widget stat(String label, String v, {Color? color}) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$label ', style: NoonText.style(12, color: AdminNoon.muted)),
            TextSpan(text: v, style: NoonText.style(12, weight: FontWeight.w700, color: color)),
          ]),
        );

    return Scaffold(
      backgroundColor: AdminNoon.paper,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('المعلمون'),
        actions: [
          if (store.canOpenSection('settings'))
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherFormScreen(teacher: t))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          // الرأس كصفحة الطالب: الاسم وشاراته
          sec(Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(t.name, style: NoonText.style(16, weight: FontWeight.w700, height: 1.2)),
              if (t.jobTitle.trim().isNotEmpty) NoonBadge(t.jobTitle.trim(), tone: NoonBadgeTone.mist),
              if (contract != null) NoonBadge(contract),
            ],
          )),

          // شريط عمله
          sec(Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AdminNoon.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 6,
                  children: [
                    stat('يدرّس', '$subjectsCount مادة · $roomsCount شعب · $studentsCount طالب'),
                    if (completionPct != null) ...[
                      sep(),
                      Tooltip(
                        message: '$done من $total مكوّن',
                        child: stat(
                          'الرصد',
                          '$completionPct%${late > 0 ? ' · $late متأخر' : ''}',
                          color: late > 0 ? _red : (completionPct >= 90 ? _green : _amber),
                        ),
                      ),
                    ],
                    if (average != null) ...[sep(), stat('معدل طلابه', '$average%')],
                  ],
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message: 'آخر 30 يوماً، وعلامات هذا العام',
                  child: Text('سجّل حضور ${d.sessions} حصة · رصد ${d.graded} علامة', style: NoonText.style(11, color: AdminNoon.muted)),
                ),
              ],
            ),
          )),

          // مواده وشعبه
          sec(lines.isEmpty
              ? const NoonEmpty('لا مواد مسندة')
              : Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AdminNoon.line)),
                  child: Column(
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: AdminNoon.line))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(lines[i].subject, style: NoonText.style(13, weight: FontWeight.w700)),
                                        Text('${_roomLabel(lines[i].room)} · ${lines[i].students} طالب', style: NoonText.style(11, color: AdminNoon.muted)),
                                      ],
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'المعدل',
                                    child: Text(
                                      lines[i].average == null ? '—' : '${lines[i].average}%',
                                      style: NoonText.style(12, weight: FontWeight.w700),
                                    ),
                                  ),
                                  if (hasAttendance) ...[
                                    const SizedBox(width: 12),
                                    Tooltip(
                                      message: 'الحضور',
                                      child: SizedBox(
                                        width: 40,
                                        child: Text(
                                          lines[i].attendance == null ? '—' : '${lines[i].attendance}%',
                                          textAlign: TextAlign.end,
                                          style: NoonText.style(12, weight: FontWeight.w700, color: _rateColor(lines[i].attendance)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (lines[i].completion != null) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    for (final c in lines[i].completion!.components)
                                      Tooltip(
                                        message: c.done ? 'رُصد' : (c.late ? 'متأخر عن موعده' : 'لم يُرصد'),
                                        child: Container(
                                          height: 22,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: c.done ? const Color(0xFFDCFCE7) : (c.late ? const Color(0xFFFEE2E2) : Colors.white),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: c.done ? const Color(0xFF86EFAC) : (c.late ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0))),
                                          ),
                                          child: Text(
                                            c.name,
                                            style: NoonText.style(
                                              10.5,
                                              weight: FontWeight.w700,
                                              color: c.done ? const Color(0xFF166534) : (c.late ? const Color(0xFF991B1B) : const Color(0xFF64748B)),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                )),

          sec(NoonFoldCard(
            title: 'بيانات التواصل',
            initiallyOpen: true,
            children: [
              _rows([
                ('الجوال', value(phone.isEmpty ? null : formatPhoneDisplay(phone), ltr: true)),
                ('التخصص', value(t.specialization)),
                ('آخر دخول للنظام', value(lastSeen)),
              ]),
              if (phone.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(onPressed: () => launchTel(phone), icon: const Icon(Icons.phone_outlined, size: 16), label: const Text('اتصال')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                        onPressed: () => launchWa(phone),
                        icon: const MessageCircleIcon(color: Colors.white, size: 16),
                        label: const Text('واتساب'),
                      ),
                    ),
                  ],
                ),
            ],
          )),

          sec(NoonFoldCard(
            title: 'الدوام هذا الشهر',
            headerExtra: dutyLabel.isEmpty ? null : Text(dutyLabel, style: NoonText.style(11, weight: FontWeight.w700, color: dutyColor)),
            children: [
              if (offDays.isEmpty)
                Text(count('present') > 0 ? 'حاضر ${count('present')} يوماً بلا غياب' : 'لم يُرصد بعد', style: NoonText.style(12, color: AdminNoon.muted))
              else
                for (final x in offDays)
                  Row(children: [
                    Text(_dm(x.date), style: NoonText.style(12)),
                    const Spacer(),
                    Text(
                      x.status == 'absent' ? 'غائب' : 'متأخر',
                      style: NoonText.style(12, weight: FontWeight.w700, color: x.status == 'absent' ? _red : _amber),
                    ),
                  ]),
            ],
          )),

          if (canSeePay)
            sec(NoonFoldCard(
              title: 'المالية',
              headerExtra: Text(
                paidMonth > 0 ? money(paidMonth) : 'لم يُصرف',
                style: NoonText.style(11, weight: FontWeight.w700, color: paidMonth > 0 ? _green : AdminNoon.muted),
              ),
              children: [
                _rows([
                  (rateLabel, value(money(t.rate))),
                  ('صُرف له هذا الشهر', value(money(paidMonth))),
                  ('سلف هذا الشهر', value(advancesMonth > 0 ? money(advancesMonth) : null)),
                  ('سلف هذا العام', value(advancesYear > 0 ? money(advancesYear) : null)),
                ]),
                if (payouts.isNotEmpty) ...[
                  Text('سجل الصرف هذا العام', style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.muted)),
                  for (final p in payouts)
                    Row(
                      children: [
                        SizedBox(width: 48, child: Text(_dm(p.paymentDate), style: NoonText.style(12))),
                        Text(
                          payoutTypeNames[p.payoutType] ?? p.payoutType,
                          style: NoonText.style(12, weight: FontWeight.w700, color: isAdvance(p) ? _amber : AdminNoon.muted),
                        ),
                        const Spacer(),
                        Text(money(p.amount), style: NoonText.style(12, weight: FontWeight.w700)),
                      ],
                    ),
                ],
              ],
            )),

          sec(NoonFoldCard(
            title: 'الإجازات',
            headerExtra: leaves.isEmpty ? null : Text('${leaves.length}', style: NoonText.style(11, color: AdminNoon.muted)),
            children: [
              if (leaves.isEmpty)
                Text('لا إجازات', style: NoonText.style(12, color: AdminNoon.muted))
              else
                for (final l in leaves)
                  Row(children: [
                    Text(l.fromDate == l.toDate ? _dm(l.fromDate) : '${_dm(l.fromDate)} - ${_dm(l.toDate)}', style: NoonText.style(12)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12, color: AdminNoon.muted))),
                    Text(l.statusLabel, style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
                  ]),
            ],
          )),

          sec(NoonFoldCard(
            title: 'البيانات الوظيفية',
            children: [
              _rows([
                ('رقم الهوية', value(t.nationalId, ltr: true)),
                ('نوع العقد', value(contract)),
                ('بداية العقد', value(t.contractStart.isEmpty ? null : _dmy(t.contractStart))),
              ]),
            ],
          )),

          sec(NoonFoldCard(title: 'التحضير', children: [_LessonPlans(teacherId: t.id)])),
        ],
      ),
    );
  }

  Widget _rows(List<(String, Widget)> rows) => Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(children: [
              Padding(
                padding: EdgeInsetsDirectional.only(end: 12, top: i == 0 ? 0 : 8),
                child: Text(rows[i].$1, style: NoonText.style(12, weight: FontWeight.w500, color: AppColors.muted)),
              ),
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: Align(alignment: AlignmentDirectional.centerStart, child: rows[i].$2),
              ),
            ]),
        ],
      );
}

/// ملفات تحضير المعلم من السحابة، تُجلب عند فتح البطاقة وحده — `LessonPlansList`.
class _LessonPlans extends StatefulWidget {
  const _LessonPlans({required this.teacherId});

  final String teacherId;

  @override
  State<_LessonPlans> createState() => _LessonPlansState();
}

class _LessonPlansState extends State<_LessonPlans> {
  late final Future<List<Map<String, dynamic>>?> _plans = supabaseSelect(
    'lesson_plans',
    filters: {'teacher_id': 'eq.${widget.teacherId}'},
    order: 'created_at.desc',
  );

  Future<void> _open(Map<String, dynamic> p) async {
    final url = await storageSignedUrl('lesson-plans', '${p['storage_path']}');
    if (url == null) {
      if (mounted) showAppSnack(context, 'تعذّر فتح الملف', error: true);
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return FutureBuilder<List<Map<String, dynamic>>?>(
      future: _plans,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator(minHeight: 2);
        final plans = snap.data;
        if (plans == null) return Text('تعذّر جلب ملفات التحضير', style: NoonText.style(12, color: AdminNoon.muted));
        if (plans.isEmpty) return Text('لا ملفات تحضير', style: NoonText.style(12, color: AdminNoon.muted));
        String scope(Map<String, dynamic> p) {
          final subject = '${p['subject_id'] ?? ''}';
          if (subject.isEmpty) return 'عام';
          final rooms = [
            for (final id in (p['room_ids'] is List ? p['room_ids'] as List : const []))
              if (store.roomById('$id') case final r?) r.name,
          ];
          return [store.subjectById(subject)?.name ?? 'مادة', rooms.join('، ')].where((s) => s.isNotEmpty).join(' · ');
        }

        return Column(
          children: [
            for (final p in plans)
              InkWell(
                onTap: () => _open(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.description_outlined, size: 18, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12.5, weight: FontWeight.w700)),
                          Text('${scope(p)} · ${_dm('${p['created_at'] ?? ''}')}', style: NoonText.style(11, color: AdminNoon.muted)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}
