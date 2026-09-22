import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/printing.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

/// طباعة كشوف كلمات مرور البوابة — طلاب / أولياء / كلاهما.
Future<void> printPortalPasswords(
  BuildContext context, {
  required AppStore store,
  required Classroom room,
  required List<Student> students,
  required String mode, // students | parents | both
}) {
  return runBusyOp(context, () async {
    final logo = PdfKit.decodeImage(store.institutionLogo);
    final title = switch (mode) {
      'students' => 'كشف كلمات مرور الطلاب',
      'parents' => 'كشف كلمات مرور أولياء الأمور',
      _ => 'كشف كلمات مرور البوابة',
    };

    late final List<dynamic> headers;
    late final List<List<String>> rows;
    late final List<int> flex;
    late final Set<int> ltrColumns;
    late final Set<int> accentColumns;

    if (mode == 'students') {
      headers = const ['م', 'اسم الطالب', 'رقم الهوية', 'كلمة المرور'];
      flex = const [1, 5, 4, 3];
      ltrColumns = const {2, 3};
      accentColumns = const {3};
      rows = [
        for (var i = 0; i < students.length; i++)
          [
            '${i + 1}',
            students[i].fullName,
            students[i].nationalId.trim().isEmpty ? '-' : students[i].nationalId.trim(),
            students[i].portalCode.trim().isEmpty ? '-' : students[i].portalCode.trim(),
          ],
      ];
    } else if (mode == 'parents') {
      headers = const ['م', 'اسم الطالب', 'ولي الأمر', 'رقم هوية ولي الأمر', 'كلمة المرور'];
      flex = const [1, 4, 3, 4, 3];
      ltrColumns = const {3, 4};
      accentColumns = const {4};
      rows = [
        for (var i = 0; i < students.length; i++)
          [
            '${i + 1}',
            students[i].fullName,
            students[i].parentName.trim().isEmpty ? '-' : students[i].parentName.trim(),
            students[i].parentNationalId.trim().isEmpty ? '-' : students[i].parentNationalId.trim(),
            students[i].parentPortalCode.trim().isEmpty ? '-' : students[i].parentPortalCode.trim(),
          ],
      ];
    } else {
      headers = const ['م', 'اسم الطالب', 'هوية الطالب', 'مرور الطالب', 'هوية ولي الأمر', 'مرور ولي الأمر'];
      flex = const [1, 4, 3, 3, 3, 3];
      ltrColumns = const {2, 3, 4, 5};
      accentColumns = const {3, 5};
      rows = [
        for (var i = 0; i < students.length; i++)
          [
            '${i + 1}',
            students[i].fullName,
            students[i].nationalId.trim().isEmpty ? '-' : students[i].nationalId.trim(),
            students[i].portalCode.trim().isEmpty ? '-' : students[i].portalCode.trim(),
            students[i].parentNationalId.trim().isEmpty ? '-' : students[i].parentNationalId.trim(),
            students[i].parentPortalCode.trim().isEmpty ? '-' : students[i].parentPortalCode.trim(),
          ],
      ];
    }

    final bytes = await PdfKit.buildSafe(
      title: title,
      institutionName: store.institutionName,
      logoBase64: store.institutionLogo,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          PdfKit.docHeader(
            institution: store.institutionName,
            title: title,
            academicYearLabel: academicYear(),
            dateLabel: isoDate(DateTime.now()),
            logo: logo,
          ),
          PdfKit.metaRow([
            'الصف / الشعبة: ${room.name}${room.gradeLevel.isNotEmpty ? ' - ${room.gradeLevel}' : ''}',
            'إجمالي الطلاب: ${students.length} طالب',
          ]),
        ],
      ),
      body: (_) => [
        PdfKit.table(
          headers: headers,
          rows: rows,
          flex: flex,
          ltrColumns: ltrColumns,
          accentColumns: accentColumns,
        ),
      ],
      endMatter: [
        PdfKit.signatureRow(const [
          'إدارة المدرسة',
          'مسؤول النظام',
          'الختم الرسمي',
        ]),
      ],
    );

    if (!context.mounted) return;
    if (bytes == null) {
      showAppSnack(context, 'تعذّر تجهيز كشف كلمات المرور', error: true);
      return;
    }
    try {
      await PdfKit.preview(bytes, PdfKit.fileName('$title ${room.name}'));
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر تنزيل الكشف', error: true);
    }
  }, message: 'جارٍ تجهيز كشف كلمات المرور...');
}
