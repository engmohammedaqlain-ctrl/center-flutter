import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// التخزين المحلي الدائم — المقابل لـ `lib/db.ts` (Dexie/IndexedDB) في النسخة المكتبية.
///
/// النسخة المكتبية تحمّل الجداول كاملةً إلى الذاكرة (`db.students.toArray()`) عند كل
/// شاشة، فالفهارس هناك لتسريع الاستعلام لا لتقسيم التحميل. لذلك يكفي هنا مخزن
/// مستندي واحد: صف لكل سجل يحمل الجدول والمعرّف والمحتوى JSON.
///
/// الكتابة **تتبع التعديل** (write-through) عبر [markDirty] + [flush]، حتى لا يضيع
/// شيء عند إغلاق التطبيق — وهي المشكلة التي كانت تُفقد كل البيانات سابقاً.
abstract class Persistence {
  Future<void> open();

  /// كل الجداول المخزّنة: اسم الجدول → صفوفه.
  Future<Map<String, List<Map<String, dynamic>>>> loadAll();

  /// استبدال محتوى جدول كامل (حذف ثم إدراج دفعة واحدة).
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows);

  /// كتابة سجلات محددة فقط دون المساس ببقية الجدول.
  ///
  /// إعادة كتابة الجدول كله عند تعديل سجل واحد كانت تُنفّذ ألف عملية لرصد
  /// حضور واحد، فيتأخر التبديل بين الأيام تأخراً محسوساً.
  Future<void> saveRecords(String table, List<Map<String, dynamic>> rows);

  /// حذف سجلات محددة.
  Future<void> deleteRecords(String table, List<String> ids);

  /// قيم الإعدادات والجلسة (المقابل لـ localStorage في النسخة المكتبية).
  Map<String, String> get settings;

  Future<void> setSetting(String key, String? value);

  /// تصفير كل البيانات مع الإبقاء على الإعدادات.
  Future<void> wipeData();

  Future<void> close();
}

/// تنفيذ لا يكتب شيئاً — للاختبارات ولأي بيئة بلا SQLite.
class NoPersistence implements Persistence {
  @override
  final Map<String, String> settings = <String, String>{};

  @override
  Future<void> open() async {}

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {};

  @override
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows) async {}

  @override
  Future<void> saveRecords(String table, List<Map<String, dynamic>> rows) async {}

  @override
  Future<void> deleteRecords(String table, List<String> ids) async {}

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
  }

  @override
  Future<void> wipeData() async {}

  @override
  Future<void> close() async {}
}

class SqflitePersistence implements Persistence {
  SqflitePersistence({this.fileName = 'center_local.db'});

  final String fileName;
  Database? _db;

  @override
  final Map<String, String> settings = <String, String>{};

  Database get _require {
    final db = _db;
    if (db == null) throw StateError('قاعدة البيانات المحلية غير مفتوحة');
    return db;
  }

  @override
  Future<void> open() async {
    // على الويب المسار اسم ملف فقط (IndexedDB)، وعلى الجوال نضمّه لمجلد قواعد البيانات.
    final path = kIsWeb ? fileName : p.join(await getDatabasesPath(), fileName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE records (
            table_name TEXT NOT NULL,
            id TEXT NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (table_name, id)
          )
        ''');
        await db.execute('CREATE INDEX idx_records_table ON records(table_name)');
        await db.execute('CREATE TABLE settings (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
      },
    );
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    settings.clear();
    final rows = await _require.query('settings');
    for (final r in rows) {
      settings['${r['k']}'] = '${r['v']}';
    }
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    final rows = await _require.query('records', columns: ['table_name', 'data']);
    if (rows.isEmpty) return {};
    // فك JSON خارج خيط الواجهة: مدرسة بـ 11 ألف طالب كانت تجمّد السبلاش ثوانٍ
    final encoded = <(String, String)>[
      for (final r in rows) ('${r['table_name']}', '${r['data']}'),
    ];
    return Isolate.run(() => _decodeRecordRows(encoded));
  }

  /// الصفوف الصالحة للكتابة مرمَّزةً نصاً — الترميز خارج خيط الواجهة.
  ///
  /// كان `jsonEncode` يجري على خيط الرسم في حلقة واحدة: حفظ جدول حضور بعد
  /// المزامنة يرمّز عشرات آلاف الصفوف دفعةً فتتجمّد الشاشة. القراءة كانت تُفكّ
  /// في خيط منفصل أصلاً؛ الكتابة الآن مثلها.
  static Future<({List<String> ids, List<String> data})> _encode(List<Map<String, dynamic>> rows) async {
    final kept = [for (final r in rows) if (r['id'] != null) r];
    final ids = [for (final r in kept) '${r['id']}'];
    // القليل يُرمَّز هنا: كلفة إنشاء خيط تفوق ترميز صفوفٍ معدودة
    if (kept.length < 200) return (ids: ids, data: [for (final r in kept) jsonEncode(r)]);
    final data = await Isolate.run(() => [for (final r in kept) jsonEncode(r)]);
    return (ids: ids, data: data);
  }

  /// حجم الدفعة الواحدة إلى قاعدة البيانات، وبين كل دفعتين فرصة لرسم إطار.
  static const _chunk = 1000;

  static void _insertChunk(Batch batch, String table, List<String> ids, List<String> data, int from, int to) {
    for (var i = from; i < to; i++) {
      batch.insert(
        'records',
        {'table_name': table, 'id': ids[i], 'data': data[i]},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows) async {
    final encoded = await _encode(rows);
    final db = _require;
    await db.transaction((txn) async {
      await txn.delete('records', where: 'table_name = ?', whereArgs: [table]);
      for (var i = 0; i < encoded.ids.length; i += _chunk) {
        final end = i + _chunk > encoded.ids.length ? encoded.ids.length : i + _chunk;
        final batch = txn.batch();
        _insertChunk(batch, table, encoded.ids, encoded.data, i, end);
        await batch.commit(noResult: true);
        await Future<void>.delayed(Duration.zero);
      }
    });
  }

  @override
  Future<void> saveRecords(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final encoded = await _encode(rows);
    for (var i = 0; i < encoded.ids.length; i += _chunk) {
      final end = i + _chunk > encoded.ids.length ? encoded.ids.length : i + _chunk;
      final batch = _require.batch();
      _insertChunk(batch, table, encoded.ids, encoded.data, i, end);
      await batch.commit(noResult: true);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> deleteRecords(String table, List<String> ids) async {
    if (ids.isEmpty) return;
    final batch = _require.batch();
    for (final id in ids) {
      batch.delete('records', where: 'table_name = ? AND id = ?', whereArgs: [table, id]);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
      await _require.delete('settings', where: 'k = ?', whereArgs: [key]);
    } else {
      settings[key] = value;
      await _require.insert(
        'settings',
        {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<void> wipeData() async {
    await _require.delete('records');
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// فك صفوف القرص في isolate منفصل — يُستدعى من [SqflitePersistence.loadAll] فقط.
Map<String, List<Map<String, dynamic>>> _decodeRecordRows(List<(String, String)> encoded) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final (table, data) in encoded) {
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic>) {
      out.putIfAbsent(table, () => []).add(decoded);
    } else if (decoded is Map) {
      out.putIfAbsent(table, () => []).add(Map<String, dynamic>.from(decoded));
    }
  }
  return out;
}
