/// حضور الطالب يوماً بيوم — المقابل لـ `dailyAttendance` في الويب.
///
/// آخر كتابة تفوز (`updated_at` ثم `created_at`). عند التعادل تُفضَّل جلسة
/// الشعبة على المادة، ثم أعلى رتبة حالة (غياب > عذر > حضور).
library;

import '../models/models.dart';
import 'school_calendar.dart';

const _dayStatusRank = {'present': 1, 'excused': 2, 'absent': 3};

/// وقت آخر كتابة للرصد بالملّي ثانية، محفوظاً مع نصه: تحويل نص التاريخ هو أغلى ما في
/// الحساب، ويتكرر لخمسين ألف رصد مع كل حساب للرئيسية والإنذارات والتقارير.
final _stampCache = Expando<(String, int)>('attendanceStamp');

int _writtenAt(AttendanceMark r) {
  final raw = r.updatedAt ?? r.createdAt ?? '';
  final cached = _stampCache[r];
  if (cached != null && cached.$1 == raw) return cached.$2;
  final at = DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  _stampCache[r] = (raw, at);
  return at;
}

/// خريطة الجلسات بمعرّفها — تُبنى مرة وتُمرَّر لـ [dailyAttendance] لكل طالب.
Map<String, ClassSession> sessionMap(Iterable<ClassSession> sessions) => {for (final s in sessions) s.id: s};

/// حضور مجمّع يوماً بيوم.
List<({String date, String status})> dailyAttendance(
  Iterable<AttendanceMark> records,
  Iterable<ClassSession> sessions, {
  // يوم العطلة لا يُحسب غياباً ولا حضوراً
  Iterable<CalendarEvent> calendar = const [],
  // خريطة الجلسات مبنية مرة واحدة للمستدعي الذي يمرّ على كل الطلاب: بناؤها لكل طالب
  // كان يكرر آلاف الجلسات آلاف المرات. حين تُمرَّر تُهمَل [sessions].
  Map<String, ClassSession>? sessionById,
}) {
  final byId = sessionById ?? sessionMap(sessions);
  final byDay = <String, ({String status, int at, bool room})>{};
  final cal = calendar.isEmpty ? null : calendar;
  final holiday = <String, bool>{};

  for (final r in records) {
    final session = byId[r.sessionId];
    final date = session != null && session.sessionDate.isNotEmpty
        ? session.sessionDate
        : (r.date.isNotEmpty ? r.date : (r.createdAt ?? '').split('T').first);
    if (date.isEmpty) continue;
    if (cal != null && (holiday[date] ??= holidayEventOn(cal, date) != null)) continue;

    final candidate = (
      status: r.status,
      at: _writtenAt(r),
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
