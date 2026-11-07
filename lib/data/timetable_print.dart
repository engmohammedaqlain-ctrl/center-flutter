/// طباعة الجدول وتصديره — المقابل لـ `timetablePrint.ts` و`timetableXlsx.ts`:
/// شعبة أو معلم في صفحة (أيام × حصص)، والجدول العام (المعلمون × خانات الأسبوع) موزعاً على صفحات.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'printing.dart';
import 'xlsx_styled.dart';
import 'timetable_model.dart';

class TimetableDoc {
  const TimetableDoc({
    required this.institution,
    required this.logo,
    required this.year,
    required this.settings,
    required this.days,
    required this.entries,
    required this.rules,
    required this.roomIds,
    required this.roomName,
    required this.roomCode,
    required this.teacherName,
    required this.subjectOf,
    required this.teacherOfGroup,
  });

  final String institution;
  final String? logo;
  final String year;
  final TimetableSettings settings;
  final List<int> days;
  final List<TimetableEntry> entries;
  final TimetableRules rules;

  /// الشعب بترتيب المدرسة: منه ترتيب المعلمين في الجدول العام.
  final List<String> roomIds;
  final String Function(String) roomName;
  final String Function(String) roomCode;
  final String Function(String) teacherName;
  final String Function(String) subjectOf;
  final String Function(String) teacherOfGroup;

  /// خانات الأسبوع بترتيبها: كل يوم بحصصه.
  List<({int day, int period})> get weekSlots => [
        for (final d in days)
          for (var p = 1; p <= settings.periodsOn(d); p++) (day: d, period: p),
      ];

  /// المعلمون بترتيب أول شعبة يدرّسها كلٌّ منهم (الروضة ثم 1/1 ...).
  List<String> masterTeachers(List<String> teacherIds) {
    final order = {for (var i = 0; i < roomIds.length; i++) roomIds[i]: i};
    int first(String t) {
      var best = 9999;
      for (final e in entries) {
        if (teacherOfGroup(e.groupId) != t) continue;
        final n = order[e.roomId] ?? 9999;
        if (n < best) best = n;
      }
      return best;
    }

    return [...teacherIds]..sort((a, b) {
        final x = first(a) - first(b);
        return x != 0 ? x : teacherName(a).compareTo(teacherName(b));
      });
  }

  /// خانة المعلم في الجدول العام: رمز الشعبة، أو x لخانة لا يحضرها، أو فارغة.
  String masterCell(String teacherId, int day, int period) {
    for (final e in entries) {
      if (e.day == day && e.period == period && teacherOfGroup(e.groupId) == teacherId) return roomCode(e.roomId);
    }
    return rules.teacherOff(teacherId, day, period) ? 'x' : '';
  }
}

pw.Widget _heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Center(
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Text(text, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ),
      ),
    );

pw.Widget _weekTable(TimetableDoc doc, String Function(int day, int period) cell) {
  final max = doc.settings.periods.length;
  return PdfKit.table(
    headers: [
      '',
      for (var i = 0; i < max; i++) '${i + 1}\n${doc.settings.periods[i].start}',
    ],
    rows: [
      for (final d in doc.days)
        [
          dayNames[d],
          for (var i = 0; i < max; i++) i + 1 > doc.settings.periodsOn(d) ? '' : cell(d, i + 1),
        ],
    ],
    flex: [2, for (var i = 0; i < max; i++) 3],
  );
}

List<pw.Widget> _roomPage(TimetableDoc doc, String roomId) => [
      _heading('جدول ${doc.roomName(roomId)}'),
      _weekTable(doc, (d, p) {
        final e = doc.entries.where((x) => x.roomId == roomId && x.day == d && x.period == p).firstOrNull;
        return e == null ? '' : '${doc.subjectOf(e.groupId)}\n${doc.teacherName(doc.teacherOfGroup(e.groupId))}';
      }),
    ];

List<pw.Widget> _teacherPage(TimetableDoc doc, String teacherId) {
  final mine = doc.entries.where((x) => doc.teacherOfGroup(x.groupId) == teacherId).toList();
  return [
    _heading('جدول ${doc.teacherName(teacherId)} · ${mine.length} حصة'),
    _weekTable(doc, (d, p) {
      final e = mine.where((x) => x.day == d && x.period == p).firstOrNull;
      return e == null ? '' : '${doc.roomName(e.roomId)}\n${doc.subjectOf(e.groupId)}';
    }),
  ];
}

/// صفحة من الجدول العام: شريط الأيام فوق جدول خانات الأسبوع. كلاهما بالترتيب المرئي من اليسار.
List<pw.Widget> _masterPage(TimetableDoc doc, List<String> teachers) {
  final slots = doc.weekSlots;
  const nameFlex = 7.0;
  pw.Widget text(String t, {bool bold = false, double size = 6.5, PdfColor? color}) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Text(
          t.isEmpty ? ' ' : t,
          textAlign: pw.TextAlign.center,
          maxLines: 1,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      );
  final head = const PdfColor.fromInt(0xFFDDF1F0);
  final line = pw.Border.all(color: PdfColors.grey600, width: 0.4);
  final dayBar = pw.Row(
    children: [
      for (final d in doc.days.reversed)
        pw.Expanded(
          flex: doc.settings.periodsOn(d) * 10,
          child: pw.Container(
            decoration: pw.BoxDecoration(color: head, border: line),
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: text(dayNames[d], bold: true, size: 7.5),
          ),
        ),
      pw.Expanded(
        flex: (nameFlex * 10).round(),
        child: pw.Container(
          decoration: pw.BoxDecoration(color: head, border: line),
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: text('المعلم', bold: true, size: 7.5),
        ),
      ),
    ],
  );
  final widths = <int, pw.TableColumnWidth>{
    for (var i = 0; i < slots.length; i++) i: const pw.FlexColumnWidth(1),
    slots.length: const pw.FlexColumnWidth(nameFlex),
  };
  final visual = slots.reversed.toList();
  return [
    _heading(['الجدول العام', doc.year].where((s) => s.isNotEmpty).join(' · ')),
    dayBar,
    pw.Table(
      columnWidths: widths,
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.4),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: head),
          children: [
            for (final s in visual) text('${s.period}', bold: true),
            text(''),
          ],
        ),
        for (final t in teachers)
          pw.TableRow(
            children: [
              for (final s in visual)
                () {
                  final v = doc.masterCell(t, s.day, s.period);
                  return text(v, color: v == 'x' ? PdfColors.grey500 : null);
                }(),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2), child: text(doc.teacherName(t), bold: true)),
            ],
          ),
      ],
    ),
  ];
}

/// `kind`: `room` أو `teacher` أو `master`. يعيد `null` إن تعذّر الإعداد.
Future<Uint8List?> buildTimetablePdf(TimetableDoc doc, String kind, List<String> ids, String title) {
  final body = <pw.Widget>[];
  void page(List<pw.Widget> widgets) {
    if (body.isNotEmpty) body.add(pw.NewPage());
    body.addAll(widgets);
  }

  if (kind == 'master') {
    final ordered = doc.masterTeachers(ids);
    const perPage = 26;
    for (var i = 0; i < ordered.length; i += perPage) {
      page(_masterPage(doc, ordered.sublist(i, i + perPage > ordered.length ? ordered.length : i + perPage)));
    }
  } else {
    for (final id in ids) {
      page(kind == 'room' ? _roomPage(doc, id) : _teacherPage(doc, id));
    }
  }
  return PdfKit.buildSafe(
    title: title,
    institutionName: doc.institution,
    logoBase64: doc.logo,
    subtitle: doc.year,
    landscape: true,
    body: (_) => body,
  );
}

/// ورقة احتياط اليوم — `printCovers`.
Future<Uint8List?> buildCoversPdf({
  required String institution,
  required String? logo,
  required String title,
  required List<List<String>> rows,
}) =>
    PdfKit.buildSafe(
      title: 'الاحتياط',
      institutionName: institution,
      logoBase64: logo,
      subtitle: title,
      body: (_) => [
        PdfKit.table(
          headers: const ['الحصة', 'الشعبة', 'المادة', 'الغائب', 'البديل'],
          rows: rows,
          flex: const [1, 3, 3, 3, 3],
        ),
      ],
    );

/// Excel: الجدول العام أولاً، ثم ورقة لكل شعبة (أيام × حصص) — `exportTimetableXlsx`.
Uint8List buildTimetableXlsx(TimetableDoc doc, List<String> teacherIds) {
  final slots = doc.weekSlots;
  final max = doc.settings.periods.length;
  final dayMerges = <(int, int, int, int)>[(0, 0, 1, 0)];
  var col = 1;
  for (final d in doc.days) {
    final n = doc.settings.periodsOn(d);
    if (n > 1) dayMerges.add((0, col, 0, col + n - 1));
    col += n;
  }
  final sheets = <StyledSheet>[
    StyledSheet(
      title: 'الجدول العام',
      details: [doc.year],
      headers: ['المعلم', for (final s in slots) '${s.period}'],
      head: [
        ['المعلم', for (final s in slots) s.period == 1 ? dayNames[s.day] : ''],
        ['', for (final s in slots) '${s.period}'],
      ],
      headMerges: dayMerges,
      landscape: true,
      nameColumn: 0,
      rows: [
        for (final t in doc.masterTeachers(teacherIds))
          [doc.teacherName(t), for (final s in slots) doc.masterCell(t, s.day, s.period)],
      ],
    ),
  ];
  for (final roomId in doc.roomIds) {
    sheets.add(StyledSheet(
      title: 'جدول ${doc.roomName(roomId)}',
      tab: doc.roomCode(roomId).replaceAll('/', '-'),
      details: [doc.year],
      headers: ['اليوم', for (var i = 0; i < max; i++) '${i + 1}'],
      landscape: true,
      nameColumn: -1,
      rows: [
      for (final d in doc.days)
        [
          dayNames[d],
          for (var i = 0; i < max; i++)
            () {
              if (i + 1 > doc.settings.periodsOn(d)) return '';
              final e = doc.entries.where((x) => x.roomId == roomId && x.day == d && x.period == i + 1).firstOrNull;
              return e == null ? '' : '${doc.subjectOf(e.groupId)} - ${doc.teacherName(doc.teacherOfGroup(e.groupId))}';
            }(),
        ],
      ],
    ));
  }
  return styledXlsx(sheets, school: doc.institution, logo: doc.logo);
}
