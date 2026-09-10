import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// النسخ الاحتياطي والاسترجاع — المقابل لـ `features/settings/BackupSettings.tsx`.
///
/// النسخة السابقة كانت تعرض إشعاراً فقط ولا تُنتج أي ملف، ولا استرجاع إطلاقاً.
class BackupService {
  const BackupService();

  static const formatVersion = 1;

  /// كل الجداول التي تدخل النسخة الاحتياطية.
  static List<String> tablesOf(AppStore store) => [
        ...AppStore.ownedTables,
        ...store.extraCloud.keys,
      ];

  /// بناء محتوى النسخة الاحتياطية كنص JSON.
  String encode(AppStore store) {
    final data = <String, dynamic>{};
    for (final table in tablesOf(store)) {
      data[table] = table == 'tenants'
          ? store.tenants.map((t) => t.toCloud()).toList()
          : store.allOf(table);
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format_version': formatVersion,
      'app_version': appVersionLabel,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tenant_id': store.tenantId,
      'institution_name': store.institutionName,
      'settings': store.db.settings,
      'data': data,
    });
  }

  /// اسم ملف يحمل المنشأة والتاريخ.
  String fileNameFor(AppStore store) {
    final n = DateTime.now();
    final stamp = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}'
        '_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
    final safe = store.institutionName.trim().isEmpty
        ? 'backup'
        : store.institutionName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return 'نسخة_${safe}_$stamp.json';
  }

  /// كتابة النسخة إلى ملف ومشاركته/حفظه.
  Future<String> export(AppStore store) async {
    await store.flush();
    final json = encode(store);
    final name = fileNameFor(store);

    final location = await getSaveLocation(suggestedName: name);
    final bytes = Uint8List.fromList(utf8.encode(json));

    if (location != null) {
      final file = XFile.fromData(bytes, mimeType: 'application/json', name: name);
      await file.saveTo(location.path);
      return location.path;
    }

    // منصات بلا حوار حفظ: نكتب في مجلد المستندات
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// عدد السجلات في نص نسخة احتياطية، للمعاينة قبل الاسترجاع.
  Map<String, int> summarize(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('الملف ليس نسخة احتياطية صالحة');
    }
    final data = decoded['data'] as Map;
    return {
      for (final e in data.entries)
        if (e.value is List && (e.value as List).isNotEmpty) '${e.key}': (e.value as List).length,
    };
  }

  /// اختيار ملف نسخة احتياطية وقراءته.
  Future<String?> pickFile() async {
    const type = XTypeGroup(label: 'نسخة احتياطية', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes());
  }

  /// استرجاع نسخة: يستبدل كل البيانات المحلية بما في الملف.
  Future<int> restore(AppStore store, String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('الملف ليس نسخة احتياطية صالحة');
    }
    final data = Map<String, dynamic>.from(decoded['data'] as Map);

    await store.wipeAllData();

    var restored = 0;
    for (final entry in data.entries) {
      final rows = entry.value;
      if (rows is! List) continue;
      final typed = rows.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
      if (typed.isEmpty) continue;
      store.putRowsFromBackup(entry.key, typed);
      restored += typed.length;
    }

    final settings = decoded['settings'];
    if (settings is Map) {
      for (final e in settings.entries) {
        // الجلسة لا تُستعاد من ملف: المستخدم يسجّل دخوله بنفسه
        if ('${e.key}'.startsWith('session_') || '${e.key}' == 'is_master_admin') continue;
        await store.db.setSetting('${e.key}', '${e.value}');
      }
    }

    await store.flush();
    store.notifySync();
    return restored;
  }
}

const appVersionLabel = '1.2.4';
