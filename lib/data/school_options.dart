/// خيارات المدرسة في `settings` — المقابل لـ `SchoolOptions.tsx` و`schoolTools.ts`
/// و`dashboardCards.ts`: تُقرأ من `extra` فلا يفقد جهاز قديم ما لا يعرفه.
library;

import 'app_settings.dart';

/// أدوات داخل الأقسام يطفئها المدير من الإعدادات ← المدرسة — `SCHOOL_TOOLS`.
const schoolTools = <({String id, String label, String hint})>[
  (id: 'announcements', label: 'إعلانات المدرسة', hint: 'زر «إعلان» في الرئيسية وقائمة الطلاب'),
  (id: 'official_docs', label: 'الأوراق الرسمية', hint: 'إثبات قيد وحسن سيرة ونقل من ملف الطالب'),
  (id: 'staff_attendance', label: 'دوام الموظفين', hint: '«الموظفون» في صفحة الحضور'),
  (id: 'student_import', label: 'استيراد الطلاب', hint: 'من ملف Excel في البيانات والنسخ'),
];

/// بطاقات الرئيسية التي يخفيها المدير — `DASHBOARD_CARDS`.
const dashboardCards = <({String id, String label})>[
  (id: 'uncovered', label: 'شعب بلا معلم اليوم'),
  (id: 'chart', label: 'الرسم البياني'),
  (id: 'grades', label: 'حسب المرحلة'),
  (id: 'absent', label: 'غائبون اليوم'),
  (id: 'chronic', label: 'الأكثر غياباً'),
  (id: 'staff', label: 'الموظفون اليوم'),
  (id: 'birthdays', label: 'أعياد الميلاد'),
  (id: 'upcoming', label: 'قادم'),
];

extension SchoolOptionSettings on AppSettings {
  /// اسم المدير على الشهادات والأوراق؛ الفارغ اسم صاحب الاشتراك.
  String get principalName => extra['principal_name'] is String ? extra['principal_name'] as String : '';

  /// الجملة أسفل سند القبض.
  String get receiptNote => extra['receipt_note'] is String ? extra['receipt_note'] as String : '';

  /// رقم ورمز تحقق QR على الشهادات، مفعّل افتراضياً.
  bool get certificateQr => extra['certificate_qr'] != false;

  List<String> _strings(String key) {
    final raw = extra[key];
    return raw is List ? [for (final v in raw) '$v'] : const [];
  }

  List<String> get toolsOff => _strings('tools_off');
  List<String> get dashboardHidden => _strings('dashboard_hidden');

  bool toolOn(String id) => !toolsOff.contains(id);
}
