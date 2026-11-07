import 'package:center_mobile/data/school_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('العطل الهجرية بتقويم أم القرى كالويب: الفطر والأضحى ورأس السنة 1446-1447', () {
    final list = officialHolidays('2025-03-01', '2025-07-01');
    String? fromOf(String title) => list.where((h) => h.title == title).firstOrNull?.from;
    expect(fromOf('عيد الفطر'), '2025-03-30');
    expect(list.firstWhere((h) => h.title == 'عيد الفطر').to, '2025-04-01');
    expect(fromOf('عيد الأضحى'), '2025-06-06');
    expect(fromOf('رأس السنة الهجرية'), '2025-06-26');
    expect(fromOf('عيد العمال'), '2025-05-01');
  });
}
