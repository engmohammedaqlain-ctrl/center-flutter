import 'portal.dart';
import 'portal_offline.dart';

/// تقدّم تحميل موارد بوابة المعلم — المقابل لـ [PullProgress] عند الإدارة.
class TeacherResourceProgress {
  const TeacherResourceProgress({
    required this.percent,
    required this.label,
    this.detail = '',
    this.records = 0,
  });

  /// 0–100 موزونة على مراحل حقيقية لا بالتساوي فقط.
  final int percent;
  final String label;
  final String detail;
  final int records;
}

typedef TeacherResourceProgressCallback = void Function(TeacherResourceProgress progress);

/// مهلة طلب واحد داخل تحميل موارد المعلم.
const teacherResourceTimeout = Duration(seconds: 12);

/// أيام أسبوع الرصد الحالي (سبت←خميس) كتاريخ ISO — مطابق لكشف المعلم.
List<String> teacherWeekDates([DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final saturday = today.subtract(Duration(days: (n.weekday + 1) % 7));
  return [
    for (var i = 0; i < 6; i++)
      () {
        final d = saturday.add(Duration(days: i));
        final m = d.month.toString().padLeft(2, '0');
        final day = d.day.toString().padLeft(2, '0');
        return '${d.year}-$m-$day';
      }(),
  ];
}

/// هل اكتمل تجهيز موارد هذا المعلم على الجهاز من قبل؟
bool teacherResourcesReady(PortalOffline offline) => offline.loadTeacherData() != null;

/// هل اكتمل تنزيل كامل خلال الدقائق الأخيرة؟ لتجنّب تكرار فوري بعد صفحة التجهيز.
bool teacherResourcesFresh(PortalOffline offline, {Duration maxAge = const Duration(minutes: 15)}) {
  final at = offline.resourcesHydratedAt;
  if (at == null) return false;
  return DateTime.now().difference(at) < maxAge;
}

/// تحميل مرتّب لموارد المعلم فقط (صفوف ← مودل ← درجات ← حضور) مع نسبة دقيقة.
///
/// لا يمس جداول الإدارة. يُستدعى من شاشة التجهيز أو بالخلفية بعد فتح البوابة.
Future<TeacherPortalData> hydrateTeacherResources({
  required PortalService service,
  required PortalOffline offline,
  required PortalUser user,
  TeacherResourceProgressCallback? onProgress,
  bool Function()? isCancelled,
}) async {
  var cancelled = false;
  bool stop() => cancelled || (isCancelled?.call() ?? false);

  void report({
    required int percent,
    required String label,
    String detail = '',
    int records = 0,
  }) {
    onProgress?.call(TeacherResourceProgress(
      percent: percent.clamp(0, 100),
      label: label,
      detail: detail,
      records: records,
    ));
  }

  report(percent: 2, label: 'جاري الاتصال بالسحابة…');

  // ── 0–20٪: بيانات الصفوف والطلاب ──────────────────────────────────────────
  final data = await service.teacherData(user).timeout(teacherResourceTimeout);
  // ردّ ناقص = الشبكة لم تُجب. المضيّ به يُعلن «تم التجهيز» على لا شيء،
  // ويُسجَّل التنزيل مكتملاً فلا يُعاد.
  if (!data.complete) throw const PortalUnavailable('موارد المعلم');
  if (stop()) return data;
  await offline.saveTeacherData(data);
  final classes = data.classes;
  final n = classes.isEmpty ? 1 : classes.length;
  var records = classes.fold<int>(0, (s, c) => s + c.students.length) +
      data.homerooms.fold<int>(0, (s, h) => s + h.students.length);
  report(
    percent: 20,
    label: 'حفظ صفوفك وطلابك…',
    detail: classes.isEmpty ? 'لا مواد مسندة' : '${classes.length} مادة',
    records: records,
  );
  if (classes.isEmpty) {
    report(percent: 100, label: 'تم تجهيز مواردك', records: records);
    return data;
  }

  // ── 20–55٪: المودل ────────────────────────────────────────────────────────
  for (var i = 0; i < classes.length; i++) {
    if (stop()) return data;
    final c = classes[i];
    final name = c.subjectName.trim().isEmpty ? 'مادة' : c.subjectName.trim();
    report(
      percent: 20 + ((i / n) * 35).floor(),
      label: 'تنزيل المودل…',
      detail: name,
      records: records,
    );
    for (final t in const ['term_1', 'term_2', 'other']) {
      if (stop()) return data;
      try {
        final list = await service
            .groupSections(
              tenantId: user.tenantId,
              groupId: c.group.id,
              term: t,
              includeHidden: true,
            )
            .timeout(teacherResourceTimeout);
        await offline.saveSections(c.group.id, t, list);
        records += list.fold<int>(0, (s, sec) => s + 1 + sec.items.length);
      } catch (_) {}
    }
    report(
      percent: 20 + (((i + 1) / n) * 35).floor(),
      label: 'تنزيل المودل…',
      detail: name,
      records: records,
    );
  }

  // ── 55–80٪: الدرجات ───────────────────────────────────────────────────────
  for (var i = 0; i < classes.length; i++) {
    if (stop()) return data;
    final c = classes[i];
    final name = c.subjectName.trim().isEmpty ? 'مادة' : c.subjectName.trim();
    report(
      percent: 55 + ((i / n) * 25).floor(),
      label: 'تنزيل الدرجات…',
      detail: name,
      records: records,
    );
    try {
      final list = await service.groupEvaluations(c.group.id).timeout(teacherResourceTimeout);
      await offline.saveEvaluations(c.group.id, list);
      records += list.length;
    } catch (_) {}
    report(
      percent: 55 + (((i + 1) / n) * 25).floor(),
      label: 'تنزيل الدرجات…',
      detail: name,
      records: records,
    );
  }

  // ── 80–98٪: حضور أسبوع اليوم ─────────────────────────────────────────────
  final dates = teacherWeekDates();
  for (var i = 0; i < classes.length; i++) {
    if (stop()) return data;
    final c = classes[i];
    final name = c.subjectName.trim().isEmpty ? 'مادة' : c.subjectName.trim();
    report(
      percent: 80 + ((i / n) * 18).floor(),
      label: 'تنزيل الحضور…',
      detail: name,
      records: records,
    );
    final roomIds = <String>{
      for (final r in c.rooms)
        if (r.id.isNotEmpty) r.id,
      if (c.group.roomId.isNotEmpty) c.group.roomId,
    };
    for (final roomId in roomIds) {
      if (stop()) return data;
      try {
        final roomOf = {
          for (final s in c.students)
            s.id: () {
              final matched = c.roomIdFor(s.section);
              return matched.isNotEmpty ? matched : roomId;
            }(),
        };
        final saved = await service
            .weekTeacherAttendance(groupId: c.group.id, dates: dates, roomOf: roomOf)
            .timeout(teacherResourceTimeout);
        for (final e in saved.entries) {
          await offline.saveMarks(roomId, e.key, e.value);
          records += e.value.length;
        }
      } catch (_) {
        try {
          final saved = await service.weekAttendance(roomId, dates).timeout(teacherResourceTimeout);
          for (final e in saved.entries) {
            await offline.saveMarks(roomId, e.key, e.value);
            records += e.value.length;
          }
        } catch (_) {}
      }
    }
    report(
      percent: 80 + (((i + 1) / n) * 18).floor(),
      label: 'تنزيل الحضور…',
      detail: name,
      records: records,
    );
  }

  report(percent: 100, label: 'تم تجهيز مواردك', records: records);
  await offline.markResourcesHydrated();
  return data;
}
