/// يولّد PDFs المعاينة الستة تحت Docs/out — شغّله من جذر المشروع:
/// `dart run Docs/generate_previews.dart`
library;

import 'reports/01_attendance_report.dart';
import 'reports/02_class_roster_report.dart';
import 'reports/03_passwords_students.dart';
import 'reports/04_passwords_parents.dart';
import 'reports/05_passwords_both.dart';
import 'reports/06_grades_report.dart';

Future<void> main() async {
  final files = await Future.wait([
    buildAttendancePreview(),
    buildClassRosterPreview(),
    buildPasswordsStudentsPreview(),
    buildPasswordsParentsPreview(),
    buildPasswordsBothPreview(),
    buildGradesPreview(),
  ]);

  // ignore: avoid_print
  print('تم توليد ${files.length} كشوفاً للمعاينة:');
  for (final f in files) {
    // ignore: avoid_print
    print(' - ${f.path}');
  }
  // ignore: avoid_print
  print('\nراجع Docs/out ثم وافق بـ «اه» قبل الدمج في التطبيق.');
}
