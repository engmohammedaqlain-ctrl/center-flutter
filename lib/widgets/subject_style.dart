import 'package:flutter/material.dart';

// شكل المادة في بطاقات «المواد والمعلمون» — المقابل لـ `features/portal/subjectStyle.ts`:
// أيقونة من كلمات اسمها، ولون ثابت من اسمها (نفسها دائماً نفس اللون).

/// توحيد الحروف: بلا تشكيل ولا تطويل، والهمزات ألفاً، والتاء المربوطة هاءً، والألف المقصورة ياءً.
String normalizeArabicName(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[ً-ٰٟـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');

// الترتيب مهم: «الرياضية» (بدنية) قبل «رياضيات»، وهما مختلفان بعد توحيد التاء.
const _rules = <(IconData, List<String>)>[
  (Icons.calculate_outlined, ['رياضيات', 'حساب', 'جبر', 'هندسه', 'math']),
  (Icons.fitness_center_rounded, ['رياض', 'بدني', 'لياقه', 'sport', 'pe']),
  (Icons.science_outlined, ['علوم', 'فيزياء', 'فيزيا', 'كيمياء', 'كيميا', 'احياء', 'احيا', 'science', 'physics', 'chemistry', 'biology']),
  (Icons.translate_rounded, ['انجليز', 'english', 'فرنس', 'french', 'مانيه', 'german', 'تركي']),
  (Icons.dark_mode_outlined, ['اسلام', 'دين', 'قران', 'شرعيه']),
  (Icons.computer_rounded, ['حاسوب', 'حاسب', 'تكنولوجيا', 'تقنيه', 'معلوماتيه', 'computer', 'ict']),
  (Icons.public_rounded, ['اجتماعيات', 'تاريخ', 'جغرافيا', 'وطنيه', 'مدنيه']),
  (Icons.palette_outlined, ['فن', 'رسم', 'art']),
  (Icons.music_note_rounded, ['موسيق', 'music', 'نشيد']),
  (Icons.menu_book_rounded, ['عربي', 'لغتنا', 'قراءه', 'ادب', 'نحو', 'املاء']),
];

List<String> _words(String name) => [
      for (final w in normalizeArabicName(name).split(RegExp('[^a-zء-ي0-9]+')))
        if (w.isNotEmpty) w.length > 3 && w.startsWith('ال') ? w.substring(2) : w,
    ];

/// أيقونة المادة من كلمات اسمها، أو `null` إن لم يطابق شيء.
IconData? subjectIcon(String name) {
  final ws = _words(name);
  for (final (icon, keywords) in _rules) {
    if (ws.any((w) => keywords.any((k) => w == k || (k != 'pe' && w.startsWith(k))))) return icon;
  }
  return null;
}

/// أول حرف من الاسم بلا «ال»: بديل الأيقونة حين لا تطابق.
String subjectInitial(String name) {
  final t = name.replaceFirst(RegExp(r'^ال(?=.{3,})'), '').trim();
  final m = RegExp('[ء-يa-zA-Z]').firstMatch(t);
  return (m?.group(0) ?? (t.isEmpty ? '' : t.characters.first)).toUpperCase();
}

/// ثمانية ألوان هادئة تصلح مع أي ثيم.
const subjectTones = [
  Color(0xFF2F6F8F),
  Color(0xFF3F7F5E),
  Color(0xFF8A5FA8),
  Color(0xFFB5651D),
  Color(0xFFB24A5A),
  Color(0xFF2C8C86),
  Color(0xFF5C6BC0),
  Color(0xFF6B7A80),
];

/// لون ثابت للمادة (djb2 على الاسم الموحَّد) — نفس لون الويب.
Color subjectTone(String name) {
  var h = 5381;
  for (final ch in normalizeArabicName(name).replaceAll(RegExp(r'\s+'), ' ').trim().runes) {
    h = ((h << 5) + h + (ch > 0xFFFF ? 0 : ch)) & 0xFFFFFFFF;
  }
  return subjectTones[h % subjectTones.length];
}
