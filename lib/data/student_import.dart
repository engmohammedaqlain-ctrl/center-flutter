/// استيراد الطلاب من Excel — المقابل لـ `studentImport.ts`: أعمدة النموذج، وفحص كل سطر قبل
/// أي كتابة. المنطق بلا واجهة ولا قاعدة: يأخذ أسطر الملف وما في المدرسة، ويعيد السليم والخطأ.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'phone.dart';

const importColumns = <({String field, String header, bool required, String example})>[
  (field: 'full_name', header: 'اسم الطالب الرباعي', required: true, example: 'أحمد محمد خالد العلي'),
  (field: 'national_id', header: 'هوية الطالب', required: true, example: '412345678'),
  (field: 'grade_level', header: 'الصف', required: true, example: 'الصف الأول'),
  (field: 'section', header: 'الشعبة', required: false, example: 'أ'),
  (field: 'phone', header: 'جوال الطالب', required: false, example: '0599123456'),
  (field: 'gender', header: 'الجنس', required: false, example: 'ذكر'),
  (field: 'birth_date', header: 'تاريخ الميلاد', required: false, example: '2018-09-01'),
  (field: 'parent_name', header: 'ولي الأمر', required: false, example: 'محمد خالد العلي'),
  (field: 'parent_national_id', header: 'هوية ولي الأمر', required: false, example: '401234567'),
  (field: 'parent_phone', header: 'جوال ولي الأمر', required: false, example: '0599765432'),
  (field: 'opening_balance', header: 'رصيد سابق', required: false, example: '0'),
];

class ImportRow {
  const ImportRow({
    required this.line,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.nationalId,
    required this.gradeLevel,
    required this.section,
    required this.phone,
    required this.phonePrefix,
    required this.gender,
    required this.birthDate,
    required this.parentName,
    required this.parentNationalId,
    required this.parentPhone,
    required this.parentPhonePrefix,
    required this.openingBalance,
  });

  /// رقم السطر في الملف كما يراه المدير (الترويسة سطر 1).
  final int line;
  final String fullName;
  final String firstName;
  final String lastName;
  final String nationalId;
  final String gradeLevel;
  final String section;
  final String phone;
  final String phonePrefix;
  final String gender;
  final String birthDate;
  final String parentName;
  final String parentNationalId;
  final String parentPhone;
  final String parentPhonePrefix;
  final double openingBalance;
}

class ImportIssue {
  const ImportIssue({required this.line, required this.column, required this.value, required this.message});

  final int line;
  final String column;
  final String value;
  final String message;
}

class ImportCheck {
  const ImportCheck({this.rows = const [], this.issues = const [], this.missingColumns = const [], this.total = 0});

  final List<ImportRow> rows;
  final List<ImportIssue> issues;

  /// أعمدة إلزامية غائبة عن الترويسة: تنبيه واحد بدل خطأ في كل سطر.
  final List<String> missingColumns;

  /// كل الأسطر غير الفارغة.
  final int total;
}

String _norm(Object? v) => '${v ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
String _key(String v) => _norm(v).toLowerCase();
String _digits(String v) => digitsOnly(v);

/// تاريخ من خلية: نص yyyy-mm-dd أو d/m/yyyy، أو رقم تاريخ Excel — `cellDate`.
String? cellDate(String v) {
  final s = _norm(v);
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
  if (m != null) return '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(s);
  if (m != null) return '${m[3]}-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}';
  final serial = double.tryParse(s);
  if (serial != null && serial > 10000 && serial < 80000) {
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
  return null;
}

bool isValidStudentPhone(String phone) {
  final d = _digits(phone);
  return RegExp(r'^05\d{8}$').hasMatch(d) || RegExp(r'^97[02]\d{9}$').hasMatch(d) || RegExp(r'^20\d{10}$').hasMatch(d);
}

/// جوال من خلية: Excel يسقط الصفر الأول من الأرقام (599123456).
({String phone, String prefix})? _cellPhone(String v) {
  final raw = v.replaceAll(RegExp(r'[\s-]'), '');
  if (raw.isEmpty) return null;
  final phone = combinePhoneAndPrefix(raw, '059');
  return isValidStudentPhone(phone) ? (phone: phone, prefix: parsePhoneAndPrefix(phone).prefix) : null;
}

/// يفحص أسطر الملف — `checkImport`: الأول ترويسة، والباقي طلاب. سطر فارغ يُتجاهل، والخطأ يُسجَّل
/// بسطره وعموده وقيمته، والسطر الخاطئ لا يدخل السليم.
ImportCheck checkImport(
  List<List<String>> sheet, {
  required List<String> grades,
  required Map<String, List<String>> sections,
  required Set<String> existingIds,
}) {
  final header = [for (final h in sheet.isEmpty ? const <String>[] : sheet.first) _key(h)];
  final col = <String, int>{};
  for (final c in importColumns) {
    final i = header.indexOf(_key(c.header));
    if (i >= 0) col[c.field] = i;
  }
  final missing = [for (final c in importColumns) if (c.required && !col.containsKey(c.field)) c.header];
  if (missing.isNotEmpty) return ImportCheck(missingColumns: missing);

  final gradeByKey = {for (final g in grades) _key(g): g};
  final seenIds = <String, int>{};
  final rows = <ImportRow>[];
  final issues = <ImportIssue>[];
  var total = 0;

  for (var idx = 1; idx < sheet.length; idx++) {
    final cells = sheet[idx];
    final line = idx + 1;
    String get(String f) {
      final i = col[f];
      return i != null && i < cells.length ? cells[i] : '';
    }

    if (cells.every((c) => _norm(c).isEmpty)) continue;
    total++;
    final bad = <ImportIssue>[];
    void flag(String field, String value, String message) => bad.add(ImportIssue(
          line: line,
          column: importColumns.firstWhere((c) => c.field == field).header,
          value: _norm(value),
          message: message,
        ));

    final fullName = _norm(get('full_name'));
    final parts = fullName.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) flag('full_name', fullName, fullName.isEmpty ? 'الاسم فارغ' : 'الاسم ناقص');

    final nationalId = _digits(_norm(get('national_id')));
    if (!RegExp(r'^\d{9}$').hasMatch(nationalId)) {
      flag('national_id', get('national_id'), 'الهوية 9 أرقام');
    } else if (existingIds.contains(nationalId)) {
      flag('national_id', nationalId, 'مسجّل مسبقاً');
    } else if (seenIds.containsKey(nationalId)) {
      flag('national_id', nationalId, 'مكررة مع سطر ${seenIds[nationalId]}');
    } else {
      seenIds[nationalId] = line;
    }

    final grade = gradeByKey[_key(get('grade_level'))];
    if (grade == null) {
      flag('grade_level', get('grade_level'), _norm(get('grade_level')).isEmpty ? 'الصف فارغ' : 'الصف غير موجود');
    }

    final section = _norm(get('section'));
    if (section.isNotEmpty && grade != null && !(sections[grade] ?? const []).any((s) => _key(s) == _key(section))) {
      flag('section', section, 'الشعبة غير موجودة في هذا الصف');
    }

    final parentPhoneRaw = _norm(get('parent_phone'));
    final parentPhone = parentPhoneRaw.isEmpty ? null : _cellPhone(parentPhoneRaw);
    if (parentPhoneRaw.isNotEmpty && parentPhone == null) flag('parent_phone', parentPhoneRaw, 'رقم غير صالح');

    // جوال الطالب: رقمه، وإلا رقم ولي أمره كما يفعل الإخوة الصغار
    final phoneRaw = _norm(get('phone'));
    final phone = phoneRaw.isNotEmpty ? _cellPhone(phoneRaw) : parentPhone;
    if (phoneRaw.isNotEmpty && phone == null) {
      flag('phone', phoneRaw, 'رقم غير صالح');
    } else if (phone == null && parentPhoneRaw.isEmpty) {
      flag('phone', '', 'جوال الطالب أو ولي الأمر مطلوب');
    }

    final gender = _norm(get('gender'));
    if (gender.isNotEmpty && gender != 'ذكر' && gender != 'أنثى') flag('gender', gender, 'ذكر أو أنثى');

    final birthRaw = _norm(get('birth_date'));
    final birth = birthRaw.isEmpty ? null : cellDate(birthRaw);
    if (birthRaw.isNotEmpty && birth == null) flag('birth_date', birthRaw, 'تاريخ غير مفهوم');

    final parentId = _digits(_norm(get('parent_national_id')));
    if (parentId.isNotEmpty && !RegExp(r'^\d{9}$').hasMatch(parentId)) {
      flag('parent_national_id', get('parent_national_id'), 'الهوية 9 أرقام');
    }

    final balanceRaw = _norm(get('opening_balance')).replaceAll(',', '');
    final balance = balanceRaw.isEmpty ? 0.0 : double.tryParse(balanceRaw);
    if (balance == null || balance < 0) flag('opening_balance', balanceRaw, 'مبلغ غير صالح');

    if (bad.isNotEmpty) {
      issues.addAll(bad);
      continue;
    }
    rows.add(ImportRow(
      line: line,
      fullName: fullName,
      firstName: parts.first,
      lastName: parts.last,
      nationalId: nationalId,
      gradeLevel: grade!,
      section: section.isEmpty ? '' : (sections[grade] ?? const []).firstWhere((s) => _key(s) == _key(section)),
      phone: phone!.phone,
      phonePrefix: phone.prefix,
      gender: gender,
      birthDate: birth ?? '',
      parentName: _norm(get('parent_name')),
      parentNationalId: parentId,
      parentPhone: parentPhone?.phone ?? '',
      parentPhonePrefix: parentPhone?.prefix ?? '059',
      openingBalance: (balance! * 100).round() / 100,
    ));
  }
  return ImportCheck(rows: rows, issues: issues, total: total);
}

/// رقم العمود من مرجع الخلية: A1 ← 0، AB3 ← 27.
int _columnOf(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u < 65 || u > 90) break;
    n = n * 26 + (u - 64);
  }
  return n - 1;
}

/// أسطر الورقة الأولى من ملف xlsx كنصوص كما خُزّنت.
List<List<String>> readXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? textOf(String name) {
    final f = archive.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  final shared = <String>[];
  final sharedXml = textOf('xl/sharedStrings.xml');
  if (sharedXml != null) {
    for (final si in XmlDocument.parse(sharedXml).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final sheetXml = textOf('xl/worksheets/sheet1.xml');
  if (sheetXml == null) throw const FormatException('الملف ليس xlsx صالحاً');

  final out = <List<String>>[];
  for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
    final number = int.tryParse(row.getAttribute('r') ?? '') ?? out.length + 1;
    while (out.length < number) {
      out.add(<String>[]);
    }
    final cells = out[number - 1];
    for (final c in row.findElements('c')) {
      final i = _columnOf(c.getAttribute('r') ?? 'A');
      while (cells.length <= i) {
        cells.add('');
      }
      final type = c.getAttribute('t');
      final v = c.findElements('v').map((e) => e.innerText).join();
      if (type == 's') {
        final at = int.tryParse(v) ?? -1;
        cells[i] = at >= 0 && at < shared.length ? shared[at] : '';
      } else if (type == 'inlineStr') {
        cells[i] = c.findAllElements('t').map((t) => t.innerText).join();
      } else {
        cells[i] = v;
      }
    }
  }
  return out;
}

String _columnName(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _esc(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// ملف xlsx بسيط بورقة واحدة: كل الخلايا نص، فلا يسقط Excel أصفار الهوية والجوال.
Uint8List writeXlsx(List<List<String>> rows, {String sheetName = 'الطلاب'}) => writeXlsxBook({sheetName: rows});

/// اسم ورقة يقبله Excel: 31 حرفاً بلا الرموز الممنوعة، وبلا تكرار.
String _sheetName(String raw, Set<String> used) {
  var base = raw.replaceAll(RegExp(r'[\\/?*\[\]:]'), '-').trim();
  if (base.isEmpty) base = 'ورقة';
  if (base.length > 28) base = base.substring(0, 28);
  var name = base;
  for (var i = 2; !used.add(name); i++) {
    name = '$base $i';
  }
  return name;
}

/// ملف xlsx بأوراق: اسم الورقة ← صفوفها، وكل الخلايا نص.
Uint8List writeXlsxBook(Map<String, List<List<String>>> sheets) {
  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  final used = <String>{};
  final names = [for (final k in sheets.keys) _sheetName(k, used)];
  final bodies = sheets.values.toList();
  final files = <String, String>{
    '[Content_Types].xml': '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '${[for (var i = 0; i < names.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
    '_rels/.rels': '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '$head<workbook xmlns="$main" xmlns:r="$rel"><sheets>'
        '${[for (var i = 0; i < names.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < names.length; i++) '<Relationship Id="rId${i + 1}" Type="$rel/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '</Relationships>',
  };
  for (var s = 0; s < names.length; s++) {
    final rows = bodies[s];
    final data = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      data.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        data.write('<c r="${_columnName(c)}${r + 1}" t="inlineStr"><is><t xml:space="preserve">${_esc(rows[r][c])}</t></is></c>');
      }
      data.write('</row>');
    }
    files['xl/worksheets/sheet${s + 1}.xml'] = '$head<worksheet xmlns="$main">'
        '<sheetViews><sheetView rightToLeft="1" workbookViewId="0"/></sheetViews><sheetData>$data</sheetData></worksheet>';
  }
  final archive = Archive();
  files.forEach((name, text) {
    final encoded = utf8.encode(text);
    archive.addFile(ArchiveFile(name, encoded.length, encoded));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
