/// نسخ المدرسة في السحابة (حاوية `school-backups`، مجلد رقم المدرسة) — `schoolBackups.ts`.
///
/// حساب المالك وحده. ثلاثة أنواع، ولكل نوع حدّه: اليومية تكتبها الدالة `school-backup` كل ليلة
/// وتُبقى 14 يوماً، واليدوية آخر [keepPoints]، و«قبل استرجاع» آخر [keepPoints].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'backup.dart';
import 'store.dart';
import 'supabase.dart';

const _bucket = 'school-backups';
const keepPoints = 5;
const dailyDays = 14;

const backupKindLabels = {'daily': 'يومية', 'manual': 'يدوية', 'auto': 'قبل استرجاع'};

class RestorePoint {
  const RestorePoint({required this.path, required this.at, required this.kind, this.error = ''});

  /// المسار الكامل في الحاوية؛ فارغ لنسخة يومية فشلت.
  final String path;
  final String at;
  final String kind;
  final String error;
}

String _kindOf(String name) => name.contains('_daily') ? 'daily' : (name.contains('_auto') ? 'auto' : 'manual');

String _parseAt(String name) {
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})').firstMatch(name);
  return m == null ? '' : '${m[1]}T${m[2]}:${m[3]}:${m[4]}Z';
}

Future<List<RestorePoint>> _listFiles(String tenantId) async {
  final files = await storageList(_bucket, tenantId);
  return [
    for (final f in files)
      if (f.name.endsWith('.json'))
        RestorePoint(path: '$tenantId/${f.name}', at: _parseAt(f.name), kind: _kindOf(f.name)),
  ];
}

/// كل النسخ مع اليومية الفاشلة من سجل التشغيل، الأحدث أولاً — `listRestorePoints`.
Future<List<RestorePoint>> listRestorePoints(String tenantId) async {
  final since = DateTime.now().toUtc().subtract(const Duration(days: dailyDays)).toIso8601String();
  final files = await _listFiles(tenantId);
  final runs = await supabaseSelect(
    'school_backup_runs',
    columns: 'created_at,error',
    filters: {'tenant_id': 'eq.$tenantId', 'status': 'eq.failed', 'created_at': 'gte.$since'},
  );
  return [
    ...files,
    for (final r in runs ?? const <Map<String, dynamic>>[])
      RestorePoint(path: '', at: '${r['created_at'] ?? ''}', kind: 'daily', error: '${r['error'] ?? 'فشلت'}'),
  ]..sort((a, b) => b.at.compareTo(a.at));
}

/// يحفظ النسخة ثم يحذف ما زاد على [keepPoints] من نوعها، الأقدم أولاً — `saveRestorePoint`.
Future<void> saveRestorePoint(AppStore store, {bool auto = false}) async {
  final tenantId = store.tenantId;
  if (tenantId == null || tenantId.isEmpty) return;
  const service = BackupService();
  await store.flush();
  final cloud = await service.fetchCloudOnlyTables(tenantId);
  final bytes = Uint8List.fromList(utf8.encode(service.encode(store, cloudData: cloud)));
  final kind = auto ? 'auto' : 'manual';
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
  await storageUpload(_bucket, '$tenantId/${stamp}_$kind.json', bytes, 'application/json');
  final mine = (await _listFiles(tenantId)).where((p) => p.kind == kind).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  if (mine.length > keepPoints) {
    await storageRemove(_bucket, [for (final p in mine.skip(keepPoints)) p.path]);
  }
}

/// تنبيه الرئيسية: آخر يومية فشلت، أو مرّ يومان بلا يومية — `dailyBackupProblem`.
Future<String?> dailyBackupProblem(String tenantId) async {
  final rows = await supabaseSelect(
    'school_backup_runs',
    columns: 'status,created_at',
    filters: {'tenant_id': 'eq.$tenantId'},
    order: 'created_at.desc',
    limit: 1,
  );
  final last = rows?.firstOrNull;
  if (last == null) return null;
  if (last['status'] == 'failed') return 'فشلت';
  final at = DateTime.tryParse('${last['created_at'] ?? ''}');
  return at != null && DateTime.now().difference(at).inHours > 48 ? 'متأخرة' : null;
}

Future<Uint8List?> downloadRestorePoint(String path) async {
  final file = await storageDownload(_bucket, path);
  return file == null ? null : Uint8List.fromList(file.bytes);
}
