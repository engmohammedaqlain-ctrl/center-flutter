/// اعتماد العلامات — المقابل لـ `features/evaluations/gradeApproval.ts`.
///
/// في وضع «بعد اعتماد الإدارة» يرصد المعلم الاختبار، ثم تعتمده الإدارة، ثم تنشره وقت
/// ما تشاء. الاختبار المعتمد لا يعدّله المعلم، والإدارة تعدّله بسبب يُكتب في السجل.
/// وحدة الاعتماد «الاختبار»: شعبة المادة وعنوانه وتاريخه، والمفتاح من حقوله فيثبت على كل جهاز.
library;

import '../models/models.dart';
import 'app_settings.dart';

/// تعديل علامة اختبار معتمد بلا سبب: الشاشة تسأل عن السبب وتعيد المحاولة.
class ApprovedReasonRequired extends StoreException {
  ApprovedReasonRequired() : super('اكتب سبب تعديل علامة معتمدة');
}

/// رسالة المعلم حين يعدّل اختباراً معتمداً.
const approvedTeacherMessage = 'اعتمدته الإدارة: التعديل من الإدارة وحدها';

String approvalKey({required String groupId, required String subjectId, required String title, required String date}) =>
    [groupId, subjectId, title.trim(), date].join('|');

/// اعتماد واحد: متى ومن.
typedef ApprovalMark = ({String at, String by});

extension GradeApprovalSettings on AppSettings {
  /// `settings.grades_approved`: مفتاح الاختبار ← من اعتمده ومتى.
  Map<String, ApprovalMark> get gradesApproved {
    final raw = extra['grades_approved'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is Map) '${e.key}': (at: '${(e.value as Map)['at'] ?? ''}', by: '${(e.value as Map)['by'] ?? ''}'),
    };
  }
}

Map<String, dynamic> approvalsToMap(Map<String, ApprovalMark> a) => {
      for (final e in a.entries) e.key: {'at': e.value.at, 'by': e.value.by},
    };

/// اعتماد اختبارات: الموجود يبقى بتاريخه الأول.
Map<String, ApprovalMark> withApproved(Map<String, ApprovalMark> current, Iterable<String> keys, String by) {
  final at = DateTime.now().toUtc().toIso8601String();
  return {
    ...current,
    for (final k in keys)
      if (!current.containsKey(k)) k: (at: at, by: by),
  };
}

/// إلغاء اعتماد (للإدارة): يعود الاختبار قابلاً لتعديل المعلم.
Map<String, ApprovalMark> withoutApproved(Map<String, ApprovalMark> current, Iterable<String> keys) {
  final drop = keys.toSet();
  return {
    for (final e in current.entries)
      if (!drop.contains(e.key)) e.key: e.value,
  };
}

/// اختبار مرصود بانتظار الاعتماد.
class PendingTest {
  PendingTest({
    required this.key,
    required this.groupId,
    required this.subjectId,
    required this.teacherId,
    required this.title,
    required this.date,
  });

  final String key;
  final String groupId;
  final String subjectId;
  final String teacherId;
  final String title;
  final String date;
  int count = 1;
}

/// الاختبارات المرصودة غير المعتمدة، الأقدم أولاً. `rows` تقييمات العام بحقول المفتاح.
List<PendingTest> pendingTests(
  Iterable<({String groupId, String subjectId, String teacherId, String title, String date})> rows,
  Map<String, ApprovalMark> approvals,
) {
  final map = <String, PendingTest>{};
  for (final r in rows) {
    if (r.subjectId.isEmpty || r.groupId.isEmpty) continue;
    final key = approvalKey(groupId: r.groupId, subjectId: r.subjectId, title: r.title, date: r.date);
    if (approvals.containsKey(key)) continue;
    final row = map[key];
    if (row != null) {
      row.count++;
    } else {
      map[key] = PendingTest(key: key, groupId: r.groupId, subjectId: r.subjectId, teacherId: r.teacherId, title: r.title, date: r.date);
    }
  }
  return map.values.toList()..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.title.compareTo(b.title));
}
