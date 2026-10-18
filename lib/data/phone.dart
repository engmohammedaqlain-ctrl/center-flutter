/// مقدمات القائمة. مصر (+20) خرجت منها: لا يستعملها أحد، وكانت أرقام تبدأ بـ 20 تُفهم مصرية.
const phonePrefixes = ['059', '056', '+970', '+972'];

/// خيارات المقدمة — `phonePrefixOptions`: رقم محفوظ سابقاً بمقدمة خارج القائمة تظهر
/// مقدمته معها حتى لا تفرغ الخانة.
List<String> phonePrefixOptions([String? current]) =>
    current != null && current.isNotEmpty && !phonePrefixes.contains(current) ? [...phonePrefixes, current] : phonePrefixes;

/// الطول المتوقع لأرقام الجوال بعد المقدمة — مطابق لـ StudentForm في Center.
int phoneTargetLength(String prefix) {
  if (prefix == '059' || prefix == '056') return 7;
  if (prefix == '+970' || prefix == '+972') return 9;
  if (prefix == '+20') return 10;
  return 7;
}

String normalizeArabicDigits(String val) {
  return val.replaceAllMapped(RegExp(r'[٠-٩]'), (m) {
    return (m.group(0)!.codeUnitAt(0) - 1632).toString();
  });
}

String digitsOnly(String val) => normalizeArabicDigits(val).replaceAll(RegExp(r'\D'), '');

/// دمج الرقم مع المقدمة كما في phoneUtils.ts.
///
/// الرقم يُعامل كاملاً بمقدمته فقط إن كان طوله طول رقم كامل. كان أي رقم يبدأ بـ 20 أو
/// 970 يُعدّ دولياً، فيصير 056 + 2020766 هو +2020766 ويرفضه الحفظ.
String combinePhoneAndPrefix(String? phone, [String? prefix]) {
  if (phone == null) return '';
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return '';
  final compact = trimmed.replaceAll(RegExp(r'[\s-]'), '');

  // رقم كامل بمقدمته
  if (RegExp(r'^\+(97[02]|20)\d+$').hasMatch(compact) || RegExp(r'^05\d{8}$').hasMatch(compact)) return compact;
  if (RegExp(r'^97[02]\d{9}$').hasMatch(compact)) return '+$compact';

  // +20 خارج القائمة لكن أرقاماً قديمة محفوظة بها
  final activePrefix = prefix != null && phonePrefixOptions('+20').contains(prefix) ? prefix : '059';

  // محلي كامل بلا الصفر: 59xxxxxxx
  if (RegExp(r'^5\d{8}$').hasMatch(compact)) {
    return activePrefix == '059' || activePrefix == '056' ? '0$compact' : '$activePrefix$compact';
  }
  return '$activePrefix$compact';
}

class ParsedPhone {
  const ParsedPhone(this.prefix, this.number);
  final String prefix;
  final String number;
}

ParsedPhone parsePhoneAndPrefix(String? fullPhone) {
  if (fullPhone == null) return const ParsedPhone('059', '');
  final str = fullPhone.trim();
  if (str.isEmpty) return const ParsedPhone('059', '');

  if (str.startsWith('+970')) return ParsedPhone('+970', str.substring(4).trim());
  if (str.startsWith('970')) return ParsedPhone('+970', str.substring(3).trim());
  if (str.startsWith('+972')) return ParsedPhone('+972', str.substring(4).trim());
  if (str.startsWith('972')) return ParsedPhone('+972', str.substring(3).trim());
  if (str.startsWith('+20')) return ParsedPhone('+20', str.substring(3).trim());
  if (str.startsWith('059')) return ParsedPhone('059', str.substring(3).trim());
  if (str.startsWith('056')) return ParsedPhone('056', str.substring(3).trim());
  return ParsedPhone('059', str);
}

/// ما يُكتب أو يُلصق في خانة الجوال — `normalizePhoneInput`: أرقام فقط (والعربية
/// تتحول)، ورقم جوال كامل بأي صيغة (0599123456، 599123456، +970599123456،
/// 00970599123456) يضبط مقدمته ويبقى باقيه. الرقم بعد المقدمة قد يبدأ هو نفسه بـ 59
/// أو 20، فلا يُفصل شيء قبل اكتمال الرقم.
ParsedPhone normalizePhoneInput(String value, String prefix) {
  final digits = digitsOnly(value);
  final full = RegExp(r'^(?:00)?(?:97[02])?0?(5[96])(\d{7})$').firstMatch(digits);
  if (full != null) return ParsedPhone('0${full[1]}', full[2]!);
  // رقم كامل قيد الكتابة يُترك يكتمل حتى يُفصل
  final max = digits.startsWith('00')
      ? 14
      : digits.startsWith('97')
          ? 12
          : digits.startsWith('0')
              ? 10
              : RegExp(r'^5[96]').hasMatch(digits)
                  ? 9
                  : phoneTargetLength(prefix);
  final limit = max > phoneTargetLength(prefix) ? max : phoneTargetLength(prefix);
  return ParsedPhone(prefix, digits.length > limit ? digits.substring(0, limit) : digits);
}

String formatPhoneDisplay(String? phone, [String? prefix]) {
  if (phone == null || phone.trim().isEmpty) return '-';
  return combinePhoneAndPrefix(phone, prefix);
}

String getWhatsAppPhone(String? phoneStr) {
  if (phoneStr == null) return '';
  var clean = phoneStr.replaceAll(RegExp(r'\D'), '');
  if (clean.startsWith('05')) {
    clean = '970${clean.substring(1)}';
  } else if (clean.startsWith('5')) {
    clean = '970$clean';
  }
  return clean;
}

bool isPhoneComplete(String number, String prefix) {
  return number.trim().length == phoneTargetLength(prefix);
}
