/// توليد بيانات تجريبية للمنشأة الحالية — المقابل لـ `injectDemoData` في `demoData.ts`: مسح الجهاز
/// والسحابة ثم مولّد الويب نفسه (`buildDemoDataset`) مرفوعاً إلى السحابة، ويُسحب إلى الجهاز.
/// حسابات الجهاز تبقى بدل الكادر التجريبي، واسم المدرسة المخصص يبقى.
library;

import '../models/models.dart';
import 'demo_data.dart' show DemoAccount, DemoDataStats;
import 'demo_dataset.dart';
import 'demo_tenant.dart';
import 'payment_methods.dart';
import 'store.dart';

Future<DemoDataStats> injectDemoDataCloud(AppStore store, {required String developerToken}) async {
  final tenantId = store.tenantId;
  if (tenantId == null || tenantId.isEmpty) {
    throw StoreException('توليد البيانات التجريبية يحتاج منشأة متصلة بالسحابة');
  }
  final keptName = store.institutionName.trim();
  final keptUsers = [for (final u in store.users) u.toCloud()];
  final me = store.deviceUser;

  await store.wipeAllDataIncludingCloud(developerToken: developerToken);

  final demo = await buildDemoDataset(tenantId: tenantId, keptUsers: keptUsers, keptName: me?.name, keptUserId: me?.id);
  await uploadAndInsertDemo(tenantId, demo);

  // هوية المدرسة كما في الويب: الاسم المخصص يبقى، ورسوم المقعد ووسائل الدفع المعتمدة في الديمو
  await store.saveInstitution(name: keptName.isEmpty ? 'مدرسة المستقبل الخاصة' : keptName);
  await store.setSeatReservationFee(demo.seatFee);
  await store.savePaymentMethods([
    for (final m in demoPaymentMethods)
      if (PaymentMethodItem.fromMap(m) case final item?) item,
  ]);
  await store.forceFullResourcePull();
  store.viewedAcademicYearId = demo.currentAcademicYearId;

  final l = demo.logins;
  return DemoDataStats(
    students: demo.rows['students']!.length,
    groups: demo.rows['groups']!.length,
    evaluations: demo.rows['student_evaluations']!.length,
    teacher: DemoAccount(name: l.teacher.name, nationalId: l.teacher.nationalId, portalCode: l.teacher.portalCode),
    student: DemoAccount(name: l.student.name, nationalId: l.student.nationalId, portalCode: l.student.portalCode),
    parent: DemoAccount(name: l.parent.name, nationalId: l.parent.nationalId, portalCode: l.parent.parentPortalCode),
  );
}
