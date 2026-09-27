import 'dart:convert';

import 'package:center_mobile/data/backup.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

/// محتوى المودل في النسخة الاحتياطية — مطابق لـ `backupCloudTables.ts` في الويب:
/// يُنسخ في `cloud_data`، ويُعاد إلى السحابة بعد دمج بقية السجلات.
void main() {
  const service = BackupService();

  Future<AppStore> seeded() async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);
    return s;
  }

  final moodle = {
    'course_sections': [
      {'id': 'sec-1', 'group_id': 'g1', 'term': 'term_1', 'title': 'الوحدة الأولى', 'color': '#2563EB'},
    ],
    'course_items': [
      {'id': 'it-1', 'section_id': 'sec-1', 'group_id': 'g1', 'title': 'درس', 'type': 'note'},
      {'id': 'it-2', 'section_id': 'sec-1', 'group_id': 'g1', 'title': 'واجب', 'type': 'assignment'},
    ],
  };

  test('النسخة تحمل محتوى المودل في cloud_data بصيغة الويب', () async {
    final s = await seeded();
    final decoded = jsonDecode(service.encode(s, cloudData: moodle)) as Map<String, dynamic>;
    final cloud = decoded['cloud_data'] as Map<String, dynamic>;
    expect((cloud['course_sections'] as List).single['title'], 'الوحدة الأولى');
    expect(cloud['course_items'] as List, hasLength(2));
    expect(service.cloudOnlyRows(decoded), 3);
    // المودل ليس جدول جهاز: لا يدخل ملخص السجلات المحلية
    expect(service.summarize(jsonEncode(decoded)).containsKey('course_items'), isFalse);
  });

  test('نسخة بلا cloud_data (قديمة) تبقى صالحة وبلا مودل', () async {
    final s = await seeded();
    final decoded = jsonDecode(service.encode(s)) as Map<String, dynamic>;
    decoded.remove('cloud_data');
    expect(service.cloudOnlyRows(decoded), 0);
    final result = await service.restore(s, jsonEncode(decoded));
    expect(result.moodle, 0);
    expect(result.moodleNote, isEmpty);
  });

  test('بلا إنترنت: تُسترجع السجلات ويُترك المودل بملاحظة', () async {
    final s = await seeded();
    expect(s.networkEnabled, isFalse);
    final json = service.encode(s, cloudData: moodle);
    final result = await service.restore(s, json);
    expect(result.moodle, 0);
    expect(result.moodleNote, anyOf(contains('بلا إنترنت'), contains('بلا منشأة نشطة')));
  });
}
