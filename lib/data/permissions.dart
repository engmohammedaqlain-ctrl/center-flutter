/// نظام الصلاحيات = أي تبويبات النظام يراها هذا الحساب — مطابق لـ
/// `lib/permissions.ts`.
library;

class SectionDef {
  const SectionDef(this.id, this.label, {this.hint, this.parent});

  final String id;
  final String label;
  final String? hint;

  /// تبويب داخل قسم آخر: لا يُتاح إلا بإتاحة أصله.
  final String? parent;
}

const accessSections = <SectionDef>[
  SectionDef('students', 'الطلاب'),
  SectionDef('classes', 'الصفوف والجداول'),
  SectionDef('attendance', 'الحضور والغياب'),
  SectionDef('evaluations', 'الدرجات والتقييمات'),
  SectionDef(
    'evaluations.edit',
    'تعديل العلامات وحذفها',
    hint: 'بدونها يرصد علامات جديدة فقط',
    parent: 'evaluations',
  ),
  SectionDef('moodle', 'المودل'),
  SectionDef('finance', 'المالية'),
  SectionDef('finance.expenses', 'المصروفات وصرف الأجور', hint: 'يكشف رواتب الموظفين', parent: 'finance'),
  SectionDef('finance.collect', 'تحصيل الدفعات وإصدار السندات', parent: 'finance'),
  SectionDef(
    'finance.cancel',
    'إلغاء السندات وعكسها',
    hint: 'بدونها يُرسل طلباً للمدير يوافق عليه',
    parent: 'finance',
  ),
  SectionDef(
    'finance.discount',
    'الخصم والإعفاء على الأقساط',
    hint: 'بدونها يُرسل طلباً للمدير يوافق عليه',
    parent: 'finance',
  ),
  SectionDef(
    'finance.refund',
    'رد المبالغ وتسوية الرصيد',
    hint: 'بدونها يُرسل طلباً للمدير يوافق عليه',
    parent: 'finance',
  ),
  SectionDef('settings', 'الإعدادات'),
  SectionDef('settings.users', 'المستخدمون والصلاحيات', hint: 'يمكّنه من منح الصلاحيات لغيره', parent: 'settings'),
  SectionDef('settings.backup', 'البيانات والنسخ الاحتياطي', hint: 'يشمل استيراد البيانات واستبدالها', parent: 'settings'),
];

final allSections = [for (final s in accessSections) s.id];

/// أفعال المالية الحساسة — `FINANCE_ACTIONS`.
const financeActions = ['finance.collect', 'finance.cancel', 'finance.discount', 'finance.refund'];

/// علامة القائمة بعد فصل أفعال المالية — `ACCESS_FORMAT_MARKER`.
const accessFormatMarker = 'access:v2';

SectionDef? sectionDef(String id) {
  for (final s in accessSections) {
    if (s.id == id) return s;
  }
  return null;
}

String sectionLabel(String id) => sectionDef(resolveSection(id) ?? id)?.label ?? id;

String? resolveSection(String? id) {
  if (id == null || id.isEmpty) return null;
  if (id == 'schedule') return 'classes';
  return sectionDef(id) == null ? null : id;
}

class RoleDefinition {
  const RoleDefinition(this.id, this.label, this.description, this.sections);

  final String id;
  final String label;
  final String description;
  final List<String> sections;
}

final roles = <String, RoleDefinition>{
  'admin': RoleDefinition('admin', 'مدير', 'كل التبويبات، وإدارة المستخدمين والنسخ الاحتياطي.', allSections),
  'accountant': const RoleDefinition(
    'accountant',
    'محاسب',
    'المالية بما فيها المصروفات، والطلاب والصفوف.',
    [
      'students',
      'classes',
      'finance',
      'finance.expenses',
      'finance.collect',
      'finance.cancel',
      'finance.discount',
      'finance.refund',
    ],
  ),
  'receptionist': const RoleDefinition(
    'receptionist',
    'سكرتير',
    'التحصيل والطلاب والصفوف والحضور. الخصم والإلغاء والرد بموافقة المدير.',
    ['students', 'classes', 'attendance', 'finance', 'finance.collect'],
  ),
};

final roleList = [roles['admin']!, roles['accountant']!, roles['receptionist']!];

String normalizeRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  if (r == 'admin' || r.contains('مدير')) return 'admin';
  if (r == 'accountant' || r.contains('محاسب')) return 'accountant';
  return 'receptionist';
}

RoleDefinition roleDefinition(String? role) => roles[normalizeRole(role)]!;

String roleLabel(String? role) => roleDefinition(role).label;

const _legacyCapabilitySections = <String, List<String>>{
  'students.view': ['students'],
  'students.edit': ['students'],
  'students.delete': ['students'],
  'schedule.view': ['classes', 'moodle'],
  'schedule.edit': ['classes', 'moodle'],
  'attendance.view': ['attendance', 'evaluations'],
  'attendance.edit': ['attendance', 'evaluations'],
  'finance.view': ['finance'],
  'finance.cashbox': ['finance', 'finance.expenses'],
  'settings.view': ['settings'],
  'settings.fees': ['settings'],
  'settings.branding': ['settings'],
};

List<String> normalizeSections(Iterable<String> stored) {
  final out = <String>{};
  for (final entry in stored) {
    if (entry == accessFormatMarker) continue;
    if (sectionDef(entry) != null) {
      out.add(entry);
      continue;
    }
    out.addAll(_legacyCapabilitySections[entry] ?? const []);
  }
  for (final s in accessSections) {
    if (s.parent != null && out.contains(s.id)) out.add(s.parent!);
  }
  return allSections.where(out.contains).toList();
}

/// القائمة كما تُحفظ على الحساب — مع علامة v2.
List<String> serializeSections(Iterable<String> sections) => [...normalizeSections(sections), accessFormatMarker];

/// التبويبات الفعلية: قائمته الخاصة، أو قالب دوره.
/// قائمة بلا `access:v2` مع تبويب المالية ترث أفعال قالب الدور.
List<String> effectiveSections(List<String>? stored, String? role) {
  if (stored == null) return [...roleDefinition(role).sections];
  final sections = normalizeSections(stored);
  if (stored.contains(accessFormatMarker) || !sections.contains('finance')) return sections;
  final inherited = roleDefinition(role).sections.where(financeActions.contains);
  return normalizeSections([...sections, ...inherited]);
}

bool roleCanAccess(String? role, String section) => roleDefinition(role).sections.contains(section);

List<String> toggleSection(List<String> current, String id) {
  final next = {...current};
  if (next.contains(id)) {
    next.remove(id);
    for (final child in accessSections) {
      if (child.parent == id) next.remove(child.id);
    }
  } else {
    next.add(id);
    final parent = sectionDef(id)?.parent;
    if (parent != null) next.add(parent);
  }
  return allSections.where(next.contains).toList();
}
