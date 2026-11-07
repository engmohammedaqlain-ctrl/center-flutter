/// الأوراق الرسمية — المقابل لـ `officialDocs.ts`: نصها بصيغة المدارس المعتادة (مذكّراً أو
/// مؤنثاً بجنس الطالب)، ورمز التحقق من السحابة (`issue_document`)، ثم PDF ورمز QR لصفحة `/v/`.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import 'printing.dart';
import 'supabase.dart';
import 'user_message.dart';

const officialDocKinds = <String, String>{
  'enrollment': 'إثبات قيد',
  'conduct': 'حسن سيرة وسلوك',
  'whom': 'لمن يهمه الأمر',
  'transfer': 'شهادة نقل',
};

const verifyBaseUrl = 'https://noonschool.app/v';

/// نص الورقة: جملة واحدة متصلة بصيغة الشهادات المدرسية — `officialDocText`.
String officialDocText({
  required String kind,
  required Student student,
  required String school,
  required String year,
  String toWhom = '',
}) {
  final f = student.gender == 'أنثى';
  String t(String m, String w) => f ? w : m;
  final who = '${t('الطالب', 'الطالبة')} ${student.fullName}'
      '${student.nationalId.isNotEmpty ? '، رقم الهوية ${student.nationalId}' : ''}';
  final where = [student.gradeLevel, student.section].where((x) => x.trim().isNotEmpty).join(' / ');
  final to = toWhom.trim();
  switch (kind) {
    case 'enrollment':
      return 'تشهد إدارة $school بأن $who ${t('مقيّد', 'مقيّدة')} لديها في $where للعام الدراسي $year، '
          '${t('وما زال', 'وما زالت')} على مقاعد الدراسة حتى تاريخه. وقد أُعطيت ${t('له', 'لها')} هذه الشهادة '
          'بناءً على طلبه${f ? 'ا' : ''} لتقديمها إلى ${to.isEmpty ? 'من يهمه الأمر' : to}.';
    case 'conduct':
      return 'تشهد إدارة $school بأن $who، ${t('المقيّد', 'المقيّدة')} لديها في $where للعام الدراسي $year، '
          '${t('حسن', 'حسنة')} السيرة والسلوك، ولم يصدر بحق${f ? 'ها' : 'ه'} ما يخل بالأنظمة المدرسية طوال فترة '
          'دراست${f ? 'ها' : 'ه'} لدينا. وقد أُعطيت ${t('له', 'لها')} هذه الشهادة بناءً على طلبه${f ? 'ا' : ''}'
          '${to.isEmpty ? '' : ' لتقديمها إلى $to'}.';
    case 'whom':
      return 'تفيد إدارة $school بأن $who ${t('مسجّل', 'مسجّلة')} لديها في $where للعام الدراسي $year. '
          'وقد أُعطيت ${t('له', 'لها')} هذه الإفادة بناءً على طلبه${f ? 'ا' : ''} لتقديمها '
          '${to.isEmpty ? 'لمن يهمه الأمر' : 'إلى $to'}، دون أدنى مسؤولية على المدرسة.';
    default:
      return 'تشهد إدارة $school بأن $who ${t('كان مقيّداً', 'كانت مقيّدة')} لديها في $where للعام الدراسي $year، '
          'وقد طلب ولي أمر${f ? 'ها' : 'ه'} نقل${f ? 'ها' : 'ه'}${to.isEmpty ? '' : ' إلى $to'}، ولا مانع لدينا من ذلك.';
  }
}

class IssuedDoc {
  const IssuedDoc({required this.serial, required this.code});

  final String serial;
  final String code;

  String get url => '$verifyBaseUrl/$code';
}

class IssuedDocRow {
  const IssuedDocRow({required this.serial, required this.kind, required this.toWhom, required this.issuedAt});

  final String serial;
  final String kind;
  final String toWhom;
  final String issuedAt;

  String get label => officialDocKinds[kind] ?? (kind == 'certificate' ? 'شهادة' : kind);
}

/// تسجيل الورقة في السحابة: رقمها التسلسلي ورمزها. يحتاج اتصالاً، فلا ورقة برقم مكرر.
Future<IssuedDoc> issueOfficialDoc(String kind, String studentId, String studentName, {String toWhom = ''}) async {
  try {
    final data = await supabaseRpcOrThrow('issue_document', {
      'p_kind': kind,
      'p_student_id': studentId,
      'p_student_name': studentName,
      'p_to_whom': toWhom.trim().isEmpty ? null : toWhom.trim(),
    });
    final map = data as Map;
    return IssuedDoc(serial: '${map['serial']}', code: '${map['code']}');
  } catch (e) {
    throw StoreException(userMessage(e, 'الأوراق الرسمية تحتاج اتصالاً بالإنترنت'));
  }
}

/// أوراق الطالب الصادرة، الأحدث أولاً؛ بلا اتصال قائمة فارغة.
Future<List<IssuedDocRow>> studentIssuedDocs(String studentId) async {
  try {
    final rows = await supabaseSelect(
      'issued_documents',
      columns: 'serial,kind,to_whom,issued_at',
      filters: {'student_id': 'eq.$studentId'},
      order: 'issued_at.desc',
      limit: 20,
    );
    return [
      for (final r in rows ?? const <Map<String, dynamic>>[])
        IssuedDocRow(
          serial: '${r['serial'] ?? ''}',
          kind: '${r['kind'] ?? ''}',
          toWhom: '${r['to_whom'] ?? ''}',
          issuedAt: '${r['issued_at'] ?? ''}',
        ),
    ];
  } catch (_) {
    return const [];
  }
}

/// رمز QR ورقم الورقة في أسفل الصفحة — `verify` في الشهادات والأوراق.
pw.Widget verifyBlock({required String serial, required String url, String label = 'رقم الوثيقة'}) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: url,
          width: 56,
          height: 56,
          color: PdfColors.black,
        ),
        pw.SizedBox(width: 8),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('$label $serial', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('امسح الرمز للتحقق من صدورها عن المدرسة', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      ],
    );

/// الورقة كاملة: إصدارها ثم بناؤها PDF — `downloadOfficialDoc`.
Future<({IssuedDoc issued, Uint8List? bytes, String label})> buildOfficialDoc({
  required String kind,
  required Student student,
  required String school,
  required String year,
  String? logo,
  String toWhom = '',
  String note = '',
  String principal = '',
}) async {
  final issued = await issueOfficialDoc(kind, student.id, student.fullName, toWhom: toWhom);
  final label = officialDocKinds[kind] ?? 'ورقة';
  final bytes = await PdfKit.buildSafe(
    title: label,
    institutionName: school,
    logoBase64: logo,
    subtitle: 'الرقم ${issued.serial} · العام الدراسي $year',
    body: (_) => [
      pw.SizedBox(height: 24),
      pw.Text(
        officialDocText(kind: kind, student: student, school: school, year: year, toWhom: toWhom),
        style: const pw.TextStyle(fontSize: 13, lineSpacing: 7),
        textAlign: pw.TextAlign.justify,
      ),
      if (note.trim().isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Text(note.trim(), style: const pw.TextStyle(fontSize: 10.5, color: PdfColors.grey800)),
      ],
      pw.SizedBox(height: 28),
      verifyBlock(serial: issued.serial, url: issued.url),
      pw.SizedBox(height: 34),
      PdfKit.signatureRow(['ختم المدرسة', principal.trim().isEmpty ? 'مدير المدرسة' : 'مدير المدرسة: ${principal.trim()}']),
    ],
  );
  return (issued: issued, bytes: bytes, label: label);
}
