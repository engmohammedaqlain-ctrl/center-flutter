/// سجلات تحذفها النسخة عند استرجاعها — `backupDeletions.ts` في الويب.
///
/// الاسترجاع دمج: ما في الملف يُكتب فوق ما على الجهاز، وما ليس فيه يبقى. ملف ترحيل يعيد
/// بناء خطة الرسوم (أقساط ثابتة صارت شهرية) يترك القديمة بجوار الجديدة، فيُطالَب الطالب
/// مرتين. الملف يسمّي ما استُبدل في `deleted` فيُحذف مع الاسترجاع.
///
/// السندات لا تُحذف أبداً (السحابة ترفض، وأثرها المالي يُلغى بإلغاء السند لا بحذفه).
library;

const undeletableBackupTables = {'payments', 'expenses', 'teacherPayouts', 'auditLog'};

/// حذف واحد: اسم جدول الجهاز (كما في الملف) ومعرّفاته.
typedef BackupDeletion = ({String table, List<String> ids});

/// يقرأ `deleted` من الملف: { جدول الجهاز: [معرّفات] }. المعرّف الموجود في بيانات الملف
/// نفسها لا يُحذف (الملف يكتبه). جدول غير معروف أو سندات: خطأ يمنع الاسترجاع كله.
List<BackupDeletion> backupDeletions(Object? deleted, Map<String, dynamic> data, Iterable<String> knownTables) {
  if (deleted == null) return const [];
  if (deleted is! Map) throw const FormatException('قائمة المحذوفات في الملف غير مفهومة');

  final known = knownTables.toSet();
  final out = <BackupDeletion>[];
  for (final e in deleted.entries) {
    final table = '${e.key}';
    final ids = e.value;
    if (!known.contains(table)) throw FormatException('قائمة المحذوفات تذكر جدولاً غير معروف: $table');
    if (undeletableBackupTables.contains(table)) {
      throw const FormatException('الملف يطلب حذف سجلات مالية، والسندات لا تُحذف');
    }
    if (ids is! List || ids.any((id) => id is! String || id.isEmpty)) {
      throw FormatException('قائمة المحذوفات في «$table» غير مفهومة');
    }
    final rows = data[table];
    final kept = {if (rows is List) for (final r in rows) if (r is Map) '${r['id']}'};
    final list = [for (final id in ids.cast<String>().toSet()) if (!kept.contains(id)) id];
    if (list.isNotEmpty) out.add((table: table, ids: list));
  }
  return out;
}
