import 'dart:convert';

import 'backup_rules.g.dart';

/// فحص ملف النسخة الاحتياطية قبل كتابته — المقابل لـ `backupValidate.ts`.
///
/// الصف الناقص حقلاً إلزامياً أو المشير إلى طالب غير موجود كان يدخل الجهاز ثم يفشل
/// رفعه ويعلق في الطابور بلا سبب مفهوم. هنا يُفحص الملف كاملاً أولاً: خطأ واحد
/// يوقف الاسترجاع قبل أن تُكتب أي بيانات. القواعد مولّدة من مخطط السحابة.

final Map<String, dynamic> backupTableRules = jsonDecode(backupRulesJson) as Map<String, dynamic>;

class BackupIssue {
  const BackupIssue({required this.table, this.rowId, this.field, required this.message});

  final String table;
  final String? rowId;
  final String? field;
  final String message;
}

class BackupCheckResult {
  BackupCheckResult({
    required this.errors,
    required this.warnings,
    required this.counts,
    required this.total,
    required this.errorCount,
  });

  final List<BackupIssue> errors;
  final List<BackupIssue> warnings;
  final Map<String, int> counts;
  final int total;

  /// عدد الأخطاء الكلي وإن لم تُدرج كلها.
  final int errorCount;
}

/// لا تُعرض آلاف الأسطر: أول مئة خطأ تكفي لتشخيص الملف.
const _maxListed = 100;

/// تواريخ العمليات: الصف بلا تاريخ يُسجَّل بيوم الاستيراد فتختل الخزينة والتقارير.
const _requiredTransactionDates = <String, List<String>>{
  'payments': ['payment_date'],
  'expenses': ['expense_date'],
  'teacher_payouts': ['payment_date'],
  'student_evaluations': ['evaluation_date'],
};

/// أعمدة إلزامية تُقبل فيها السلسلة الفارغة: جوال الطالب لمن لا رقم له.
const _blankAllowed = <String, List<String>>{
  'students': ['phone'],
};

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timeRe = RegExp(r'^\d{2}:\d{2}(:\d{2})?$');

bool _isEmpty(Object? v) => v == null || v == '';

num? _asNumber(Object? v) => v is num ? v : (v is String ? num.tryParse(v.trim()) : null);

String? _typeError(String type, Object? value) {
  switch (type) {
    case 'number':
      final n = _asNumber(value);
      return n != null && n.isFinite ? null : 'يجب أن يكون رقماً';
    case 'boolean':
      return value is bool ? null : 'يجب أن يكون true أو false';
    case 'json':
      return value is Map || value is List ? null : 'يجب أن يكون كائناً أو قائمة';
    case 'date':
      return value is String && _dateRe.hasMatch(value) ? null : 'تاريخ بصيغة YYYY-MM-DD';
    case 'time':
      return value is String && _timeRe.hasMatch(value) ? null : 'وقت بصيغة HH:MM';
    case 'timestamp':
      return value is String && DateTime.tryParse(value) != null ? null : 'وقت بصيغة ISO مثل 2025-09-01T08:00:00Z';
    default:
      return value is String || value is num ? null : 'يجب أن يكون نصاً';
  }
}

/// هل ينطبق شرط الفهرس الجزئي على الصف؟ نمط لا نعرفه يُعدّ غير منطبق.
bool _partialIndexApplies(Map row, String where) {
  for (final raw in where.split(RegExp(r'\s+AND\s+', caseSensitive: false))) {
    final clause = raw.trim();
    RegExpMatch? m;
    if ((m = RegExp(r'^(\w+) IS NULL$', caseSensitive: false).firstMatch(clause)) != null) {
      if (!_isEmpty(row[m!.group(1)])) return false;
    } else if ((m = RegExp(r'^(\w+) IS NOT NULL$', caseSensitive: false).firstMatch(clause)) != null) {
      if (row[m!.group(1)] == null) return false;
    } else if ((m = RegExp(r"^(\w+) <> ''$").firstMatch(clause)) != null) {
      if (row[m!.group(1)] == '') return false;
    } else {
      return false;
    }
  }
  return true;
}

String? _uniqueKey(Map row, Map unique) {
  final where = unique['where'];
  if (where is String && !_partialIndexApplies(row, where)) return null;
  final cols = [for (final c in unique['columns'] as List) '$c'];
  if (cols.any((c) => _isEmpty(row[c]))) return null;
  return cols.map((c) => '${row[c]}').join('\u0000');
}

String? _crossFieldError(String table, Map row) {
  if (table == 'sessions' && _isEmpty(row['group_id']) && _isEmpty(row['room_id'])) {
    return 'الحصة بلا مادة ولا شعبة: لا مكان لها في السحابة';
  }
  if (table == 'payments' && _isEmpty(row['student_id']) && _isEmpty(row['payer_name'])) {
    return 'سند بلا طالب وبلا اسم دافع';
  }
  return null;
}

/// يفحص صفوف النسخة مقابل قواعد المخطط — `validateBackupTables`.
///
/// [rows] مفاتيحها أسماء الجداول السحابية. [existingIds] معرّفات الجهاز: المفتاح
/// الأجنبي يُقبل إن وُجد هدفه هنا. [existingRows] صفوف الجهاز لفحص التفرّد معها.
BackupCheckResult validateBackupTables(
  Map<String, List> rows, {
  Map<String, Set<String>> existingIds = const {},
  Map<String, List<Map<String, dynamic>>> existingRows = const {},
}) {
  final errors = <BackupIssue>[];
  final warnings = <BackupIssue>[];
  final counts = <String, int>{};
  var errorCount = 0;
  var total = 0;

  void addError(BackupIssue i) {
    errorCount++;
    if (errors.length < _maxListed) errors.add(i);
  }

  void addWarning(BackupIssue i) {
    if (warnings.length < _maxListed) warnings.add(i);
  }

  final fileIds = <String, Set<String>>{
    for (final e in rows.entries) e.key: {for (final r in e.value) if (r is Map && r['id'] is String) r['id'] as String},
  };
  bool idExists(String table, String id) => (fileIds[table]?.contains(id) ?? false) || (existingIds[table]?.contains(id) ?? false);

  for (final entry in rows.entries) {
    final table = entry.key;
    final list = entry.value;
    final rules = backupTableRules[table];
    if (rules is! Map) {
      addWarning(BackupIssue(table: table, message: 'جدول غير معروف في النظام: سيُتجاهل'));
      continue;
    }
    counts[table] = list.length;
    total += list.length;

    final columns = Map<String, dynamic>.from(rules['columns'] as Map);
    final required = [for (final f in rules['required'] as List) '$f'];
    final uniques = [for (final u in rules['uniques'] as List) u as Map];
    final seenIds = <String>{};
    final seenUnique = [for (final _ in uniques) <String, String>{}];
    final reportedUnknown = <String>{};
    final deviceUnique = [
      for (final u in uniques)
        () {
          final map = <String, String>{};
          for (final d in existingRows[table] ?? const <Map<String, dynamic>>[]) {
            if (d['id'] == null) continue;
            final key = _uniqueKey(d, u);
            if (key != null) map.putIfAbsent(key, () => '${d['id']}');
          }
          return map;
        }(),
    ];

    for (var index = 0; index < list.length; index++) {
      final row = list[index];
      final at = 'الصف ${index + 1}';
      if (row is! Map) {
        addError(BackupIssue(table: table, message: '$at: ليس كائناً'));
        continue;
      }
      final id = row['id'];
      if (id is! String || id.trim().isEmpty) {
        addError(BackupIssue(table: table, field: 'id', message: '$at: بلا معرّف'));
        continue;
      }
      if (!seenIds.add(id)) {
        addError(BackupIssue(table: table, rowId: id, field: 'id', message: 'معرّف مكرر داخل الملف'));
        continue;
      }

      for (final field in required) {
        final blankOk = (_blankAllowed[table]?.contains(field) ?? false) && row[field] == '';
        if (_isEmpty(row[field]) && !blankOk) {
          addError(BackupIssue(table: table, rowId: id, field: field, message: 'حقل إلزامي ناقص'));
        }
      }
      for (final field in _requiredTransactionDates[table] ?? const <String>[]) {
        if (_isEmpty(row[field])) {
          addError(BackupIssue(table: table, rowId: id, field: field, message: 'تاريخ العملية ناقص: ستُسجَّل بتاريخ يوم الاستيراد'));
        }
      }

      for (final e in row.entries) {
        final field = '${e.key}';
        final value = e.value;
        final col = columns[field];
        if (col is! Map) {
          if (reportedUnknown.add(field)) {
            addWarning(BackupIssue(table: table, field: field, message: 'عمود غير موجود في السحابة: سيُحذف عند الرفع'));
          }
          continue;
        }
        if (_isEmpty(value)) {
          if (col['notNull'] == true && value != null && !required.contains(field)) {
            addError(BackupIssue(table: table, rowId: id, field: field, message: 'عمود إلزامي بقيمة فارغة'));
          }
          continue;
        }
        final typeMsg = _typeError('${col['type']}', value);
        if (typeMsg != null) {
          addError(BackupIssue(table: table, rowId: id, field: field, message: typeMsg));
          continue;
        }
        final ref = col['ref'];
        if (ref is String && !idExists(ref, '$value')) {
          addError(BackupIssue(table: table, rowId: id, field: field, message: 'يشير إلى سجل غير موجود في $ref: $value'));
        }
      }

      final cross = _crossFieldError(table, row);
      if (cross != null) addError(BackupIssue(table: table, rowId: id, message: cross));

      for (var i = 0; i < uniques.length; i++) {
        final key = _uniqueKey(row, uniques[i]);
        if (key == null) continue;
        final cols = [for (final c in uniques[i]['columns'] as List) '$c'].join(' + ');
        final first = seenUnique[i][key];
        if (first != null) {
          addError(BackupIssue(table: table, rowId: id, field: cols, message: 'قيمة مكررة، وهي فريدة في القاعدة (تعارض مع $first)'));
        } else {
          seenUnique[i][key] = id;
        }
        final deviceId = deviceUnique[i][key];
        if (deviceId != null && deviceId != id) {
          addError(BackupIssue(
            table: table,
            rowId: id,
            field: cols,
            message: table == 'payments'
                ? 'رقم السند مستعمل لسند آخر على الجهاز ($deviceId): سيُعاد ترقيمه تلقائياً عند الرفع'
                : 'القيمة مستعملة لسجل آخر على الجهاز ($deviceId)',
          ));
        }
      }
    }
  }

  _checkDerivedBalances(rows, addWarning);
  _checkPaymentLinks(rows, existingRows, addError, addWarning);
  return BackupCheckResult(errors: errors, warnings: warnings, counts: counts, total: total, errorCount: errorCount);
}

/// السند المربوط بقسط طالب آخر يشوّه رصيد الطالبين، والعكس المشير إلى سند غائب.
void _checkPaymentLinks(
  Map<String, List> rows,
  Map<String, List<Map<String, dynamic>>> existingRows,
  void Function(BackupIssue) addError,
  void Function(BackupIssue) addWarning,
) {
  final payments = [for (final p in rows['payments'] ?? const []) if (p is Map) p];
  if (payments.isEmpty) return;
  final owner = <String, String>{};
  for (final inst in rows['installments'] ?? const []) {
    if (inst is Map && inst['id'] != null && inst['student_id'] != null) owner['${inst['id']}'] = '${inst['student_id']}';
  }
  for (final inst in existingRows['installments'] ?? const <Map<String, dynamic>>[]) {
    if (inst['id'] != null && inst['student_id'] != null) owner.putIfAbsent('${inst['id']}', () => '${inst['student_id']}');
  }
  final paymentIds = <String>{
    for (final p in payments) if (p['id'] != null) '${p['id']}',
    for (final p in existingRows['payments'] ?? const <Map<String, dynamic>>[]) if (p['id'] != null) '${p['id']}',
  };
  for (final p in payments) {
    if (p['id'] == null) continue;
    final id = '${p['id']}';
    final o = p['installment_id'] == null ? null : owner['${p['installment_id']}'];
    if (o != null && p['student_id'] != null && o != '${p['student_id']}') {
      addError(BackupIssue(table: 'payments', rowId: id, field: 'installment_id', message: 'سند مربوط بقسط طالب آخر ($o)'));
    }
    for (final field in const ['reverses_payment_id', 'reversed_by_payment_id']) {
      final target = p[field];
      if (target != null && '$target'.isNotEmpty && !paymentIds.contains('$target')) {
        addWarning(BackupIssue(table: 'payments', rowId: id, field: field, message: 'يشير إلى سند غير موجود: $target'));
      }
    }
  }
}

/// الرصيد مشتق لا مخزَّن: رصيد افتتاحي بلا أقساط ولا سندات يصير صفراً.
void _checkDerivedBalances(Map<String, List> rows, void Function(BackupIssue) addWarning) {
  final students = [for (final s in rows['students'] ?? const []) if (s is Map) s];
  if (students.isEmpty) return;
  final withRecords = <String>{
    for (final i in rows['installments'] ?? const []) if (i is Map && i['student_id'] != null) '${i['student_id']}',
    for (final p in rows['payments'] ?? const []) if (p is Map && p['student_id'] != null) '${p['student_id']}',
  };
  var affected = 0;
  for (final s in students) {
    final balance = _asNumber(s['balance']) ?? 0;
    if (balance == 0 || withRecords.contains('${s['id']}')) continue;
    affected++;
  }
  if (affected > 0) {
    addWarning(BackupIssue(
      table: 'students',
      field: 'balance',
      message: '$affected طالباً برصيد بلا أقساط ولا سندات: سيصير صفراً لأن الرصيد يُحسب من الأقساط. اجعله قسطاً باسم «رصيد سابق»',
    ));
  }
}

/// المبلغ النصي "200" يكسر حساب الأرصدة: الأعمدة الرقمية تُحوَّل أرقاماً — `normalizeBackupRow`.
Map<String, dynamic> normalizeBackupRow(String table, Map<String, dynamic> row) {
  final rules = backupTableRules[table];
  if (rules is! Map) return row;
  final out = Map<String, dynamic>.from(row);
  for (final e in (rules['columns'] as Map).entries) {
    if ((e.value as Map)['type'] != 'number') continue;
    final v = out[e.key];
    if (v is String && v.trim().isNotEmpty) {
      final n = num.tryParse(v.trim());
      if (n != null) out[e.key] = n;
    }
  }
  return out;
}

/// نص تقرير الفحص كما يُعرض — `formatBackupIssues`.
String formatBackupIssues(List<BackupIssue> issues) => issues
    .map((i) => '${[i.table, i.field, i.rowId].whereType<String>().where((s) => s.isNotEmpty).join(' · ')}: ${i.message}')
    .join('\n');

// ── أعوام الملف المؤقتة — `backupYears.ts` ──────────────────────────────────

/// معرّف عام يبدأ بـ `ay_@` مؤقت: ملف جُهّز خارج البرنامج لا يعرف رقم المنشأة.
const yearPlaceholderPrefix = 'ay_@';

bool isYearPlaceholder(Object? id) => id is String && id.startsWith(yearPlaceholderPrefix);

String _compactLabel(String label) => label.replaceAll(RegExp(r'\s+'), '');

/// يستبدل معرّفات الأعوام المؤقتة في كل جداول النسخة — `remapYearPlaceholders`.
/// [resolve] يعطي المعرّف الحقيقي من تسمية العام.
Map<String, dynamic> remapYearPlaceholders(Map<String, dynamic> data, String Function(String label) resolve) {
  final mapped = <String, String>{};
  final years = data['academicYears'];
  for (final y in years is List ? years : const []) {
    if (y is Map && isYearPlaceholder(y['id']) && !mapped.containsKey(y['id'])) {
      mapped['${y['id']}'] = resolve('${y['label'] ?? ''}');
    }
  }
  if (mapped.isEmpty) return data;
  return {
    for (final e in data.entries)
      e.key: e.value is! List
          ? e.value
          : [
              for (final row in e.value as List)
                if (row is! Map)
                  row
                else
                  {
                    ...row,
                    if (e.key == 'academicYears' && mapped.containsKey(row['id'])) 'id': mapped[row['id']],
                    if (mapped.containsKey(row['academic_year_id'])) 'academic_year_id': mapped[row['academic_year_id']],
                  },
            ],
  };
}

/// العام الحقيقي لتسمية: عام الجهاز بالتسمية نفسها، وإلا المعرّف الحتمي — `pickRealYearId`.
String pickRealYearId(String label, List<({String id, String label})> deviceYears, String Function(String label) deterministicId) {
  for (final y in deviceYears) {
    if (_compactLabel(y.label) == _compactLabel(label)) return y.id;
  }
  return deterministicId(label);
}
