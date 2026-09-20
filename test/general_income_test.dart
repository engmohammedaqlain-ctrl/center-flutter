import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppStore seeded() {
    final store = AppStore.forTesting();
    injectDemoData(store);
    if (store.academicYears.isEmpty) {
      store.academicYears.add(
        AcademicYear(
          id: 'year-2026',
          label: '2026 / 2027',
          startsOn: '2026-08-01',
          endsOn: '2027-07-31',
          isCurrent: true,
        ),
      );
    }
    return store;
  }

  test('إضافة إيراد عام تختم العام وتحفظه كسند بلا طالب', () {
    final store = seeded();
    final yearId =
        store.operationalAcademicYear?.id ?? store.viewedAcademicYearId;

    final income = store.addGeneralIncome(
      title: 'جمعية الأمل',
      category: 'تبرعات',
      amount: 250,
      date: DateTime(2026, 9, 17),
      note: 'صيانة الصفوف',
    );

    expect(income.academicYearId, yearId);
    final payment = store.payments.singleWhere((p) => p.id == income.id);
    expect(payment.studentId, isEmpty);
    expect(payment.purpose, 'other_income');
    expect(payment.payerName, 'جمعية الأمل');
    expect(
      store.pendingSyncs.singleWhere((p) => p.recordId == income.id).tableName,
      'payments',
    );
  });

  test('تعديل الإيراد ينعكس في القائمة وصف المزامنة', () {
    final store = seeded();
    final income =
        store.addGeneralIncome(
            title: 'جهة أولى',
            category: 'منح',
            amount: 100,
            date: DateTime.now(),
          )
          ..title = 'جهة معدلة'
          ..amount = 125
          ..note = 'بيان معدل';

    store.updateGeneralIncome(income);

    final saved = store.generalIncomes.singleWhere((e) => e.id == income.id);
    expect(saved.title, 'جهة معدلة');
    expect(saved.amount, 125);
    expect(saved.note, 'بيان معدل');
    expect(store.recordOf('payments', income.id)?['payer_name'], 'جهة معدلة');
  });

  test('حذف الإيراد المالي يلغي سند اليوم ولا يسقط أثره', () {
    final store = seeded();
    final income = store.addGeneralIncome(
      title: 'متبرع',
      category: 'تبرعات',
      amount: 75,
      date: DateTime.now(),
    );

    store.deleteGeneralIncome(income.id, reason: 'سند مكرر');

    expect(
      store.generalIncomes.singleWhere((e) => e.id == income.id).cancelled,
      isTrue,
    );
  });
}
