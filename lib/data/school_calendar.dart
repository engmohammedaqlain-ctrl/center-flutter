/// تقويم المدرسة (العطل والامتحانات) من الإعدادات — `schoolCalendar.ts` و`officialHolidays.ts`.
library;

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

/// الشهر واليوم الهجريان بالحساب المدني: يختلف عن أم القرى في الويب يوماً أحياناً،
/// والمقترح يعدّله المدير قبل إضافته.
({int month, int day}) _hijriOf(DateTime d) {
  final a = (14 - d.month) ~/ 12;
  final y = d.year + 4800 - a;
  final m = d.month + 12 * a - 3;
  final jd = d.day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
  var l = jd - 1948440 + 10632;
  final n = (l - 1) ~/ 10631;
  l = l - 10631 * n + 354;
  final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
  l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
  final month = (24 * l) ~/ 709;
  return (month: month, day: l - (709 * month) ~/ 24);
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
