/// حضور الطالب يوماً بيوم — المقابل لـ `dailyAttendance` في الويب.
///
/// للطالب رصدان: كشف الشعبة من الإدارة، ورصد كل مادة من معلمها. عدّ السجلات
/// كما هي كان يجعل غياب يوم بست مواد ستة أيام غياب. كشف الشعبة مرجع اليوم إن
/// وُجد، وإلا أقوى حالة من حصص المواد (غياب ثم عذر ثم حضور).
library;

import '../models/models.dart';

const _dayStatusRank = {'present': 1, 'excused': 2, 'absent': 3};

/// حضور مجمّع يوماً بيوم.
List<({String date, String status})> dailyAttendance(
  Iterable<AttendanceMark> records,
  Iterable<ClassSession> sessions,
) {
  final sessionById = {for (final s in sessions) s.id: s};
  final byDay = <String, ({String? room, String? subject})>{};

  for (final r in records) {
    final session = sessionById[r.sessionId];
    final date = session != null && session.sessionDate.isNotEmpty
        ? session.sessionDate
        : (r.date.isNotEmpty ? r.date : (r.createdAt ?? '').split('T').first);
    if (date.isEmpty) continue;

    final prev = byDay[date] ?? (room: null, subject: null);
    final isRoom = session != null && session.groupId.isEmpty;
    final current = isRoom ? prev.room : prev.subject;
    final rank = _dayStatusRank[r.status] ?? 0;
    final prevRank = current == null ? -1 : (_dayStatusRank[current] ?? 0);
    if (current == null || rank > prevRank) {
      byDay[date] = isRoom
          ? (room: r.status, subject: prev.subject)
          : (room: prev.room, subject: r.status);
    } else {
      byDay.putIfAbsent(date, () => prev);
    }
  }

  final out = <({String date, String status})>[];
  for (final e in byDay.entries) {
    final status = e.value.room ?? e.value.subject;
    if (status == null) continue;
    out.add((date: e.key, status: status));
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
