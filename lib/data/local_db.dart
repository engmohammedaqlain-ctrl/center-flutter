import 'dart:async';
import 'dart:convert';

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
    final out = <String, List<Map<String, dynamic>>>{};
    final rows = await _require.query('records', columns: ['table_name', 'data']);
    for (final r in rows) {
      final table = '${r['table_name']}';
      final decoded = jsonDecode('${r['data']}');
      if (decoded is Map<String, dynamic>) {
        out.putIfAbsent(table, () => []).add(decoded);
      }
    }
    return out;
  }

  @override
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows) async {
    final db = _require;
    await db.transaction((txn) async {
      await txn.delete('records', where: 'table_name = ?', whereArgs: [table]);
      final batch = txn.batch();
      for (final row in rows) {
        final id = row['id'];
        if (id == null) continue;
        batch.insert('records', {
          'table_name': table,
          'id': '$id',
          'data': jsonEncode(row),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
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
