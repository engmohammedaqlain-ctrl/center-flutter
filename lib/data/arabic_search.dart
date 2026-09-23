/// بحث الأسماء العربية — المقابل لـ `matchStudentSearch` في `lib/utils.ts`.
///
/// البحث الحرفي (`contains`) كان يُسقط الطالب لفروق إملائية لا يقصدها الباحث:
/// همزة كُتبت ولم تُكتب، تاء مربوطة مقابل هاء، «عبدالرحمن» مقابل «عبد الرحمن»،
/// أو بحثٌ بالاسم الأول والعائلة معاً وبينهما اسم الأب. الويب يتسامح مع هذا
/// كله، والجوال كان يردّ «لا نتائج» على اسمٍ موجود.

const _easternDigits = '٠١٢٣٤٥٦٧٨٩';

/// أرقام مشرقية إلى لاتينية — يُكتب بها رقم الهاتف أحياناً.
String toWesternDigits(String text) {
  if (text.isEmpty) return text;
  final out = StringBuffer();
  for (final rune in text.runes) {
    final i = _easternDigits.codeUnits.indexOf(rune);
    out.write(i >= 0 ? '$i' : String.fromCharCode(rune));
  }
  return out.toString();
}

/// توحيد الهمزات والتاء المربوطة والياء، وإسقاط التشكيل والتطويل والترقيم.
String normalizeArabic(String? text) {
  if (text == null || text.isEmpty) return '';
  final out = StringBuffer();
  for (final rune in toWesternDigits(text.toLowerCase()).runes) {
    // التشكيل والتنوين والألف الخنجرية والتطويل: تُسقط
    if ((rune >= 0x064B && rune <= 0x065F) || rune == 0x0670 || rune == 0x0640) continue;
    out.write(switch (String.fromCharCode(rune)) {
      'أ' || 'إ' || 'آ' || 'ء' => 'ا',
      'ئ' => 'ي', // فائز/فايز، وائل/وايل
      'ة' => 'ه',
      'ى' => 'ي',
      '.' || ',' || '/' || r'\' || '،' || '؛' || ':' || '!' || '؟' || '-' || '_' || '(' || ')' => ' ',
      final ch => ch,
    });
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// كلمة بحث واحدة داخل اسم مُوحَّد، مع الأسماء المركّبة وأل التعريف.
bool _tokenMatches(String target, String token) {
  if (target.contains(token)) return true;
  // «عبدالرحمن» مقابل «عبد الرحمن»
  if (token.startsWith('عبد') && token.length > 4 && target.contains('عبد ${token.substring(3)}')) {
    return true;
  }
  // «ابوبكر» مقابل «ابو بكر»
  if (token.startsWith('ابو') && token.length > 4 && target.contains('ابو ${token.substring(3)}')) {
    return true;
  }
  // «العوض» والطالب مسجَّل «عوض»
  if (token.startsWith('ال') && token.length >= 4 && target.contains(token.substring(2))) {
    return true;
  }
  return false;
}

/// مطابقة اسم: تامة، أو كل كلمة من البحث موجودة في الاسم بأي ترتيب.
///
/// فيقع «محمد السويركي» على «محمد خليل إبراهيم السويركي».
bool matchArabicName(String? fullName, String? query) {
  final q = normalizeArabic(query);
  if (q.isEmpty) return true;
  final target = normalizeArabic(fullName);
  if (target.isEmpty) return false;
  if (target.contains(q)) return true;

  final tokens = q.split(' ').where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return true;
  return tokens.every((t) => _tokenMatches(target, t));
}

/// أرقام فقط — لمقارنة الهواتف والهويات بلا فواصل ولا مسافات.
String _digitsOnly(String? value) =>
    toWesternDigits(value ?? '').replaceAll(RegExp(r'[\s\-_()]'), '');

/// بحث الطالب كاملاً: الهواتف والهوية أولاً، ثم اسمه واسم وليّه.
bool matchStudentSearch({
  required String fullName,
  required String query,
  String phone = '',
  String parentPhone = '',
  String nationalId = '',
  String parentName = '',
  String parentNationalId = '',
}) {
  final q = query.trim();
  if (q.isEmpty) return true;

  final asNumber = _digitsOnly(q);
  if (asNumber.isNotEmpty && RegExp(r'\d').hasMatch(asNumber)) {
    for (final field in [phone, parentPhone, nationalId, parentNationalId]) {
      final digits = _digitsOnly(field);
      if (digits.isNotEmpty && digits.contains(asNumber)) return true;
    }
  }

  if (matchArabicName(fullName, q)) return true;
  if (parentName.isNotEmpty && matchArabicName(parentName, q)) return true;
  return false;
}
