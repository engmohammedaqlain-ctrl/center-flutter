/// مدرسة قياس الأداء: بناء profile فقط (`--dart-define=PERF_SCHOOL=true`).
///
/// على جوال تجربة بلا حساب مدرسة كبيرة: أول فتح يولّد مدرسة بحجم مدرسة المستر
/// (2000 طالب، 50 ألف رصد حضور، أقساط وسندات وعلامات، وختم سيرفر لكل سجل) في
/// قاعدة منفصلة `perf_local.db` بلا أي اتصال بالسحابة، ويدخل إليها. كل فتح بعده
/// يحمّل ما يحمّله فتح مدرسة حقيقية بهذا الحجم، فيُقاس على الجوال نفسه.
/// النسخ العادية لا تحمل هذا الكود (الثابت `false` يحذفه المترجم).
library;

import '../models/models.dart';
import 'demo_data.dart';
import 'perf_log.dart';
import 'store.dart';

const perfSchool = bool.fromEnvironment('PERF_SCHOOL');
const perfSchoolDb = 'perf_local.db';

Future<void> ensurePerfSchool(AppStore s) async {
  if (s.loggedIn) {
    PerfLog.mark('مدرسة القياس محفوظة — فتح عادي');
    return;
  }
  PerfLog.mark('توليد مدرسة القياس');
  injectDemoData(s);
  final err = await s.login('amal', 'amal2026');
  if (err != null) {
    PerfLog.mark('تعذّر دخول مدرسة القياس: $err');
    return;
  }
  final today = DateTime.now();
  final rooms = s.rooms;
  const nStudents = 2000;
  for (var i = 0; i < nStudents; i++) {
    final room = rooms[i % rooms.length];
    s.students.add(Student(
      id: 'm-$i',
      fullName: 'طالب رقم $i محمد',
      gradeLevel: room.gradeLevel,
      section: room.name,
      phone: '05991${i.toString().padLeft(5, '0')}',
      parentName: 'ولي $i',
      parentPhone: '05981${i.toString().padLeft(5, '0')}',
      nationalId: '${800000000 + i}',
      balance: 0,
    ));
    for (var k = 0; k < 6; k++) {
      s.installments.add(Installment(
        id: 'm-inst-$i-$k',
        studentId: 'm-$i',
        title: 'قسط ${k + 1}',
        amount: 250,
        dueDate: today.subtract(Duration(days: (k * 30) - 60)),
        paidAmount: k.isEven ? 250 : 0,
      ));
    }
    for (var k = 0; k < 5; k++) {
      s.payments.add(Payment(
        id: 'm-pay-$i-$k',
        receiptNumber: '2026/${100000 + i * 5 + k}',
        studentId: 'm-$i',
        amount: 250,
        method: 'cash',
        date: today.subtract(Duration(days: k * 30)),
        installmentId: 'm-inst-$i-$k',
      ));
    }
  }
  // جلسات 120 يوماً لكل شعبة، و25 يوم رصد لكل طالب ≈ 50 ألف رصد
  for (final room in rooms) {
    for (var d = 0; d < 120; d++) {
      final date = isoDate(today.subtract(Duration(days: d)));
      s.sessions.add(ClassSession(id: 'ses_room_${room.id}_$date', groupId: '', roomId: room.id, sessionDate: date));
    }
  }
  for (var i = 0; i < nStudents; i++) {
    final room = rooms[i % rooms.length];
    for (var d = 0; d < 25; d++) {
      final date = isoDate(today.subtract(Duration(days: d)));
      final sid = 'ses_room_${room.id}_$date';
      s.attendance.add(AttendanceMark(
        id: 'att_${sid}_m-$i',
        studentId: 'm-$i',
        date: date,
        status: i % 9 == 0 ? 'absent' : 'present',
        sessionId: sid,
        updatedAt: '${date}T07:30:00.000Z',
      ));
    }
  }
  final evals = s.extraCloud.putIfAbsent('student_evaluations', () => []);
  for (var i = 0; i < nStudents; i++) {
    for (var k = 0; k < 6; k++) {
      evals.add(Evaluation(
        id: 'm-ev-$i-$k',
        studentId: 'm-$i',
        title: 'اختبار $k',
        score: 70,
        maxScore: 100,
        evaluationDate: isoDate(today.subtract(Duration(days: k * 10))),
        term: 'term_1',
      ).toCloud());
    }
  }
  for (final t in ['students', 'installments', 'payments', 'sessions', 'attendance', 'student_evaluations']) {
    s.markDirty(t);
  }
  void stamp(String table, Iterable<String> ids) =>
      s.rememberServerStamps(table, {for (final id in ids) id: '2026-10-01T00:00:00.000Z'});
  stamp('students', s.students.map((x) => x.id));
  stamp('installments', s.installments.map((x) => x.id));
  stamp('payments', s.payments.map((x) => x.id));
  stamp('sessions', s.sessions.map((x) => x.id));
  stamp('attendance', s.attendance.map((x) => x.id));
  stamp('student_evaluations', evals.map((x) => '${x['id']}'));
  await s.flush();
  s.notifyListeners();
  PerfLog.mark('مدرسة القياس جاهزة — أغلق التطبيق وافتحه للقياس');
}
