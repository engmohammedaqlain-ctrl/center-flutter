import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

const _red = InstitutionColors(
  sidebarBg: '#4A0E17',
  activeItem: '#DC2626',
  primaryButton: '#4A0E17',
  actionButton: '#B91C1C',
  appBg: '#FFF9F9',
);

Future<AppStore> school(FakeDisk disk) async {
  final s = AppStore.forTesting();
  await s.bootstrap(disk);
  injectDemoData(s);
  await s.login('amal', 'amal2026');
  return s;
}

void main() {
  setUp(AppColors.reset);
  tearDownAll(AppColors.reset);

  test('the palette follows the institution colours', () {
    expect(AppColors.amber, const Color(0xFFE88C15));

    AppColors.apply(_red);
    expect(AppColors.amber, const Color(0xFFB91C1C), reason: 'لون الإجراء');
    expect(AppColors.navy, const Color(0xFF4A0E17), reason: 'خلفية الترويسة');
    expect(AppColors.heading, const Color(0xFF4A0E17), reason: 'لون العناوين');
    expect(AppColors.bg, const Color(0xFFFFF9F9), reason: 'خلفية العمل');
  });

  test('derived shades stay in the same family as their base', () {
    AppColors.apply(_red);
    // الغامق أغمق من الأساس، والفاتح أفتح منه
    double lum(Color c) => c.computeLuminance();
    expect(lum(AppColors.navyDark), lessThan(lum(AppColors.navy)));
    expect(lum(AppColors.navyMid), greaterThan(lum(AppColors.navy)));
    expect(lum(AppColors.amberDark), lessThan(lum(AppColors.amber)));
  });

  test('all five identity colours reach the interface', () {
    AppColors.apply(_red);
    // كل لون يختاره المدير له أثر مرئي؛ إهمال أحدها يترك موضعاً بلون غريب
    expect(AppColors.navy, const Color(0xFF4A0E17), reason: 'sidebarBg');
    expect(AppColors.accent, const Color(0xFFDC2626), reason: 'activeItem');
    expect(AppColors.heading, const Color(0xFF4A0E17), reason: 'primaryButton');
    expect(AppColors.amber, const Color(0xFFB91C1C), reason: 'actionButton');
    expect(AppColors.bg, const Color(0xFFFFF9F9), reason: 'appBg');
  });

  test('the highlight is distinct from the action colour', () {
    AppColors.apply(_red);
    expect(
      AppColors.accent,
      isNot(AppColors.amber),
      reason: 'القسم المفتوح يجب أن يتمايز عن زر الإجراء',
    );
  });

  test('a missing highlight falls back to the action colour', () {
    AppColors.apply(const InstitutionColors(actionButton: '#B91C1C', activeItem: ''));
    expect(AppColors.accent, const Color(0xFFB91C1C));
  });

  test('a three-digit value is read as CSS shorthand', () {
    // '#bad' لون صالح مختصر، لا قيمة فاسدة
    expect(parseHexColor('#bad'), const Color(0xFFBBAADD));
    expect(parseHexColor('#ZZZ'), isNull);
  });

  test('badge tints stay amber, as they are written literally in Center', () {
    AppColors.apply(_red);
    // اشتقاقها من لون الإجراء كان يجعلها زهرية باهتة مع هوية حمراء
    expect(AppColors.amberSoft, const Color(0xFFFFF7ED));
    expect(AppColors.amberBorder, const Color(0xFFFED7AA));
  });

  test('semantic colours never move', () {
    AppColors.apply(_red);
    expect(AppColors.success, const Color(0xFF16A34A));
    expect(AppColors.danger, const Color(0xFFDC2626));
    expect(AppColors.muted, const Color(0xFF64748B));
  });

  test('a bad colour value falls back instead of blanking the screen', () {
    AppColors.apply(const InstitutionColors(sidebarBg: 'not-a-colour', actionButton: '#ZZZZZZ'));
    expect(AppColors.navy, const Color(0xFF0B2545));
    expect(AppColors.amber, const Color(0xFFE88C15));
  });

  test('saving the identity repaints and reaches the cloud row', () async {
    final s = await school(FakeDisk());
    await s.saveInstitution(colors: _red);

    expect(AppColors.amber, const Color(0xFFB91C1C));

    final row = s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);
    expect((row['colors'] as Map)['actionButton'], '#B91C1C');
    expect(
      s.pendingSyncs.any((p) => p.tableName == 'institution_settings'),
      isTrue,
      reason: 'الهوية تُرفع لتصل بقية الأجهزة',
    );
  });

  test('colours arriving from another device are applied on pull', () async {
    final s = await school(FakeDisk());
    expect(AppColors.amber, const Color(0xFFE88C15));

    // صف الهوية كما يصل من السحابة بعد تغييره على سطح المكتب
    s.putRows('institution_settings', [
      {
        'id': s.tenantId,
        'institution_type': 'school',
        'institution_name': 'مدرسة آل الأشقر',
        'colors': _red.toMap(),
        'sync_status': 'synced',
      }
    ]);
    await s.onPulled();

    expect(AppColors.amber, const Color(0xFFB91C1C), reason: 'اللون يتبع الجهاز الآخر');
    expect(s.institutionName, 'مدرسة آل الأشقر');
  });

  test('the chosen palette survives a restart', () async {
    final disk = FakeDisk();
    final first = await school(disk);
    await first.saveInstitution(colors: _red);
    await first.flush();

    AppColors.reset();
    final second = AppStore.forTesting();
    await second.bootstrap(disk);

    expect(AppColors.amber, const Color(0xFFB91C1C));
    expect(jsonDecode(second.db.settings[institutionColorsKey]!)['sidebarBg'], '#4A0E17');
  });
}
