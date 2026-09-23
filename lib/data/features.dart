/// ميزات كل مدرسة — المقابل لـ `lib/features.ts` في الويب.
///
/// القيم في `tenants.features`؛ المفتاح الغائب يأخذ افتراضه، والمجهول يُتجاهل.
/// التبعية تُحسب عند القراءة ولا تُكتب.
library;

const featureKeys = <String>[
  'attendance',
  'evaluations',
  'moodle',
  'finance.expenses',
  'students.attachments',
  'portal.teacher',
  'portal.teacher.class',
  'portal.teacher.attendance',
  'portal.teacher.grades',
  'portal.teacher.moodle',
  'portal.student',
  'portal.parent',
  'portal.student.moodle',
  'portal.attendance',
  'portal.grades',
  'portal.finance',
];

typedef FeatureState = Map<String, bool>;
typedef FeatureMap = Map<String, bool>;

enum FeatureGroup { modules, teacherPortal, familyPortal, administration }

class FeatureDef {
  const FeatureDef({
    required this.label,
    required this.description,
    required this.group,
    required this.defaultOn,
    this.requires = const [],
    this.requiresAny = const [],
  });

  final String label;
  final String description;
  final FeatureGroup group;
  final bool defaultOn;
  final List<String> requires;
  final List<String> requiresAny;
}

const featureGroups = <({FeatureGroup key, String label})>[
  (key: FeatureGroup.modules, label: 'الوحدات'),
  (key: FeatureGroup.teacherPortal, label: 'بوابة المعلم'),
  (key: FeatureGroup.familyPortal, label: 'بوابة الطالب وولي الأمر'),
  (key: FeatureGroup.administration, label: 'الإدارة'),
];

const _familyPortals = ['portal.student', 'portal.parent'];

const features = <String, FeatureDef>{
  'attendance': FeatureDef(
    label: 'الحضور',
    description: 'قسم الحضور، وإحصاءاته في ملف الطالب',
    group: FeatureGroup.modules,
    defaultOn: true,
  ),
  'evaluations': FeatureDef(
    label: 'الدرجات',
    description: 'قسم الدرجات ونظام العلامات',
    group: FeatureGroup.modules,
    defaultOn: true,
  ),
  'moodle': FeatureDef(
    label: 'المودل',
    description: 'الوحدات والملفات والواجبات',
    group: FeatureGroup.modules,
    defaultOn: true,
  ),
  'finance.expenses': FeatureDef(
    label: 'المصروفات والرواتب',
    description: 'سندات صرف المصروفات ورواتب المعلمين',
    group: FeatureGroup.administration,
    defaultOn: true,
  ),
  'students.attachments': FeatureDef(
    label: 'مرفقات الطلاب',
    description: 'صورة الهوية وشهادة الميلاد',
    group: FeatureGroup.administration,
    defaultOn: false,
  ),
  'portal.teacher': FeatureDef(
    label: 'بوابة المعلم',
    description: 'دخول المعلم برقم الهوية وكلمة المرور',
    group: FeatureGroup.teacherPortal,
    defaultOn: true,
  ),
  'portal.teacher.attendance': FeatureDef(
    label: 'رصد الحضور',
    description: 'يرصد حضور شعبه',
    group: FeatureGroup.teacherPortal,
    defaultOn: true,
    requires: ['portal.teacher', 'attendance'],
  ),
  'portal.teacher.grades': FeatureDef(
    label: 'رصد الدرجات',
    description: 'يرصد درجات طلابه',
    group: FeatureGroup.teacherPortal,
    defaultOn: true,
    requires: ['portal.teacher', 'evaluations'],
  ),
  'portal.teacher.moodle': FeatureDef(
    label: 'محتوى المودل',
    description: 'يضيف الوحدات والملفات والواجبات',
    group: FeatureGroup.teacherPortal,
    defaultOn: true,
    requires: ['portal.teacher', 'moodle'],
  ),
  'portal.teacher.class': FeatureDef(
    label: 'صفي',
    description: 'شعبة المربي: الطلاب وكلمات المرور والدرجات بلا مالية',
    group: FeatureGroup.teacherPortal,
    defaultOn: true,
    requires: ['portal.teacher'],
  ),
  'portal.student': FeatureDef(
    label: 'بوابة الطالب',
    description: 'دخول الطالب برقم هويته',
    group: FeatureGroup.familyPortal,
    defaultOn: true,
  ),
  'portal.parent': FeatureDef(
    label: 'بوابة ولي الأمر',
    description: 'دخول ولي الأمر ومتابعة أبنائه',
    group: FeatureGroup.familyPortal,
    defaultOn: true,
  ),
  'portal.student.moodle': FeatureDef(
    label: 'مودل الطالب',
    description: 'تبويب المودل في بوابة الطالب',
    group: FeatureGroup.familyPortal,
    defaultOn: true,
    requires: ['portal.student', 'moodle'],
  ),
  'portal.attendance': FeatureDef(
    label: 'الحضور',
    description: 'سجل الحضور',
    group: FeatureGroup.familyPortal,
    defaultOn: true,
    requires: ['attendance'],
    requiresAny: _familyPortals,
  ),
  'portal.grades': FeatureDef(
    label: 'الدرجات',
    description: 'الدرجات والنتائج',
    group: FeatureGroup.familyPortal,
    defaultOn: true,
    requires: ['evaluations'],
    requiresAny: _familyPortals,
  ),
  'portal.finance': FeatureDef(
    label: 'الرسوم',
    description: 'الأقساط والسندات',
    group: FeatureGroup.familyPortal,
    defaultOn: true,
    requiresAny: _familyPortals,
  ),
};

/// أقسام الإدارة المرتبطة بميزة.
const sectionFeature = <String, String>{
  'attendance': 'attendance',
  'evaluations': 'evaluations',
  'moodle': 'moodle',
};

bool isFeatureKey(String key) => featureKeys.contains(key);

/// القيم المخزنة المعروفة وحدها، بلا تبعيات.
FeatureMap normalizeFeatures(Object? raw) {
  final out = <String, bool>{};
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final key = '${e.key}';
    final value = e.value;
    if (isFeatureKey(key) && value is bool) out[key] = value;
  }
  return out;
}

/// القيمة المختارة للمفتاح (المخزنة أو الافتراضية) دون تبعياته.
FeatureState selectedFeatures(Object? raw) {
  final stored = normalizeFeatures(raw);
  return {
    for (final key in featureKeys) key: stored[key] ?? features[key]!.defaultOn,
  };
}

/// الحالة الفعلية: المفتاح مختار وكل ما يعتمد عليه فعّال.
FeatureState resolveFeatures(Object? raw) {
  final selected = selectedFeatures(raw);
  final out = <String, bool>{};
  bool visit(String key) {
    if (out.containsKey(key)) return out[key]!;
    final def = features[key]!;
    final on = selected[key]! &&
        def.requires.every(visit) &&
        (def.requiresAny.isEmpty || def.requiresAny.any(visit));
    out[key] = on;
    return on;
  }

  for (final key in featureKeys) {
    visit(key);
  }
  return out;
}

List<String> featureBlockers(String key, Object? raw) {
  final state = resolveFeatures(raw);
  final def = features[key];
  if (def == null) return const [];
  final blockers = def.requires.where((dep) => !(state[dep] ?? false)).toList();
  if (def.requiresAny.isNotEmpty && !def.requiresAny.any((dep) => state[dep] ?? false)) {
    blockers.addAll(def.requiresAny);
  }
  return blockers;
}

List<String> teacherPortalTabs(FeatureState state) {
  final tabs = <String>[];
  // صفي أولاً: متابعة شعبة المربي قبل الرصد
  if (state['portal.teacher.class'] == true) tabs.add('class');
  if (state['portal.teacher.attendance'] == true) tabs.add('attendance');
  if (state['portal.teacher.grades'] == true) tabs.add('evaluations');
  if (state['portal.teacher.moodle'] == true) tabs.add('moodle');
  return tabs;
}

List<String> familyPortalTabs(FeatureState state, {required bool isParent}) {
  final tabs = <String>[];
  if (!isParent && state['portal.student.moodle'] == true) tabs.add('moodle');
  tabs.add('subjects');
  if (state['portal.attendance'] == true) tabs.add('attendance');
  if (state['portal.grades'] == true) tabs.add('evaluations');
  if (state['portal.finance'] == true) tabs.add('financial');
  return tabs;
}

List<String> featureWarnings(Object? raw) {
  final state = resolveFeatures(raw);
  final warnings = <String>[];
  if (state['portal.teacher'] == true && teacherPortalTabs(state).isEmpty) {
    warnings.add('بوابة المعلم بلا أقسام مفعّلة');
  }
  return warnings;
}

/// حدود الاشتراك: عدد صحيح موجب فقط؛ سواه = بلا حد.
class TenantLimits {
  const TenantLimits({this.maxStudents, this.maxStorageMb});

  final int? maxStudents;
  final int? maxStorageMb;

  Map<String, dynamic> toMap() => {
        if (maxStudents != null) 'max_students': maxStudents,
        if (maxStorageMb != null) 'max_storage_mb': maxStorageMb,
      };
}

TenantLimits normalizeLimits(Object? raw) {
  final value = raw is Map ? raw : const {};
  int? positive(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n == null || n <= 0) return null;
    return n;
  }

  return TenantLimits(
    maxStudents: positive(value['max_students']),
    maxStorageMb: positive(value['max_storage_mb']),
  );
}
