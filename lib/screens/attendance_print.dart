import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/phone.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';

/// طباعة كشف الحضور الأسبوعي — المقابل لزر الطباعة في `pages/Attendance.tsx`.
Future<void> printWeeklyAttendance(
  BuildContext context, {
  required AppStore store,
  required String title,
  required List<SchoolDay> week,
  required List<Student> students,
  required String ownerId,
}) async {
  final room = store.roomById(ownerId);
  final period = week.length >= 2
      ? 'الفترة: من ${week.first.dayName} ${week.first.shortDate} إلى ${week.last.dayName} ${week.last.shortDate}'
      : 'الفترة: ${week.first.dayName} ${week.first.shortDate}';
  final extracted = isoDate(DateTime.now());
  final subtitle = [
    period,
    if (room?.gradeLevel.trim().isNotEmpty ?? false) 'المرحلة: ${room!.gradeLevel.trim()}',
    if (title.trim().isNotEmpty) 'الشعبة: $title',
    'إجمالي الطلاب: ${students.length}',
    'تاريخ الاستخراج: $extracted',
  ].join('   ·   ');

  final rows = <List<String>>[];
  for (var i = 0; i < students.length; i++) {
    final s = students[i];
    final cells = <String>['${i + 1}', s.fullName];
    var absences = 0;
    for (final d in week) {
      final status = store.attendanceInSession(ownerId, s.id, d.dateStr);
      if (status == 'absent') absences++;
      cells.add(switch (status) {
        'present' => '✔',
        'absent' => 'غ',
        'excused' => 'م',
        _ => '',
      });
    }
    // كالويب: هاتف ولي الأمر فقط، بلا احتياط برقم الطالب
    final parentPhone = s.parentPhone.trim().isEmpty
        ? '—'
        : formatPhoneDisplay(s.parentPhone, s.parentPhonePrefix);
    cells.add('$absences');
    cells.add(parentPhone);
    cells.add('');
    rows.add(cells);
  }

  final dayFlex = List<int>.filled(week.length, 2);
  final parentCol = 2 + week.length + 1; // #, اسم, أيام..., غياب, ولي الأمر
  final bytes = await PdfKit.build(
    title: 'سجل التفقد والدوام الأسبوعي الرسمي',
    institutionName: store.institutionName,
    logoBase64: store.institutionLogo,
    subtitle: subtitle,
    landscape: true,
    body: (ctx) => [
      pw.Text('كشف الحضور والغياب', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      PdfKit.table(
        headers: [
          '#',
          'اسم الطالب',
          ...week.map((d) => '${d.dayName}\n${d.shortDate}'),
          'الغياب',
          'ولي الأمر',
          'ملاحظات',
        ],
        rows: rows,
        flex: [1, 5, ...dayFlex, 2, 3, 3],
        ltrColumns: {parentCol},
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('توقيع المعلم / مربي الصف: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('توقيع المشرف الإداري: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('مدير المدرسة / الختم الرسمي: ....................', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'الرموز: ✔ حاضر · غ غائب · م مأذون',
        style: const pw.TextStyle(fontSize: 8),
      ),
    ],
  );

  if (!context.mounted) return;
  await PdfKit.preview(bytes, PdfKit.fileName('كشف تفقد وحضور الطلاب $title'));
}

/// طباعة كشف طلاب الصف — المقابل لـ `ClassPrintRoster.tsx`.
Future<void> printClassRoster(
  BuildContext context, {
  required AppStore store,
  required Classroom room,
  required List<Student> students,
}) async {
  final teacher = store.teacherById(room.teacherId);

  final bytes = await PdfKit.build(
    title: 'كشف بيانات وحضور طلاب الصف',
    institutionName: store.institutionName,
    logoBase64: store.institutionLogo,
    subtitle: [
      'الصف / الشعبة: ${room.name}${room.gradeLevel.isNotEmpty ? ' (${room.gradeLevel})' : ''}',
      'مربي الصف: ${teacher?.name ?? 'غير محدد'}',
      'إجمالي الطلاب: ${students.length} طالب',
    ].join('   ·   '),
    body: (ctx) => [
      _rosterTable(students),
      pw.SizedBox(height: 28),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            children: [
              pw.Text('توقيع مربي الصف', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 22),
              pw.Container(
                width: 140,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.black, style: pw.BorderStyle.dashed)),
                ),
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  teacher?.name ?? '................................',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text('اعتماد الإدارة المدرسية', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 22),
              pw.Container(
                width: 140,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.black, style: pw.BorderStyle.dashed)),
                ),
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  '................................',
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  if (!context.mounted) return;
  await PdfKit.preview(bytes, PdfKit.fileName('كشف طلاب ${room.name}'));
}

/// أعمدة مطابقة لـ ClassPrintRoster: م، اسم كامل، الجنس، هاتف، ولي الأمر (هاتف)، ملاحظات/حضور.
pw.Widget _rosterTable(List<Student> students) {
  pw.Widget cell(pw.Widget child, {bool head = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: pw.BoxDecoration(
          color: head ? PdfColors.grey200 : null,
          border: const pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: child,
      );

  pw.Widget textCell(String text, {bool head = false, bool forceLtr = false}) {
    final style = pw.TextStyle(fontSize: head ? 9 : 8.5, fontWeight: head ? pw.FontWeight.bold : null);
    return cell(forceLtr ? ltr(text, style: style) : pw.Text(text, style: style), head: head);
  }

  pw.Widget parentCell(Student s) {
    final name = s.parentName.trim();
    final phone = s.parentPhone.trim();
    if (name.isEmpty && phone.isEmpty) {
      return textCell('—');
    }
    final phoneDisplay = phone.isEmpty ? '' : formatPhoneDisplay(s.parentPhone, s.parentPhonePrefix);
    return cell(
      pw.Row(
        children: [
          if (name.isNotEmpty) pw.Text(name, style: const pw.TextStyle(fontSize: 8.5)),
          if (name.isNotEmpty && phoneDisplay.isNotEmpty) pw.SizedBox(width: 4),
          if (phoneDisplay.isNotEmpty)
            ltr('($phoneDisplay)', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    columnWidths: const {
      0: pw.FlexColumnWidth(1),
      1: pw.FlexColumnWidth(5),
      2: pw.FlexColumnWidth(2),
      3: pw.FlexColumnWidth(3),
      4: pw.FlexColumnWidth(4),
      5: pw.FlexColumnWidth(3),
    },
    children: [
      pw.TableRow(
        children: [
          textCell('م', head: true),
          textCell('اسم الطالب الكامل', head: true),
          textCell('الجنس', head: true),
          textCell('الهاتف', head: true),
          textCell('ولي الأمر / الهاتف', head: true),
          textCell('ملاحظات / الحضور', head: true),
        ],
      ),
      if (students.isEmpty)
        pw.TableRow(
          children: [
            textCell(''),
            textCell('لا يوجد طلاب مسجلين في هذا الصف'),
            textCell(''),
            textCell(''),
            textCell(''),
            textCell(''),
          ],
        )
      else
        for (var i = 0; i < students.length; i++)
          pw.TableRow(
            children: [
              textCell('${i + 1}'),
              textCell(students[i].fullName),
              textCell(students[i].gender.trim().isEmpty ? '—' : genderLabel(students[i].gender)),
              textCell(
                students[i].phone.trim().isEmpty
                    ? '—'
                    : formatPhoneDisplay(students[i].phone, students[i].phonePrefix),
                forceLtr: true,
              ),
              parentCell(students[i]),
              textCell(''),
            ],
          ),
    ],
  );
}
