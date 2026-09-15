import 'dart:convert';

/// وسائل الدفع وقواعد الخصم — المقابل لـ `features/finance/paymentMethods.ts`.
///
/// المفاتيح وأسماء الحقول مطابقة حرفياً لما تكتبه النسخة المكتبية في
/// `localStorage` وفي عمود `colors` من `institution_settings`، فما تضبطه إحدى
/// النسختين يقرأه الطرف الآخر كما هو.

const customPaymentMethodsKey = 'custom_payment_methods';
const discountRulesKey = 'school_discount_rules';

/// مفتاح وسائل الدفع داخل كائن ألوان المنشأة المتزامن.
const customPaymentMethodsColorKey = '__custom_payment_methods';

const paymentMethodTypes = {
  'cash': 'نقدي',
  'bank': 'بنكي',
  'wallet': 'محفظة',
  'other': 'أخرى',
};

/// وسيلة دفع واحدة — مطابق لـ `PaymentMethodItem`.
class PaymentMethodItem {
  const PaymentMethodItem({
    required this.id,
    required this.name,
    this.type = 'other',
    this.isDefault = false,
    this.enabled = true,
  });

  final String id;
  final String name;

  /// `cash | bank | wallet | other`
  final String type;

  /// وسيلة أساسية في النظام: تُعطَّل ويُعدَّل اسمها ولا تُحذف.
  final bool isDefault;
  final bool enabled;

  String get typeLabel => paymentMethodTypes[type] ?? 'أخرى';

  PaymentMethodItem copyWith({String? name, String? type, bool? enabled}) => PaymentMethodItem(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        isDefault: isDefault,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'is_default': isDefault,
        'enabled': enabled,
      };

  static PaymentMethodItem? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    final name = '${raw['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    final type = '${raw['type'] ?? 'other'}'.trim();
    return PaymentMethodItem(
      id: id,
      name: name,
      type: paymentMethodTypes.containsKey(type) ? type : 'other',
      isDefault: raw['is_default'] == true,
      // الحقل الغائب يعني مفعّلة، كما في `m.enabled !== false`
      enabled: raw['enabled'] != false,
    );
  }
}

/// الوسائل الأساسية — مطابقة لـ `DEFAULT_PAYMENT_METHODS` معرّفاً واسماً وترتيباً.
// وسائل محددة الاسم وحدها: «تحويل بنكي» و«أخرى» كانتا بلا جهة معروفة، فتُسجَّل
// السندات بوسيلة لا تقول من أي بنك أو محفظة ورد المبلغ. أسماؤهما تبقى معروفة في
// `paymentMethodNames` لسندات قديمة سُجّلت بهما.
const defaultPaymentMethods = <PaymentMethodItem>[
  PaymentMethodItem(id: 'cash', name: 'نقداً', type: 'cash', isDefault: true),
  PaymentMethodItem(id: 'bop', name: 'بنك فلسطين', type: 'bank', isDefault: true),
  PaymentMethodItem(id: 'palpay', name: 'محفظة بال بي', type: 'wallet', isDefault: true),
  PaymentMethodItem(id: 'jawwal_pay', name: 'محفظة جوال بي', type: 'wallet', isDefault: true),
];

List<PaymentMethodItem> decodePaymentMethods(Object? raw) {
  final data = raw is String ? _tryDecode(raw) : raw;
  if (data is! List) return defaultPaymentMethods;
  final out = <PaymentMethodItem>[];
  for (final item in data) {
    final parsed = PaymentMethodItem.fromMap(item);
    if (parsed != null) out.add(parsed);
  }
  // قائمة فارغة أو تالفة لا تترك المستخدم بلا وسيلة قبض واحدة
  return out.isEmpty ? defaultPaymentMethods : out;
}

String encodePaymentMethods(List<PaymentMethodItem> methods) =>
    jsonEncode([for (final m in methods) m.toMap()]);

Object? _tryDecode(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

/// قواعد الخصم المقترحة — مطابق لـ `SchoolDiscountRules`.
///
/// اقتراح لا إلزام: النظام يقترح الخصم على من ينطبق عليه، والقرار للإدارة.
class SchoolDiscountRules {
  const SchoolDiscountRules({
    this.autoSuggestExcellence = false,
    this.excellenceMinGpa = 90,
    this.excellenceDiscountRate = 10,
    this.autoSuggestSiblings = false,
    this.siblingsDiscountRate = 10,
  });

  /// اقتراح خصم المتفوقين تلقائياً
  final bool autoSuggestExcellence;

  /// الحد الأدنى للمعدل المؤهل للخصم (%)
  final double excellenceMinGpa;

  /// نسبة خصم التفوق (%)
  final double excellenceDiscountRate;

  /// اقتراح خصم الإخوة تلقائياً
  final bool autoSuggestSiblings;

  /// نسبة خصم الإخوة (%)
  final double siblingsDiscountRate;

  static const defaults = SchoolDiscountRules();

  SchoolDiscountRules copyWith({
    bool? autoSuggestExcellence,
    double? excellenceMinGpa,
    double? excellenceDiscountRate,
    bool? autoSuggestSiblings,
    double? siblingsDiscountRate,
  }) {
    return SchoolDiscountRules(
      autoSuggestExcellence: autoSuggestExcellence ?? this.autoSuggestExcellence,
      excellenceMinGpa: excellenceMinGpa ?? this.excellenceMinGpa,
      excellenceDiscountRate: excellenceDiscountRate ?? this.excellenceDiscountRate,
      autoSuggestSiblings: autoSuggestSiblings ?? this.autoSuggestSiblings,
      siblingsDiscountRate: siblingsDiscountRate ?? this.siblingsDiscountRate,
    );
  }

  Map<String, dynamic> toMap() => {
        'autoSuggestExcellence': autoSuggestExcellence,
        'excellenceMinGpa': excellenceMinGpa,
        'excellenceDiscountRate': excellenceDiscountRate,
        'autoSuggestSiblings': autoSuggestSiblings,
        'siblingsDiscountRate': siblingsDiscountRate,
      };

  String encode() => jsonEncode(toMap());

  /// الحقل الغائب يعود لقيمته الافتراضية لا إلى صفر — كما في نشر الكائن فوق
  /// `DEFAULT_DISCOUNT_RULES` في النسخة المكتبية.
  factory SchoolDiscountRules.decode(String? raw) {
    final data = raw == null ? null : _tryDecode(raw);
    if (data is! Map) return defaults;

    double num_(String key, double fallback) {
      final v = data[key];
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? fallback;
    }

    bool flag(String key, bool fallback) {
      final v = data[key];
      return v is bool ? v : fallback;
    }

    return SchoolDiscountRules(
      autoSuggestExcellence: flag('autoSuggestExcellence', defaults.autoSuggestExcellence),
      excellenceMinGpa: num_('excellenceMinGpa', defaults.excellenceMinGpa),
      excellenceDiscountRate: num_('excellenceDiscountRate', defaults.excellenceDiscountRate),
      autoSuggestSiblings: flag('autoSuggestSiblings', defaults.autoSuggestSiblings),
      siblingsDiscountRate: num_('siblingsDiscountRate', defaults.siblingsDiscountRate),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SchoolDiscountRules &&
      other.autoSuggestExcellence == autoSuggestExcellence &&
      other.excellenceMinGpa == excellenceMinGpa &&
      other.excellenceDiscountRate == excellenceDiscountRate &&
      other.autoSuggestSiblings == autoSuggestSiblings &&
      other.siblingsDiscountRate == siblingsDiscountRate;

  @override
  int get hashCode => Object.hash(
        autoSuggestExcellence,
        excellenceMinGpa,
        excellenceDiscountRate,
        autoSuggestSiblings,
        siblingsDiscountRate,
      );
}
