import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:center_mobile/data/xlsx_styled.dart';
import 'package:flutter_test/flutter_test.dart';

String _file(List<int> zip, String name) =>
    utf8.decode(ZipDecoder().decodeBytes(zip).files.firstWhere((f) => f.name == name).content as List<int>);

void main() {
  test('Excel منسّق كالويب: عنوان مدموج ورأس مثبّت، والأرقام أرقام والجوال نص', () {
    final bytes = styledXlsx([
      const StyledSheet(
        title: 'كشف العلامات',
        details: ['الرياضيات', 'السابع'],
        headers: ['#', 'الاسم', 'الجوال', 'العلامة'],
        rows: [
          ['1', 'ريم', '0599123456', '85'],
          ['2', 'يوسف', '0599000000', '72.5'],
        ],
      ),
    ], school: 'مدرسة نون');
    final sheet = _file(bytes, 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('<mergeCell ref="A1:D1"/>'));
    expect(sheet, contains('rightToLeft="1"'));
    expect(sheet, contains('state="frozen"'));
    expect(sheet, contains('<v>85</v>'));
    expect(sheet, contains('<v>72.5</v>'));
    expect(sheet, contains('0599123456</t>'));
    expect(_file(bytes, 'xl/styles.xml'), contains('FF128A91'));
    expect(_file(bytes, 'xl/workbook.xml'), contains('_xlnm.Print_Titles'));
  });

  test('أسماء الأوراق فريدة، والرأس من صفين يُدمج', () {
    final bytes = styledXlsx([
      const StyledSheet(title: 'جدول', headers: ['أ', 'ب'], rows: []),
      const StyledSheet(
        title: 'جدول',
        headers: ['المعلم', '1', '2'],
        head: [
          ['المعلم', 'السبت', ''],
          ['', '1', '2'],
        ],
        headMerges: [(0, 0, 1, 0), (0, 1, 0, 2)],
        rows: [],
      ),
    ], school: 'م');
    final book = _file(bytes, 'xl/workbook.xml');
    expect(book, contains('name="جدول"'));
    expect(book, contains('name="جدول (2)"'));
    final sheet2 = _file(bytes, 'xl/worksheets/sheet2.xml');
    expect(sheet2, contains('<mergeCell ref="A4:A5"/>'));
    expect(sheet2, contains('<mergeCell ref="B4:C4"/>'));
  });
}
