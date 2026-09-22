import 'package:center_mobile/data/class_tiers.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classTier لا يجمع كل الصفوف تحت الثانوية عند غياب stage_tier', () {
    final store = AppStore.forTesting();
    injectDemoData(store);

    store.gradeFees.add(
      GradeFee(
        id: 'gf-middle',
        gradeName: 'سابع',
        monthlyFee: 100,
        tier: 'middle',
        academicYearId: store.viewedAcademicYearId,
      ),
    );

    final room = Classroom(
      id: 'r-mid',
      name: 'سابع أ',
      gradeLevel: 'سابع',
      teacherId: '',
      tier: '',
      academicYearId: store.viewedAcademicYearId,
    );

    expect(classTier(store, room), 'middle');
    expect(classTier(store, room..tier = 'secondary'), 'middle');
  });

  test('guessStageTier: ابتدائي صريح يسبق رقم الصف', () {
    expect(guessStageTier('سادس ابتدائي'), 'primary');
    expect(guessStageTier('عاشر'), 'secondary');
    expect(guessStageTier('روضة الأمل'), 'kindergarten');
  });
}
