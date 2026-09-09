const phonePrefixes = ['059', '056', '+970', '+972', '+20'];

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

/// دمج الرقم مع المقدمة كما في phoneUtils.ts
String combinePhoneAndPrefix(String? phone, [String? prefix]) {
  if (phone == null) return '';
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('+970') ||
      trimmed.startsWith('+972') ||
      trimmed.startsWith('+20') ||
      trimmed.startsWith('059') ||
      trimmed.startsWith('056')) {
    return trimmed;
  }

  if (trimmed.startsWith('970') || trimmed.startsWith('972') || trimmed.startsWith('20')) {
    return '+$trimmed';
  }

  final activePrefix = prefix != null && phonePrefixes.contains(prefix) ? prefix : '059';

  if (activePrefix == '059' || activePrefix == '056') {
    if (trimmed.startsWith('05')) return trimmed;
    if (trimmed.startsWith('59') || trimmed.startsWith('56')) return '0$trimmed';
    return '$activePrefix$trimmed';
  }

  if (trimmed.startsWith('05')) {
    return '$activePrefix${trimmed.substring(1)}';
  }

  return '$activePrefix$trimmed';
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
  if (str.startsWith('20') && str.length > 9) return ParsedPhone('+20', str.substring(2).trim());
  if (str.startsWith('059')) return ParsedPhone('059', str.substring(3).trim());
  if (str.startsWith('056')) return ParsedPhone('056', str.substring(3).trim());
  return ParsedPhone('059', str);
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
