/// نشر العلامات للأهل — المقابل لـ `isGradePublished` في gradeLock.ts و`PublishScope` في types/settings.ts.
///
/// «فور الرصد» (الافتراضي): كل علامة ظاهرة. «بعد اعتماد الإدارة» (`grades_publish_manual`):
/// العلامة تظهر إن شملها النشر العام (`grades_published_until`) أو نشر جزئي لمادة أو صف
/// حتى تاريخ (`grades_published_scoped`). مفروض في القاعدة أيضاً (20261115_grades_publish_scope.sql)،
/// فالبوابة لا ترى ما لم يُنشر مهما كان في الجهاز.
library;

import 'app_settings.dart';

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// نشر علامات مادة أو صف (أو الاثنين) حتى تاريخ.
class PublishScope {
  const PublishScope({required this.until, this.subjectId = '', this.grade = ''});

  final String until;
  final String subjectId;
  final String grade;

  Map<String, dynamic> toMap() => {
        'until': until,
        if (subjectId.isNotEmpty) 'subject_id': subjectId,
        if (grade.isNotEmpty) 'grade': grade,
      };
}

extension GradePublishSettings on AppSettings {
  bool get gradesPublishManual => extra['grades_publish_manual'] == true;

  String get gradesPublishedUntil {
    final v = '${extra['grades_published_until'] ?? ''}';
    return _dateRe.hasMatch(v) ? v : '';
  }

  List<PublishScope> get gradesPublishedScoped {
    final raw = extra['grades_published_scoped'];
    if (raw is! List) return const [];
    return [
      for (final p in raw)
        if (p is Map && _dateRe.hasMatch('${p['until'] ?? ''}') && ('${p['subject_id'] ?? ''}'.isNotEmpty || '${p['grade'] ?? ''}'.trim().isNotEmpty))
          PublishScope(until: '${p['until']}', subjectId: '${p['subject_id'] ?? ''}', grade: '${p['grade'] ?? ''}'.trim()),
    ];
  }
}

/// هل تظهر العلامة للأهل؟ [manual] يتجاوز إعداد المدرسة (عدّ ما ينتظر الاعتماد).
bool isGradePublished(String evaluationDate, AppSettings s, {String subjectId = '', String grade = '', bool? manual}) {
  if (!(manual ?? s.gradesPublishManual)) return true;
  if (evaluationDate.length < 10) return false;
  final date = evaluationDate.substring(0, 10);
  final until = s.gradesPublishedUntil;
  if (until.isNotEmpty && date.compareTo(until) <= 0) return true;
  final g = grade.trim();
  return s.gradesPublishedScoped.any(
    (p) => date.compareTo(p.until) <= 0 && (p.subjectId.isEmpty || p.subjectId == subjectId) && (p.grade.isEmpty || p.grade == g),
  );
}
