import 'dart:typed_data';

import 'package:center_mobile/data/demo_dataset.dart';
import 'package:center_mobile/data/demo_extras.dart';
import 'package:center_mobile/data/demo_images.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoDataset d;
  late DemoTimetablePlan plan;

  setUpAll(() async {
    final blank = Uint8List(0);
    final images = DemoImages(avatars: {'ذكر': List.filled(avatarVariants, blank), 'أنثى': List.filled(avatarVariants, blank)}, doc: blank, transfer: blank);
    d = await buildDemoDataset(images: images);
    plan = enrichDemoDataset(d, now: DateTime(2026, 11, 7));
  });

  test('الجدول بلا تضارب: لا معلم ولا شعبة بحصتين معاً', () {
    final teacherOf = {for (final g in d.rows['groups']!) '${g['id']}': '${g['teacher_id']}'};
    final teacherSlots = <String>{};
    final roomSlots = <String>{};
    for (final e in plan.entries) {
      expect(roomSlots.add('${e.roomId}|${e.day}|${e.period}'), true);
      expect(teacherSlots.add('${teacherOf[e.groupId]}|${e.day}|${e.period}'), true);
      expect(e.period >= 1 && e.period <= 7, true);
      expect(e.day >= 0 && e.day <= 4, true);
    }
  });

  test('كل حصص المجموعات الأسبوعية موضوعة', () {
    expect(plan.unplaced, 0);
    var want = 0;
    for (final g in d.rows['groups']!) {
      want += plan.weekly['${g['id']}']! * (g['room_ids'] as List).length;
      expect(g['weekly_periods'], plan.weekly['${g['id']}']!.toDouble());
    }
    expect(plan.entries.length, want);
  });

  test('لكل معلم شروط أجر، وفيهم الثابت والحصة والمختلط وبالحصة، ووسم صاحب البيانات', () {
    final teachers = d.rows['teachers']!;
    expect({for (final t in teachers) t['contract_type']}, containsAll(['fixed', 'sessions', 'mixed']));
    expect(teachers.any((t) => t['pay_profile'] is Map && (t['pay_profile'] as Map)['per_lesson'] == true), true);
    expect(teachers.every((t) => '${t['notes']}'.contains(demoOwnerTag)), true);
    expect((teachers.first['salary_history'] as List).length, 2);
  });
}
