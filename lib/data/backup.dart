import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';

/// النسخ الاحتياطي والاسترجاع — المقابل لـ `BackupSettings.tsx`.
///
/// صيغة الملف موحّدة مع الويب: مفاتيح Dexie في `data`، ورأس `app_name` /
/// `schema_version` / `tenant_code`. الاسترجاع يدمج ولا يمسح، ويتخطى السجل
/// الأحدث محلياً، ويرفض نسخة منشأة أخرى.
class BackupService {
  const BackupService();

  static const schemaVersion = 1;
  static const appName = 'Center System';

  /// سحابة ← اسم Dexie في ملف الويب (والعكس عند التصدير).
  static const cloudToDexie = <String, String>{
    'users': 'users',
    'academic_years': 'academicYears',
    'subjects': 'subjects',
    'rooms': 'rooms',
    'teachers': 'teachers',
    'grade_fees': 'gradeFees',
    'groups': 'groups',
    'students': 'students',
    'student_years': 'studentYears',
    'student_attachments': 'attachments',
    'enrollments': 'enrollments',
    'installments': 'installments',
    'payments': 'payments',
    'sessions': 'sessions',
    'attendance': 'attendance',
    'teacher_payouts': 'teacherPayouts',
    'expenses': 'expenses',
    'finance_attachments': 'financeAttachments',
    'audit_log': 'auditLog',
    'finance_requests': 'financeRequests',
    'student_evaluations': 'evaluations',
  };

  static final dexieToCloud = {for (final e in cloudToDexie.entries) e.value: e.key};

  /// أسماء قديمة في نسخ الجوال السابقة (مفاتيح سحابية مباشرة).
  static String resolveCloudTable(String key) {
    if (cloudToDexie.containsKey(key)) return key;
    return dexieToCloud[key] ?? key;
  }

  /// بناء محتوى النسخة بصيغة الويب.
  String encode(AppStore store) {
    final data = <String, dynamic>{};
    for (final e in cloudToDexie.entries) {
      final rows = store.allOf(e.key);
      if (rows.isEmpty) continue;
      data[e.value] = rows;
    }
    // طابور المزامنة باسم الويب
    if (store.pendingSyncs.isNotEmpty) {
      data['pendingSyncs'] = [for (final p in store.pendingSyncs) p.toJson()];
    }

    return const JsonEncoder.withIndent('  ').convert({
      'app_name': appName,
      'version': appVersionLabel,
      'schema_version': schemaVersion,
      'tenant_id': store.tenantId,
      'tenant_code': store.currentTenant?.code,
      'tenant_name': store.institutionName.isEmpty ? store.currentTenant?.name : store.institutionName,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
  }

  String fileNameFor(AppStore store) {
    final n = DateTime.now();
    final stamp =
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return 'school_backup_$stamp.json';
  }

  Future<String> export(AppStore store) async {
    await store.flush();
    final json = encode(store);
    final name = fileNameFor(store);
    final bytes = Uint8List.fromList(utf8.encode(json));
    const mime = 'application/json';
    const type = XTypeGroup(label: 'نسخة احتياطية', extensions: ['json']);

    final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!mobile) {
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [type],
      );
      if (location == null) {
        throw const FormatException('أُلغي الحفظ');
      }
      await XFile.fromData(bytes, mimeType: mime, name: name).saveTo(location.path);
      return location.path;
    }

    // الجوال: ورقة مشاركة النظام لاختيار الملفات / Drive / البريد…
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}$name';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mime, name: name)],
        subject: 'نسخة احتياطية',
        text: 'نسخة احتياطية من النظام المدرسي',
      ),
    );
    return path;
  }

  Map<String, int> summarize(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('الملف ليس نسخة احتياطية صالحة');
    }
    final data = decoded['data'] as Map;
    final out = <String, int>{};
    for (final e in data.entries) {
      if (e.key == 'pendingSyncs') continue;
      if (e.value is! List || (e.value as List).isEmpty) continue;
      final cloud = resolveCloudTable('${e.key}');
      out[cloud] = (e.value as List).length;
    }
    return out;
  }

  /// يرفض نسخة منشأة أخرى قبل أي دمج.
  void validateTenant(AppStore store, Map backup) {
    final code = '${backup['tenant_code'] ?? ''}';
    final local = store.currentTenant?.code ?? '';
    if (code.isNotEmpty && local.isNotEmpty && code != local) {
      throw FormatException(
        'هذه النسخة لمنشأة أخرى، لا يمكن استرجاعها هنا',
      );
    }
  }

  Future<String?> pickFile() async {
    const type = XTypeGroup(label: 'نسخة احتياطية', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes());
  }

  /// دمج: السجل الأحدث محلياً لا يُستبدل، وكل مسترجَع يُسجَّل للرفع.
  /// يعيد (مسترجَع، متخطّى لأنه أحدث محلياً).
  Future<({int restored, int skipped})> restore(AppStore store, String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('الملف ليس نسخة احتياطية صالحة');
    }
    validateTenant(store, decoded);

    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    var restored = 0;
    var skipped = 0;

    for (final entry in data.entries) {
      if (entry.key == 'pendingSyncs' || entry.key == 'institutionSettings') continue;
      final rows = entry.value;
      if (rows is! List) continue;
      final cloud = resolveCloudTable('${entry.key}');
      if (cloud == 'tenants') continue;

      final typed = rows
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .where((r) => '${r['id'] ?? ''}'.isNotEmpty)
          .toList();
      if (typed.isEmpty) continue;

      final toRestore = <Map<String, dynamic>>[];
      for (final r in typed) {
        final id = '${r['id']}';
        final local = store.recordOf(cloud, id);
        if (local != null) {
          final localTs = DateTime.tryParse('${local['updated_at'] ?? ''}')?.millisecondsSinceEpoch ?? 0;
          final fileTs = DateTime.tryParse('${r['updated_at'] ?? ''}')?.millisecondsSinceEpoch ?? 0;
          if (localTs > fileTs) {
            skipped++;
            continue;
          }
        }
        r['sync_status'] = 'pending';
        toRestore.add(r);
      }
      if (toRestore.isEmpty) continue;

      store.putRowsFromBackup(cloud, toRestore);
      for (final r in toRestore) {
        store.queueBackupSync(cloud, '${r['id']}', r);
      }
      restored += toRestore.length;
    }

    // صيغة الجوال القديمة: إعدادات الجهاز داخل الملف
    final settings = decoded['settings'];
    if (settings is Map) {
      for (final e in settings.entries) {
        if ('${e.key}'.startsWith('session_') || '${e.key}' == 'is_master_admin') continue;
        await store.db.setSetting('${e.key}', '${e.value}');
      }
    }

    store.recalculateAllBalances();
    await store.flush();
    store.notifySync();
    return (restored: restored, skipped: skipped);
  }
}

const appVersionLabel = '3.7';
