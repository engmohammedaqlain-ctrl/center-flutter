/// ملف جدول الشعبة أو المعلم: صورة أو PDF يرفعه مدير المدرسة — `scheduleFile.ts` و
/// `scheduleFiles.service.ts`. في السحابة وحدها كملفات التحضير، والقراءة تحددها سياسات القاعدة
/// لصاحبها (20261202_schedule_files.sql).
library;

import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'supabase.dart';

const scheduleBucket = 'schedule-files';
const maxScheduleBytes = 10 * 1024 * 1024;
const scheduleExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'webp'];

const _extMime = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};
const _mimeExt = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

class ScheduleFile {
  const ScheduleFile({
    required this.id,
    required this.kind,
    required this.ownerId,
    required this.storagePath,
    required this.fileName,
    required this.mime,
    required this.sizeBytes,
    required this.updatedAt,
  });

  final String id;

  /// `room` أو `teacher`.
  final String kind;
  final String ownerId;
  final String storagePath;
  final String fileName;
  final String mime;
  final int sizeBytes;
  final String updatedAt;

  bool get isPdf => mime == 'application/pdf';

  String downloadName(String title) {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
    return '${clean.isEmpty ? 'جدول' : clean}.${_mimeExt[mime] ?? 'bin'}';
  }

  factory ScheduleFile.fromMap(Map<String, dynamic> m) => ScheduleFile(
        id: '${m['id']}',
        kind: '${m['kind'] ?? 'room'}',
        ownerId: '${m['owner_id'] ?? ''}',
        storagePath: '${m['storage_path'] ?? ''}',
        fileName: '${m['file_name'] ?? ''}',
        mime: '${m['mime'] ?? ''}',
        sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
        updatedAt: '${m['updated_at'] ?? ''}',
      );
}

/// حجم مقروء: 340 ك.ب أو 2.4 م.ب — `sizeLabel`.
String scheduleSizeLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round().clamp(1, 1024)} ك.ب';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
}

class ScheduleFiles {
  ScheduleFiles._();

  /// ملف شعبة أو معلم، أو `null`. يرمي عند تعذّر الجلب.
  static Future<ScheduleFile?> get(String kind, String ownerId) async {
    final rows = await supabaseSelect(
      'schedule_files',
      filters: {'kind': 'eq.$kind', 'owner_id': 'eq.$ownerId'},
      limit: 1,
    );
    if (rows == null) throw StoreException('تعذّر جلب الجدول');
    return rows.isEmpty ? null : ScheduleFile.fromMap(rows.first);
  }

  /// رفع جدول جديد أو استبدال القائم.
  static Future<ScheduleFile> save({
    required String tenantId,
    required String kind,
    required String ownerId,
    required String name,
    required Uint8List bytes,
  }) async {
    final ext = name.split('.').last.toLowerCase();
    final mime = _extMime[ext];
    if (mime == null) throw StoreException('صورة (JPG أو PNG) أو PDF فقط');
    if (bytes.length > maxScheduleBytes) throw StoreException('الملف أكبر من 10 ميجابايت');
    if (bytes.isEmpty) throw StoreException('الملف فارغ');

    final id = const Uuid().v4();
    final path = '$tenantId/$id.${_mimeExt[mime]}';
    try {
      await storageUpload(scheduleBucket, path, bytes, mime);
    } catch (_) {
      throw StoreException('تعذّر رفع الملف');
    }
    ScheduleFile? existing;
    try {
      existing = await get(kind, ownerId);
    } catch (_) {}
    final now = DateTime.now().toUtc().toIso8601String();
    final fields = <String, dynamic>{
      'storage_path': path,
      'file_name': name.length > 200 ? name.substring(0, 200) : name,
      'mime': mime,
      'size_bytes': bytes.length,
      'updated_at': now,
    };
    try {
      if (existing != null) {
        await supabaseUpdate('schedule_files', {'id': 'eq.${existing.id}'}, fields);
      } else {
        await supabaseUpsert('schedule_files', [
          {'id': id, 'kind': kind, 'owner_id': ownerId, 'tenant_id': tenantId, 'created_at': now, ...fields},
        ]);
      }
    } catch (_) {
      await storageRemove(scheduleBucket, [path]);
      throw StoreException('تعذّر حفظ الجدول');
    }
    if (existing != null) await storageRemove(scheduleBucket, [existing.storagePath]);
    return ScheduleFile(
      id: existing?.id ?? id,
      kind: kind,
      ownerId: ownerId,
      storagePath: path,
      fileName: name,
      mime: mime,
      sizeBytes: bytes.length,
      updatedAt: now,
    );
  }

  static Future<void> remove(ScheduleFile file) async {
    try {
      await supabaseDelete('schedule_files', {'id': 'eq.${file.id}'});
    } catch (_) {
      throw StoreException('تعذّر الحذف');
    }
    await storageRemove(scheduleBucket, [file.storagePath]);
  }

  /// ملف الجدول الذي تراه هذه الجلسة (معلم: جدوله، طالب أو ولي أمر: شعبة الطالب) — `mine`.
  static Future<ScheduleFile?> mine() async {
    try {
      final rows = await supabaseSelect('schedule_files', order: 'updated_at.desc', limit: 1);
      return rows == null || rows.isEmpty ? null : ScheduleFile.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> download(ScheduleFile file) async {
    final got = await storageDownload(scheduleBucket, file.storagePath);
    return got == null ? null : Uint8List.fromList(got.bytes);
  }
}
