import 'dart:async';
import 'dart:convert';

import '../models/models.dart';
import 'grading.dart';
import 'institution.dart';
import 'local_db.dart';
import 'portal.dart';
import 'supabase.dart';

/// عمل بوابة المعلم بلا إنترنت — المقابل لما تفعله الإدارة بقاعدتها المحلية.
///
/// ما يصل من السحابة يُحفظ على الجهاز، فيُفتح في المرة التالية ولو بلا شبكة.
/// وما يرصده المعلم يُطبَّق محلياً ويُصفّ في طابور يُرفع أول ما يعود الاتصال،
/// فلا ينتظر المعلم شبكةً ليرصد حضوراً أو درجة.
class PortalOffline {
  PortalOffline(this._db);

  final Persistence _db;

  static const _kData = 'portal_cache_data';
  static const _kSections = 'portal_cache_sections';
  static const _kMarks = 'portal_cache_marks';
  static const _kEvaluations = 'portal_cache_evals';
  static const _kQueue = 'portal_pending_ops';
  static const _kSyncedAt = 'portal_cache_synced_at';

  Map<String, dynamic> _read(String key) {
    final raw = _db.settings[key];
    if (raw == null || raw.isEmpty) return {};
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String key, Object value) => _db.setSetting(key, jsonEncode(value));

  /// آخر مرة وصلت فيها بيانات من السحابة.
  DateTime? get syncedAt => DateTime.tryParse(_db.settings[_kSyncedAt] ?? '');

  /// آخر مرة اكتمل فيها تنزيل موارد المعلم (مودل/درجات/حضور).
  DateTime? get resourcesHydratedAt => DateTime.tryParse(_db.settings['portal_teacher_hydrated_at'] ?? '');

  Future<void> markResourcesHydrated() =>
      _db.setSetting('portal_teacher_hydrated_at', DateTime.now().toIso8601String());

  // ── صفوف المعلم وطلابه ────────────────────────────────────────────────────

  /// حفظ نسخة الجهاز. الردّ الناقص لا يُكتب: فتح البوابة بلا شبكة كان يبني
  /// نسخةً فارغة (لا مجموعات ولا طلاب) ويضعها مكان كشوف المعلم، فيصبح بلا
  /// صفوف ولا شعبة يربّيها حتى ينجح سحبٌ كامل. الناقص يُعرض ولا يُحفظ.
  Future<void> saveTeacherData(TeacherPortalData data) async {
    if (!data.complete) return;
    await _write(_kData, {
      'classes': [
        for (final c in data.classes)
          {
            'group': c.group.toCloud(),
            'subject_name': c.subjectName,
            'room_name': c.roomName,
            'rooms': [
              for (final r in c.rooms) {'id': r.id, 'name': r.name, 'grade_level': r.gradeLevel},
            ],
            'students': [for (final s in c.students) s.toCloud()],
          },
      ],
      'branding': {
        'name': data.branding.name,
        'logo': data.branding.logo,
        // الألوان تُحفظ معها: البوابة تفتح بلا شبكة بهوية المدرسة لا بالافتراضي
        'colors': data.branding.colors.toMap(),
        'grading_scheme': data.branding.gradingScheme.toMap(),
      },
      // أسماء المواد: بلا حفظها يفتح المعلم «الدرجات» بلا نت على قائمة مواد فارغة
      'subjects': [for (final s in data.subjects) s.toCloud()],
      // الميزات تُحفظ حتى لا تختفي تبويبات المودل/الدرجات عند فتح البوابة بلا نت
      if (data.features != null) 'features': data.features,
    });
    await _db.setSetting(_kSyncedAt, DateTime.now().toIso8601String());
  }

  /// آخر نسخة محفوظة، أو `null` إن لم يسبق أن وصلت بيانات على هذا الجهاز.
  TeacherPortalData? loadTeacherData() {
    final raw = _read(_kData);
    if (raw.isEmpty) return null;
    final classesRaw = raw['classes'];
    if (classesRaw is! List) return null;

    final brandingRaw = raw['branding'];
    final branding = brandingRaw is Map
        ? PortalBranding(
            name: '${brandingRaw['name'] ?? ''}',
            logo: '${brandingRaw['logo'] ?? ''}',
            colors: InstitutionColors.fromMap(
              brandingRaw['colors'] is Map ? Map<String, dynamic>.from(brandingRaw['colors'] as Map) : null,
            ),
            gradingScheme: brandingRaw['grading_scheme'] is Map
                ? GradingScheme.fromMap(Map<String, dynamic>.from(brandingRaw['grading_scheme'] as Map))
                : GradingScheme.empty,
          )
        : const PortalBranding();

    final featuresRaw = raw['features'];
    final subjectsRaw = raw['subjects'];
    return TeacherPortalData(
      branding: branding,
      features: featuresRaw is Map ? Map<String, dynamic>.from(featuresRaw) : null,
      subjects: [
        if (subjectsRaw is List)
          for (final s in subjectsRaw)
            if (s is Map) SubjectItem.fromCloud(Map<String, dynamic>.from(s)),
      ],
      classes: [
        for (final c in classesRaw)
          if (c is Map)
            TeacherClass(
              group: Group.fromCloud(Map<String, dynamic>.from(c['group'] as Map)),
              subjectName: '${c['subject_name'] ?? ''}',
              roomName: '${c['room_name'] ?? ''}',
              rooms: [
                for (final r in (c['rooms'] as List? ?? const []))
                  if (r is Map)
                    PortalRoom(
                      id: '${r['id'] ?? ''}',
                      name: '${r['name'] ?? ''}',
                      gradeLevel: '${r['grade_level'] ?? ''}',
                    ),
              ],
              students: [
                for (final s in (c['students'] as List? ?? const []))
                  if (s is Map) Student.fromCloud(Map<String, dynamic>.from(s)),
              ],
            ),
      ],
    );
  }

  /// وصف عربي لعملية معلّقة — ورقة تفاصيل المزامنة في بوابة المعلم.
  static String pendingOpLabel(Map<String, dynamic> op) {
    switch ('${op['kind']}') {
      case 'attendance':
        return 'رصد حضور · ${op['date'] ?? ''}';
      case 'evaluations':
        final n = (op['rows'] as List?)?.length ?? 0;
        return n > 0 ? 'درجات ($n)' : 'درجات';
      case 'evaluation_score':
        return 'تعديل علامة';
      case 'evaluation_delete':
        return 'حذف تقييم';
      case 'section_upsert':
        return 'وحدة دراسية';
      case 'section_visible':
        return 'إظهار/إخفاء وحدة';
      case 'section_delete':
        return 'حذف وحدة';
      case 'item_upsert':
        return 'مادة / واجب';
      case 'item_delete':
        return 'حذف مادة';
      default:
        return '${op['kind'] ?? 'عملية'}';
    }
  }

  // ── وحدات المودل ─────────────────────────────────────────────────────────

  String _sectionsKey(String groupId, String term) => '$groupId|$term';

  Future<void> saveSections(String groupId, String term, List<CourseSection> sections) async {
    final all = _read(_kSections);
    all[_sectionsKey(groupId, term)] = [
      // الوحدة ومحتواها معاً: المودل بلا شبكة يحتاج الملفات والواجبات لا العناوين فقط
      for (final s in sections) {...s.toCloud(), 'items': [for (final i in s.items) i.toCloud()]},
    ];
    await _write(_kSections, all);
  }

  List<CourseSection>? loadSections(String groupId, String term) {
    final raw = _read(_kSections)[_sectionsKey(groupId, term)];
    if (raw is! List) return null;
    return [
      for (final s in raw)
        if (s is Map)
          CourseSection.fromCloud(Map<String, dynamic>.from(s)).copyWith(
            items: [
              for (final i in (s['items'] as List? ?? const []))
                if (i is Map) CourseItem.fromCloud(Map<String, dynamic>.from(i)),
            ],
          ),
    ];
  }

  // ── كشف حضور يوم ─────────────────────────────────────────────────────────

  String _marksKey(String roomId, String date) => '$roomId|$date';

  Future<void> saveMarks(String roomId, String date, Map<String, String> statuses) async {
    final all = _read(_kMarks);
    all[_marksKey(roomId, date)] = statuses;
    await _write(_kMarks, all);
  }

  /// رصد أيام الأسبوع المحفوظة لشعبة — ما لم يُحفظ منها لا يظهر.
  Map<String, Map<String, String>> loadWeekMarks(String roomId, List<String> dates) => {
        for (final date in dates) date: ?loadMarks(roomId, date),
      };

  Map<String, String>? loadMarks(String roomId, String date) {
    final raw = _read(_kMarks)[_marksKey(roomId, date)];
    if (raw is! Map) return null;
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }

  // ── سجل الدرجات ──────────────────────────────────────────────────────────

  Future<void> saveEvaluations(String groupId, List<StudentEvaluation> rows) async {
    final all = _read(_kEvaluations);
    all[groupId] = [for (final e in rows) e.toCloud()];
    await _write(_kEvaluations, all);
  }

  List<StudentEvaluation>? loadEvaluations(String groupId) {
    final raw = _read(_kEvaluations)[groupId];
    if (raw is! List) return null;
    return [
      for (final e in raw)
        if (e is Map) StudentEvaluation.fromCloud(Map<String, dynamic>.from(e)),
    ];
  }

  // ── طابور ما لم يُرفع بعد ────────────────────────────────────────────────

  List<Map<String, dynamic>> get pending {
    final raw = _db.settings[_kQueue];
    if (raw == null || raw.isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      return value is List ? [for (final e in value) Map<String, dynamic>.from(e as Map)] : const [];
    } catch (_) {
      return const [];
    }
  }

  /// ما ينتظر الرفع من رصد هذا المعلم وحده — رصد زميله لا يُرفع باسمه.
  List<Map<String, dynamic>> pendingOf(String userId) =>
      [for (final op in pending) if ('${op['user_id'] ?? ''}' == userId) op];

  int pendingCountOf(String userId) => pendingOf(userId).length;

  Future<void> _setPending(List<Map<String, dynamic>> ops) => _db.setSetting(_kQueue, jsonEncode(ops));

  /// رصد حضور ينتظر الرفع. الكشف الواحد يُستبدل بأحدثه: رصدٌ للشعبة نفسها
  /// وليومها لا يُرفع مرتين.
  Future<void> queueAttendance({
    required String roomId,
    required String date,
    required Map<String, String> statuses,
    required String userId,
  }) async {
    final ops = [...pending]..removeWhere(
        (op) => op['kind'] == 'attendance' && op['room_id'] == roomId && op['date'] == date,
      );
    ops.add({
      'kind': 'attendance',
      'user_id': userId,
      'room_id': roomId,
      'date': date,
      'statuses': statuses,
    });
    await _setPending(ops);
  }

  /// كشف درجات ينتظر الرفع.
  Future<void> queueEvaluations(List<StudentEvaluation> batch, String tenantId, String userId) async {
    if (batch.isEmpty) return;
    final ops = [...pending];
    ops.add({
      'kind': 'evaluations',
      'user_id': userId,
      'tenant_id': tenantId,
      'rows': [for (final e in batch) e.toCloud()],
    });
    await _setPending(ops);

    // تُضاف إلى سجل مادتها أيضاً: المعلم يرى ما رصده توّاً ولو بلا شبكة
    final byGroup = <String, List<StudentEvaluation>>{};
    for (final e in batch) {
      if (e.groupId.isNotEmpty) byGroup.putIfAbsent(e.groupId, () => []).add(e);
    }
    for (final entry in byGroup.entries) {
      await saveEvaluations(entry.key, [...entry.value, ...?loadEvaluations(entry.key)]);
    }
  }

  /// عملية عامة تنتظر الرفع: وحدة أُنشئت، أو علامة عُدّلت، أو قسم حُذف.
  Future<void> queueOp(Map<String, dynamic> op, String userId) async {
    await _setPending([...pending, {...op, 'user_id': userId}]);
  }

  /// رفع ما في الطابور. يعيد عدد ما رُفع، ويترك ما تعذّر رفعه مكانه.
  Future<int> flush(PortalService service, PortalUser user) async {
    final all = pending;
    if (all.isEmpty) return 0;

    // رصد معلم آخر على الجهاز نفسه يبقى في مكانه حتى يدخل صاحبه
    final remaining = [for (final op in all) if ('${op['user_id'] ?? ''}' != user.id) op];
    var done = 0;
    for (final op in pendingOf(user.id)) {
      try {
        switch ('${op['kind']}') {
          case 'attendance':
            await service.saveAttendance(
              roomId: '${op['room_id']}',
              date: '${op['date']}',
              statuses: {
                for (final e in (op['statuses'] as Map? ?? {}).entries) '${e.key}': '${e.value}',
              },
              teacher: user,
            );
            done++;
          case 'evaluations':
            await service.saveEvaluations(
              [
                for (final r in (op['rows'] as List? ?? const []))
                  if (r is Map) StudentEvaluation.fromCloud(Map<String, dynamic>.from(r)),
              ],
              '${op['tenant_id']}',
            );
            done++;
          case 'evaluation_score':
            await service.updateEvaluationScore('${op['id']}', (op['score'] as num).toDouble());
            done++;
          case 'evaluation_delete':
            await service.deleteEvaluation('${op['id']}');
            done++;
          case 'section_upsert':
            await service.saveSection(CourseSection.fromCloud(Map<String, dynamic>.from(op['row'] as Map)));
            done++;
          case 'section_visible':
            await service.setSectionVisible('${op['id']}', op['visible'] == true);
            done++;
          case 'section_delete':
            await service.deleteSection(
              CourseSection.fromCloud(Map<String, dynamic>.from(op['row'] as Map)).copyWith(
                items: [
                  for (final i in (op['items'] as List? ?? const []))
                    if (i is Map) CourseItem.fromCloud(Map<String, dynamic>.from(i)),
                ],
              ),
              '${op['tenant_id']}',
            );
            done++;
          case 'item_upsert':
            await service.saveItem(CourseItem.fromCloud(Map<String, dynamic>.from(op['row'] as Map)));
            done++;
          case 'item_delete':
            await service.deleteItem(
              CourseItem.fromCloud(Map<String, dynamic>.from(op['row'] as Map)),
              '${op['tenant_id']}',
            );
            done++;
          default:
            // عملية لا نعرفها: تُسقط بدل أن تعلق الطابور إلى الأبد
            break;
        }
      } on MoodleNotSaved {
        // السحابة ردّت ولم تقبل (لا صلاحية أو حُذف العنصر): إعادتها لن تنجح أبداً
      } catch (_) {
        remaining.add(op);
      }
    }
    await _setPending(remaining);
    return done;
  }

  /// هل السحابة في المتناول الآن؟ فحص سريع قبل محاولة الرفع.
  Future<bool> online() => probeCloud();

  /// خروج المعلم: تُمسح النسخة المعروضة من الجهاز. أما ما رُصد ولم يُرفع بعد
  /// فيبقى — إتلافه يضيّع كشف صفٍّ حقيقياً، ويُرفع حين يدخل صاحبه ومعه شبكة.
  Future<void> clear() async {
    for (final key in [_kData, _kSections, _kMarks, _kEvaluations, _kSyncedAt]) {
      await _db.setSetting(key, null);
    }
  }

  /// مسح كل شيء بما فيه الطابور — للاختبارات وإعادة ضبط الجهاز.
  Future<void> clearAll() async {
    await clear();
    await _db.setSetting(_kQueue, null);
  }
}
