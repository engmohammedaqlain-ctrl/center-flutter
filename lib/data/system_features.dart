import 'dart:convert';

/// أعلام الميزات — المقابل لـ `lib/systemFeatures.ts` في النسخة المكتبية.
///
/// تُحفظ تحت المفتاح `center_system_features` نفسه وبأسماء الحقول نفسها،
/// لأن النسخة المكتبية تقرأها من `localStorage` بهذا الشكل: أي اختلاف في
/// التسمية يجعل الإعداد الذي يضبطه أحدهما غير مقروء عند الآخر.
///
/// الحفظ محلي لكل جهاز — كما في سطح المكتب تماماً. جدول `institution_settings`
/// المشترك لا يحمل عموداً لها، وإرسالها فيه كان يُسقطها `sanitizePayload`
/// صامتاً ويُوهم بمزامنة لا تحدث.
class SystemFeatures {
  const SystemFeatures({
    this.enableExpenses = true,
    this.enableEvaluations = true,
    this.enableStudentPortal = true,
  });

  /// تفعيل إدارة وتتبع المصروفات التشغيلية وصرف أجور المعلمين
  final bool enableExpenses;

  /// تفعيل رصد ونتائج تقييمات ودرجات الطلاب
  final bool enableEvaluations;

  /// تفعيل بوابة الطالب
  final bool enableStudentPortal;

  static const defaults = SystemFeatures();

  SystemFeatures copyWith({
    bool? enableExpenses,
    bool? enableEvaluations,
    bool? enableStudentPortal,
  }) {
    return SystemFeatures(
      enableExpenses: enableExpenses ?? this.enableExpenses,
      enableEvaluations: enableEvaluations ?? this.enableEvaluations,
      enableStudentPortal: enableStudentPortal ?? this.enableStudentPortal,
    );
  }

  Map<String, dynamic> toMap() => {
        'enableExpenses': enableExpenses,
        'enableEvaluations': enableEvaluations,
        'enableStudentPortal': enableStudentPortal,
      };

  /// الحقل الغائب أو غير المنطقي يعود إلى قيمته الافتراضية — مطابق لدمج
  /// `{ ...DEFAULT_FEATURES, ...JSON.parse(raw) }`. ميزة تُعطَّل بسبب سطر
  /// تالف في الإعدادات خطأ أسوأ من تجاهل السطر.
  factory SystemFeatures.fromMap(Map<String, dynamic> m) {
    bool read(String key, bool fallback) {
      final v = m[key];
      if (v is bool) return v;
      if (v is String) {
        if (v == 'true') return true;
        if (v == 'false') return false;
      }
      return fallback;
    }

    return SystemFeatures(
      enableExpenses: read('enableExpenses', defaults.enableExpenses),
      enableEvaluations: read('enableEvaluations', defaults.enableEvaluations),
      enableStudentPortal: read('enableStudentPortal', defaults.enableStudentPortal),
    );
  }

  /// قراءة العلم من النص المحفوظ. النص التالف يعود بالافتراضي بلا رمي.
  factory SystemFeatures.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final data = jsonDecode(raw);
      if (data is Map) return SystemFeatures.fromMap(Map<String, dynamic>.from(data));
    } catch (_) {
      // إعداد تالف لا يجوز أن يمنع فتح التطبيق
    }
    return defaults;
  }

  String encode() => jsonEncode(toMap());

  @override
  bool operator ==(Object other) =>
      other is SystemFeatures &&
      other.enableExpenses == enableExpenses &&
      other.enableEvaluations == enableEvaluations &&
      other.enableStudentPortal == enableStudentPortal;

  @override
  int get hashCode => Object.hash(enableExpenses, enableEvaluations, enableStudentPortal);
}

/// مفتاح التخزين — مطابق حرفياً لـ `STORAGE_KEY` في systemFeatures.ts
const systemFeaturesKey = 'center_system_features';
