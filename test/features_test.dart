import 'package:center_mobile/data/features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeFeatures يتجاهل المفاتيح المجهولة وغير البوليانية', () {
    expect(
      normalizeFeatures({
        'attendance': false,
        'unknown': true,
        'evaluations': 'yes',
      }),
      {'attendance': false},
    );
  });

  test('resolveFeatures يطفئ التابع عند تعطيل المتطلب', () {
    final state = resolveFeatures({
      'moodle': false,
      'portal.teacher': true,
      'portal.teacher.moodle': true,
    });
    expect(state['portal.teacher'], isTrue);
    expect(state['portal.teacher.moodle'], isFalse);
  });

  test('familyPortalTabs يبقي المواد دائماً', () {
    final tabs = familyPortalTabs(resolveFeatures({'portal.attendance': false}), isParent: true);
    expect(tabs, contains('subjects'));
    expect(tabs, isNot(contains('attendance')));
  });

  test('normalizeLimits يحذف غير الموجب', () {
    final limits = normalizeLimits({'max_students': '250', 'max_storage_mb': 0});
    expect(limits.maxStudents, 250);
    expect(limits.maxStorageMb, isNull);
  });
}
