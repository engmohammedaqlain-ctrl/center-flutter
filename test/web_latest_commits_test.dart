import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

void main() {
  group('كوميتات الويب الأخيرة', () {
    test('تكرار الجوال مسموح بـ allowDuplicatePhone', () {
      final s = _seeded();
      final first = Student(
        id: s.newId(),
        fullName: 'الطالب الأول',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599111000',
        phonePrefix: '059',
        parentName: 'ولي',
        parentPhone: '0598111000',
        balance: 0,
        nationalId: '111111111',
      );
      s.upsertStudent(first, isNew: true);

      final sibling = Student(
        id: s.newId(),
        fullName: 'الطالب الثاني',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599111000',
        phonePrefix: '059',
        parentName: 'ولي',
        parentPhone: '0598111000',
        balance: 0,
        nationalId: '222222222',
      );
      expect(
        () => s.upsertStudent(sibling, isNew: true),
        throwsA(isA<StoreException>()),
      );
      s.upsertStudent(sibling, isNew: true, allowDuplicatePhone: true);
      expect(s.students.where((stu) => stu.phone.contains('9111000')).length, 2);
    });

    test('خطة مخصصة عند التسجيل تستخدم معرّفات custom_', () {
      final s = _seeded();
      final student = Student(
        id: s.newId(),
        fullName: 'طالب مخصص',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599333444',
        phonePrefix: '059',
        parentName: 'ولي',
        parentPhone: '0598333444',
        balance: 0,
        nationalId: '333333333',
      );
      final schedule = [
        PlanItem(id: 'slot_1', title: 'قسط مخصص 1', amount: 80, dueDate: '2026-10-01'),
        PlanItem(id: 'slot_2', title: 'قسط مخصص 2', amount: 80, dueDate: '2026-11-01'),
      ];
      s.upsertStudent(student, isNew: true, customPlanItems: schedule);
      expect(student.usesCustomPlan, isTrue);
      final own = s.installments.where((i) => i.studentId == student.id && !isSeatInstallmentTitle(i.title)).toList();
      expect(own, hasLength(2));
      expect(own.every((i) => isCustomInstallmentId(i.id)), isTrue);
    });

    test('buildStudentPlan مع customIds لا يستخدم plan_', () {
      final rows = buildStudentPlan(
        [PlanItem(id: 'slot_1', title: 'ق', amount: 50, dueDate: '2026-10-01')],
        'stu1',
        customIds: true,
      );
      expect(rows.single.id, startsWith('custom_'));
    });
  });
}
