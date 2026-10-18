import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/report_cards.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// شهادات صف أو شعبة، أو كشف نتائجها — من كشف العلامات وصفحة الصفوف.
Future<void> openClassReportCards(
  BuildContext context,
  AppStore store, {
  String? roomId,
  String grade = '',
  bool summary = false,
}) async {
  final report = loadClassReportCards(store, roomId: roomId, grade: grade);
  if (report.cards.isEmpty) {
    showAppSnack(context, 'لا توجد علامات مرصودة لطلاب هذا الصف بعد.', error: true);
    return;
  }
  await showReportCardsSheet(
    context,
    store,
    cards: report.cards,
    skipped: report.skipped,
    title: '${summary ? 'كشف نتائج' : 'شهادات'} ${report.label}',
    summary: summary,
  );
}

/// نافذة الشهادة: اختيار الفصل الأول أو الفصلين، والترتيب على شهادات الصف، ثم ملف PDF
/// فيه كل طالب في صفحة (أو كشف النتائج في ملف وحده) — `ReportCardModal`.
Future<void> showReportCardsSheet(
  BuildContext context,
  AppStore store, {
  required List<ReportCardStudent> cards,
  List<String> skipped = const [],
  required String title,
  bool summary = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (_) => _ReportCardsSheet(store: store, cards: cards, skipped: skipped, title: title, summary: summary),
  );
}

class _ReportCardsSheet extends StatefulWidget {
  const _ReportCardsSheet({
    required this.store,
    required this.cards,
    required this.skipped,
    required this.title,
    required this.summary,
  });

  final AppStore store;
  final List<ReportCardStudent> cards;
  final List<String> skipped;
  final String title;
  final bool summary;

  @override
  State<_ReportCardsSheet> createState() => _ReportCardsSheetState();
}

class _ReportCardsSheetState extends State<_ReportCardsSheet> {
  late ReportCardTerms terms = reportHasTerm2(widget.cards) ? ReportCardTerms.both : ReportCardTerms.term1;

  /// الترتيب على الشهادة لا يُطبع إلا إن اختير.
  bool withRank = false;

  bool get isClass => widget.cards.length > 1;

  Future<void> _print() => runBusyOp(context, () async {
        final bytes = await buildReportCardsPdf(
          widget.store,
          widget.cards,
          terms: terms,
          summary: widget.summary,
          withRank: isClass && withRank,
        );
        if (!mounted) return;
        if (bytes == null) {
          showAppSnack(context, 'تعذّر تجهيز الملف', error: true);
          return;
        }
        final name = '${widget.title}${terms == ReportCardTerms.term1 ? ' الفصل الأول' : ''}';
        DocExport.showActions(context, bytes, PdfKit.fileName(name));
      }, message: 'جارٍ التجهيز...');

  @override
  Widget build(BuildContext context) {
    final heading = widget.summary ? 'كشف نتائج الصف' : (isClass ? 'شهادات الصف (${widget.cards.length})' : 'الشهادة');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(heading, style: AppText.title),
            const SizedBox(height: 12),
            SegmentedButton<ReportCardTerms>(
              segments: const [
                ButtonSegment(value: ReportCardTerms.term1, label: Text('الفصل الأول')),
                ButtonSegment(value: ReportCardTerms.both, label: Text('الفصلان')),
              ],
              selected: {terms},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => terms = v.first),
            ),
            if (isClass && !widget.summary)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: withRank,
                onChanged: (v) => setState(() => withRank = v),
                title: const Text('الترتيب على الشهادة', style: TextStyle(fontSize: 13)),
              ),
            if (widget.skipped.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(Corner.box),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  'بلا علامات فلم تُطبع لهم شهادة (${widget.skipped.length}): ${widget.skipped.join('، ')}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                ),
              ),
            ],
            const SizedBox(height: 14),
            PrimaryButton(label: 'طباعة', icon: Icons.print_outlined, expand: true, height: 46, onPressed: _print),
            const SizedBox(height: 6),
            GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

/// ملف الشهادات (كل طالب في صفحة) أو كشف نتائج الصف.
Future<Uint8List?> buildReportCardsPdf(
  AppStore store,
  List<ReportCardStudent> cards, {
  required ReportCardTerms terms,
  bool summary = false,
  bool withRank = false,
}) async {
  try {
    final doc = pw.Document(theme: await PdfKit.theme());
    final logo = PdfKit.decodeImage(store.institutionLogo);
    final stamp = PdfKit.decodeImage(store.institutionStamp);
    final yearLabel = store.viewedAcademicYear?.label ?? '';
    final pass = store.gradingForViewedYear.passPercent;
    final ranks = cards.length > 1 || summary ? reportClassRanks(cards, terms) : const <String, int>{};
    final term1End = store.viewedAcademicYear?.term1End ?? '';
    const margin = pw.EdgeInsets.symmetric(vertical: 12 * PdfPageFormat.mm, horizontal: 14 * PdfPageFormat.mm);

    if (summary) {
      final first = cards.first;
      final sections = {for (final c in cards) c.section};
      final passed = cards.where((c) => (reportCardAverage(c, terms) ?? -1) >= pass).length;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          _header(
            store.institutionName,
            yearLabel,
            logo,
            'كشف نتائج الصف',
            [first.gradeLevel, sections.length == 1 ? first.section : ''].where((x) => x.isNotEmpty).join(' - ') +
                (terms == ReportCardTerms.term1 ? ' · الفصل الأول' : ''),
          ),
          pw.SizedBox(height: 10),
          pw.Text('عدد الطلاب ${cards.length} · ناجح $passed · راسب ${cards.length - passed}'),
          pw.SizedBox(height: 8),
          PdfKit.table(
            headers: const ['#', 'الطالب', 'المعدل', 'الترتيب', 'النتيجة'],
            flex: const [1, 6, 2, 2, 2],
            rows: [
              for (var i = 0; i < cards.length; i++)
                () {
                  final a = reportCardAverage(cards[i], terms);
                  return [
                    '${i + 1}',
                    cards[i].studentName,
                    a == null ? '—' : '$a%',
                    '${ranks[cards[i].id] ?? '—'}',
                    reportResultText(a, pass),
                  ];
                }(),
            ],
          ),
        ],
      ));
      return doc.save();
    }

    final both = terms == ReportCardTerms.both;
    for (final card in cards) {
      final rank = withRank ? ranks[card.id] : null;
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        textDirection: pw.TextDirection.rtl,
        build: (_) => _cardPage(
          card,
          both: both,
          institution: store.institutionName,
          yearLabel: yearLabel,
          logo: logo,
          stamp: stamp,
          pass: pass,
          rank: rank == null ? null : (place: rank, of: cards.length),
          term1End: term1End,
        ),
      ));
    }
    return doc.save();
  } catch (_) {
    return null;
  }
}

pw.Widget _header(String institution, String yearLabel, pw.MemoryImage? logo, String title, String subtitle) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.6))),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(children: [
          if (logo != null) pw.Padding(padding: const pw.EdgeInsets.only(left: 8), child: pw.Image(logo, width: 40, height: 40)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(institution.trim().isEmpty ? 'المدرسة' : institution, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            if (yearLabel.isNotEmpty) pw.Text('العام الدراسي $yearLabel', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          ]),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)),
          if (subtitle.isNotEmpty)
            pw.Text(subtitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey700)),
        ]),
      ],
    ),
  );
}

pw.Widget _result(String text) => pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: text == 'راسب' ? PdfColors.red700 : PdfColors.black),
    );

/// شهادة طالب واحد، صفحة مستقلة — `ReportCardSheet`.
pw.Widget _cardPage(
  ReportCardStudent card, {
  required bool both,
  required String institution,
  required String yearLabel,
  required pw.MemoryImage? logo,
  required pw.MemoryImage? stamp,
  required double pass,
  required ({int place, int of})? rank,
  required String term1End,
}) {
  final cells = [for (final r in card.rows) (row: r, t1: reportTermCell(r.term1), t2: reportTermCell(r.term2))];
  final anyPartial = cells.any((c) => c.t1.partial || (both && c.t2.partial));
  final avg = reportAverages(card);
  final finalAvg = both ? avg.year : avg.t1;
  // شهادة الفصل الأول تعدّ غيابه وحده
  final misses = card.misses?.where((m) => both || term1End.isEmpty || m.date.compareTo(term1End) <= 0).toList();
  final absent = misses?.where((m) => m.status == 'absent').length ?? 0;
  final excused = misses?.where((m) => m.status == 'excused').length ?? 0;
  String pct(int? v) => v == null ? '—' : '$v%';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _header(institution, yearLabel, logo, 'الشهادة المدرسية', both ? '' : 'الفصل الأول'),
      pw.SizedBox(height: 12),
      pw.Wrap(spacing: 24, runSpacing: 4, children: [
        pw.Text('الطالب: ${card.studentName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        if (card.gradeLevel.isNotEmpty) pw.Text('الصف: ${card.gradeLevel}'),
        if (card.section.isNotEmpty) pw.Text('الشعبة: ${card.section}'),
        if (rank != null) pw.Text('الترتيب: ${rank.place} من ${rank.of}'),
      ]),
      pw.SizedBox(height: 12),
      PdfKit.table(
        headers: ['المادة', 'العلامة', 'الفصل الأول', if (both) 'الفصل الثاني', if (both) 'السنة', 'النتيجة'],
        flex: [5, 2, 2, if (both) 2, if (both) 3, 2],
        rows: [
          for (final c in cells)
            [
              c.row.subjectName,
              trimNum(c.row.fullMark),
              c.t1.text,
              if (both) c.t2.text,
              if (both) c.row.yearGrade == null ? '—' : '${c.row.yearGrade!.score.round()} / ${trimNum(c.row.yearGrade!.yearFullMark)}',
              _result(reportResultText(both ? c.row.yearGrade?.percent : c.t1.pct, pass)),
            ],
          [
            'المعدل',
            '',
            pct(avg.t1),
            if (both) pct(avg.t2),
            if (both) pct(avg.year),
            _result(reportResultText(finalAvg, pass)),
          ],
        ],
      ),
      if (anyPartial) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('* غير مكتمل', style: const pw.TextStyle(fontSize: 8))),
      if (misses != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('أيام الغياب: $absent${excused > 0 ? ' · بإذن: $excused' : ''}'),
        ),
      pw.SizedBox(height: 30),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _signature('مربي الصف', card.homeroomName),
          if (stamp != null) pw.Image(stamp, width: 70, height: 70),
          _signature('المدير', ''),
        ],
      ),
    ],
  );
}

pw.Widget _signature(String label, String name) => pw.SizedBox(
      width: 130,
      child: pw.Column(children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 14, child: pw.Text(name, style: const pw.TextStyle(fontSize: 9))),
        pw.SizedBox(height: 18),
        pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.8),
      ]),
    );
