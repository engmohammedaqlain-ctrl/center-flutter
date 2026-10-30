import 'package:flutter/material.dart';

import '../data/phone.dart';
import '../data/store.dart';
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

Color _rateColor(int? n) => n == null
    ? AdminNoon.muted
    : n >= 85
        ? const Color(0xFF16A34A)
        : n >= 70
            ? const Color(0xFF92400E)
            : const Color(0xFFBA1A1A);

/// سطر لكل مادة وشعبة يدرّسها: طلابها وحضورهم في حصصه — `ClassLine` في TeacherDetail.tsx.
class _ClassLine {
  const _ClassLine({required this.subject, required this.room, required this.students, required this.attendance});

  final String subject;
  final Classroom room;
  final int students;
  final int? attendance;
}

/// صفحة المعلم للإدارة كملف الطالب — مطابق لـ `TeacherDetail.tsx`: رأس بالاسم والوظيفة،
/// شريط عمله، مواده وشعبه، ثم بطاقات التواصل والمالية والبيانات الوظيفية.
///
/// الحسابات تُعاد مع كل تغيّر في المخزن لكنها خفيفة (شعب المعلم وحصصه في 30 يوماً)،
/// بلا أي طلب سحابي. الدوام والإجازات والرصد والتحضير ومعدل طلابه لا مقابل لها في
/// الجوال بعد، فلا تظهر.
class TeacherDetailScreen extends StatelessWidget {
  const TeacherDetailScreen({super.key, required this.teacherId});

  final String teacherId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return TableGate(
      tables: const ['sessions', 'attendance', 'student_evaluations', 'teacher_payouts'],
      message: 'جارٍ تحميل صفحة المعلم...',
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final t = store.teacherById(teacherId);
          if (t == null) {
            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(title: const Text('المعلمون')),
              body: const NoonEmpty('المعلم غير موجود'),
            );
          }
          return _TeacherPage(store: store, t: t);
        },
      ),
    );
  }
}

class _TeacherPage extends StatelessWidget {
  const _TeacherPage({required this.store, required this.t});

  final AppStore store;
  final Teacher t;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = isoDate(now);
    final month = today.substring(0, 7);
    final since = isoDate(now.subtract(const Duration(days: 30)));

    final groups = store.groupsInViewedYear.where((g) => g.teacherId == t.id && g.status != 'archived').toList();
    final groupIds = {for (final g in groups) g.id};
    // حضور حصصه في آخر 30 يوماً: سجلات جلسات مجموعاته
    final mine = store.sessions.where((s) => groupIds.contains(s.groupId) && s.sessionDate.compareTo(since) >= 0).toList();
    final mineIds = {for (final s in mine) s.id};
    final records = mineIds.isEmpty ? const <AttendanceMark>[] : store.attendance.where((a) => mineIds.contains(a.sessionId)).toList();

    final lines = <_ClassLine>[];
    for (final g in groups) {
      for (final roomId in g.allRoomIds) {
        final room = store.roomById(roomId);
        if (room == null) continue;
        final members = store.studentsOf(room).where((s) => s.status == 'active').toList();
        final ids = {for (final s in members) s.id};
        final recs = records.where((r) => ids.contains(r.studentId)).toList();
        final present = recs.where((r) => r.status == 'present').length;
        lines.add(_ClassLine(
          subject: store.subjectById(g.subjectId)?.name ?? '—',
          room: room,
          students: members.length,
          attendance: recs.isEmpty ? null : (present / recs.length * 100).round(),
        ));
      }
    }
    lines.sort((a, b) {
      final byRoom = _roomLabel(a.room).compareTo(_roomLabel(b.room));
      return byRoom != 0 ? byRoom : a.subject.compareTo(b.subject);
    });

    // الطالب في أكثر من مادة للمعلم يُعدّ مرة لكل شعبة، لا لكل مادة
    final studentsCount = {for (final l in lines) l.room.id: l.students}.values.fold<int>(0, (a, b) => a + b);
    final roomsCount = {for (final l in lines) l.room.id}.length;
    final subjectsCount = {for (final l in lines) l.subject}.length;
    final graded = store.evaluations.where((e) => e.teacherId == t.id).length;
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

    Widget sec(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 10), child: child);
    Widget value(String? v, {bool ltr = false}) => (v == null || v.trim().isEmpty)
        ? Text('—', style: NoonText.style(12, color: AdminNoon.faint))
        : Text(v, textDirection: ltr ? TextDirection.ltr : null, style: NoonText.style(12, weight: FontWeight.w700));

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
          // الرأس: الاسم وشاراته
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
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminNoon.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'يدرّس  ', style: NoonText.style(12, color: AdminNoon.muted)),
                    TextSpan(text: '$subjectsCount مادة · $roomsCount شعب · $studentsCount طالب'),
                  ]),
                  style: NoonText.style(12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Tooltip(
                  message: 'آخر 30 يوماً، وعلامات هذا العام',
                  child: Text(
                    'سجّل حضور ${mine.length} حصة · رصد $graded علامة',
                    style: NoonText.style(11, color: AdminNoon.muted),
                  ),
                ),
              ],
            ),
          )),

          // مواده وشعبه
          sec(lines.isEmpty
              ? const NoonEmpty('لا مواد مسندة')
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AdminNoon.line),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: i == 0 ? null : Border(top: BorderSide(color: AdminNoon.line)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(lines[i].subject, style: NoonText.style(13, weight: FontWeight.w700)),
                                    Text(_roomLabel(lines[i].room), style: NoonText.style(11, color: AdminNoon.muted)),
                                  ],
                                ),
                              ),
                              Text('${lines[i].students} طالب', style: NoonText.style(11, color: AdminNoon.muted)),
                              if (hasAttendance) ...[
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    lines[i].attendance == null ? '—' : '${lines[i].attendance}%',
                                    textAlign: TextAlign.end,
                                    style: NoonText.style(12, weight: FontWeight.w700, color: _rateColor(lines[i].attendance)),
                                  ),
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
              ]),
              if (phone.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => launchTel(phone),
                        icon: const Icon(Icons.phone_outlined, size: 16),
                        label: const Text('اتصال'),
                      ),
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

          if (canSeePay)
            sec(NoonFoldCard(
              title: 'المالية',
              headerExtra: Text(
                paidMonth > 0 ? money(paidMonth) : 'لم يُصرف',
                style: NoonText.style(11, weight: FontWeight.w700, color: paidMonth > 0 ? const Color(0xFF16A34A) : AdminNoon.muted),
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
                          style: NoonText.style(12, weight: FontWeight.w700, color: isAdvance(p) ? const Color(0xFF92400E) : AdminNoon.muted),
                        ),
                        const Spacer(),
                        Text(money(p.amount), style: NoonText.style(12, weight: FontWeight.w700)),
                      ],
                    ),
                ],
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
