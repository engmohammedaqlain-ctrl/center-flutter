import 'package:center_mobile/data/institution.dart';
import 'package:flutter_test/flutter_test.dart';

/// اسم النظام ليس اسم مدرسة — كالويب (`customName` في `institution.ts`).
///
/// السجل السحابي يحمل أحياناً اسم النظام في خانة اسم المنشأة، وكانت الترويسة
/// على الجوال تعرضه مكان اسم المدرسة بينما الويب يعرض الاسم الصحيح.
void main() {
  test('اسم النظام يُعامَل كفارغ فيعود النداء إلى اسم المنشأة', () {
    expect(customInstitutionName('نون - نظام الإدارة المدرسي'), '');
    expect(customInstitutionName('نظام الإدارة المدرسي'), '');
    expect(customInstitutionName('  نون - نظام الإدارة المدرسي  '), '');
  });

  test('اسم مدرسة حقيقي يمرّ مشذّباً', () {
    expect(customInstitutionName('  مدرسة حسام الدلو الخاصة  '), 'مدرسة حسام الدلو الخاصة');
    expect(customInstitutionName('نون الدولية'), 'نون الدولية');
  });

  test('الفارغ والمعدوم فارغان', () {
    expect(customInstitutionName(null), '');
    expect(customInstitutionName('   '), '');
  });
}
