/// الملف الشامل للطالب وملف المعلم — المقابل لـ `studentFile.ts` و`downloadDocPdf`:
/// مستند رسمي بترويسة كشوف المدرسة: البيانات، الحضور، التحصيل، المالية، ثم التواقيع.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import 'attendance_days.dart';
import 'balance.dart';
import 'followup.dart';
import 'grading.dart';
import 'phone.dart';
import 'portal_usage.dart';
import 'printing.dart';
import 'report_cards.dart';
import 'reports_data.dart';
import 'school_calendar.dart';
import 'store.dart';

String _dmy(String d) => d.length >= 10 ? d.substring(0, 10).split('-').reversed.join('/') : '—';
String _pct(double? n) => n == null ? '—' : '${trimNum((n * 10).round() / 10)}%';
String _money(double v) => '${trimNum(v)} شيكل';

/// عنوان قسم بخط تحته — `{kind: 'section'}`.
pw.Widget docSection(String title) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    );

/// حقول بعمودين — `{kind: 'fields'}`.
pw.Widget docFields(List<(String, String)> fields) {
  final rows = <pw.Widget>[];
  for (var i = 0; i < fields.length; i += 2) {
    pw.Widget cell((String, String) f) => pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${f.$1}: ', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Expanded(child: pw.Text(f.$2, style: const pw.TextStyle(fontSize: 9.5))),
              ],
            ),
          ),
        );
    rows.add(pw.Row(children: [
      cell(fields[i]),
      if (i + 1 < fields.length) cell(fields[i + 1]) else pw.Expanded(child: pw.SizedBox()),
    ]));
  }
  return pw.Column(children: rows);
}

/// صف أرقام — `{kind: 'stats'}`.
pw.Widget docStats(List<(String, String)> items) => pw.Row(
      children: [
        for (final s in items)
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 2),
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey500)),
              child: pw.Column(
                children: [
                  pw.Text(s.$2, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(s.$1, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ),
          ),
      ],
    );

/// الملف الشامل PDF: `null` إن تعذّر البناء.
Future<Uint8List?> buildStudentFile(AppStore store, Student student) async {
  final year = store.viewedAcademicYear;
  final today = isoDate(DateTime.now());
  bool inYear(String d) =>
      year == null || (d.compareTo(year.startsOn) >= 0 && (year.endsOn.isEmpty || d.compareTo(year.endsOn) <= 0));

  // الحضور
  final marks = store.attendance.where((a) => a.studentId == student.id);
  final days = dailyAttendance(marks, store.sessions, calendar: store.settings.calendar)
      .where((d) => inYear(d.date) && d.date.compareTo(today) <= 0)
      .toList();
  int count(String s) => days.where((d) => d.status == s).length;
  final rate = days.isEmpty ? null : (count('present') / days.length * 100).round();
  final sent = store.financeAudit
      .where((a) => a.action == absenceAlertAction && a.studentId == student.id)
      .toList()
    ..sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));

  // التحصيل بنظام علامات السنة المعروضة
  final grading = store.gradingForViewedYear;
  final pass = grading.passPercent;
  final rows = buildReportCardRows(
    store.evaluationsOfStudent(student.id).where((e) => e.subjectId.isNotEmpty),
    grading,
    student.gradeLevel,
    (id) => store.subjects.where((s) => s.id == id).firstOrNull?.name ?? 'مادة',
    year: year,
  );
  double? resultOf(SubjectGradeSummary r) => r.yearGrade?.percent ?? r.term2.currentAverage ?? r.term1.currentAverage;
  final results = [for (final r in rows) if (resultOf(r) case final v?) v];
  final overall = results.isEmpty ? null : results.reduce((a, b) => a + b) / results.length;

  // المالية
  final installments = store.installments.where((i) => i.studentId == student.id).toList();
  final split = dueAndScheduled(installments, fallbackBalance: student.balance);
  final paid = store.paymentsOf(student.id).where((p) => !p.cancelled).fold<double>(0, (n, p) => n + p.amount);
  final total = installments.where((i) => !i.isExempt).fold<double>(0, (n, i) => n + i.amount);
  final unpaid = installments.where((i) => !i.isExempt && unpaidOf(i) > 0).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  Map<String, AccountUsage>? usage;
  try {
    usage = await accountUsage();
  } catch (_) {}

  final klass = [student.gradeLevel, student.section].where((x) => x.trim().isNotEmpty).join(' - ');
  const orphanLabels = {'father': 'يتيم الأب', 'mother': 'يتيم الأم', 'both': 'يتيم الأبوين'};
  final fields = <(String, String)>[
    ('اسم الطالب', student.fullName),
    ('رقم الهوية', student.nationalId.isEmpty ? '—' : student.nationalId),
    ('الصف والشعبة', klass.isEmpty ? '—' : klass),
    ('تاريخ الميلاد', _dmy(student.birthDate)),
    ('الجنس', student.gender.isEmpty ? '—' : student.gender),
    ('تاريخ التسجيل', _dmy(isoDate(student.enrolledAt))),
    ('ولي الأمر', student.parentName.isEmpty ? '—' : student.parentName),
    ('جوال ولي الأمر', formatPhoneDisplay(student.parentPhone, student.parentPhonePrefix)),
    ('اليتم', orphanLabels[student.orphanStatus] ?? 'لا'),
    ('الحالة الصحية', student.medicalCondition.isNotEmpty ? student.medicalCondition : student.healthStatus),
    if (usage != null) ...[
      ('دخول ولي الأمر للبوابة', lastSeenLabel(usage['parent:${student.id}'])),
      ('دخول الطالب للبوابة', lastSeenLabel(usage['student:${student.id}'])),
    ],
  ];

  return PdfKit.buildSafe(
    title: 'الملف الشامل للطالب',
    institutionName: store.institutionName,
    logoBase64: store.institutionLogo,
    subtitle: [student.fullName, if (klass.isNotEmpty) klass, if (year != null) year.label, 'صدر ${_dmy(today)}'].join(' · '),
    body: (_) => [
      docSection('البيانات الشخصية'),
      docFields(fields),
      docSection('الحضور والغياب'),
      docStats([
        ('نسبة الحضور', rate == null ? '—' : '$rate%'),
        ('أيام الحضور', '${count('present')}'),
        ('الغياب', '${count('absent')}'),
        ('المأذون', '${count('excused')}'),
        ('الأيام المرصودة', '${days.length}'),
      ]),
      if (sent.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'الإنذارات المرسلة للأهل: ${sent.map((a) => '${a.summary} (${_dmy(a.createdAt ?? '')})').join('، ')}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
      docSection('التحصيل الدراسي'),
      if (rows.isEmpty)
        pw.Text('لا علامات مرصودة بعد', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700))
      else
        PdfKit.table(
          headers: ['المادة', 'الفصل الأول', 'الفصل الثاني', 'النتيجة', 'التقدير'],
          flex: const [4, 2, 2, 2, 2],
          rows: [
            for (final r in rows)
              [
                r.subjectName,
                _pct(r.term1.currentAverage),
                _pct(r.term2.currentAverage),
                _pct(resultOf(r)),
                resultOf(r) == null ? '—' : bands[bandOf(resultOf(r)!, pass)],
              ],
            if (overall != null) ['المعدل العام', '', '', _pct(overall), bands[bandOf(overall, pass)]],
          ],
        ),
      docSection('الوضع المالي'),
      docStats([
        ('الرسوم', _money(total)),
        ('المدفوع', _money(paid)),
        ('المتأخر', _money(split.due)),
        ('القادم', _money(split.scheduled)),
      ]),
      if (unpaid.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        PdfKit.table(
          headers: ['القسط', 'الاستحقاق', 'المبلغ', 'المتبقي'],
          flex: const [4, 2, 2, 2],
          rows: [
            for (final i in unpaid) [i.title, _dmy(isoDate(i.dueDate)), _money(i.amount), _money(unpaidOf(i))],
          ],
        ),
      ],
      pw.SizedBox(height: 28),
      PdfKit.signatureRow(['مربي الصف', 'مدير المدرسة', 'الختم']),
    ],
  );
}
