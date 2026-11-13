/// نص رسائل SMS ومستلموها — `smsText.ts` في الويب: عدد أجزاء الرسالة (اللي بتنحسب من رصيد
/// الشريحة)، والمتغيرات داخل النص (اسم الطالب، المستحق...)، وقائمة المستلمين. منطق خالص بلا واجهة.
library;

/// متغيرات النص: كل واحد بيتبدّل بقيمته لكل طالب.
const smsVars = <({String tag, String label})>[
  (tag: '{الاسم}', label: 'اسم الطالب'),
  (tag: '{الاسم الكامل}', label: 'الاسم الكامل'),
  (tag: '{ولي الأمر}', label: 'ولي الأمر'),
  (tag: '{الصف}', label: 'الصف'),
  (tag: '{المستحق}', label: 'المستحق'),
  (tag: '{المدرسة}', label: 'المدرسة'),
];

/// اسم الطالب الأول.
const smsNameTag = '{الاسم}';

/// المدرسة نفسها لكل الرسائل؛ الباقي بيختلف من طالب لطالب.
final _perStudent = [for (final v in smsVars) if (v.tag != '{المدرسة}') v.tag];

// أحرف GSM-7 الأساسية: نص كله منها = 160 حرف بالرسالة، وغير هيك (عربي مثلاً) = 70
const _gsmChars =
    '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
const _gsmExtChars = '^{}\\[~]|€'; // حرفين لكل واحد

final Set<int> _gsm = _gsmChars.runes.toSet();
final Set<int> _gsmExt = _gsmExtChars.runes.toSet();

/// إيموجي ورموز مصورة: كلها خارج الصفحة الأساسية (زوج UTF-16) أو برموز ☀ ✂ ⌚ ⬆ ومحدّد الإيموجي.
bool _isEmoji(int r) =>
    r >= 0x1F000 ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2300 && r <= 0x23FF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    r == 0xFE0F ||
    r == 0x200D;

class SmsCount {
  const SmsCount({
    required this.chars,
    required this.parts,
    required this.perPart,
    required this.capacity,
    required this.remaining,
    required this.unicode,
    required this.emoji,
    required this.toFewer,
  });

  /// الأحرف كما تعدّها الشبكة (المسافات والأسطر منها، والإيموجي بحرفين).
  final int chars;

  /// عدد الرسائل اللي بتنحسب من الرصيد.
  final int parts;

  /// سعة الجزء الواحد: 70/67 للعربي، 160/153 للإنجليزي.
  final int perPart;

  /// سعة كل الأجزاء الحالية (70، 134، 201...).
  final int capacity;

  /// الحروف الباقية قبل ما تصير رسالة زيادة.
  final int remaining;

  /// عربي أو فيه رمز خارج الأبجدية الأساسية: الرسالة 70 بدل 160.
  final bool unicode;

  /// فيه إيموجي (كل واحد بحرفين).
  final bool emoji;

  /// كم حرف لازم ينحذف حتى تنقص رسالة (0 لو رسالة وحدة).
  final int toFewer;
}

/// عدّاد الرسائل كما تحسبه جوال وأوريدو (معيار GSM):
/// - إنجليزي/أرقام بس (GSM-7): 160 حرف للرسالة، والأطول أجزاء كل واحد 153. ^ { } [ ] ~ | € \ بحرفين.
/// - حرف عربي واحد أو أي رمز خارجها (UCS-2): 70 حرف، والأطول أجزاء كل واحد 67.
///   الإيموجي حرفين (زوج UTF-16)، فالعدّ بوحدات UTF-16 لا بالرموز.
/// - المسافات والأسطر والترقيم كلها أحرف. وكل جزء رسالة من الرصيد.
SmsCount smsParts(String text) {
  var gsm = true;
  var gsmChars = 0;
  var emoji = false;
  for (final r in text.runes) {
    if (_gsmExt.contains(r)) {
      gsmChars += 2;
    } else if (_gsm.contains(r)) {
      gsmChars += 1;
    } else {
      gsm = false;
      if (_isEmoji(r)) emoji = true;
    }
  }
  // String.length بوحدات UTF-16: الإيموجي حرفين
  final chars = gsm ? gsmChars : text.length;
  final single = gsm ? 160 : 70;
  final multi = gsm ? 153 : 67;
  final parts = chars == 0 ? 0 : (chars <= single ? 1 : (chars + multi - 1) ~/ multi);
  final perPart = parts <= 1 ? single : multi;
  final capacity = parts <= 1 ? single : parts * multi;
  final fewer = parts <= 1 ? chars : (parts - 1 == 1 ? single : (parts - 1) * multi);
  return SmsCount(
    chars: chars,
    parts: parts,
    perPart: perPart,
    capacity: capacity,
    remaining: capacity - chars,
    unicode: !gsm,
    emoji: emoji,
    toFewer: chars - fewer,
  );
}

/// طالب كما يحتاجه نص الرسالة.
class SmsStudent {
  const SmsStudent({
    required this.id,
    required this.firstName,
    this.fullName = '',
    this.parentName = '',
    this.parentPhone = '',
    this.phone = '',
    this.gradeLevel = '',
    this.section = '',
  });

  final String id;
  final String firstName;
  final String fullName;
  final String parentName;
  final String parentPhone;
  final String phone;
  final String gradeLevel;
  final String section;
}

/// لمين الرسالة: أولياء الأمور (رقم ولي الأمر) أو الطلاب أنفسهم (رقم الطالب).
enum SmsAudience { parents, students }

bool hasPerStudentVars(String text) => _perStudent.any(text.contains);

/// 1234.6 ← «1,235»: كـ `toLocaleString('en-US')` بعد التقريب.
String smsAmount(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer(n.round() < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// النص بقيم طالب واحد. [dueOf]: المستحق على الطالب (أقساط حلّ موعدها) بالشيكل.
String fillSmsVars(String text, SmsStudent s, {String school = '', double Function(String id)? dueOf}) {
  final grade = [s.gradeLevel, s.section].where((x) => x.isNotEmpty).join(' ');
  final values = <String, String>{
    '{الاسم}': s.firstName.trim(),
    '{الاسم الكامل}': (s.fullName.isNotEmpty ? s.fullName : s.firstName).trim(),
    '{ولي الأمر}': s.parentName.trim(),
    '{الصف}': grade,
    '{المستحق}': '${smsAmount(dueOf?.call(s.id) ?? 0)} شيكل',
    '{المدرسة}': school.trim(),
  };
  var out = text;
  for (final v in smsVars) {
    out = out.split(v.tag).join(values[v.tag]!);
  }
  return out;
}

final _spaces = RegExp(r'[\s-]');
final _nonDigit = RegExp(r'\D');

String smsPhoneOf(SmsStudent s, SmsAudience audience) =>
    (audience == SmsAudience.students ? s.phone : s.parentPhone).replaceAll(_spaces, '');

bool smsHasPhone(SmsStudent s, SmsAudience audience) =>
    smsPhoneOf(s, audience).replaceAll(_nonDigit, '').length >= 7;

class SmsMessage {
  const SmsMessage({required this.to, required this.message, required this.ref});

  final String to;
  final String message;

  /// رقم الطالب: منه بتنعرف رسائله بملفه.
  final String ref;

  Map<String, dynamic> toJson() => {'to': to, 'message': message, 'ref': ref};
}

/// رسالة لكل رقم. النص بلا متغيرات طالب: رسالة وحدة للرقم حتى لو إله أكثر من ابن.
/// فيه متغيرات: رسالة لكل طالب بقيمه. الطالب بلا رقم يُعدّ بـ `missing`.
({List<SmsMessage> messages, int missing}) buildSmsMessages(
  Iterable<SmsStudent> students,
  String text, {
  SmsAudience audience = SmsAudience.parents,
  String school = '',
  double Function(String id)? dueOf,
}) {
  final body = text.trim();
  final perStudent = hasPerStudentVars(body);
  final seen = <String>{};
  final messages = <SmsMessage>[];
  var missing = 0;
  for (final s in students) {
    if (!smsHasPhone(s, audience)) {
      missing++;
      continue;
    }
    final phone = smsPhoneOf(s, audience);
    final message = fillSmsVars(body, s, school: school, dueOf: dueOf);
    final key = perStudent ? '$phone|$message' : phone;
    if (!seen.add(key)) continue;
    messages.add(SmsMessage(to: phone, message: message, ref: s.id));
  }
  return (messages: messages, missing: missing);
}

/// أطول رسالة فعلية بعد وضع القيم: عليها يُحسب عدد الأجزاء.
String longestSmsMessage(List<SmsMessage> messages, String fallback) {
  if (messages.isEmpty) return fallback;
  var a = '';
  for (final m in messages) {
    if (m.message.length > a.length) a = m.message;
  }
  return a;
}

/// مجموع أجزاء كل الرسائل الفعلية: هاد اللي بينحسب من الرصيد.
int totalSmsParts(List<SmsMessage> messages) {
  var n = 0;
  for (final m in messages) {
    n += smsParts(m.message).parts;
  }
  return n;
}

/// تمييز العدد: 3 أحرف، 11 حرف.
String smsLetters(int n) => n >= 3 && n <= 10 ? 'أحرف' : 'حرف';
