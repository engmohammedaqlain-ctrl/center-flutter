import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

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
    final parentPhone = s.parentPhone.trim().isEmpty ? s.phone : s.parentPhone;
    cells.add('$absences');
    cells.add(parentPhone);
    cells.add('');
    rows.add(cells);
  }

  final dayFlex = List<int>.filled(week.length, 2);
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
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('المعلم / مربي الصف: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('المشرف الإداري: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('مدير المركز / الختم الرسمي: ....................', style: const pw.TextStyle(fontSize: 9)),
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
  final rows = [
    for (var i = 0; i < students.length; i++)
      [
        '${i + 1}',
        students[i].fullName,
        students[i].nationalId,
        students[i].parentName,
        students[i].parentPhone.isEmpty ? students[i].phone : students[i].parentPhone,
        students[i].isDebtor ? money(students[i].balance) : 'خالص',
        '',
      ],
  ];

  final bytes = await PdfKit.build(
    title: 'كشف طلاب الصف — ${room.name}',
    institutionName: store.institutionName,
    logoBase64: store.institutionLogo,
    subtitle: [
      if (room.gradeLevel.isNotEmpty) 'المرحلة: ${room.gradeLevel}',
      if (teacher != null) 'المربي: ${teacher.name}',
      'عدد الطلاب: ${students.length} من ${room.capacity}',
    ].join('   ·   '),
    body: (ctx) => [
      PdfKit.table(
        headers: ['#', 'اسم الطالب', 'رقم الهوية', 'ولي الأمر', 'الهاتف', 'المستحق', 'التوقيع'],
        rows: rows,
        flex: [1, 6, 3, 4, 3, 2, 3],
      ),
      if (room.notes.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text('ملاحظات: ${room.notes}', style: const pw.TextStyle(fontSize: 9)),
      ],
      pw.SizedBox(height: 22),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('توقيع المربي: ....................', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('ختم وتوقيع الإدارة: ....................', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    ],
  );

  if (!context.mounted) return;
  await PdfKit.preview(bytes, PdfKit.fileName('كشف طلاب ${room.name}'));
}
