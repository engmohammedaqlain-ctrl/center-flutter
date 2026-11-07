/// تقويم المدرسة (العطل والامتحانات) من الإعدادات — `schoolCalendar.ts` و`officialHolidays.ts`.
library;

import 'package:hijri/hijri_calendar.dart';
import '../models/models.dart';
import 'app_settings.dart';

const calendarKindLabels = {'holiday': 'عطلة', 'exam': 'امتحان'};

class CalendarEvent {
  const CalendarEvent({required this.id, required this.kind, required this.title, required this.from, required this.to});

  final String id;

  /// `holiday` أو `exam`.
  final String kind;
  final String title;
  final String from;
  final String to;

  Map<String, dynamic> toMap() => {'id': id, 'kind': kind, 'title': title, 'from': from, 'to': to};

  CalendarEvent withDates({String? from, String? to}) {
    final start = from ?? this.from;
    final end = to ?? this.to;
    return CalendarEvent(id: id, kind: kind, title: title, from: start, to: end.compareTo(start) < 0 ? start : end);
  }

  static CalendarEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final from = '${raw['from'] ?? ''}';
    if (from.isEmpty) return null;
    final to = '${raw['to'] ?? ''}';
    return CalendarEvent(
      id: '${raw['id'] ?? ''}',
      kind: raw['kind'] == 'exam' ? 'exam' : 'holiday',
      title: '${raw['title'] ?? ''}',
      from: from,
      to: to.isEmpty ? from : to,
    );
  }
}

extension SchoolCalendarSettings on AppSettings {
  List<CalendarEvent> get calendar {
    final raw = extra['calendar'];
    return [
      if (raw is List)
        for (final e in raw)
          if (CalendarEvent.fromMap(e) case final event?) event,
    ];
  }

  /// أيام العطلة الأسبوعية بترقيم JavaScript (الأحد 0 … السبت 6)، والافتراضي الجمعة.
  List<int> get weekend {
    final raw = extra['weekend'] ?? (extra['payroll'] is Map ? (extra['payroll'] as Map)['weekend'] : null);
    final days = [
      if (raw is List)
        for (final d in raw)
          if (d is num && d >= 0 && d <= 6) d.toInt(),
    ];
    return days.isEmpty ? const [5] : days;
  }
}

/// عطلة أسبوعية؟ `weekend` بترقيم JavaScript، وDart يعدّ الأحد 7.
bool isWeekendDay(DateTime d, List<int> weekend) => weekend.contains(d.weekday % 7);

CalendarEvent? holidayEventOn(Iterable<CalendarEvent> events, String date) {
  for (final e in events) {
    if (e.kind == 'holiday' && e.from.compareTo(date) <= 0 && date.compareTo(e.to) <= 0) return e;
  }
  return null;
}

/// ما لم ينتهِ بعد، بترتيب بدايته — `upcomingEvents`.
List<CalendarEvent> upcomingEvents(Iterable<CalendarEvent> events, String today) =>
    events.where((e) => e.to.compareTo(today) >= 0).toList()..sort((a, b) => a.from.compareTo(b.from));

/// «12/3» أو «12/3 - 15/3» — `eventRange`.
String eventRange(CalendarEvent e) {
  String short(String d) => d.length >= 10 ? '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}' : d;
  return e.from == e.to ? short(e.from) : '${short(e.from)} - ${short(e.to)}';
}

const _hijri = <({int month, int day, String title, int days})>[
  (month: 1, day: 1, title: 'رأس السنة الهجرية', days: 1),
  (month: 3, day: 12, title: 'المولد النبوي', days: 1),
  (month: 7, day: 27, title: 'الإسراء والمعراج', days: 1),
  (month: 10, day: 1, title: 'عيد الفطر', days: 3),
  (month: 12, day: 10, title: 'عيد الأضحى', days: 4),
];

const _gregorian = <({int month, int day, String title})>[
  (month: 1, day: 1, title: 'رأس السنة الميلادية'),
  (month: 1, day: 7, title: 'عيد الميلاد الشرقي'),
  (month: 5, day: 1, title: 'عيد العمال'),
  (month: 11, day: 15, title: 'عيد الاستقلال'),
  (month: 12, day: 25, title: 'عيد الميلاد'),
];

/// الشهر واليوم الهجريان بتقويم أم القرى — كالويب (`islamic-umalqura`). موعد العيد قد يختلف يوماً
/// حسب الرؤية، فالمقترح يعتمده المدير أو يحذفه.
({int month, int day}) _hijriOf(DateTime d) {
  final h = HijriCalendar.fromDate(DateTime(d.year, d.month, d.day));
  return (month: h.hMonth, day: h.hDay);
}

/// العطل الرسمية المعتادة في فلسطين لفترة — `officialHolidays`: اقتراح يعتمده المدير.
List<({String title, String from, String to})> officialHolidays(String from, String to) {
  final out = <({String title, String from, String to})>[];
  final end = parseIsoDate(to);
  final start = parseIsoDate(from);
  if (start == null || end == null) return out;
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    for (final g in _gregorian) {
      if (g.month == d.month && g.day == d.day) out.add((title: g.title, from: isoDate(d), to: isoDate(d)));
    }
    final h = _hijriOf(d);
    for (final x in _hijri) {
      if (x.month == h.month && x.day == h.day) {
        out.add((title: x.title, from: isoDate(d), to: isoDate(DateTime(d.year, d.month, d.day + x.days - 1))));
      }
    }
  }
  return out..sort((a, b) => a.from.compareTo(b.from));
}
