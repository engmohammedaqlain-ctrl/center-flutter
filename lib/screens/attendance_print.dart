import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/phone.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

/// طباعة كشف الحضور الأسبوعي — مطابق لتقارير Docs المعتمدة.
Future<void> printWeeklyAttendance(
  BuildContext context, {
  required AppStore store,
  required String title,
  required List<SchoolDay> week,
  required List<Student> students,
  required String ownerId,
}) {
  return runBusyOp(context, () async {
    final room = store.roomById(ownerId);
    final period = week.length >= 2
        ? 'الفترة: من ${week.first.dayName} ${week.first.shortDate} إلى ${week.last.dayName} ${week.last.shortDate}'
        : 'الفترة: ${week.first.dayName} ${week.first.shortDate}';
    final grade = room?.gradeLevel.trim() ?? '';
    final logo = PdfKit.decodeImage(store.institutionLogo);

    final rows = <List<String>>[];
    for (var i = 0; i < students.length; i++) {
      final s = students[i];
      final cells = <String>['${i + 1}', s.fullName];
      var absences = 0;
      for (final d in week) {
        final status = store.attendanceInSession(ownerId, s.id, d.dateStr);
        if (status == 'absent') absences++;
        cells.add(switch (status) {
          'present' => '✓',
          'absent' => '✕',
          'excused' => 'م',
          _ => '',
        });
      }
      final parentPhone = s.parentPhone.trim().isEmpty
          ? '-'
          : formatPhoneDisplay(s.parentPhone, s.parentPhonePrefix);
      cells.add('$absences');
      cells.add(parentPhone);
      cells.add('');
      rows.add(cells);
    }

    final dayFlex = List<int>.filled(week.length, 2);
    final parentCol = 2 + week.length + 1;
    final bytes = await PdfKit.buildSafe(
      title: 'كشف الحضور والغياب',
      institutionName: store.institutionName,
      logoBase64: store.institutionLogo,
      landscape: true,
      header: (_) => pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 1.2)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logo != null) ...[
                        pw.SizedBox(width: 32, height: 32, child: pw.Image(logo)),
                        pw.SizedBox(height: 3),
                      ],
                      pw.Text(store.institutionName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('سجل التفقد والدوام الأسبوعي الرسمي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('العام الدراسي: ${academicYear()}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.3))),
                        child: pw.Text('كشف الحضور والغياب', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(period, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        [
                          if (grade.isNotEmpty) 'المرحلة: $grade',
                          if (title.trim().isNotEmpty) 'شعبة $title',
                        ].join('، '),
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text('إجمالي الطلاب: ${students.length} طالب', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('تاريخ الاستخراج: ${isoDate(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
        ],
      ),
      body: (_) => [
        PdfKit.table(
          headers: [
            '#',
            'اسم الطالب',
            ...week.map((d) => d.dayName),
            'الغياب',
            'ولي الأمر',
            'ملاحظات',
          ],
          rows: rows,
          flex: [1, 5, ...dayFlex, 2, 3, 3],
          ltrColumns: {parentCol},
        ),
      ],
      endMatter: [
        PdfKit.signatureRow(const [
          'توقيع المعلم / مربي الصف',
          'توقيع المشرف الإداري',
          'مدير المدرسة / الختم الرسمي',
        ]),
      ],
    );

    if (!context.mounted) return;
    if (bytes == null) {
      showAppSnack(context, 'تعذّر تجهيز كشف الحضور', error: true);
      return;
    }
    try {
      await PdfKit.preview(bytes, PdfKit.fileName('كشف تفقد وحضور الطلاب $title'));
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر تنزيل كشف الحضور', error: true);
    }
  }, message: 'جارٍ تجهيز كشف الحضور...');
}

/// طباعة كشف طلاب الصف — مطابق لـ ClassPrintRoster / Docs.
Future<void> printClassRoster(
  BuildContext context, {
  required AppStore store,
  required Classroom room,
  required List<Student> students,
}) {
  return runBusyOp(context, () async {
    final teacher = store.teacherById(room.teacherId);
    final logo = PdfKit.decodeImage(store.institutionLogo);
    final rows = [
      for (var i = 0; i < students.length; i++)
        [
          '${i + 1}',
          students[i].fullName,
          students[i].gender.trim().isEmpty ? '-' : genderLabel(students[i].gender),
          students[i].phone.trim().isEmpty
              ? '-'
              : formatPhoneDisplay(students[i].phone, students[i].phonePrefix),
          _parentCellText(students[i]),
          '',
        ],
    ];

    final bytes = await PdfKit.buildSafe(
      title: 'كشف بيانات وحضور طلاب الصف',
      institutionName: store.institutionName,
      logoBase64: store.institutionLogo,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          PdfKit.docHeader(
            institution: store.institutionName,
            title: 'كشف بيانات وحضور طلاب الصف',
            academicYearLabel: academicYear(),
            dateLabel: isoDate(DateTime.now()),
            logo: logo,
          ),
          PdfKit.metaRow([
            'الصف / الشعبة: ${room.name}${room.gradeLevel.isNotEmpty ? ' - ${room.gradeLevel}' : ''}',
            'مربي الصف: ${teacher?.name ?? 'غير محدد'}',
            'إجمالي الطلاب: ${students.length} طالب',
          ]),
        ],
      ),
      body: (_) => [
        PdfKit.table(
          headers: const ['م', 'اسم الطالب الكامل', 'الجنس', 'الهاتف', 'ولي الأمر / الهاتف', 'ملاحظات / الحضور'],
          rows: rows.isEmpty
              ? [
                  ['', 'لا يوجد طلاب مسجلين في هذا الصف', '', '', '', ''],
                ]
              : rows,
          flex: const [1, 5, 2, 3, 4, 3],
          ltrColumns: const {3},
        ),
      ],
      endMatter: [
        PdfKit.signatureRow(const [
          'توقيع مربي الصف',
          'اعتماد الإدارة المدرسية',
        ]),
        if ((teacher?.name ?? '').isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(teacher!.name, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
            ),
          ),
      ],
    );

    if (!context.mounted) return;
    if (bytes == null) {
      showAppSnack(context, 'تعذّر تجهيز كشف الصف', error: true);
      return;
    }
    try {
      await PdfKit.preview(bytes, PdfKit.fileName('كشف طلاب ${room.name}'));
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر تنزيل كشف الصف', error: true);
    }
  }, message: 'جارٍ تجهيز كشف الصف...');
}

String _parentCellText(Student s) {
  final name = s.parentName.trim();
  final phone = s.parentPhone.trim();
  if (name.isEmpty && phone.isEmpty) return '-';
  final phoneDisplay = phone.isEmpty ? '' : formatPhoneDisplay(s.parentPhone, s.parentPhonePrefix);
  if (name.isEmpty) return phoneDisplay;
  if (phoneDisplay.isEmpty) return name;
  return '$name ($phoneDisplay)';
}
