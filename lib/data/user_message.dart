/// رسائل خطأ للمستخدم — المقابل لـ `userMessage` في الويب.
///
/// ما كُتب عربياً يُعرض كما هو؛ التقني يُترجم لعبارة قصيرة مفهومة؛
/// وما لا يُعرف يرجع للعبارة الاحتياطية. الأصل يبقى في السجل للمطور.
library;

final _rules = <(RegExp, String)>[
  (
    RegExp(
      r'failed to fetch|networkerror|network request failed|load failed|fetch failed|err_internet|err_network|timed? ?out|econn|enotfound|SocketException|ClientException',
      caseSensitive: false,
    ),
    'تعذّر الاتصال بالإنترنت',
  ),
  (
    RegExp(
      r'jwt|refresh[_ ]token|not authenticated|unauthori[sz]ed|invalid login|\b401\b|PGRST303|انتهت جلسة',
      caseSensitive: false,
    ),
    'انتهت الجلسة، سجّل الدخول من جديد',
  ),
  (
    RegExp(
      r'row-level security|permission denied|forbidden|\b42501\b|\b403\b|لا تملك صلاحية',
      caseSensitive: false,
    ),
    'لا تملك صلاحية لهذا الإجراء',
  ),
  (
    RegExp(r'duplicate key|unique constraint|\b23505\b|already exists', caseSensitive: false),
    'هذا السجل موجود مسبقاً',
  ),
  (
    RegExp(r'foreign key|\b23503\b', caseSensitive: false),
    'مرتبط بسجل غير موجود بعد — ارفع البيانات المرتبطة أولاً',
  ),
  (
    RegExp(r'QuotaExceeded|quota|no space', caseSensitive: false),
    'مساحة التخزين ممتلئة',
  ),
  (
    RegExp(
      r'PGRST|schema cache|does not exist|\b42703\b|\b42P01\b|could not find',
      caseSensitive: false,
    ),
    'النظام يحتاج تحديثاً، تواصل مع الدعم',
  ),
  (
    RegExp(r'\b5\d\d\b|server error|bad gateway|service unavailable|internal|busy|مشغول', caseSensitive: false),
    'الخادم مشغول، حاول بعد قليل',
  ),
  (
    RegExp(r'invalid input syntax for type (date|timestamp)', caseSensitive: false),
    'تاريخ غير صالح في أحد الحقول',
  ),
  (
    RegExp(r'invalid input syntax for type (numeric|integer|bigint|uuid)', caseSensitive: false),
    'قيمة غير صالحة في أحد الحقول',
  ),
  (
    RegExp(r'violates not-null', caseSensitive: false),
    'حقل إلزامي فارغ',
  ),
];

final _hasArabic = RegExp(r'[\u0600-\u06FF]');
final _latinWord = RegExp(r'[A-Za-z]{4,}');

/// رسالة جاهزة للعرض. [fallback] إن لم يُعرف السبب.
String userMessage(Object? err, [String fallback = 'تعذّر إتمام العملية']) {
  var raw = '${(err is Exception ? err.toString() : err) ?? ''}'.trim();
  if (raw.startsWith('Exception: ')) raw = raw.substring('Exception: '.length).trim();
  if (raw.startsWith('FormatException: ')) {
    raw = raw.substring('FormatException: '.length).trim();
  }
  if (raw.isEmpty) return fallback;

  // JSON سحابة خام
  if (raw.startsWith('{') && raw.contains('"')) {
    final code = RegExp(r'"code"\s*:\s*"([^"]+)"').firstMatch(raw)?.group(1);
    if (code == '42501') return 'لا تملك صلاحية لهذا الإجراء';
    final msg = RegExp(r'"(?:message|msg|error)"\s*:\s*"([^"]+)"').firstMatch(raw)?.group(1);
    if (msg != null && msg.isNotEmpty) {
      final translated = userMessage(msg, fallback);
      if (translated != fallback) return translated;
      if (_hasArabic.hasMatch(msg) && msg.length <= 120) return msg;
    }
    return fallback;
  }

  if (_hasArabic.hasMatch(raw) && !_latinWord.hasMatch(raw)) {
    // اختصر الجمل الطويلة جداً
    if (raw.length > 120) return fallback;
    return raw;
  }

  for (final (pattern, text) in _rules) {
    if (pattern.hasMatch(raw)) return text;
  }
  return fallback;
}

/// خطأ مزامنة جدول: اسم عربي قصير + سبب مفهوم.
String syncTableMessage(String tableLabel, Object error) {
  final reason = userMessage(error, 'تعذّر الرفع');
  return '$tableLabel: $reason';
}
