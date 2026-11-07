import 'dart:typed_data';

import 'package:center_mobile/data/demo_dataset.dart';
import 'package:center_mobile/data/demo_images.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final blank = Uint8List(0);
  final images = DemoImages(avatars: {'ذكر': List.filled(avatarVariants, blank), 'أنثى': List.filled(avatarVariants, blank)}, doc: blank, transfer: blank);

  test('مدرسة الديمو كاملة: 81 طالباً وتسع شعب وسبعة معلمين، والمودل مع المنشأة وحدها', () async {
    final local = await buildDemoDataset(images: images);
    expect(local.rows['students']!.length, 81);
    expect(local.rows['rooms']!.length, 9);
    expect(local.rows['teachers']!.length, 7);
    expect(local.moodleSections, isEmpty);
    final remote = await buildDemoDataset(tenantId: 't-1', images: images);
    expect(remote.moodleSections, isNotEmpty);
    expect(remote.rows['payment_requests']!.every((r) => (r['image_paths'] as List).first.toString().startsWith('t-1/')), true);
  });

  test('المسدَّد مشتق من السندات: لا قسط يتجاوز مبلغه، والحالة تطابقه', () async {
    final d = await buildDemoDataset(images: images);
    for (final i in d.rows['installments']!) {
      final paid = (i['paid_amount'] as num).toDouble();
      final amount = (i['amount'] as num).toDouble();
      expect(paid <= amount + 0.01, true);
      expect(i['status'], paid >= amount - 0.01 ? 'paid' : (paid > 0 ? 'partially_paid' : 'unpaid'));
    }
  });

  test('الهويات وكلمات البوابة لا تتكرر، والإخوة يتشاركون ولي الأمر', () async {
    final d = await buildDemoDataset(images: images);
    final students = d.rows['students']!;
    final ids = [...students.map((s) => s['national_id']), ...d.rows['teachers']!.map((t) => t['national_id'])];
    expect(ids.toSet().length, ids.length);
    final khudair = students.where((s) => s['last_name'] == 'خضير').toList();
    expect(khudair.length, 2);
    expect(khudair[0]['parent_national_id'], khudair[1]['parent_national_id']);
    expect(d.logins.parent.nationalId, khudair[0]['parent_national_id']);
  });

  test('المجموعة الواحدة تخدم شعب المرحلة، والطالب لا يُسجَّل فيها مرتين', () async {
    final d = await buildDemoDataset(images: images);
    final seen = <String>{};
    for (final e in d.rows['enrollments']!) {
      expect(seen.add('${e['student_id']}|${e['group_id']}'), true);
    }
  });
}
