import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/payment_methods.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/system_features.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _store() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  return s;
}

/// صف `institution_settings` كما يكتبه سطح المكتب في السحابة.
void _cloudRow(AppStore s, Map<String, dynamic> colors) {
  s.extraCloud['institution_settings'] = [
    {
      'id': s.tenantId,
      'institution_type': 'school',
      'institution_name': 'مدرسة الأمل النموذجية',
      'logo': null,
      'colors': colors,
      'updated_at': '2026-09-13T10:00:00.000Z',
    },
  ];
}

void main() {
  group('إعدادات المنشأة تصل من سطح المكتب إلى الجوال', () {
    test('رسم حجز المقعد يُستعاد من الجدول المتزامن', () async {
      final s = _store();
      expect(s.seatReservationFee, 0);

      _cloudRow(s, {AppStore.seatFeeColorKey: 50});
      await s.hydrateInstitution();

      expect(s.seatReservationFee, 50, reason: 'كان يبقى محلياً على الجهاز الذي ضبطه');
      expect(s.db.settings[seatReservationFeeKey], '50');
    });

    test('أشهر الدراسة تُستعاد، وإفراغها في السحابة يوقف الرسوم هنا', () async {
      final s = _store();
      _cloudRow(s, {AppStore.studyMonthsColorKey: [9, 10, 11]});
      await s.hydrateInstitution();
      expect(s.studyMonths, [9, 10, 11]);

      _cloudRow(s, {AppStore.studyMonthsColorKey: <int>[]});
      await s.hydrateInstitution();
      expect(s.studyMonths, isNull, reason: 'الرسوم الشهرية متوقفة');
    });

    test('الميزات وقواعد الخصم ووسائل الدفع تُستعاد كذلك', () async {
      final s = _store();
      _cloudRow(s, {
        '__system_features': const SystemFeatures(enableEvaluations: false).toMap(),
        '__discount_rules': const SchoolDiscountRules(autoSuggestExcellence: true, excellenceMinGpa: 85).toMap(),
        customPaymentMethodsColorKey: [
          {'id': 'cash', 'name': 'نقداً', 'type': 'cash', 'enabled': true},
          {'id': 'bank', 'name': 'بنك القدس', 'type': 'bank', 'enabled': true},
        ],
      });

      await s.hydrateInstitution();

      expect(s.features.enableEvaluations, isFalse);
      expect(s.discountRules.autoSuggestExcellence, isTrue);
      expect(s.discountRules.excellenceMinGpa, 85);
      expect(s.paymentMethods.map((m) => m.name), contains('بنك القدس'));
    });
  });

  group('ما يُضبط على الجوال يصل بقية الأجهزة', () {
    Map<String, dynamic> colorsOf(AppStore s) {
      final row = s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);
      return Map<String, dynamic>.from(row['colors'] as Map);
    }

    test('رسم الحجز وأشهر الدراسة يُكتبان في صف المنشأة', () async {
      final s = _store();
      await s.setSeatReservationFee(75);
      await s.saveStudyMonths([9, 10]);

      final colors = colorsOf(s);
      expect(colors[AppStore.seatFeeColorKey], 75.0);
      expect(colors[AppStore.studyMonthsColorKey], [9, 10]);
    });

    test('الميزات وقواعد الخصم كذلك', () async {
      final s = _store();
      await s.saveFeatures(enableExpenses: false);
      await s.saveDiscountRules(const SchoolDiscountRules(autoSuggestExcellence: true));

      final colors = colorsOf(s);
      expect((colors['__system_features'] as Map)['enableExpenses'], isFalse);
      expect((colors['__discount_rules'] as Map)['autoSuggestExcellence'], isTrue);
    });

    test('الكتابة لا تمسح إعدادات كتبتها نسخة أخرى في العمود نفسه', () async {
      final s = _store();
      await s.db.setSetting(institutionColorsKey, jsonEncode({'__unknown_setting': 'يبقى'}));

      await s.setSeatReservationFee(20);

      final colors = colorsOf(s);
      expect(colors['__unknown_setting'], 'يبقى');
      expect(colors[AppStore.seatFeeColorKey], 20.0);
    });
  });
}
