import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/phone.dart';
import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import 'sheet_export.dart';

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
      // بلا انتظار: مؤشر التجهيز يُغلق ويُختار الإجراء فوقه
      DocExport.showActions(context, bytes, PdfKit.fileName('كشف تفقد وحضور الطلاب $title'));
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
      // بلا انتظار: مؤشر التجهيز يُغلق ويُختار الإجراء فوقه
      DocExport.showActions(context, bytes, PdfKit.fileName('كشف طلاب ${room.name}'));
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

/// كشف حضور لأيام [days] (أسبوع أو أيام دوام شهر) كجدول واحد يُطبع أو يُنزَّل Excel:
/// رمز لكل يوم، ومجموع الغياب والمأذون.
SheetData attendanceSheet({
  required AppStore store,
  required String title,
  required String periodLabel,
  required List<String> days,
  required List<Student> students,
  required String ownerId,
}) {
  String symbol(String? s) => switch (s) { 'present' => '✔', 'absent' => 'غ', 'excused' => 'م', _ => '' };
  final month = days.length > 6;
  return SheetData(
    title: 'كشف الحضور والغياب $periodLabel',
    institution: store.institutionName,
    logo: store.institutionLogo,
    landscape: true,
    yearLabel: academicYear(),
    meta: [title, '${students.length} طالب', '✔ حاضر · غ غائب · م مأذون'],
    headers: [
      'م',
      'الطالب',
      for (final d in days) month ? '${int.parse(d.substring(8))}' : '${int.parse(d.substring(8))}/${int.parse(d.substring(5, 7))}',
      'غياب',
      'مأذون',
    ],
    flex: [2, 9, for (final _ in days) month ? 2 : 3, 3, 3],
    signatures: const ['مربي الصف', 'المشرف الإداري', 'مدير المدرسة'],
    rows: [
      for (var i = 0; i < students.length; i++)
        () {
          final statuses = [for (final d in days) store.attendanceInSession(ownerId, students[i].id, d)];
          return [
            '${i + 1}',
            students[i].fullName,
            for (final s in statuses) symbol(s),
            '${statuses.where((s) => s == 'absent').length}',
            '${statuses.where((s) => s == 'excused').length}',
          ];
        }(),
    ],
  );
}

/// أيام دوام شهر التاريخ [date]، عدا الجمعة.
List<String> schoolDaysOfMonth(String date) {
  final y = int.parse(date.substring(0, 4)), m = int.parse(date.substring(5, 7));
  return [
    for (var d = DateTime(y, m, 1); d.month == m; d = d.add(const Duration(days: 1)))
      if (d.weekday != DateTime.friday) isoDate(d),
  ];
}

/// زر الطباعة في كشف الحضور: الأسبوع أو الشهر، PDF أو Excel.
Future<void> showAttendanceExport(
  BuildContext context, {
  required AppStore store,
  required String title,
  required List<SchoolDay> week,
  required String day,
  required List<Student> students,
  required String ownerId,
}) async {
  final monthName = gregorianMonths[int.parse(day.substring(5, 7)) - 1];
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('كشف الأسبوع'),
            onTap: () => Navigator.pop(sheet, 'week'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text('كشف شهر $monthName'),
            onTap: () => Navigator.pop(sheet, 'month'),
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('كشف الأسبوع Excel'),
            onTap: () => Navigator.pop(sheet, 'week_excel'),
          ),
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: Text('كشف شهر $monthName Excel'),
            onTap: () => Navigator.pop(sheet, 'month_excel'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'week') {
    await printWeeklyAttendance(context, store: store, title: title, week: week, students: students, ownerId: ownerId);
    return;
  }
  final isMonth = choice.startsWith('month');
  final sheet = attendanceSheet(
    store: store,
    title: title,
    periodLabel: isMonth ? '$monthName ${day.substring(0, 4)}' : '${week.first.shortDate} - ${week.last.shortDate}',
    days: isMonth ? schoolDaysOfMonth(day) : [for (final d in week) d.dateStr],
    students: students,
    ownerId: ownerId,
  );
  if (choice.endsWith('excel')) {
    await downloadSheetCsv(context, sheet);
  } else {
    await printSheet(context, sheet);
  }
}
