import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_validate.dart';
import 'payment_methods.dart';
import 'store.dart';
import 'supabase.dart';
import 'user_message.dart';

/// النسخ الاحتياطي والاسترجاع — المقابل لـ `BackupSettings.tsx`.
///
/// صيغة الملف موحّدة مع الويب: مفاتيح Dexie في `data`، ورأس `app_name` /
/// `schema_version` / `tenant_code`. الاسترجاع يدمج ولا يمسح، ويتخطى السجل
/// الأحدث محلياً، ويرفض نسخة منشأة أخرى.
class BackupService {
  const BackupService();

  static const schemaVersion = 1;

  /// جداول المودل: محتوى تعليمي يعيش في السحابة وحدها بلا نسخة على الجهاز —
  /// `CLOUD_ONLY_TABLES`. تُنسخ في `cloud_data` وإلا ضاعت وحدات المواد وواجباتها
  /// عند استرجاع المنشأة. الأب قبل الابن: القسم قبل عناصره احتراماً للمفتاح الأجنبي.
  /// الملفات نفسها تبقى في حاوية التخزين: العنصر يحمل رابطها.
  static const cloudOnlyTables = ['course_sections', 'course_items'];

  static const _cloudPage = 1000;
  static const _cloudWriteChunk = 500;

  /// كل صفوف المنشأة من جداول المودل، بلا ختم المنشأة (يُعاد ختمه عند الاسترجاع).
  Future<Map<String, List<Map<String, dynamic>>>> fetchCloudOnlyTables(String tenantId) async {
    final out = {for (final t in cloudOnlyTables) t: <Map<String, dynamic>>[]};
    for (final table in cloudOnlyTables) {
      for (var from = 0;; from += _cloudPage) {
        final rows = await supabaseSelect(
          table,
          filters: {'tenant_id': 'eq.$tenantId'},
          order: 'created_at.asc',
          limit: _cloudPage,
          offset: from,
        );
        if (rows == null) throw FormatException('تعذّر جلب محتوى المودل ($table)');
        out[table]!.addAll([for (final r in rows) Map<String, dynamic>.from(r)..remove('tenant_id')]);
        if (rows.length < _cloudPage) break;
      }
    }
    return out;
  }

  /// إعادة صفوف المودل إلى السحابة — `restoreCloudOnlyTables`. تحتاج اتصالاً: لا
  /// مكان لها على الجهاز تنتظر فيه. يعيد عدد الصفوف المكتوبة.
  Future<int> restoreCloudOnlyTables(String tenantId, Map cloudData) async {
    var written = 0;
    for (final table in cloudOnlyTables) {
      final raw = cloudData[table];
      final list = [
        if (raw is List)
          for (final r in raw)
            if (r is Map && '${r['id'] ?? ''}'.isNotEmpty) Map<String, dynamic>.from(r),
      ];
      for (var i = 0; i < list.length; i += _cloudWriteChunk) {
        final end = i + _cloudWriteChunk > list.length ? list.length : i + _cloudWriteChunk;
        final chunk = [for (final r in list.sublist(i, end)) {...r, 'tenant_id': tenantId}];
        try {
          await supabaseUpsert(table, chunk);
        } catch (e) {
          throw FormatException('تعذّر استرجاع محتوى المودل ($table): ${userMessage(e, 'رفضت السحابة الكتابة')}');
        }
        written += chunk.length;
      }
    }
    return written;
  }

  /// عدد صفوف المودل في ملف النسخة.
  int cloudOnlyRows(Map backup) {
    final cloud = backup['cloud_data'];
    if (cloud is! Map) return 0;
    return cloudOnlyTables.fold<int>(0, (sum, t) => sum + (cloud[t] is List ? (cloud[t] as List).length : 0));
  }
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
    'student_sections': 'studentSections',
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
    'payment_requests': 'paymentRequests',
    'payment_methods': 'paymentMethods',
    'student_evaluations': 'evaluations',
  };

  static final dexieToCloud = {for (final e in cloudToDexie.entries) e.value: e.key};

  /// أسماء قديمة في نسخ الجوال السابقة (مفاتيح سحابية مباشرة).
  static String resolveCloudTable(String key) {
    if (cloudToDexie.containsKey(key)) return key;
    return dexieToCloud[key] ?? key;
  }

  /// بناء محتوى النسخة بصيغة الويب.
  String encode(AppStore store, {Map<String, List<Map<String, dynamic>>> cloudData = const {}}) {
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
      'cloud_data': cloudData,
    });
  }

  String fileNameFor(AppStore store) {
    final n = DateTime.now();
    final stamp =
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return 'school_backup_$stamp.json';
  }

  /// يعيد مسار الملف، وملاحظة إن تعذّر جلب محتوى المودل (يُحفظ الملف بدونه).
  Future<({String path, String note})> export(AppStore store) async {
    await store.flush();
    // محتوى المودل سحابي بلا نسخة على الجهاز: يُجلب مع النسخة وإلا ضاع كله
    var cloudData = <String, List<Map<String, dynamic>>>{};
    var note = '';
    final tid = store.tenantId;
    if (tid != null && tid.isNotEmpty) {
      try {
        if (!store.networkEnabled) throw const FormatException('بلا اتصال');
        cloudData = await fetchCloudOnlyTables(tid);
      } catch (_) {
        note = 'بلا محتوى المودل (تعذّر الاتصال)';
      }
    }
    final json = encode(store, cloudData: cloudData);
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
      return (path: location.path, note: note);
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
    return (path: path, note: note);
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

  /// ملف مفحوص جاهز للكتابة — ما يمرّ به الاسترجاع بين الفحص والتأكيد والكتابة.
  BackupPlan prepare(AppStore store, String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('الملف ليس نسخة احتياطية صالحة');
    }
    validateTenant(store, decoded);

    // ملف مُجهَّز خارج البرنامج: معرّف عامه المؤقت (ay_@...) يُستبدل بعام الجهاز
    // نفسه أو بالمعرّف الحتمي، وإلا نشأ عام ثانٍ «حالي» وتوزعت البيانات بين عامين
    final deviceYears = [for (final y in store.academicYears) (id: y.id, label: y.label)];
    final data = remapYearPlaceholders(
      Map<String, dynamic>.from(decoded['data'] as Map),
      (label) => pickRealYearId(label, deviceYears, store.yearIdFor),
    );

    // ── الفحص قبل أي كتابة ─────────────────────────────────────────────
    final byCloud = <String, List>{};
    for (final e in data.entries) {
      if (e.key == 'pendingSyncs' || e.value is! List) continue;
      byCloud[resolveCloudTable(e.key)] = e.value as List;
    }
    final existingIds = <String, Set<String>>{
      for (final cloud in cloudToDexie.keys) cloud: {for (final r in store.allOf(cloud)) '${r['id']}'},
    };
    final cloudData = decoded['cloud_data'];
    if (cloudData is Map) {
      for (final t in cloudOnlyTables) {
        if (cloudData[t] is List) byCloud[t] = cloudData[t] as List;
      }
    }
    final check = validateBackupTables(
      byCloud,
      existingIds: existingIds,
      existingRows: {'payments': store.allOf('payments'), 'installments': store.allOf('installments')},
    );
    return BackupPlan(backup: decoded, data: data, byCloud: byCloud, check: check, moodleRows: cloudOnlyRows(decoded));
  }

  /// أول جدول في الملف له سجلات مملوكة لمنشأة أخرى في السحابة — `findForeignOwnedTable`.
  ///
  /// ملف مدرسة يُسترجع في مدرسة ثانية كان يُقبل ثم يعلق رفعه كله: المعرّف فريد
  /// على مستوى المنصة، وRLS تخفي صف الآخرين. يتطلب اتصالاً؛ الفشل يُرمى.
  Future<({String table, int count})?> findForeignOwnedTable(Map<String, List> byCloud) async {
    for (final e in byCloud.entries) {
      if (e.key == 'payment_methods' || cloudOnlyTables.contains(e.key)) continue;
      final ids = [
        for (final r in e.value)
          if (r is Map && r['id'] is String && (r['id'] as String).isNotEmpty) r['id'] as String,
      ];
      for (var i = 0; i < ids.length; i += 1000) {
        final chunk = ids.sublist(i, i + 1000 > ids.length ? ids.length : i + 1000);
        final res = await supabaseRpc('ids_owned_elsewhere', {'p_table': e.key, 'p_ids': chunk});
        if (res == null) throw const FormatException('تعذّر فحص ملكية السجلات');
        if (res is num && res > 0) return (table: e.key, count: res.toInt());
      }
    }
    return null;
  }

  /// فحص ثم كتابة. ملف فيه خطأ يُرفض قبل أن يُكتب منه شيء.
  Future<({int restored, int skipped, int moodle, String moodleNote})> restore(AppStore store, String json) async {
    final plan = prepare(store, json);
    if (plan.check.errorCount > 0) {
      throw FormatException(
        'الملف مرفوض: ${plan.check.errorCount} خطأ. أوّلها — ${formatBackupIssues(plan.check.errors.take(1).toList())}',
      );
    }
    return write(store, plan);
  }

  /// دمج ملف مفحوص: السجل الأحدث محلياً لا يُستبدل، وكل مسترجَع يُسجَّل للرفع.
  /// يعيد (مسترجَع، متخطّى لأنه أحدث محلياً، عناصر مودل كُتبت في السحابة، ملاحظة المودل).
  Future<({int restored, int skipped, int moodle, String moodleNote})> write(AppStore store, BackupPlan plan) async {
    final decoded = plan.backup;
    final data = plan.data;
    var restored = 0;
    var skipped = 0;

    for (final entry in data.entries) {
      if (entry.key == 'pendingSyncs') continue;
      final rows = entry.value;
      if (rows is! List) continue;
      final cloud = resolveCloudTable(entry.key);
      // جدول لا يعرفه النظام: نبّه الفحص أنه سيُتجاهل
      if (!cloudToDexie.containsKey(cloud)) continue;

      final typed = rows
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .where((r) => '${r['id'] ?? ''}'.isNotEmpty)
          .toList();
      if (typed.isEmpty) continue;

      final toRestore = <Map<String, dynamic>>[];
      for (final r in typed) {
        final local = store.recordOf(cloud, '${r['id']}');
        if (local != null) {
          // الصف المؤرَّخ يُقدَّم على غير المؤرَّخ: ملف بلا وقت تعديل لا يدهس الأحدث
          final localTs = DateTime.tryParse('${local['updated_at'] ?? ''}');
          final fileTs = DateTime.tryParse('${r['updated_at'] ?? ''}');
          if (localTs != null && (fileTs == null || localTs.isAfter(fileTs))) {
            skipped++;
            continue;
          }
        }
        // المبلغ النصي يمرّ من الفحص ثم يكسر حساب الأرصدة: يُحوَّل رقماً قبل الكتابة
        toRestore.add({...normalizeBackupRow(cloud, r), 'sync_status': 'pending'});
      }
      if (toRestore.isEmpty) continue;

      store.putRowsFromBackup(cloud, toRestore);
      for (final r in toRestore) {
        store.queueBackupSync(cloud, '${r['id']}', r);
      }
      restored += toRestore.length;
    }

    // عام مسترجَع حالي بجوار عام حالي آخر على الجهاز: يُوحَّد الآن
    final years = data['academicYears'];
    if (years is List && years.isNotEmpty) {
      try {
        await store.ensureCurrentAcademicYear();
      } catch (_) {}
    }

    // وسائل الدفع في ملف قديم (قبل جدولها): النسخة الجديدة تحملها ضمن الجداول
    final methodsTable = data['paymentMethods'];
    final legacyMethods = decoded['payment_methods'];
    if (!(methodsTable is List && methodsTable.isNotEmpty) && legacyMethods is List && legacyMethods.isNotEmpty) {
      try {
        await store.savePaymentMethods(decodePaymentMethods(legacyMethods));
      } catch (_) {}
    }

    // صيغة الجوال القديمة: إعدادات الجهاز داخل الملف
    final settings = decoded['settings'];
    if (settings is Map) {
      for (final e in settings.entries) {
        if ('${e.key}'.startsWith('session_') || '${e.key}' == 'is_master_admin') continue;
        await store.db.setSetting('${e.key}', '${e.value}');
      }
    }

    if (data['institutionSettings'] is List) await store.hydrateInstitution();
    store.recalculateAllBalances();
    await store.flush();
    store.notifySync();

    // ── محتوى المودل: سحابي بحت، ولا يُقبل قبل رفع مجموعاته ────────────
    var moodle = 0;
    var moodleNote = '';
    final cloud = decoded['cloud_data'];
    if (cloud is Map && cloudOnlyRows(decoded) > 0) {
      final tid = store.tenantId;
      if (tid == null || tid.isEmpty) {
        moodleNote = 'وتُرك محتوى المودل (بلا منشأة نشطة)';
      } else if (!store.networkEnabled) {
        moodleNote = 'وتُرك محتوى المودل (بلا إنترنت)';
      } else {
        try {
          await store.sync.push();
          moodle = await restoreCloudOnlyTables(tid, cloud);
          // المودل يُكتب في السحابة مباشرة: بلا إشارة لا تعرف البوابات المفتوحة به
          if (moodle > 0) store.announceChange(const ['course_sections', 'course_items']);
        } catch (e) {
          moodleNote = 'وتعذّر محتوى المودل: ${userMessage(e, 'رفضت السحابة الكتابة')}';
        }
      }
    }
    return (restored: restored, skipped: skipped, moodle: moodle, moodleNote: moodleNote);
  }
}

const appVersionLabel = '2.2';

/// ملف مفحوص قبل الكتابة: بياناته بعد استبدال الأعوام المؤقتة، وجداوله بأسمائها
/// السحابية، ونتيجة الفحص، وعدد عناصر المودل.
class BackupPlan {
  const BackupPlan({required this.backup, required this.data, required this.byCloud, required this.check, required this.moodleRows});

  final Map backup;
  final Map<String, dynamic> data;
  final Map<String, List> byCloud;
  final BackupCheckResult check;
  final int moodleRows;

  /// ملف جُهّز خارج البرنامج (بلا رمز منشأة) لا يُقبل دون فحص الملكية.
  bool get hasTenantCode => '${backup['tenant_code'] ?? ''}'.isNotEmpty;
}
