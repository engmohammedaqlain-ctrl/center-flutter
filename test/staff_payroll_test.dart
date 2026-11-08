import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// رواتب الإدارة: الموظف يُضاف للرواتب من المستخدمين، فيظهر في الرواتب ويغيب عن المعلمين
/// — مطابق لـ `staffPayroll.test.ts` في الويب.
void main() {
  AppStore school() {
    final store = AppStore.forTesting();
    injectDemoData(store);
    store.currentTenant = store.tenants.first;
    store.users.add(AppUser(id: 'u-sec', name: 'سكرتيرة', role: 'receptionist'));
    return store;
  }

  test('يُضاف براتبه ووظيفته مربوطاً بحسابه، ومرة واحدة', () {
    final store = school();
    final before = store.teachers.length;
    final t = store.addStaffToPayroll(store.users.last, jobTitle: 'سكرتيرة المدرسة', salary: 1500);

    expect(t.userId, 'u-sec');
    expect(t.isAdminStaff, isTrue);
    expect(t.rate, 1500);
    expect(t.contractType, 'fixed');
    expect(t.jobTitle, 'سكرتيرة المدرسة');
    expect(t.toCloud()['user_id'], 'u-sec');
    expect(store.staffPayRecord('u-sec')?.id, t.id);

    expect(store.addStaffToPayroll(store.users.last, jobTitle: 'x', salary: 9).id, t.id);
    expect(store.teachers.length, before + 1);
  });

  test('لا يظهر مع المعلمين، ويبقى للرواتب والدوام', () {
    final store = school();
    final t = store.addStaffToPayroll(store.users.last, jobTitle: '', salary: 1000);
    expect(store.teachersInViewedYear.any((x) => x.id == t.id), isTrue);
    expect(store.teachingStaffInViewedYear.any((x) => x.id == t.id), isFalse);
    expect(store.teachingStaffInViewedYear, isNotEmpty);
  });

  test('المعلم لا يحمل user_id في الرفع فلا يمسّه', () {
    final store = school();
    final teacher = store.teachingStaffInViewedYear.first;
    expect(teacher.toCloud().containsKey('user_id'), isFalse);
  });

  test('اسمه في الرواتب يتبع اسمه في المستخدمين، ونسخه بحسابه', () {
    final store = school();
    final t = store.addStaffToPayroll(store.users.last, jobTitle: '', salary: 1000);
    final u = store.users.last;
    store.updateUser(AppUser(id: u.id, name: 'سكرتيرة جديدة', role: u.role, capabilities: u.capabilities));
    expect(store.teacherById(t.id)?.name, 'سكرتيرة جديدة');
    expect(store.linkedTeacherIds(t.id), {t.id});
  });

  test('الإزالة تحذف ملف الراتب، إلا إن صُرف له سند', () {
    final store = school();
    store.addStaffToPayroll(store.users.last, jobTitle: '', salary: 1000);
    store.removeStaffFromPayroll('u-sec');
    expect(store.staffPayRecord('u-sec'), isNull);

    final t = store.addStaffToPayroll(store.users.last, jobTitle: '', salary: 1000);
    store.addTeacherPayout(teacherId: t.id, amount: 1000, paymentDate: '2026-11-01');
    expect(() => store.removeStaffFromPayroll('u-sec'), throwsA(isA<StoreException>()));
    expect(store.staffPayRecord('u-sec'), isNotNull);
  });
}
