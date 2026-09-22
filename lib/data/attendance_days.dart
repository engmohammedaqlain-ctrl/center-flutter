/// حضور الطالب يوماً بيوم — المقابل لـ `dailyAttendance` في الويب.
///
/// آخر كتابة تفوز (`updated_at` ثم `created_at`). عند التعادل تُفضَّل جلسة
/// الشعبة على المادة، ثم أعلى رتبة حالة (غياب > عذر > حضور).
library;

import '../models/models.dart';

const _dayStatusRank = {'present': 1, 'excused': 2, 'absent': 3};

/// حضور مجمّع يوماً بيوم.
List<({String date, String status})> dailyAttendance(
  Iterable<AttendanceMark> records,
  Iterable<ClassSession> sessions,
) {
  final sessionById = {for (final s in sessions) s.id: s};
  final byDay = <String, ({String status, int at, bool room})>{};

  for (final r in records) {
    final session = sessionById[r.sessionId];
    final date = session != null && session.sessionDate.isNotEmpty
        ? session.sessionDate
        : (r.date.isNotEmpty ? r.date : (r.createdAt ?? '').split('T').first);
    if (date.isEmpty) continue;

    final parsed = DateTime.tryParse(r.updatedAt ?? r.createdAt ?? '');
    final candidate = (
      status: r.status,
      at: parsed?.millisecondsSinceEpoch ?? 0,
      room: session != null && session.groupId.isEmpty,
    );
    final prev = byDay[date];
    final wins = prev == null ||
        candidate.at > prev.at ||
        (candidate.at == prev.at &&
            (candidate.room != prev.room
                ? candidate.room
                : (_dayStatusRank[candidate.status] ?? 0) > (_dayStatusRank[prev.status] ?? 0)));
    if (wins) byDay[date] = candidate;
  }

  final out = [
    for (final e in byDay.entries) (date: e.key, status: e.value.status),
  ];
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
