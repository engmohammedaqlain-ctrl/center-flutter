import 'package:center_mobile/data/backup_validate.dart';
import 'package:flutter_test/flutter_test.dart';

/// فحص ملف الاسترجاع — مطابق لـ `backupValidate.ts` و`backupYears.ts` في الويب.
void main() {
  test('القواعد مولّدة لكل جداول الويب', () {
    expect(backupTableRules.keys, containsAll(['students', 'payments', 'payment_methods', 'student_sections', 'course_items']));
  });

  test('حقل إلزامي ناقص ومفتاح مكسور يرفضان الملف قبل أي كتابة', () {
    final check = validateBackupTables({
      'payments': [
        {'id': 'p1', 'student_id': 'غائب', 'amount': 50, 'payment_method': 'cash'},
      ],
    });
    expect(check.errorCount, greaterThan(0));
    final text = formatBackupIssues(check.errors);
    expect(text, contains('payment_date'));
    expect(text, contains('يشير إلى سجل غير موجود'));
  });

  test('معرّف مكرر وجدول غير معروف', () {
    final check = validateBackupTables({
      'subjects': [
        {'id': 's1', 'name': 'رياضيات'},
        {'id': 's1', 'name': 'علوم'},
      ],
      'strange': [],
    });
    expect(check.errors.any((e) => e.message.contains('مكرر')), isTrue);
    expect(check.warnings.any((w) => w.table == 'strange'), isTrue);
  });

  test('المبلغ النصي يصير رقماً', () {
    final row = normalizeBackupRow('payments', {'id': 'p', 'amount': '200'});
    expect(row['amount'], 200);
  });

  test('العام المؤقت يُستبدل بعام الجهاز بالتسمية نفسها في كل الجداول', () {
    final data = remapYearPlaceholders({
      'academicYears': [
        {'id': 'ay_@1', 'label': '2026 / 2027'},
      ],
      'students': [
        {'id': 'x', 'academic_year_id': 'ay_@1'},
      ],
    }, (label) => pickRealYearId(label, [(id: 'ay_real', label: '2026/2027')], (l) => 'det_$l'));
    expect((data['academicYears'] as List).single['id'], 'ay_real');
    expect((data['students'] as List).single['academic_year_id'], 'ay_real');
  });
}
