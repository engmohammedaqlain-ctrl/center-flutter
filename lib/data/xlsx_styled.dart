/// ملف Excel منسّق كالويب (`xlsxExport.ts`): ورقة من اليمين لليسار، واسم المدرسة عنواناً مدموجاً
/// بشعارها، ثم عنوان الكشف وتفاصيله، ثم رأس جدول ملوّن مثبّت يتكرر في الطباعة، وحدود وعروض أعمدة
/// مناسبة وصفوف متناوبة اللون، والأرقام أرقام فعلية. مكتوب بـ XML مباشرة بلا مكتبة.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

/// ألوان نون (ARGB) — `COLOR`.
const _ink = 'FF0A3336';
const _teal = 'FF128A91';
const _mist = 'FFDDF1F0';
const _band = 'FFF4F7F7';
const _line = 'FFB9CFCD';
const _muted = 'FF51696B';
const _white = 'FFFFFFFF';

/// كشف واحد — `SheetData`. [head] صفوف رأس الجدول (واحد عادةً)، و[headMerges] دمج داخله
/// (صف بداية، عمود بداية، صف نهاية، عمود نهاية) من صفر.
class StyledSheet {
  const StyledSheet({
    required this.title,
    required this.headers,
    required this.rows,
    this.tab,
    this.details = const [],
    this.landscape = false,
    this.head,
    this.headMerges = const [],
    this.nameColumn = 1,
  });

  final String title;
  final String? tab;
  final List<String> details;
  final List<String> headers;
  final List<List<Object?>> rows;
  final bool landscape;
  final List<List<String>>? head;
  final List<(int, int, int, int)> headMerges;

  /// عمود الاسم يُحاذى يميناً (الثاني افتراضاً كالويب)؛ -1 بلا.
  final int nameColumn;

  List<List<String>> get headRows => head ?? [headers];
}

String _esc(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _col(int index) {
  var n = index + 1;
  var out = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// رقم يُكتب رقماً: لا الهوية ولا الجوال (صفر في أوله) ولا الطويل.
num? _asNumber(Object? v) {
  if (v is num) return v;
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty || s.length > 12 || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) return null;
  final digits = s.startsWith('-') ? s.substring(1) : s;
  if (digits.length > 1 && digits.startsWith('0') && !digits.startsWith('0.')) return null;
  return num.tryParse(s);
}

String _text(Object? v) => v == null ? '' : (v is double && v == v.roundToDouble() ? '${v.toInt()}' : '$v');

/// عرض كل عمود بعدد حروف أطول خلية فيه بين حدّين — `columnWidths`.
List<double> _widths(StyledSheet s) {
  final cols = s.headers.length;
  return [
    for (var c = 0; c < cols; c++)
      () {
        var longest = 0;
        for (final r in s.headRows) {
          if (c < r.length) longest = math.max(longest, r[c].length);
        }
        for (final r in s.rows) {
          if (c < r.length) longest = math.max(longest, _text(r[c]).length);
        }
        return math.min(40, math.max(4, (longest * 1.25).ceil() + 2)).toDouble();
      }(),
  ];
}

/// اسم ورقة يقبله Excel: 31 حرفاً بلا الرموز الممنوعة، وفريد.
String _sheetName(String raw, Set<String> used) {
  var base = raw.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
  if (base.isEmpty) base = 'كشف';
  if (base.length > 31) base = base.substring(0, 31);
  var name = base;
  for (var n = 2; !used.add(name); n++) {
    name = '${base.length > 27 ? base.substring(0, 27) : base} ($n)';
  }
  return name;
}

const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="6">'
    '<font><sz val="11"/><name val="Arial"/></font>'
    '<font><b/><sz val="16"/><color rgb="$_white"/><name val="Arial"/></font>'
    '<font><b/><sz val="13"/><color rgb="$_ink"/><name val="Arial"/></font>'
    '<font><sz val="11"/><color rgb="$_muted"/><name val="Arial"/></font>'
    '<font><b/><sz val="11"/><color rgb="$_white"/><name val="Arial"/></font>'
    '<font><b/><sz val="11"/><color rgb="$_ink"/><name val="Arial"/></font>'
    '</fonts>'
    '<fills count="6">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="$_ink"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="$_mist"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="$_teal"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="$_band"/></patternFill></fill>'
    '</fills>'
    '<borders count="2"><border/>'
    '<border><left style="thin"><color rgb="$_line"/></left><right style="thin"><color rgb="$_line"/></right>'
    '<top style="thin"><color rgb="$_line"/></top><bottom style="thin"><color rgb="$_line"/></bottom></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
    '<cellXfs count="9">'
    '<xf/>'
    // 1 اسم المدرسة
    '<xf fontId="1" fillId="2" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>'
    // 2 عنوان الكشف
    '<xf fontId="2" fillId="3" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>'
    // 3 التفاصيل
    '<xf fontId="3" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>'
    // 4 رأس الجدول
    '<xf fontId="4" fillId="4" borderId="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1" readingOrder="2"/></xf>'
    // 5 خلية وسطاً، 6 مع شريط، 7 الاسم يميناً، 8 الاسم مع شريط
    '<xf borderId="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>'
    '<xf fillId="5" borderId="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" readingOrder="2"/></xf>'
    '<xf fontId="5" borderId="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" readingOrder="2"/></xf>'
    '<xf fontId="5" fillId="5" borderId="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" readingOrder="2"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

/// الشعار من رابط `data:` أو base64: بايتاته ونوعه ونسبته، و`null` إن تعذّر.
({Uint8List bytes, String ext, double ratio})? _logo(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final comma = raw.indexOf(',');
    final bytes = base64Decode(comma >= 0 ? raw.substring(comma + 1) : raw);
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.height == 0) return null;
    // PNG دائماً: Excel يقبله أياً كان أصل الشعار
    return (bytes: Uint8List.fromList(img.encodePng(decoded)), ext: 'png', ratio: decoded.width / decoded.height);
  } catch (_) {
    return null;
  }
}

/// ملف Excel منسّق بورقة أو أكثر — `buildBookWorkbook`.
Uint8List styledXlsx(List<StyledSheet> sheets, {required String school, String? logo}) {
  const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const pkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
  final picture = _logo(logo);
  final used = <String>{};
  final names = [for (final s in sheets) _sheetName(s.tab ?? s.title, used)];
  final files = <String, List<int>>{};
  final definedNames = StringBuffer();

  for (var i = 0; i < sheets.length; i++) {
    final s = sheets[i];
    final cols = math.max(1, s.headers.length);
    final last = _col(cols - 1);
    final data = StringBuffer();
    final merges = <String>[];
    var row = 0;

    void banner(String value, int style, double height) {
      row++;
      data.write('<row r="$row" ht="$height" customHeight="1"><c r="A$row" s="$style" t="inlineStr"><is><t xml:space="preserve">${_esc(value)}</t></is></c>');
      for (var c = 1; c < cols; c++) {
        data.write('<c r="${_col(c)}$row" s="$style"/>');
      }
      data.write('</row>');
      if (cols > 1) merges.add('A$row:$last$row');
    }

    banner(school, 1, 38);
    banner(s.title, 2, 26);
    final details = s.details.where((d) => d.trim().isNotEmpty).join('  •  ');
    if (details.isNotEmpty) banner(details, 3, 22);
    row++;
    data.write('<row r="$row" ht="8" customHeight="1"/>');

    final headStart = row + 1;
    for (final h in s.headRows) {
      row++;
      data.write('<row r="$row" ht="24" customHeight="1">');
      for (var c = 0; c < cols; c++) {
        final v = c < h.length ? h[c] : '';
        data.write(v.isEmpty
            ? '<c r="${_col(c)}$row" s="4"/>'
            : '<c r="${_col(c)}$row" s="4" t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
      }
      data.write('</row>');
    }
    final headEnd = row;
    for (final (r1, c1, r2, c2) in s.headMerges) {
      merges.add('${_col(c1)}${headStart + r1}:${_col(c2)}${headStart + r2}');
    }

    for (var r = 0; r < s.rows.length; r++) {
      row++;
      final band = r.isOdd;
      data.write('<row r="$row" ht="20" customHeight="1">');
      for (var c = 0; c < cols; c++) {
        final v = c < s.rows[r].length ? s.rows[r][c] : null;
        final isName = c == s.nameColumn && cols > 2;
        final style = isName ? (band ? 8 : 7) : (band ? 6 : 5);
        final ref = '${_col(c)}$row';
        final n = _asNumber(v);
        final text = _text(v);
        if (n != null) {
          data.write('<c r="$ref" s="$style"><v>$n</v></c>');
        } else if (text.isEmpty) {
          data.write('<c r="$ref" s="$style"/>');
        } else {
          data.write('<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_esc(text)}</t></is></c>');
        }
      }
      data.write('</row>');
    }

    final widths = _widths(s);
    final colsXml = StringBuffer('<cols>');
    for (var c = 0; c < widths.length; c++) {
      colsXml.write('<col min="${c + 1}" max="${c + 1}" width="${widths[c]}" customWidth="1"/>');
    }
    colsXml.write('</cols>');
    final mergeXml = merges.isEmpty ? '' : '<mergeCells count="${merges.length}">${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>';
    final hasLogo = picture != null;
    files['xl/worksheets/sheet${i + 1}.xml'] = utf8.encode(
      '$head<worksheet xmlns="$main" xmlns:r="$rel">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<sheetViews><sheetView rightToLeft="1" showGridLines="0" workbookViewId="0">'
      '<pane ySplit="$headEnd" topLeftCell="A${headEnd + 1}" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="15"/>'
      '$colsXml<sheetData>$data</sheetData>$mergeXml'
      '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>'
      '<pageSetup paperSize="9" orientation="${s.landscape ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>'
      '${hasLogo ? '<drawing r:id="rId1"/>' : ''}'
      '</worksheet>',
    );
    // رأس الجدول يتكرر في كل صفحة مطبوعة
    definedNames.write('<definedName name="_xlnm.Print_Titles" localSheetId="$i">\'${_esc(names[i].replaceAll("'", "''"))}\'!\$$headStart:\$$headEnd</definedName>');
    if (hasLogo) {
      const height = 32;
      final width = (height * math.min(picture.ratio, 3)).round();
      files['xl/worksheets/_rels/sheet${i + 1}.xml.rels'] = utf8.encode(
        '$head<Relationships xmlns="$pkgRel"><Relationship Id="rId1" Type="$rel/drawing" Target="../drawings/drawing${i + 1}.xml"/></Relationships>',
      );
      files['xl/drawings/drawing${i + 1}.xml'] = utf8.encode(
        '$head<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$rel">'
        '<xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>76200</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>38100</xdr:rowOff></xdr:from>'
        '<xdr:ext cx="${width * 9525}" cy="${height * 9525}"/>'
        '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="2" name="logo"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
        '<xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
        '<xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>',
      );
      files['xl/drawings/_rels/drawing${i + 1}.xml.rels'] = utf8.encode(
        '$head<Relationships xmlns="$pkgRel"><Relationship Id="rId1" Type="$rel/image" Target="../media/logo.${picture.ext}"/></Relationships>',
      );
    }
  }
  if (picture != null) files['xl/media/logo.${picture.ext}'] = picture.bytes;

  files['[Content_Types].xml'] = utf8.encode(
    '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
    '${picture == null ? '' : [for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/drawings/drawing${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'].join()}'
    '</Types>',
  );
  files['_rels/.rels'] = utf8.encode(
    '$head<Relationships xmlns="$pkgRel"><Relationship Id="rId1" Type="$rel/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  files['xl/workbook.xml'] = utf8.encode(
    '$head<workbook xmlns="$main" xmlns:r="$rel"><sheets>'
    '${[for (var i = 0; i < names.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets><definedNames>$definedNames</definedNames></workbook>',
  );
  files['xl/_rels/workbook.xml.rels'] = utf8.encode(
    '$head<Relationships xmlns="$pkgRel">'
    '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="$rel/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
    '<Relationship Id="rId${sheets.length + 1}" Type="$rel/styles" Target="styles.xml"/>'
    '</Relationships>',
  );
  files['xl/styles.xml'] = utf8.encode(_styles);

  final archive = Archive();
  files.forEach((name, bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
