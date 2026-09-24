import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/features.dart';
import '../data/grading.dart';
import '../data/institution.dart';
import '../data/portal.dart';
import '../data/image_shrink.dart';
import '../data/portal_offline.dart';
import '../data/realtime.dart';
import '../data/store.dart';
import '../data/academic_matching.dart';
import '../data/teacher_resources.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/attendance_view.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import '../widgets/list_paging.dart';
import 'portal_chrome.dart';

export 'student_portal_screen.dart' show StudentPortalScreen;

// بوابتا المعلم والطالب — المقابل لـ `pages/TeacherPortal.tsx` و`pages/StudentPortal.tsx`.
//
// التصميم منقول عن النسخة المكتبية عنصراً عنصراً: ترويسة بيضاء بالشعار واسم
// المنشأة وزر خروج وردي، ثم شريط تبويبات بخط سفلي بلون التمييز، ثم بطاقات
// بيضاء بزوايا مستديرة على خلفية رمادية فاتحة. الألوان الثابتة هي درجات
// Tailwind نفسها المكتوبة في الصفحتين.

/// أسماء الشعب الظاهرة للمعلم: من حقل الطالب ومن أسماء القاعات فقط.
/// لا نأخذ اسم المجموعة/المادة — كان يظهر «اللغة الإنجليزية - أ. …» كشعبة بالخطأ.
List<String> _teacherSectionsFor(Iterable<TeacherClass> classes, {String grade = ''}) {
  final g = grade.trim();
  final list = <String>{};
  for (final c in classes) {
    if (g.isNotEmpty && c.group.gradeLevel.trim().isNotEmpty && c.group.gradeLevel.trim() != g) {
      continue;
    }
    for (final s in c.students) {
      final sec = s.section.trim();
      if (_isTeacherSectionLabel(sec, subjectName: c.subjectName)) list.add(sec);
    }
    for (final part in c.roomName.split(RegExp(r'\s*[،,]\s*'))) {
      final name = part.trim();
      if (_isTeacherSectionLabel(name, subjectName: c.subjectName)) list.add(name);
    }
  }
  return list.toList()..sort();
}

/// هل النص اسم شعبة لا اسم مادة/معلم؟
bool _isTeacherSectionLabel(String name, {String subjectName = ''}) {
  final n = name.trim();
  if (n.isEmpty) return false;
  // «مادة - أ. فلان» أو شرطة طويلة — ليست شعبة
  if (n.contains(' - ') || n.contains(' — ') || n.contains(' – ')) return false;
  final sub = subjectName.trim();
  if (sub.isNotEmpty) {
    if (n == sub || n.startsWith('$sub ') || n.startsWith('$sub-') || n.startsWith('$sub—')) {
      return false;
    }
  }
  return true;
}

/// هل النصّان يشيران لنفس الشعبة بعد نزع بادئة «شعبة» والأقواس.
bool _sameSectionSoft(String? a, String? b) {
  if (isSameSectionName(a, b)) return true;
  final soft = RegExp(r'^شعبة\s*[\(]?\s*');
  String strip(String? v) =>
      (v ?? '').trim().replaceFirst(soft, '').replaceAll(RegExp(r'[)]'), '').trim();
  final x = strip(a);
  final y = strip(b);
  return x.isNotEmpty && normalizeAcademicText(x) == normalizeAcademicText(y);
}

/// هل الطالب ضمن الشعبة المختارة (تطابق حقل شعبته مع الاختيار).
bool _teacherStudentInSection(Student s, String section, String grade) {
  final want = section.trim();
  if (want.isEmpty) return true;
  final have = s.section.trim();
  if (have.isEmpty) return false;
  if (have == want) return true;
  if (belongsToSection(
        section: have,
        grade: s.gradeLevel,
        roomName: want,
        roomGrade: grade,
      )) {
    return true;
  }
  return _sameSectionSoft(have, want);
}

/// قاعات المجموعة كما تُعرض في [TeacherClass.roomName].
List<String> _teacherRoomParts(TeacherClass c) => [
      for (final part in c.roomName.split(RegExp(r'\s*[،,]\s*')))
        if (_isTeacherSectionLabel(part.trim(), subjectName: c.subjectName)) part.trim(),
    ];

/// طلاب الرصد لهذه المادة والشعبة.
///
/// - بلا اختيار شعبة → كل مسجّلي المادة.
/// - قاعة واحدة للمادة ولا حقول شعب عند الطلاب → كل المسجّلين.
/// - عدة شعب أو طلاب لهم حقل شعبة → طلاب الشعبة المختارة فقط.
List<Student> _teacherRosterStudents(
  TeacherClass? current, {
  required String sectionFilter,
  required String grade,
}) {
  final all = current?.students ?? const <Student>[];
  if (current == null || all.isEmpty) return all;
  final sec = sectionFilter.trim();
  if (sec.isEmpty) return all;

  final rooms = _teacherRoomParts(current);
  final hasStudentSections = all.any((s) => s.section.trim().isNotEmpty);
  // مادة بقاعة واحدة وطلاب بلا حقل شعبة: لا معنى للتصفية
  if (rooms.length <= 1 && !hasStudentSections) return all;

  final g = grade.trim().isNotEmpty ? grade.trim() : current.group.gradeLevel;
  return all.where((s) {
    final have = s.section.trim();
    // بلا شعبة مسجّلة: يظهر فقط إن كانت المادة بقاعة واحدة (شعبته هي قاعة المادة)
    if (have.isEmpty) return rooms.length <= 1;
    return _teacherStudentInSection(s, sec, g);
  }).toList();
}

// ═══ ألوان البوابة (درجات Tailwind في الصفحتين) ═════════════════════════════

abstract final class _C {
  static const bg = Color(0xFFF8FAFC);
  static const line = Color(0xFFE2E8F0);
  static const lineStrong = Color(0xFFCBD5E1);
  static const soft = Color(0xFFF1F5F9);
  static const text = Color(0xFF0F172A);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const navy = Color(0xFF0B2545);

  static const emerald50 = Color(0xFFECFDF5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);

  static const rose50 = Color(0xFFFFF1F2);
  static const rose200 = Color(0xFFFECDD3);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);

  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);




  static const blue50 = Color(0xFFEFF6FF);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);
  static const purple50 = Color(0xFFFAF5FF);
  static const purple700 = Color(0xFF7E22CE);
}

const _mono = 'monospace';

/// ألوان الهوية بعد قراءتها من إعدادات المنشأة، بافتراضي Center.
class _Brand {
  _Brand(PortalBranding b)
      : primary = parseHexColor(b.colors.primaryButton) ?? const Color(0xFF0B2545),
        active = parseHexColor(b.colors.activeItem) ?? const Color(0xFFE88C15),
        action = parseHexColor(b.colors.actionButton) ?? const Color(0xFFE88C15),
        side = parseHexColor(b.colors.sidebarBg) ?? const Color(0xFF0B2545);

  final Color primary;
  final Color active;
  final Color action;
  final Color side;
}

TextStyle _base(BuildContext context) => Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

// ═══ عناصر مشتركة ═══════════════════════════════════════════════════════════




/// بطاقة البوابة: بيضاء بإطار رفيع وزوايا 16.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: _C.line),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

/// «الشعبة / المادة:» — عنوان الحقل.
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text, style: const TextStyle(color: _C.slate600, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _Select<T> extends StatelessWidget {
  const _Select({
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 40,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double height;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    // إن كانت القيمة الحالية ليست ضمن العناصر، لا نمرّرها — وإلا يتعطل الزر.
    final safeValue = value != null && items.any((i) => i.value == value) ? value : null;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(Corner.input),
        border: Border.all(color: _C.lineStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: safeValue,
          hint: hint == null
              ? null
              : Text(
                  hint!,
                  style: _base(context).copyWith(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w600),
                ),
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(Corner.input),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: _C.muted),
          style: _base(context).copyWith(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    this.hint,
    this.keyboardType,
    this.errorText,
    this.onChanged,
    this.maxLines = 1,
    this.ltr = false,
    this.center = false,
    this.dense = false,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool ltr;
  final bool center;

  /// حقل صغير داخل صف طالب (الدرجة والملاحظة).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder outline(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Corner.input), borderSide: BorderSide(color: c, width: w));

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      textAlign: center ? TextAlign.center : TextAlign.start,
      textDirection: ltr ? TextDirection.ltr : null,
      style: _base(context).copyWith(color: _C.text, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: ltr ? _mono : null),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: _C.bg,
        errorText: errorText,
        errorStyle: const TextStyle(color: _C.rose700, fontSize: 10.5, fontWeight: FontWeight.w700),
        contentPadding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 9 : 12),
        border: outline(_C.lineStrong),
        enabledBorder: outline(_C.lineStrong),
        focusedBorder: outline(_C.navy, 1.4),
        errorBorder: outline(_C.rose200),
        focusedErrorBorder: outline(_C.rose700, 1.4),
      ),
    );
  }
}

/// حقل تاريخ بشكل الحقول: التاريخ مقابل أيقونة التقويم.
class _DateBox extends StatelessWidget {
  const _DateBox({required this.date, required this.onPicked});

  /// `yyyy-mm-dd`
  final String date;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final current = parseIsoDate(date) ?? DateTime.now();
    return InkWell(
      borderRadius: BorderRadius.circular(Corner.input),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(current.year - 3),
          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
          cancelText: 'إلغاء',
          confirmText: 'اختيار',
        );
        if (picked != null) onPicked(isoDate(picked));
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(Corner.input),
          border: Border.all(color: _C.lineStrong),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                formatDate(current),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _C.text, fontSize: 12, fontFamily: _mono),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_outlined, size: 15, color: _C.text),
          ],
        ),
      ),
    );
  }
}

/// زر ممتلئ بلون الهوية.
class _Solid extends StatelessWidget {
  const _Solid({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.height = 44,
    this.busy = false,
    this.radius = Corner.field,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool busy;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else if (icon != null)
                    Icon(icon, size: 16, color: Colors.white),
                  if (busy || icon != null) const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر فاتح بإطار — «الكل حاضر» و«إلغاء».
class _Soft extends StatelessWidget {
  const _Soft({
    required this.label,
    required this.onTap,
    this.icon,
    this.fg = _C.muted,
    this.bg = Colors.white,
    this.border = _C.lineStrong,
    this.height = 40,
    this.radius = Corner.field,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color fg;
  final Color bg;
  final Color border;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شارة حالة بإطار.
class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.fg, required this.bg, this.radius = Corner.chip});

  final String text;
  final Color fg;
  final Color bg;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة فارغة: رسالة في المنتصف، بإطار متقطع حين تدعو لإضافة شيء.
class _Empty extends StatelessWidget {
  const _Empty(this.message, {this.icon, this.dashed = false, this.action, this.onAction, this.height = 110});

  final String message;
  final IconData? icon;
  final bool dashed;
  final String? action;
  final VoidCallback? onAction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 32, color: _C.lineStrong), const SizedBox(height: 8)],
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _C.faint, fontSize: 12, fontWeight: FontWeight.w800, height: 1.6),
          ),
          if (action != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  color: _C.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!dashed) return _Card(padding: EdgeInsets.zero, child: body);
    return CustomPaint(
      painter: const _DashedBorder(color: _C.lineStrong, radius: Corner.card),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Corner.card)),
        child: body,
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color || old.radius != radius;
}

/// شريط نجاح أخضر مقتضب.
class _Success extends StatelessWidget {
  const _Success(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _C.emerald50,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: _C.emerald200),
      ),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: _C.emerald600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: _C.emerald800, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// «الفصل الأول / الفصل الثاني / أخرى» — أزرار مجزّأة على خلفية رمادية.
class _TermSwitch extends StatelessWidget {
  const _TermSwitch({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _terms = ['term_1', 'term_2', 'other'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _C.soft, borderRadius: BorderRadius.circular(Corner.box)),
      child: Row(
        children: [
          for (final t in _terms)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == t ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(Corner.chip),
                    boxShadow: value == t
                        ? const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 2, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Text(
                    academicTermLabels[t]!,
                    style: TextStyle(
                      color: value == t ? _C.navy : _C.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ألوان شارة نوع المادة التعليمية.
({Color fg, Color bg}) _itemTypeColors(String type) => switch (type) {
      'file' => (fg: _C.blue700, bg: _C.blue50),
      'link' => (fg: _C.purple700, bg: _C.purple50),
      'assignment' => (fg: _C.emerald700, bg: _C.emerald50),
      _ => (fg: _C.slate700, bg: _C.soft),
    };

/// فتح ملف مادة داخل التطبيق — صورٌ معاينة، وروابط يوتيوب/درايف في تبويب داخلي.
Future<void> _openMaterial(
  BuildContext context,
  String url, {
  PortalService service = const PortalService(),
  String fileName = '',
}) =>
    openPortalMaterial(context, url, service: service, fileName: fileName);

/// حالة تحميل أو خطأ بشكل Center.
Widget _loadingView([String message = 'جارِ تحميل البيانات...']) => Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: _C.navy),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );

Widget _errorView(String message, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 34, color: _C.faint),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            _Soft(label: 'إعادة المحاولة', icon: Icons.refresh, onTap: retry, fg: _C.navy),
          ],
        ),
      ),
    );

// ══════════════════════════════════════════════════════════════════════════
// بوابة المعلم
// ══════════════════════════════════════════════════════════════════════════

class TeacherPortalScreen extends StatefulWidget {
  const TeacherPortalScreen({
    super.key,
    required this.user,
    required this.onExit,
    this.service = const PortalService(),
    this.offline,
  });

  final PortalUser user;
  final VoidCallback onExit;

  /// قابلة للاستبدال في الاختبارات كي لا تمسّ السحابة.
  final PortalService service;

  /// مخزن العمل بلا إنترنت. يُستبدل في الاختبارات بقاعدة في الذاكرة.
  final PortalOffline? offline;

  @override
  State<TeacherPortalScreen> createState() => _TeacherPortalScreenState();
}

class _TeacherPortalScreenState extends State<TeacherPortalScreen> {
  TeacherPortalData? data;
  String? error;
  bool loading = true;

  String tab = 'attendance';
  String groupId = '';

  /// الرصد يمشي كالويب: الصف ← الشعبة ← المادة، لا اختيار مجموعة مباشرةً.
  String gradeFilter = '';
  String sectionFilter = '';

  // رصد الحضور
  String sessionDate = isoDate(DateTime.now());

  /// الأسبوع المعروض في شريط الأيام — صفر أسبوع اليوم.
  int weekOffset = 0;
  /// رصد الأسبوع المعروض: `{تاريخ: {معرّف الطالب: الحالة}}`.
  Map<String, Map<String, String>> weekMarks = {};
  bool savingAttendance = false;
  int _marksToken = 0;

  /// دفع الرصد إلى السحابة بعد سكون اللمس: المعلم يضغط عدة طلاب متتابعين
  /// فيُرفع كشف اليوم مرة واحدة لا مرة لكل ضغطة.
  Timer? _pushTimer;

  /// كشف ينتظر دفعه بعد السكون — يُرفع فوراً إن غادر المعلم الشاشة قبله.
  ({String roomId, String date, Map<String, String> statuses, Set<String> dirty})? _duePush;

  /// طلاب تغيّر رصدهم منذ آخر رفع — delta بدل يوم كامل.
  final _dirtyMarks = <String>{};

  Map<String, String> get marks => weekMarks[sessionDate] ?? const {};

  // رصد الدرجات — النموذج في صفحة منفصلة؛ هنا السجل فقط
  List<StudentEvaluation> recent = const [];
  /// أسماء طلاب السجل — من كشف الشعب + جلب ناقص من السحابة.
  Map<String, String> evalNames = const {};
  int recentVisible = kListPageSize;
  int attendanceVisible = kListPageSize;

  // المودل
  String term = 'term_1';
  List<CourseSection> sections = const [];
  bool loadingMoodle = false;
  String? moodleMessage;
  int _moodleToken = 0;

  PortalService get _service => widget.service;

  late final PortalOffline _offline = widget.offline ?? PortalOffline(AppStore.instance.db);

  /// آخر محاولة اتصال فشلت: البوابة تعمل من نسخة الجهاز.
  bool offline = false;

  /// رصدٌ محفوظ على الجهاز ينتظر الرفع.
  int pendingOps = 0;

  TeacherClass? get _current => data?.classes.where((c) => c.group.id == groupId).firstOrNull;

  List<TeacherClass> get _classes => data?.classes ?? const <TeacherClass>[];

  /// صفوف المعلم: مراحل شعبه المسندة.
  List<String> _grades() {
    final list = <String>{
      for (final c in _classes)
        if (c.group.gradeLevel.trim().isNotEmpty) c.group.gradeLevel.trim(),
    }.toList()
      ..sort();
    return list;
  }

  /// شعب الصف المختار — لالمادة الحالية إن وُجدت، وإلا لكل مواد الصف.
  List<String> _sections([String? grade]) {
    final g = grade ?? gradeFilter;
    final current = _current;
    if (current != null) {
      final local = _teacherSectionsFor([current], grade: g);
      if (local.isNotEmpty) return local;
    }
    return _teacherSectionsFor(_classes, grade: g);
  }

  /// مواد المعلم في الصف المختار — الشعبة تُصفّي الطلاب لا قائمة المواد.
  List<TeacherClass> _subjectClasses({String? grade, String? section}) {
    final g = (grade ?? gradeFilter).trim();
    return [
      for (final c in _classes)
        if (g.isEmpty || c.group.gradeLevel.trim().isEmpty || c.group.gradeLevel.trim() == g) c,
    ];
  }

  /// طلاب الرصد: طلاب الشعبة المختارة من مسجّلي المادة.
  List<Student> _students() {
    // شعبة مطلوبة متى وُجدت شعب: كشف الحضور لشعبة واحدة لا لصفّ بأكمله
    if (sectionFilter.trim().isEmpty && _sections().isNotEmpty) return const [];
    return _teacherRosterStudents(_current, sectionFilter: sectionFilter, grade: gradeFilter);
  }

  /// اختيار الصف: يعيد ضبط الشعبة والمادة تحته، ويختار الوحيد منهما تلقائياً.
  void _selectGrade(String value) {
    setState(() {
      gradeFilter = value;
      sectionFilter = '';
      final sections = _sections();
      if (sections.isNotEmpty) sectionFilter = sections.first;
      final subjects = _subjectClasses();
      groupId = subjects.length == 1 ? subjects.first.group.id : '';
      _resetRecording();
    });
    if (groupId.isNotEmpty) {
      _loadMarks();
      _loadEvaluations();
    }
  }

  void _selectSection(String value) {
    setState(() {
      sectionFilter = value;
      final subjects = _subjectClasses();
      if (!subjects.any((c) => c.group.id == groupId)) {
        groupId = subjects.length == 1 ? subjects.first.group.id : '';
      }
      _resetRecording();
    });
    if (groupId.isNotEmpty) {
      _loadMarks();
      _loadEvaluations();
    }
  }

  /// تفريغ رصد الحضور عند تبديل النطاق.
  void _resetRecording() {
    weekMarks = {};
    attendanceVisible = kListPageSize;
    recentVisible = kListPageSize;
    evalNames = const {};
  }

  @override
  void initState() {
    super.initState();
    // نسخة الجهاز قبل أول رسم — بلا وميض تحميل عند فتح البوابة بلا نت
    final cached = _offline.loadTeacherData();
    if (cached != null) {
      _applyTeacherData(cached, fromCache: true);
      pendingOps = _offline.pendingCountOf(widget.user.id);
    }
    _load();
    _startPortalRealtime();
  }

  PortalRealtime? _portalRt;

  void _startPortalRealtime() {
    final tid = widget.user.tenantId;
    if (tid.isEmpty) return;
    _portalRt = PortalRealtime(onChanged: (tables) {
      if (!mounted) return;
      // جداول تهمّ المعلم: حضور/درجات/مودل — وإلا إعادة تحميل عامة
      const relevant = {
        'attendance',
        'sessions',
        'student_evaluations',
        'course_sections',
        'course_items',
        'enrollments',
        'groups',
        'students',
      };
      if (tables != null && tables.isNotEmpty && !tables.any(relevant.contains)) return;
      unawaited(_load());
    });
    unawaited(_portalRt!.connect(tid));
  }

  @override
  void dispose() {
    // رصدٌ لُمس قبل أقلّ من ثانية ثم أُغلقت الشاشة: يُرسل أو يُصفّ، ولا يضيع
    final due = _duePush;
    _pushTimer?.cancel();
    if (due != null) unawaited(_pushOnLeave(due));
    unawaited(_portalRt?.disconnect() ?? Future.value());
    super.dispose();
  }

  /// رفع أخير بلا لمس الحالة — الشاشة لم تعد موجودة.
  Future<void> _pushOnLeave(
    ({String roomId, String date, Map<String, String> statuses, Set<String> dirty}) due,
  ) async {
    try {
      await _service.saveAttendance(
        roomId: due.roomId,
        date: due.date,
        statuses: due.statuses,
        teacher: widget.user,
        changedStudentIds: due.dirty.isEmpty ? null : due.dirty,
      );
    } catch (_) {
      await _offline.queueAttendance(
        roomId: due.roomId,
        date: due.date,
        statuses: due.statuses,
        userId: widget.user.id,
      );
    }
  }

  /// مهلة طلبات بوابة المعلم — بلاها يعلق الانتظار عند انقطاع الشبكة.
  static const _cloudTimeout = Duration(seconds: 10);

  /// تطبيق بيانات المعلم على الحالة (كاش أو سحابة) مع اختيار الصف/الشعبة.
  void _applyTeacherData(TeacherPortalData result, {required bool fromCache}) {
    final tabs = teacherPortalTabs(resolveFeatures(result.features));
    if (tabs.isNotEmpty && !tabs.contains(tab)) tab = tabs.first;
    if (result.classes.every((c) => c.group.id != groupId)) {
      groupId = result.classes.isEmpty ? '' : result.classes.first.group.id;
    }
    final current = result.classes.where((c) => c.group.id == groupId).firstOrNull;
    if (current != null) {
      final g = current.group.gradeLevel.trim();
      if (g.isNotEmpty) gradeFilter = g;
      // الحضور يُرصد لشعبة بعينها: صفٌّ بلا شعبة يخلط كشفين في واحد
      final secs = {
        for (final s in current.students)
          if (s.section.trim().isNotEmpty) s.section.trim(),
      }.toList()
        ..sort();
      if (secs.isNotEmpty && (sectionFilter.isEmpty || !secs.contains(sectionFilter))) {
        sectionFilter = secs.first;
      }
    }
    data = result;
    loading = false;
    error = null;
    offline = fromCache;
    pendingOps = _offline.pendingCountOf(widget.user.id);
  }

  Future<void> _load() async {
    // الكاش من صفحة التجهيز أو دخول سابق — الشاشة فورية بلا انتظار
    final cached = _offline.loadTeacherData();
    if (cached != null) {
      if (!mounted) return;
      setState(() => _applyTeacherData(cached, fromCache: true));
      _refreshTab();
    } else if (data == null) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final result = await _service.teacherData(widget.user).timeout(_cloudTimeout);
      // ردّ ناقص والجهاز يحمل نسخة: نسخة الجهاز أوثق. عرضها بدل الردّ الفارغ
      // يمنع اختفاء الصفوف والطلاب لحظةَ انقطاع الشبكة.
      if (!result.complete) {
        if (!mounted) return;
        final haveCopy = cached != null || data != null;
        setState(() {
          offline = true;
          loading = false;
          if (!haveCopy) error = 'تعذّر الاتصال بالسحابة.';
          pendingOps = _offline.pendingCountOf(widget.user.id);
        });
        return;
      }
      await _offline.saveTeacherData(result);
      if (!mounted) return;
      setState(() => _applyTeacherData(result, fromCache: false));
      unawaited(_flushPending());
      // تحديث الموارد بالخلفية إن لم يكتمل تنزيل حديث (صفحة التجهيز)
      if (!teacherResourcesFresh(_offline)) {
        unawaited(
          hydrateTeacherResources(
            service: _service,
            offline: _offline,
            user: widget.user,
            isCancelled: () => !mounted,
          ),
        );
      }
      _refreshTab();
    } catch (_) {
      if (!mounted) return;
      if (data == null) {
        setState(() {
          loading = false;
          error = 'تعذّر الاتصال بالسحابة.';
        });
        return;
      }
      setState(() {
        offline = true;
        pendingOps = _offline.pendingCountOf(widget.user.id);
      });
    }
  }

  /// عملية كتابة تعمل بلا شبكة: تُجرَّب على السحابة، وإن تعذّرت تُصفّ لتُرفع
  /// لاحقاً. في الحالتين يُطبَّق أثرها على الشاشة، فلا ينتظر المعلم شبكة.
  /// عند انشغال السيرفر تُعاد المحاولة مرة قصيرة قبل التصفيف.
  Future<bool> _writeOrQueue(
    Future<void> Function() send,
    Map<String, dynamic> op, {
    List<String> announceTables = const [],
  }) async {
    try {
      await _sendWithBusyRetry(send);
      if (announceTables.isNotEmpty) _portalRt?.announce(announceTables);
      if (mounted) setState(() => offline = false);
      return true;
    } catch (e) {
      await _offline.queueOp(op, widget.user.id);
      if (mounted) {
        setState(() {
          offline = true;
          pendingOps = _offline.pendingCountOf(widget.user.id);
        });
        if (_isServerBusy(e)) {
          showAppSnack(context, 'الخادم مشغول، حُفظ الرصد محلياً ويُرفع تلقائياً', error: true);
        }
      }
      return false;
    }
  }

  Future<void> _sendWithBusyRetry(Future<void> Function() send) async {
    try {
      await send();
    } catch (e) {
      if (!_isServerBusy(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await send();
    }
  }

  bool _isServerBusy(Object e) {
    final t = '$e'.toLowerCase();
    return t.contains('503') ||
        t.contains('502') ||
        t.contains('504') ||
        t.contains('429') ||
        t.contains('timeout') ||
        t.contains('busy') ||
        t.contains('مشغول') ||
        t.contains('unavailable');
  }

  /// ضغطة زر المزامنة: ورقة التفاصيل كالإدارة، ثم رفع/تحديث.
  Future<void> _syncNow() async {
    await openPortalSyncSheet(
      context,
      offline: _offline,
      userId: widget.user.id,
      syncedAt: _offline.syncedAt,
      onSync: () async {
        try {
          await _flushPending();
        } catch (e) {
          if (!mounted) return false;
          showAppSnack(
            context,
            _isServerBusy(e) ? 'الخادم مشغول، أعد المحاولة بعد لحظات' : 'تعذّرت المزامنة',
            error: true,
          );
          return false;
        }
        if (!mounted) return false;
        await _load();
        return !offline && pendingOps == 0;
      },
    );
  }

  /// رفع ما رُصد بلا شبكة. يُستدعى كلما ثبت أن السحابة في المتناول.
  Future<void> _flushPending() async {
    if (_offline.pendingCountOf(widget.user.id) == 0) {
      if (mounted && pendingOps != 0) setState(() => pendingOps = 0);
      return;
    }
    final sent = await _offline.flush(_service, widget.user);
    if (!mounted) return;
    setState(() => pendingOps = _offline.pendingCountOf(widget.user.id));
    if (sent > 0) showAppSnack(context, 'تمت مزامنة $sent من الرصد المحفوظ');
  }

  /// بيانات التبويب المفتوح للشعبة المختارة.
  void _refreshTab() {
    switch (tab) {
      case 'attendance':
        _loadMarks();
      case 'evaluations':
        _loadEvaluations();
      case 'moodle':
        _loadMoodle();
    }
  }

  void _selectGroup(String? id) {
    if (id == null || id == groupId) return;
    setState(() {
      groupId = id;
      final current = data?.classes.where((c) => c.group.id == id).firstOrNull;
      if (current != null) {
        final g = current.group.gradeLevel.trim();
        if (g.isNotEmpty) gradeFilter = g;
      }
      sectionFilter = '';
      final secs = _sections();
      if (secs.isNotEmpty) sectionFilter = secs.first;
      weekMarks = {};
      recent = const [];
      evalNames = const {};
      sections = const [];
      recentVisible = kListPageSize;
      attendanceVisible = kListPageSize;
    });
    _refreshTab();
  }

  void _selectTab(String id) {
    if (id == tab) return;
    setState(() => tab = id);
    _refreshTab();
  }

  // ── الحضور ────────────────────────────────────────────────────────────────

  Future<void> _loadMarks() async {
    final c = _current;
    if (c == null) return;
    final token = ++_marksToken;
    final roomId = _attendanceRoomId;
    final dates = [for (final d in _schoolWeek(weekOffset)) d.dateStr];

    // النسخة المحفوظة تُعرض فوراً، ثم تُصحَّح من السحابة إن وصلت
    final cached = _offline.loadWeekMarks(roomId, dates);
    setState(() => weekMarks = cached);

    try {
      final students = _current?.students ?? const <Student>[];
      final roomOf = {
        for (final s in students)
          s.id: () {
            final matched = _current?.roomIdFor(s.section) ?? '';
            return matched.isNotEmpty ? matched : roomId;
          }(),
      };
      final saved = await (groupId.isNotEmpty
              ? _service.weekTeacherAttendance(groupId: groupId, dates: dates, roomOf: roomOf)
              : _service.weekAttendance(roomId, dates))
          .timeout(_cloudTimeout);
      if (!mounted || token != _marksToken) return;
      for (final e in saved.entries) {
        await _offline.saveMarks(roomId, e.key, e.value);
      }
      if (!mounted || token != _marksToken) return;
      setState(() {
        weekMarks = {...cached, ...saved};
        offline = false;
      });
      _flushPending();
    } catch (_) {
      if (!mounted || token != _marksToken) return;
      setState(() {
        offline = true;
        pendingOps = _offline.pendingCountOf(widget.user.id);
      });
    }
  }

  /// الشعبة التي يُرصد حضورها: المختارة، أو شعبة المادة الوحيدة، وإلا قاعة
  /// المجموعة نفسها — بيانات قديمة بلا قائمة شعب تبقى قابلة للرصد.
  String get _attendanceRoomId {
    final c = _current;
    if (c == null) return '';
    final matched = c.roomIdFor(sectionFilter);
    return matched.isNotEmpty ? matched : c.group.roomId;
  }

  /// `null` تعني «لم يُرصد بعد» — لا «حاضر». الإدارة تعدّها كذلك، وعدّها حضوراً
  /// يجعل صفاً لم يُفتح كشفه يبدو مكتمل الحضور.
  String? _statusOf(String studentId) => marks[studentId];

  /// لمسة الرصد تُحدّث المسودّة فقط — الحفظ دفعة واحدة بزر «حفظ الرصد».
  void _setMark(String studentId, String? status) {
    final roomId = _attendanceRoomId;
    if (roomId.isEmpty) return;

    final day = {...marks};
    if (status == null) {
      day.remove(studentId);
    } else {
      day[studentId] = status;
    }
    setState(() => weekMarks = {...weekMarks, sessionDate: day});
    _dirtyMarks.add(studentId);

    unawaited(_offline.saveMarks(roomId, sessionDate, day));
    _duePush = (roomId: roomId, date: sessionDate, statuses: day, dirty: {..._dirtyMarks});
    // بلا رفع تلقائي — ينتظر زر الحفظ
    _pushTimer?.cancel();
    _pushTimer = null;
  }

  Future<void> _saveAttendanceNow() async {
    final due = _duePush;
    if (due == null && _dirtyMarks.isEmpty) return;
    final roomId = due?.roomId ?? _attendanceRoomId;
    final date = due?.date ?? sessionDate;
    final statuses = due?.statuses ?? marks;
    final dirty = due?.dirty ?? {..._dirtyMarks};
    if (roomId.isEmpty) return;
    _pushTimer?.cancel();
    _dirtyMarks.clear();
    _duePush = null;
    await runBusyOp(
      context,
      () => _pushMarks(roomId, date, statuses, changedStudentIds: dirty),
      message: 'جارٍ حفظ الرصد...',
    );
  }

  /// رفع كشف يوم. ما لم يُرفع يُصفّ ليُرسل حين يعود الاتصال.
  /// الواجهة لا تُحجز: الرصد محلي فوري، والمزامنة تُظهر فقط على زر المزامنة.
  Future<void> _pushMarks(
    String roomId,
    String date,
    Map<String, String> statuses, {
    Set<String>? changedStudentIds,
  }) async {
    if (mounted) setState(() => savingAttendance = true);
    try {
      await _sendWithBusyRetry(
        () => _service.saveAttendance(
          roomId: roomId,
          date: date,
          statuses: statuses,
          teacher: widget.user,
          changedStudentIds: changedStudentIds,
        ),
      );
      _portalRt?.announce(const ['attendance', 'sessions']);
      if (!mounted) return;
      setState(() {
        savingAttendance = false;
        offline = false;
      });
      _flushPending();
    } catch (e) {
      await _offline.queueAttendance(
        roomId: roomId,
        date: date,
        statuses: statuses,
        userId: widget.user.id,
      );
      if (!mounted) return;
      setState(() {
        savingAttendance = false;
        offline = true;
        pendingOps = _offline.pendingCountOf(widget.user.id);
      });
      if (_isServerBusy(e)) {
        showAppSnack(context, 'الخادم مشغول، حُفظ الرصد محلياً ويُرفع تلقائياً', error: true);
      }
    }
  }

  // ── الدرجات ───────────────────────────────────────────────────────────────

  Future<void> _loadEvaluations() async {
    final c = _current;
    if (c == null) return;
    final groupId = c.group.id;

    Map<String, String> rosterNames() => {
          for (final cl in _classes)
            for (final s in cl.students)
              if (s.fullName.trim().isNotEmpty) s.id: s.fullName.trim(),
        };

    // الكاش أولاً — كشف الدرجات يظهر بلا نت فور فتح التبويب
    final cached = _offline.loadEvaluations(groupId);
    if (cached != null) {
      setState(() {
        recent = cached;
        evalNames = rosterNames();
        recentVisible = kListPageSize;
      });
    }

    try {
      final list = await _service.groupEvaluations(groupId).timeout(_cloudTimeout);
      await _offline.saveEvaluations(groupId, list);
      if (!mounted || _current?.group.id != groupId) return;

      final names = rosterNames();
      final missing = {
        for (final e in list)
          if (e.studentId.isNotEmpty && !names.containsKey(e.studentId)) e.studentId,
      };
      if (missing.isNotEmpty) {
        try {
          names.addAll(
            await _service.studentNamesByIds(missing, widget.user.tenantId).timeout(_cloudTimeout),
          );
        } catch (_) {}
      }
      if (!mounted || _current?.group.id != groupId) return;
      setState(() {
        recent = list;
        evalNames = names;
        recentVisible = kListPageSize;
        offline = false;
      });
    } catch (_) {
      if (!mounted || _current?.group.id != groupId) return;
      setState(() {
        offline = true;
        pendingOps = _offline.pendingCountOf(widget.user.id);
      });
    }
  }

  Future<void> _deleteEvaluation(StudentEvaluation e) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف التقييم',
      message: 'هل أنت متأكد من حذف هذا التقييم؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;

    // يُحذف من الشاشة ومن نسخة الجهاز فوراً، ويُرفع الحذف حين يتاح الاتصال
    setState(() => recent = [for (final x in recent) if (x.id != e.id) x]);
    if (e.groupId.isNotEmpty) await _offline.saveEvaluations(e.groupId, recent);
    await _writeOrQueue(
      () => _service.deleteEvaluation(e.id),
      {'kind': 'evaluation_delete', 'id': e.id},
      announceTables: const ['student_evaluations'],
    );
  }

  /// تعديل علامة مرصودة — كنقر الخلية في كشف الويب.
  Future<void> _editScore(StudentEvaluation e, double score) async {
    final updated = [
      for (final x in recent) x.id == e.id ? x.copyWith(score: score) : x,
    ];
    setState(() => recent = updated);
    if (e.groupId.isNotEmpty) await _offline.saveEvaluations(e.groupId, updated);
    await _writeOrQueue(
      () => _service.updateEvaluationScore(e.id, score),
      {'kind': 'evaluation_score', 'id': e.id, 'score': score},
      announceTables: const ['student_evaluations'],
    );
  }

  // ── المودل ────────────────────────────────────────────────────────────────

  Future<void> _loadMoodle() async {
    final c = _current;
    if (c == null) return;
    final token = ++_moodleToken;
    final gid = c.group.id;

    // وحدات محفوظة تظهر فوراً — بلا انتظار شبكة (مثل الحضور)
    final cached = _offline.loadSections(gid, term);
    setState(() {
      if (cached != null) {
        sections = cached;
        loadingMoodle = false;
      } else {
        loadingMoodle = true;
      }
    });

    try {
      final list = await _service
          .groupSections(
            tenantId: widget.user.tenantId,
            groupId: gid,
            term: term,
            includeHidden: true,
          )
          .timeout(_cloudTimeout);
      await _offline.saveSections(gid, term, list);
      if (!mounted || token != _moodleToken) return;
      setState(() {
        sections = list;
        loadingMoodle = false;
        offline = false;
      });
    } catch (_) {
      if (!mounted || token != _moodleToken) return;
      setState(() {
        if (cached != null) sections = cached;
        loadingMoodle = false;
        offline = true;
        pendingOps = _offline.pendingCountOf(widget.user.id);
      });
    }
  }

  void _flash(String message) {
    setState(() => moodleMessage = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && moodleMessage == message) setState(() => moodleMessage = null);
    });
  }

  Future<void> _newSection() async {
    final c = _current;
    if (c == null) return;
    final created = await Navigator.of(context).push<CourseSection>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            titleSpacing: 0,
            title: const Text(
              'إضافة قسم أو وحدة دراسية',
              style: TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
          ),
          body: _NewSectionSheet(
            service: _service,
            tenantId: widget.user.tenantId,
            groupId: c.group.id,
            initialTerm: term,
            sortOrder: sections.length,
            color: _Brand(data!.branding).primary,
            rooms: c.rooms,
            asPage: true,
          ),
        ),
      ),
    );
    if (created == null || !mounted) return;
    if (created.term == term || (term == 'other' && created.term == 'general')) {
      setState(() => sections = [...sections, created]);
      await _cacheSections();
    }
    final sent = await _writeOrQueue(
      () => _service.saveSection(created),
      {'kind': 'section_upsert', 'row': created.toCloud()},
      announceTables: const ['course_sections'],
    );
    if (mounted) _flash(sent ? 'تم إنشاء القسم بنجاح' : 'حُفظ على الجهاز، سيُرفع عند عودة الاتصال');
  }

  Future<void> _toggleVisibility(CourseSection sec) async {
    final next = !sec.isVisible;
    setState(() => sections = [for (final s in sections) s.id == sec.id ? s.copyWith(isVisible: next) : s]);
    await _cacheSections();
    final sent = await _writeOrQueue(
      () => _service.setSectionVisible(sec.id, next),
      {'kind': 'section_visible', 'id': sec.id, 'visible': next},
      announceTables: const ['course_sections'],
    );
    if (!mounted) return;
    if (sent) {
      _flash(next ? 'الوحدة ظاهرة للطلاب' : 'الوحدة مخفية عن الطلاب');
    } else {
      _flash('حُفظ الإظهار محلياً، سيُرفع عند عودة الاتصال');
    }
  }

  /// حفظ وحدات الفصل المعروضة على الجهاز بعد كل تعديل.
  Future<void> _cacheSections() async {
    final c = _current;
    if (c != null) await _offline.saveSections(c.group.id, term, sections);
  }

  Future<void> _deleteSection(CourseSection sec) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف القسم',
      message: 'تأكيد حذف قسم "${sec.title}" وجميع مواده؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;

    setState(() => sections = sections.where((s) => s.id != sec.id).toList());
    await _cacheSections();
    await _writeOrQueue(
      () => _service.deleteSection(sec, widget.user.tenantId),
      {
        'kind': 'section_delete',
        'tenant_id': widget.user.tenantId,
        'row': sec.toCloud(),
        'items': [for (final i in sec.items) i.toCloud()],
      },
    );
  }

  Future<void> _newItem(CourseSection sec) async {
    final created = await Navigator.of(context).push<CourseItem>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            titleSpacing: 0,
            title: const Text(
              'إضافة مادة تعليمية / واجب',
              style: TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
          ),
          body: _NewItemSheet(
            service: _service,
            tenantId: widget.user.tenantId,
            section: sec,
            color: _Brand(data!.branding).primary,
            asPage: true,
          ),
        ),
      ),
    );
    if (created == null || !mounted) return;
    setState(() => sections = [
          for (final s in sections) s.id == sec.id ? s.copyWith(items: [...s.items, created]) : s,
        ]);
    await _cacheSections();
    if (!mounted) return;
    final sent = await runBusyOp(
      context,
      () => _writeOrQueue(
        () => _service.saveItem(created),
        {'kind': 'item_upsert', 'row': created.toCloud()},
      ),
      message: 'جارٍ حفظ المادة...',
    );
    if (mounted) _flash(sent ? 'تمت إضافة المادة بنجاح' : 'حُفظت على الجهاز، سترفع عند عودة الاتصال');
  }

  Future<void> _deleteItem(CourseSection sec, CourseItem item) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف المادة',
      message: 'تأكيد حذف "${item.title}"؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;

    setState(() => sections = [
          for (final s in sections)
            s.id == sec.id ? s.copyWith(items: s.items.where((i) => i.id != item.id).toList()) : s,
        ]);
    await _cacheSections();
    await _writeOrQueue(
      () => _service.deleteItem(item, widget.user.tenantId),
      {'kind': 'item_delete', 'tenant_id': widget.user.tenantId, 'row': item.toCloud()},
    );
  }

  Future<void> _copySection(CourseSection sec) async {
    final others = data!.classes.where((c) => c.group.id != groupId).toList();
    if (others.isEmpty) {
      showAppSnack(context, 'لا توجد شعب أخرى مسندة لك', error: true);
      return;
    }
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _CopySectionSheet(
        service: _service,
        tenantId: widget.user.tenantId,
        section: sec,
        targets: others,
        color: _Brand(data!.branding).primary,
      ),
    );
    if (count != null && mounted) _flash('تم نسخ القسم بنجاح إلى $count مادة');
  }

  /// إجراء التبويب المفتوح، قريباً من الإبهام بدل أعلى الشاشة.
  ThumbAction? _thumbAction(_Brand brand) {
    if (groupId.isEmpty && tab != 'attendance') return null;
    return switch (tab) {
      'moodle' => ThumbAction(
          label: 'إضافة وحدة',
          icon: Icons.add,
          color: brand.primary,
          onPressed: _current == null ? null : _newSection,
        ),
      'evaluations' => ThumbAction(
          label: 'رصد درجات',
          icon: Icons.add,
          color: brand.primary,
          onPressed: _current == null ? null : _openEvaluationForm,
        ),
      _ => _dirtyMarks.isNotEmpty || _duePush != null
          ? ThumbAction(
              label: 'حفظ الرصد',
              icon: Icons.save_rounded,
              color: AppColors.amber,
              onPressed: savingAttendance ? null : _saveAttendanceNow,
            )
          : ThumbAction(
              label: 'الكل حاضر',
              icon: Icons.done_all,
              color: AppColors.success,
              onPressed: _students().isEmpty ? null : _markAllPresent,
            ),
    };
  }

  /// رصد الجميع حاضرين في المسودّة — يُحفظ بزر الحفظ.
  void _markAllPresent() {
    final roomId = _attendanceRoomId;
    if (roomId.isEmpty) return;
    final day = {for (final s in _students()) s.id: 'present'};
    setState(() => weekMarks = {...weekMarks, sessionDate: day});
    _dirtyMarks
      ..clear()
      ..addAll(day.keys);
    unawaited(_offline.saveMarks(roomId, sessionDate, day));
    _duePush = (roomId: roomId, date: sessionDate, statuses: day, dirty: {..._dirtyMarks});
    _pushTimer?.cancel();
    _pushTimer = null;
  }

  // ── البناء ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final branding = data?.branding ?? const PortalBranding();
    final brand = _Brand(branding);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: AppText.family),
        child: Column(
        children: [
          PortalChromeHeader(
            branding: branding,
            displayName: widget.user.name,
            gradeLine: '',
            onExit: widget.onExit,
            action: _PortalSyncButton(
              offline: offline,
              pending: pendingOps,
              busy: savingAttendance,
              onTap: _syncNow,
            ),
          ),
          Expanded(
            child: loading
                ? _loadingView()
                : error != null
                    ? _errorView(error!, _load)
                    // الإجراء الأساسي لكل تبويب في منطقة الإبهام، كشاشات الإدارة
                    : ThumbActionLayer(
                        action: _thumbAction(brand),
                        secondary: tab == 'attendance' && (_dirtyMarks.isNotEmpty || _duePush != null)
                            ? ThumbAction(
                                label: 'الكل حاضر',
                                icon: Icons.done_all,
                                color: AppColors.success,
                                onPressed: _students().isEmpty ? null : _markAllPresent,
                              )
                            : null,
                        child: RefreshIndicator(
                          onRefresh: _load,
                          color: brand.active,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, thumbActionClearance),
                            children: switch (tab) {
                              'evaluations' => _evaluationsTab(brand),
                              'moodle' => _moodleTab(brand),
                              _ => _attendanceTab(brand),
                            },
                          ),
                        ),
                      ),
          ),
          PortalBottomNav(
            items: [
              for (final id in teacherPortalTabs(resolveFeatures(data?.features)))
                if (id == 'attendance')
                  const PortalNavItem(id: 'attendance', label: 'الحضور', icon: Icons.how_to_reg_outlined)
                else if (id == 'evaluations')
                  const PortalNavItem(id: 'evaluations', label: 'الدرجات', icon: Icons.workspace_premium_outlined)
                else if (id == 'moodle')
                  const PortalNavItem(id: 'moodle', label: 'المودل', icon: Icons.menu_book_outlined),
            ],
            activeId: tab,
            onSelect: _selectTab,
          ),
        ],
      ),
      ),
    );
  }



  /// اختيار نطاق الرصد: الصف ثم الشعبة ثم المادة — كنافذة الرصد في الويب.
  Widget _scopePicker() {
    final grades = _grades();
    final effectiveGrade = gradeFilter.isNotEmpty
        ? gradeFilter
        : (_current?.group.gradeLevel.trim().isNotEmpty == true
            ? _current!.group.gradeLevel.trim()
            : (grades.isEmpty ? '' : grades.first));
    final sections = _sections(effectiveGrade);
    final subjects = _subjectClasses(grade: effectiveGrade, section: sectionFilter);

    final gradeValue = grades.contains(effectiveGrade) ? effectiveGrade : null;
    final sectionValue = sections.contains(sectionFilter) ? sectionFilter : null;
    final subjectValue = subjects.any((c) => c.group.id == groupId) ? groupId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('الصف:'),
        _Select<String>(
          value: gradeValue,
          items: [
            if (grades.isEmpty)
              const DropdownMenuItem(value: '__none__', child: Text('لا صفوف مسندة'))
            else
              for (final g in grades) DropdownMenuItem(value: g, child: Text(g)),
          ],
          onChanged: grades.isEmpty
              ? null
              : (v) {
                  if (v != null && v != '__none__') _selectGrade(v);
                },
        ),
        const SizedBox(height: 10),
        const _Label('الشعبة:'),
        _Select<String>(
          value: sectionValue,
          hint: sections.isEmpty
              ? (effectiveGrade.isEmpty ? 'اختر الصف أولاً' : 'لا شعب في هذا الصف')
              : 'اختر الشعبة',
          items: [
            if (sections.isEmpty)
              DropdownMenuItem(
                value: '__none__',
                child: Text(effectiveGrade.isEmpty ? 'اختر الصف أولاً' : 'لا شعب في هذا الصف'),
              )
            else
              for (final s in sections) DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: sections.isEmpty
              ? null
              : (v) {
                  if (v != null && v != '__none__') _selectSection(v);
                },
        ),
        const SizedBox(height: 10),
        const _Label('المادة:'),
        _Select<String>(
          value: subjectValue,
          hint: 'اختر المادة',
          items: [
            if (subjects.isEmpty)
              const DropdownMenuItem(value: '__none__', child: Text('لا مواد'))
            else
              for (final c in subjects)
                DropdownMenuItem(
                  value: c.group.id,
                  child: Text(
                    c.subjectName.trim().isEmpty
                        ? cleanGroupName(c.group.name, c.group.gradeLevel)
                        : c.subjectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: subjects.isEmpty
              ? null
              : (v) {
                  if (v != null && v != '__none__') _selectGroup(v);
                },
        ),
        const SizedBox(height: 10),
      ],
    );
  }


  // ── تبويب رصد الحضور ─────────────────────────────────────────────────────

  /// كشف الحضور — نفس كشف الإدارة: شريط أيام الأسبوع، وملخّص اليوم، وصفّ
  /// لكل طالب بمفتاح رصد. الرصد يُحفظ في كشف الشعبة اليومي نفسه.
  List<Widget> _attendanceTab(_Brand brand) {
    final students = _students();
    var present = 0, absent = 0, excused = 0, unmarked = 0;
    for (final s in students) {
      switch (_statusOf(s.id)) {
        case 'present':
          present++;
        case 'absent':
          absent++;
        case 'excused':
          excused++;
        default:
          unmarked++;
      }
    }

    final week = _schoolWeek(weekOffset);
    // اكتمال رصد كل يوم في الشريط، كشريط الإدارة
    final dayProgress = <String, double>{
      for (final d in week)
        d.dateStr: students.isEmpty
            ? 0
            : students.where((s) => (weekMarks[d.dateStr] ?? const {}).containsKey(s.id)).length / students.length,
    };
    final selected = week.firstWhere(
      (d) => d.dateStr == sessionDate,
      orElse: () => week.where((d) => d.isToday).firstOrNull ?? week.first,
    );
    final visible = listPage(students, attendanceVisible);

    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // سطر واحد كشاشة الإدارة: زر الصف، لا ثلاث قوائم. المادة لا تُسأل
            // هنا — الحضور اليومي للشعبة كلها لا لحصة مادة.
            _AttendanceClassButton(
              label: _attendanceClassLabel(),
              onTap: _pickAttendanceClass,
            ),
            const SizedBox(height: 8),
            // الأيام بين سهمي الأسبوع، والسحب عليها ينقل بين الأسابيع أيضاً
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 200) return;
                // في العربية الأسبوع التالي على اليسار: السحب لليمين يُظهره
                setState(() => weekOffset += v > 0 ? 1 : -1);
                _loadMarks();
              },
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                children: [
                    _weekArrow(Icons.chevron_left, () {
                      setState(() => weekOffset--);
                      _loadMarks();
                    }),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Row(
                          children: [
                            for (final day in week)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: AttendanceDayChip(
                                    day: day,
                                    selected: day.dateStr == selected.dateStr,
                                    progress: dayProgress[day.dateStr] ?? 0,
                                    onTap: () => setState(() => sessionDate = day.dateStr),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _weekArrow(Icons.chevron_right, () {
                      setState(() => weekOffset++);
                      _loadMarks();
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AttendanceDaySummary(
        day: selected,
        total: students.length,
        present: present,
        absent: absent,
        excused: excused,
        unmarked: unmarked,
      ),
      const SizedBox(height: 12),
      if (sectionFilter.trim().isEmpty && _sections().isNotEmpty)
        const _Empty('اختر الشعبة من زر الصف لعرض كشفها', height: 150)
      else if (students.isEmpty)
        const _Empty('لا يوجد طلاب مسجلون في هذه الشعبة', height: 150)
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Corner.card),
            border: Border.all(color: AppColors.line),
            boxShadow: cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++)
                AttendanceStudentRow(
                  key: ValueKey('${visible[i].id}|$sessionDate'),
                  index: i + 1,
                  student: visible[i],
                  status: _statusOf(visible[i].id),
                  canEdit: true,
                  last: i == visible.length - 1,
                  onSet: (status) => _setMark(visible[i].id, status),
                ),
            ],
          ),
        ),
      LoadMoreButton(
        shown: visible.length,
        total: students.length,
        onMore: () => setState(() => attendanceVisible += kListPageSize),
      ),
    ];
  }

  /// عنوان زر الصف: «الصف · الشعبة»، أو دعوة للاختيار.
  String _attendanceClassLabel() {
    final parts = [
      if (gradeFilter.trim().isNotEmpty) gradeFilter.trim(),
      if (sectionFilter.trim().isNotEmpty) sectionFilter.trim(),
    ];
    return parts.isEmpty ? 'اختر الصف' : parts.join('  ·  ');
  }

  /// ورقة اختيار الصف ثم الشعبة — ورقة واحدة كورقة الإدارة.
  Future<void> _pickAttendanceClass() async {
    final grades = _grades();
    if (grades.isEmpty) return;

    final picked = await showModalBottomSheet<({String grade, String section})>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
      ),
      builder: (_) => _AttendanceClassSheet(
        grades: grades,
        initialGrade: gradeFilter.isNotEmpty ? gradeFilter : grades.first,
        sectionsOf: _sections,
        currentSection: sectionFilter,
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      gradeFilter = picked.grade;
      sectionFilter = picked.section;
      // المادة تتبع الصف: الحضور لا يسأل عنها، والتبويبات الأخرى تحتاجها
      final subjects = _subjectClasses();
      if (!subjects.any((c) => c.group.id == groupId)) {
        groupId = subjects.isEmpty ? '' : subjects.first.group.id;
      }
      _resetRecording();
    });
    _loadMarks();
  }

  /// أيام الأسبوع المدرسي — نفس حساب الإدارة (السبت أوله، والجمعة عطلة).
  List<SchoolDay> _schoolWeek(int offsetWeeks) {
    final now = DateTime.now();
    final saturday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: (now.weekday + 1) % 7))
        .add(Duration(days: offsetWeeks * 7));
    const names = ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
    final today = isoDate(now);
    return [
      for (var i = 0; i < 6; i++)
        () {
          final d = saturday.add(Duration(days: i));
          return SchoolDay(
            date: d,
            dateStr: isoDate(d),
            dayName: names[i],
            shortDate: '${d.day}/${d.month}',
            isToday: isoDate(d) == today,
          );
        }(),
    ];
  }

  Widget _weekArrow(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(icon, size: 20, color: AppColors.muted),
    );
  }

  /// مخطط الرصد في بوابة المعلم: النموذج الافتراضي إن لم تُعرّف مكوّنات.
  GradingScheme get _evalRecordingScheme =>
      withDefaultTerms(data?.branding.gradingScheme ?? GradingScheme.empty);

  // ── تبويب الدرجات: السجل هنا، والرصد صفحة منفصلة لكشف الطلاب الطويل ──

  Future<void> _openEvaluationForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TeacherEvaluationFormPage(
          offline: _offline,
          user: widget.user,
          service: _service,
          classes: _classes,
          branding: data?.branding ?? const PortalBranding(),
          gradingScheme: _evalRecordingScheme,
          initialGroupId: groupId,
          initialGrade: gradeFilter,
          initialSection: sectionFilter,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      showAppSnack(context, 'تم حفظ كشف الدرجات');
      _loadEvaluations();
    }
  }

  List<Widget> _evaluationsTab(_Brand brand) {

    String nameOf(String studentId) {
      final fromMap = evalNames[studentId]?.trim() ?? '';
      if (fromMap.isNotEmpty) return fromMap;
      for (final cl in _classes) {
        final s = cl.students.where((x) => x.id == studentId).firstOrNull;
        if (s != null && s.fullName.trim().isNotEmpty) return s.fullName.trim();
      }
      return 'طالب';
    }

    final groups = _recentByEvaluation();

    return [
      // النطاق وحده في البطاقة: زر الرصد انتقل إلى منطقة الإبهام، والشرح
      // المكتوب كان يشغل مساحةً بلا فائدة يومية
      _Card(child: _scopePicker()),
      if (groups.isNotEmpty) ...[
        const SizedBox(height: 14),
        // بطاقة لكل اختبار بمعدّله، وتُفتح فتظهر درجات طلابه
        Row(
          children: [
            Expanded(
              child: Text(
                'التقييمات السابقة',
                style: TextStyle(
                  fontFamily: AppText.family,
                  color: AppColors.heading,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${groups.length}',
              style: const TextStyle(color: AppColors.faint, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecentEvaluationCard(
              title: entry.title,
              meta: entry.meta,
              average: entry.average,
              rows: entry.rows,
              nameOf: nameOf,
              onDelete: _deleteEvaluation,
              onEditScore: _editScore,
            ),
          ),
      ] else ...[
        const SizedBox(height: 16),
        const _Empty('لا تقييمات سابقة لهذه المادة بعد', height: 110),
      ],
    ];
  }


  /// سجل الدرجات مجموعاً بالتقييم: اختبار واحد ببطاقة، لا صفّاً لكل طالب.
  List<({String title, String meta, int average, List<StudentEvaluation> rows})> _recentByEvaluation() {
    final groups = <String, List<StudentEvaluation>>{};
    for (final e in recent) {
      groups.putIfAbsent('${e.title}|${e.evaluationDate}|${e.type}', () => []).add(e);
    }

    final out = <({String title, String meta, int average, List<StudentEvaluation> rows})>[];
    for (final rows in groups.values) {
      final first = rows.first;
      final scored = rows.where((e) => e.percent != null).toList();
      final average = scored.isEmpty
          ? 0
          : (scored.fold<int>(0, (a, e) => a + (e.percent ?? 0)) / scored.length).round();
      out.add((
        title: first.title.isEmpty ? 'تقييم' : first.title,
        meta: [
          first.typeLabel,
          if (first.evaluationDate.isNotEmpty) first.evaluationDate.split('T').first,
          '${rows.length} طالب',
        ].where((x) => x.trim().isNotEmpty).join('  ·  '),
        average: average,
        rows: rows,
      ));
    }
    return out;
  }

  // ── تبويب المودل ─────────────────────────────────────────────────────────

  List<Widget> _moodleTab(_Brand brand) {
    final classes = data?.classes ?? const <TeacherClass>[];
    final hasGroup = _current != null;

    return [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('المادة / المجموعة:', style: TextStyle(color: _C.muted, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            _Select<String>(
              value: groupId,
              height: 36,
              items: classes.isEmpty
                  ? const [DropdownMenuItem(value: '', child: Text('لا توجد مواد مسندة لك'))]
                  : [
                      for (final k in classes)
                        DropdownMenuItem(
                          value: k.group.id,
                          child: Text(
                            [
                              if (k.subjectName.trim().isNotEmpty) k.subjectName.trim(),
                              if (k.roomName.trim().isNotEmpty) '— ${k.roomName.trim()}',
                              if (k.subjectName.trim().isEmpty)
                                (k.roomName.trim().isNotEmpty
                                    ? k.roomName.trim()
                                    : cleanGroupName(k.group.name, k.group.gradeLevel)),
                              if (k.group.gradeLevel.trim().isNotEmpty)
                                '(${k.group.gradeLevel.trim()})',
                            ].where((e) => e.toString().trim().isNotEmpty).join(' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
              onChanged: classes.isEmpty ? null : _selectGroup,
            ),
            const SizedBox(height: 10),
            _TermSwitch(
              value: term,
              onChanged: (t) {
                setState(() => term = t);
                _loadMoodle();
              },
            ),
            const SizedBox(height: 10),
            // الإضافة تحت الفصل بعرض الشعبة كاملاً — هي الإجراء المقصود هنا
            _Solid(
              label: 'إضافة وحدة / قسم',
              icon: Icons.add,
              color: brand.primary,
              height: 42,
              radius: Corner.field,
              onTap: hasGroup ? _newSection : null,
            ),
          ],
        ),
      ),
      if (moodleMessage != null) ...[const SizedBox(height: 12), _Success(moodleMessage!)],
      const SizedBox(height: 16),
      if (loadingMoodle)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _C.navy)),
              SizedBox(height: 8),
              Text('جارٍ تحميل الوحدات الدراسية...', style: TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        )
      else if (sections.isEmpty)
        _Empty(
          'لا توجد وحدات مضافة لهذه المادة في هذا الفصل',
          icon: Icons.layers_outlined,
          dashed: true,
          height: 200,
          action: hasGroup ? 'انقر هنا لإضافة أول وحدة' : null,
          onAction: hasGroup ? _newSection : null,
        )
      else
        for (final sec in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: sec.isVisible ? Colors.white : const Color(0x33FFFBEB),
              borderRadius: BorderRadius.circular(Corner.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(Corner.card),
                onTap: () => _openSectionPage(sec),
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Corner.card),
                    border: Border.all(color: sec.isVisible ? _C.line : _C.amber200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sec.title,
                              style: const TextStyle(
                                fontFamily: AppText.family,
                                color: _C.navy,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _Badge(sec.termLabel, fg: _C.muted, bg: _C.line, radius: Corner.chip),
                                _Badge('${sec.items.length} عنصر', fg: _C.muted, bg: _C.line, radius: Corner.chip),
                                if (!sec.isVisible)
                                  const _Badge('مخفي', fg: _C.amber700, bg: _C.amber100, radius: Corner.chip),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const AppChevron(color: _C.faint),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  Future<void> _openSectionPage(CourseSection sec) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _TeacherSectionPage(
          sectionId: sec.id,
          liveSection: () => sections.where((s) => s.id == sec.id).firstOrNull ?? sec,
          rooms: _current?.rooms ?? const [],
          onAddItem: () => _newItem(sec),
          onCopy: () => _copySection(sec),
          onToggle: () => _toggleVisibility(sec),
          onDelete: () async {
            await _deleteSection(sec);
            if (mounted) Navigator.of(context).pop();
          },
          onEditRooms: (_current?.rooms.length ?? 0) > 1 ? () => _editSectionRooms(sec) : null,
          onOpenItem: (it) => _openMaterial(
            context,
            it.contentUrl,
            service: _service,
            fileName: it.fileName,
          ),
          onDeleteItem: (it) => _deleteItem(sec, it),
          service: _service,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// تعديل شعب الوحدة — كل الشعب = null في السحابة.
  Future<void> _editSectionRooms(CourseSection sec) async {
    final rooms = _current?.rooms ?? const <PortalRoom>[];
    if (rooms.length <= 1) return;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (_) => _SectionRoomsSheet(
        title: sec.title,
        rooms: rooms,
        selected: sec.roomIds.isEmpty ? rooms.map((r) => r.id).toList() : [...sec.roomIds],
        color: _Brand(data!.branding).primary,
      ),
    );
    if (picked == null || !mounted) return;
    final allSelected = rooms.every((r) => picked.contains(r.id));
    final roomIds = allSelected ? const <String>[] : picked;
    setState(() => sections = [
          for (final s in sections) s.id == sec.id ? s.copyWith(roomIds: roomIds) : s,
        ]);
    await _cacheSections();
    await _writeOrQueue(
      () => _service.updateSection(sec.id, roomIds: roomIds),
      {
        'kind': 'section_upsert',
        'row': sections.firstWhere((s) => s.id == sec.id).toCloud(),
      },
    );
    if (mounted) _flash('حُفظت الشعب');
  }
}

/// صفحة رصد درجات المعلم — منفصلة عن التبويب لأن كشف الطلاب يطول.
class _TeacherEvaluationFormPage extends StatefulWidget {
  const _TeacherEvaluationFormPage({
    required this.user,
    required this.service,
    required this.offline,
    required this.classes,
    required this.branding,
    required this.gradingScheme,
    this.initialGroupId = '',
    this.initialGrade = '',
    this.initialSection = '',
  });

  final PortalUser user;
  final PortalService service;
  final PortalOffline offline;
  final List<TeacherClass> classes;
  final PortalBranding branding;
  final GradingScheme gradingScheme;
  final String initialGroupId;
  final String initialGrade;
  final String initialSection;

  @override
  State<_TeacherEvaluationFormPage> createState() => _TeacherEvaluationFormPageState();
}

class _TeacherEvaluationFormPageState extends State<_TeacherEvaluationFormPage> {
  static const _uuid = Uuid();

  late String groupId = widget.initialGroupId;
  late String gradeFilter = widget.initialGrade;
  late String sectionFilter = widget.initialSection;

  final evalTitle = TextEditingController();
  final evalMax = TextEditingController(text: trimNum(defaultFullMark));
  String evalType = 'quiz';
  late String evalDate = isoDate(DateTime.now());
  late String evalTerm = termForDate(evalDate);
  String evalComponentId = '';
  String? titleError;
  final _scores = <String, TextEditingController>{};
  final _notes = <String, TextEditingController>{};
  bool saving = false;
  int rosterVisible = kListPageSize;

  _Brand get brand => _Brand(widget.branding);

  TeacherClass? get _current => widget.classes.where((c) => c.group.id == groupId).firstOrNull;

  @override
  void initState() {
    super.initState();
    // إن فُتحت الصفحة بلا شعبة: اختر الوحيدة، أو شعبة قاعة المادة الحالية
    final secs = _sections();
    if (sectionFilter.isEmpty && secs.isNotEmpty) {
      if (secs.length == 1) {
        sectionFilter = secs.first;
      } else {
        final current = _current;
        final rooms = current == null
            ? const <String>[]
            : current.roomName
                .split(RegExp(r'\s*[،,]\s*'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty);
        sectionFilter = rooms.cast<String>().where(secs.contains).firstOrNull ?? secs.first;
      }
    }
  }

  List<String> _grades() {
    final list = <String>{
      for (final c in widget.classes)
        if (c.group.gradeLevel.trim().isNotEmpty) c.group.gradeLevel.trim(),
    }.toList()
      ..sort();
    return list;
  }

  List<String> _sections([String? grade]) {
    final g = grade ?? gradeFilter;
    final current = _current;
    if (current != null) {
      final local = _teacherSectionsFor([current], grade: g);
      if (local.isNotEmpty) return local;
    }
    return _teacherSectionsFor(widget.classes, grade: g);
  }

  List<TeacherClass> _subjectClasses({String? grade, String? section}) {
    final g = (grade ?? gradeFilter).trim();
    return [
      for (final c in widget.classes)
        if (g.isEmpty || c.group.gradeLevel.trim().isEmpty || c.group.gradeLevel.trim() == g) c,
    ];
  }

  List<Student> _students() => _teacherRosterStudents(
        _current,
        sectionFilter: sectionFilter,
        grade: gradeFilter,
      );

  TextEditingController _ctl(Map<String, TextEditingController> map, String id) =>
      map.putIfAbsent(id, TextEditingController.new);

  double get _maxScore {
    final v = double.tryParse(evalMax.text.trim());
    return (v == null || v <= 0) ? defaultFullMark : v;
  }

  void _clearScores() {
    for (final c in [..._scores.values, ..._notes.values]) {
      c.dispose();
    }
    _scores.clear();
    _notes.clear();
    rosterVisible = kListPageSize;
  }

  void _selectGrade(String value) {
    setState(() {
      gradeFilter = value;
      sectionFilter = '';
      final sections = _sections();
      if (sections.length == 1) sectionFilter = sections.first;
      final subjects = _subjectClasses();
      groupId = subjects.length == 1 ? subjects.first.group.id : '';
      _clearScores();
    });
  }

  void _selectSection(String value) {
    setState(() {
      sectionFilter = value;
      final subjects = _subjectClasses();
      if (!subjects.any((c) => c.group.id == groupId)) {
        groupId = subjects.length == 1 ? subjects.first.group.id : '';
      }
      _clearScores();
    });
  }

  void _selectGroup(String? id) {
    if (id == null || id == groupId) return;
    setState(() {
      groupId = id;
      final current = widget.classes.where((c) => c.group.id == id).firstOrNull;
      if (current != null) {
        final g = current.group.gradeLevel.trim();
        if (g.isNotEmpty) gradeFilter = g;
      }
      sectionFilter = '';
      final secs = _sections();
      if (secs.length == 1) sectionFilter = secs.first;
      _clearScores();
      evalMax.text = trimNum(defaultFullMark);
      evalComponentId = '';
    });
  }

  @override
  void dispose() {
    evalTitle.dispose();
    evalMax.dispose();
    for (final c in [..._scores.values, ..._notes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final c = _current;
    if (c == null || saving) return;

    final title = evalTitle.text.trim();
    setState(() => titleError = title.isEmpty ? 'يرجى إدخال عنوان الاختبار أو التقييم' : null);
    if (title.isEmpty) {
      showAppSnack(context, 'يرجى تحديد عنوان التقييم واختيار المادة', error: true);
      return;
    }

    final max = _maxScore;
    final batch = <StudentEvaluation>[];
    for (final s in _students()) {
      final raw = _ctl(_scores, s.id).text.trim();
      if (raw.isEmpty) continue;
      final score = double.tryParse(raw);
      if (score == null || score < 0 || score > max) {
        showAppSnack(context, 'درجة غير صالحة للطالب ${s.fullName} (من 0 إلى ${trimNum(max)})', error: true);
        return;
      }
      final comps = evalTerm.isEmpty ? const <GradingComponent>[] : widget.gradingScheme.of(evalTerm);
      final comp = comps.where((x) => x.id == evalComponentId).firstOrNull;
      batch.add(StudentEvaluation(
        id: _uuid.v4(),
        studentId: s.id,
        groupId: c.group.id,
        subjectId: c.group.subjectId,
        teacherId: widget.user.id,
        title: title,
        score: score,
        maxScore: max,
        evaluationDate: evalDate,
        type: evalComponentId.isNotEmpty ? evaluationTypeForComponent(comp?.name) : evalType,
        notes: _ctl(_notes, s.id).text.trim(),
        term: evalTerm,
        componentId: evalTerm.isNotEmpty && evalComponentId.isNotEmpty ? evalComponentId : '',
      ));
    }
    if (batch.isEmpty) {
      showAppSnack(context, 'يرجى إدخال درجة واحدة على الأقل', error: true);
      return;
    }

    setState(() => saving = true);
    try {
      await widget.service.saveEvaluations(batch, widget.user.tenantId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      // بلا شبكة: الدرجات تُحفظ على الجهاز وتُرفع أول ما يعود الاتصال
      await widget.offline.queueEvaluations(batch, widget.user.tenantId, widget.user.id);
      if (!mounted) return;
      setState(() => saving = false);
      showAppSnack(context, 'حُفظت على الجهاز، سترفع عند عودة الاتصال');
      Navigator.pop(context, true);
    }
  }

  Widget _scopePicker() {
    final grades = _grades();
    final effectiveGrade = gradeFilter.isNotEmpty
        ? gradeFilter
        : (_current?.group.gradeLevel.trim().isNotEmpty == true
            ? _current!.group.gradeLevel.trim()
            : (grades.isEmpty ? '' : grades.first));
    final sections = _sections(effectiveGrade);
    final subjects = _subjectClasses(grade: effectiveGrade, section: sectionFilter);

    final gradeValue = grades.contains(effectiveGrade) ? effectiveGrade : null;
    final sectionValue = sections.contains(sectionFilter) ? sectionFilter : null;
    final subjectValue = subjects.any((c) => c.group.id == groupId) ? groupId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('الصف:'),
        _Select<String>(
          value: gradeValue,
          items: [
            if (grades.isEmpty)
              const DropdownMenuItem(value: '__none__', child: Text('لا صفوف مسندة'))
            else
              for (final g in grades) DropdownMenuItem(value: g, child: Text(g)),
          ],
          onChanged: grades.isEmpty
              ? null
              : (v) {
                  if (v != null && v != '__none__') _selectGrade(v);
                },
        ),
        const SizedBox(height: 10),
        const _Label('الشعبة:'),
        _Select<String>(
          value: sectionValue,
          hint: sections.isEmpty
              ? (effectiveGrade.isEmpty ? 'اختر الصف أولاً' : 'لا شعب في هذا الصف')
              : 'اختر الشعبة',
          items: [
            if (sections.isEmpty)
              DropdownMenuItem(
                value: '__none__',
                child: Text(effectiveGrade.isEmpty ? 'اختر الصف أولاً' : 'لا شعب في هذا الصف'),
              )
            else
              for (final s in sections) DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: sections.isEmpty
              ? null
              : (v) {
                  if (v != null && v != '__none__') _selectSection(v);
                },
        ),
        const SizedBox(height: 10),
        const _Label('المادة:'),
        _Select<String>(
          value: subjectValue,
          hint: 'اختر المادة',
          items: [
            if (subjects.isEmpty)
              const DropdownMenuItem(value: '__none__', child: Text('لا مواد'))
            else
              for (final c in subjects)
                DropdownMenuItem(
                  value: c.group.id,
                  child: Text(
                    c.subjectName.trim().isEmpty
                        ? cleanGroupName(c.group.name, c.group.gradeLevel)
                        : c.subjectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: subjects.isEmpty
              ? null
              : (v) {
                  if (v != null && v != '__none__') _selectGroup(v);
                },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = _students();
    final visibleStudents = listPage(students, rosterVisible);
    final scheme = widget.gradingScheme;
    final components = evalTerm.isEmpty ? const <GradingComponent>[] : scheme.of(evalTerm);
    final useComponents = evalTerm.isNotEmpty && components.isNotEmpty;
    final fullMark = defaultFullMark;

    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)],
        );

    Widget field(String label, Widget input) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [_Label(label), input],
        );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'رصد درجات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _scopePicker(),
                field(
                  'العنوان',
                  _Input(
                    controller: evalTitle,
                    hint: 'العنوان',
                    errorText: titleError,
                    onChanged: (_) {
                      if (titleError != null) setState(() => titleError = null);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                pair(
                  field(
                    'الفصل',
                    _Select<String>(
                      value: evalTerm.isEmpty ? 'term_1' : evalTerm,
                      height: 36,
                      items: [
                        for (final e in gradingTermLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() {
                        evalTerm = v ?? 'term_1';
                        evalComponentId = '';
                        evalTitle.clear();
                      }),
                    ),
                  ),
                  useComponents
                      ? field(
                          'المكوّن',
                          _Select<String>(
                            value: evalComponentId,
                            height: 36,
                            items: [
                              const DropdownMenuItem(value: '', child: Text('اختر المكوّن')),
                              for (final c in components)
                                DropdownMenuItem(
                                  value: c.id,
                                  child: Text('${c.name} (من ${trimNum(componentMark(c, fullMark))})'),
                                ),
                            ],
                            onChanged: (id) {
                              final cid = id ?? '';
                              setState(() {
                                evalComponentId = cid;
                                final comp = components.where((x) => x.id == cid).firstOrNull;
                                if (comp == null) return;
                                evalTitle.text = comp.name;
                                final mark = componentMark(comp, fullMark);
                                evalMax.text = trimNum(mark > 0 ? mark : fullMark);
                                evalType = evaluationTypeForComponent(comp.name);
                                titleError = null;
                              });
                            },
                          ),
                        )
                      : field(
                          'النوع',
                          _Select<String>(
                            value: evalType,
                            height: 36,
                            items: [
                              for (final e in evaluationTypeNames.entries)
                                DropdownMenuItem(value: e.key, child: Text(e.value)),
                            ],
                            onChanged: (v) => setState(() => evalType = v ?? evalType),
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                pair(
                  field(
                    'من',
                    _Input(controller: evalMax, keyboardType: TextInputType.number, ltr: true),
                  ),
                  field(
                    'التاريخ',
                    _DateBox(
                      date: evalDate,
                      onPicked: (d) => setState(() {
                        final next = termForDate(d);
                        evalDate = d;
                        if (next != evalTerm) {
                          evalComponentId = '';
                          evalTitle.clear();
                        }
                        evalTerm = next;
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'قائمة الطلاب (${students.length})',
                    style: const TextStyle(color: _C.navy, fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
                if (students.isNotEmpty)
                  InkWell(
                    onTap: () {
                      final full = trimNum(_maxScore);
                      setState(() {
                        for (final s in _students()) {
                          _ctl(_scores, s.id).text = full;
                        }
                      });
                    },
                    child: const Text(
                      'رصد الدرجة الكاملة للجميع',
                      style: TextStyle(color: _C.blue600, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              'اترك الدرجة فارغة لمن لم يختبر',
              style: TextStyle(color: _C.muted, fontSize: 11),
            ),
          ),
          if (students.isEmpty)
            const _Empty('لا يوجد طلاب مسجلون في هذه الشعبة', height: 110)
          else ...[
            for (final s in visibleStudents)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Card(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _C.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: _Input(
                          controller: _ctl(_scores, s.id),
                          hint: 'من ${trimNum(_maxScore)}',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ltr: true,
                          center: true,
                          dense: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: _Input(controller: _ctl(_notes, s.id), hint: 'ملاحظة', dense: true),
                      ),
                    ],
                  ),
                ),
              ),
            LoadMoreButton(
              shown: visibleStudents.length,
              total: students.length,
              onMore: () => setState(() => rosterVisible += kListPageSize),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: saving || students.isEmpty ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: brand.action,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corner.field)),
              ),
              child: Text(
                saving ? 'جاري الحفظ...' : 'حفظ كشف الدرجات',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// صفحة وحدة المودل للمعلم — محتوى طويل يُقرأ براحة في شاشة مستقلة.
class _TeacherSectionPage extends StatefulWidget {
  const _TeacherSectionPage({
    required this.sectionId,
    required this.liveSection,
    required this.rooms,
    required this.onAddItem,
    required this.onCopy,
    required this.onToggle,
    required this.onDelete,
    required this.onOpenItem,
    required this.onDeleteItem,
    required this.service,
    this.onEditRooms,
  });

  final String sectionId;
  final CourseSection Function() liveSection;
  final List<PortalRoom> rooms;
  final Future<void> Function() onAddItem;
  final VoidCallback onCopy;
  final Future<void> Function() onToggle;
  final Future<void> Function() onDelete;
  final ValueChanged<CourseItem> onOpenItem;
  final Future<void> Function(CourseItem) onDeleteItem;
  final VoidCallback? onEditRooms;
  final PortalService service;

  @override
  State<_TeacherSectionPage> createState() => _TeacherSectionPageState();
}

class _TeacherSectionPageState extends State<_TeacherSectionPage> {
  late CourseSection section = widget.liveSection();

  Future<void> _refreshAfter(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    setState(() => section = widget.liveSection());
  }

  String get _roomsLabel {
    if (section.roomIds.isEmpty) return 'كل الشعب';
    final names = [
      for (final id in section.roomIds)
        widget.rooms.where((r) => r.id == id).map((r) => r.name).firstOrNull,
    ].whereType<String>().where((n) => n.trim().isNotEmpty);
    return names.isEmpty ? 'شعب محددةدة' : names.join('، ');
  }

  @override
  Widget build(BuildContext context) {
    final sec = section;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sec.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            Text(
              _roomsLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppText.family, color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Soft(
                label: 'مادة',
                icon: Icons.add,
                fg: _C.navy,
                height: 34,
                radius: Corner.field,
                onTap: () => _refreshAfter(widget.onAddItem),
              ),
              if (widget.onEditRooms != null)
                _Soft(
                  label: 'الشعب',
                  icon: Icons.meeting_room_outlined,
                  fg: _C.muted,
                  height: 34,
                  radius: Corner.field,
                  onTap: () => _refreshAfter(() async {
                    widget.onEditRooms!();
                  }),
                ),
              _Soft(label: 'نسخ', icon: Icons.copy_outlined, fg: _C.muted, height: 34, radius: Corner.field, onTap: widget.onCopy),
              _Soft(
                label: sec.isVisible ? 'إخفاء' : 'إظهار',
                icon: sec.isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                fg: sec.isVisible ? _C.muted : _C.amber600,
                height: 34,
                radius: Corner.field,
                onTap: () => _refreshAfter(widget.onToggle),
              ),
              _Soft(label: 'حذف', icon: Icons.delete_outline, fg: _C.rose600, height: 34, radius: Corner.field, onTap: widget.onDelete),
            ],
          ),
          const SizedBox(height: 14),
          if (sec.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'لا توجد مواد أو واجبات مضافة في هذه الوحدة',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AppText.family, color: _C.faint, fontSize: 12),
              ),
            )
          else
            for (final it in sec.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ItemTile(
                  item: it,
                  service: widget.service,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.contentUrl.isNotEmpty)
                        _Soft(
                          label: 'فتح',
                          icon: it.type == 'file' ? Icons.description_outlined : Icons.open_in_new,
                          fg: _C.navy,
                          height: 28,
                          radius: Corner.field,
                          onTap: () => widget.onOpenItem(it),
                        ),
                      IconButton(
                        tooltip: 'حذف المادة',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.delete_outline, size: 16, color: _C.rose600),
                        onPressed: () => _refreshAfter(() => widget.onDeleteItem(it)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// مادة تعليمية: نوعها وعنوانها ووصفها وموعد تسليمها، مقابل إجراءاتها.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.trailing, this.service = const PortalService()});

  final CourseItem item;
  final Widget trailing;
  final PortalService service;

  @override
  Widget build(BuildContext context) {
    final colors = _itemTypeColors(item.type);
    final overdue = item.isOverdue();
    final showImage = item.contentUrl.isNotEmpty &&
        item.type != 'link' &&
        portalLooksLikeImage(item.contentUrl, fileName: item.fileName);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: _C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Badge(item.typeLabel, fg: colors.fg, bg: colors.bg, radius: Corner.chip),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontFamily: AppText.family,
                            color: _C.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (item.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description.trim(),
                        style: const TextStyle(
                          fontFamily: AppText.family,
                          color: _C.slate600,
                          fontSize: 12.5,
                          height: 1.65,
                        ),
                      ),
                    ],
                    if (item.type == 'assignment' && item.dueDate.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'تاريخ التسليم: ${item.dueDate}${overdue ? ' (منتهٍ)' : ''}',
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: overdue ? _C.faint : _C.emerald700,
                          fontSize: 11,
                          fontWeight: overdue ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
          if (showImage)
            PortalInlineImage(url: item.contentUrl, fileName: item.fileName, service: service),
        ],
      ),
    );
  }
}

// ── نوافذ المودل ───────────────────────────────────────────────────────────

Widget _sheetFrame(BuildContext context, {required String title, required List<Widget> children}) {
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontFamily: AppText.family, color: _C.navy, fontSize: 13, fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _sheetActions(BuildContext context, {required String label, required Color color, required bool busy, required VoidCallback? onSave}) {
  return Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: _Solid(label: busy ? 'جارٍ الحفظ...' : label, color: color, busy: busy, onTap: onSave, height: 40, radius: Corner.field),
        ),
        const SizedBox(width: 8),
        Expanded(child: _Soft(label: 'إلغاء', onTap: () => Navigator.pop(context), height: 40, radius: Corner.field)),
      ],
    ),
  );
}

class _NewSectionSheet extends StatefulWidget {
  const _NewSectionSheet({
    required this.service,
    required this.tenantId,
    required this.groupId,
    required this.initialTerm,
    required this.sortOrder,
    required this.color,
    this.rooms = const [],
    this.asPage = false,
  });

  final PortalService service;
  final String tenantId;
  final String groupId;
  final String initialTerm;
  final int sortOrder;
  final Color color;
  final List<PortalRoom> rooms;
  final bool asPage;

  @override
  State<_NewSectionSheet> createState() => _NewSectionSheetState();
}

class _NewSectionSheetState extends State<_NewSectionSheet> {
  final title = TextEditingController();
  late String term = widget.initialTerm == 'general' ? 'other' : widget.initialTerm;
  late List<String> selectedRooms = [for (final r in widget.rooms) r.id];
  String? titleError;
  bool busy = false;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      setState(() => titleError = 'يرجى إدخال عنوان الوحدة');
      return;
    }
    final allSelected =
        widget.rooms.isEmpty || widget.rooms.every((r) => selectedRooms.contains(r.id));
    // كل الشعب → فارغ في السحابة: شعبة تُضاف لاحقاً ترى الوحدة تلقائياً
    final roomIds = allSelected || widget.rooms.length <= 1 ? const <String>[] : [...selectedRooms];
    Navigator.pop(
      context,
      CourseSection(
        id: const Uuid().v4(),
        tenantId: widget.tenantId,
        groupId: widget.groupId,
        term: term,
        title: title.text.trim(),
        sortOrder: widget.sortOrder,
        createdAt: DateTime.now().toIso8601String(),
        roomIds: roomIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = <Widget>[
        const _Label('عنوان الوحدة / القسم:'),
        _Input(
          controller: title,
          hint: 'مثال: الوحدة الأولى - الجبر والمصفوفات',
          errorText: titleError,
          onChanged: (_) {
            if (titleError != null) setState(() => titleError = null);
          },
        ),
        const SizedBox(height: 12),
        const _Label('الفصل الدراسي:'),
        _Select<String>(
          value: term,
          items: const [
            DropdownMenuItem(value: 'term_1', child: Text('الفصل الأول')),
            DropdownMenuItem(value: 'term_2', child: Text('الفصل الثاني')),
            DropdownMenuItem(value: 'other', child: Text('أخرى')),
          ],
          onChanged: (v) => setState(() => term = v ?? term),
        ),
        if (widget.rooms.length > 1) ...[
          const SizedBox(height: 12),
          const _Label('الشعب المستهدفة (فارغ الكل = كل الشعب):'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in widget.rooms)
                FilterChip(
                  label: Text(r.name, style: const TextStyle(fontFamily: AppText.family, fontSize: 11, fontWeight: FontWeight.w800)),
                  selected: selectedRooms.contains(r.id),
                  onSelected: (on) {
                    setState(() {
                      if (on) {
                        selectedRooms = [...selectedRooms, r.id];
                      } else if (selectedRooms.length > 1) {
                        selectedRooms = [for (final id in selectedRooms) if (id != r.id) id];
                      }
                    });
                  },
                  selectedColor: widget.color.withValues(alpha: 0.15),
                  checkmarkColor: widget.color,
                  side: BorderSide(color: selectedRooms.contains(r.id) ? widget.color : _C.line),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
        _sheetActions(context, label: 'حفظ القسم', color: widget.color, busy: busy, onSave: _save),
    ];
    if (widget.asPage) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        children: form,
      );
    }
    return _sheetFrame(context, title: 'إضافة قسم أو وحدة دراسية', children: form);
  }
}

/// اختيار شعب وحدة قائمة.
class _SectionRoomsSheet extends StatefulWidget {
  const _SectionRoomsSheet({
    required this.title,
    required this.rooms,
    required this.selected,
    required this.color,
  });

  final String title;
  final List<PortalRoom> rooms;
  final List<String> selected;
  final Color color;

  @override
  State<_SectionRoomsSheet> createState() => _SectionRoomsSheetState();
}

class _SectionRoomsSheetState extends State<_SectionRoomsSheet> {
  late List<String> selected = [...widget.selected];

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(
      context,
      title: 'الشعب — ${widget.title}',
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in widget.rooms)
              FilterChip(
                label: Text(r.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                selected: selected.contains(r.id),
                onSelected: (on) {
                  setState(() {
                    if (on) {
                      selected = [...selected, r.id];
                    } else if (selected.length > 1) {
                      selected = [for (final id in selected) if (id != r.id) id];
                    }
                  });
                },
                selectedColor: widget.color.withValues(alpha: 0.15),
                checkmarkColor: widget.color,
                side: BorderSide(color: selected.contains(r.id) ? widget.color : _C.line),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
        _sheetActions(
          context,
          label: 'حفظ',
          color: widget.color,
          busy: false,
          onSave: () => Navigator.pop(context, selected),
        ),
      ],
    );
  }
}

class _NewItemSheet extends StatefulWidget {
  const _NewItemSheet({
    required this.service,
    required this.tenantId,
    required this.section,
    required this.color,
    this.asPage = false,
  });

  final PortalService service;
  final String tenantId;
  final CourseSection section;
  final Color color;
  final bool asPage;

  @override
  State<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends State<_NewItemSheet> {
  final title = TextEditingController();
  final url = TextEditingController();
  final description = TextEditingController();
  String type = 'file';
  String dueDate = '';
  XFile? file;
  int fileSize = 0;
  List<int>? fileBytes;

  /// اسم ما يُرفع فعلاً — قد يختلف امتداده عن المختار بعد التصغير.
  String fileName = '';
  String? titleError;
  String? error;

  /// يُصغَّر الآن: اللمس على «حفظ» قبل انتهائه يرفع الأصل الضخم.
  bool shrinking = false;
  String? shrunkNotice;
  bool busy = false;

  @override
  void dispose() {
    title.dispose();
    url.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF أو صورة',
          extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'],
          uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png', 'org.webmproject.webp'],
        ),
      ],
    );
    if (picked == null) return;
    final original = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => shrinking = ImageShrink.isImage(picked.name));

    // صورة الهاتف تأتي بأبعاد ضخمة: تُصغَّر قبل أن تستهلك باقة المعلم رفعاً
    // وباقة الطالب تنزيلاً — وقبل أن ترتد عند حد العشرة ميجابايت.
    final shrunk = await ImageShrink.forUpload(original, picked.name);
    final bytes = shrunk.bytes;
    final saved = ImageShrink.savedPercent(original.length, bytes.length);
    if (!mounted) return;
    setState(() {
      shrinking = false;
      if (bytes.length > PortalService.maxMaterialBytes) {
        error = 'حجم الملف يتجاوز 10 ميجابايت';
        file = null;
        fileBytes = null;
      } else if (PortalService.materialMime(shrunk.fileName) == null) {
        error = 'نوع الملف غير مدعوم؛ يُسمح بملفات PDF والصور فقط';
        file = null;
        fileBytes = null;
      } else {
        error = null;
        file = picked;
        fileName = shrunk.fileName;
        fileBytes = bytes;
        fileSize = bytes.length;
        shrunkNotice = saved >= 10 ? 'صُغّرت الصورة $saved٪' : null;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      titleError = title.text.trim().isEmpty ? 'يرجى إدخال العنوان' : null;
      error = null;
    });
    if (titleError != null) return;
    if (type == 'file' && fileBytes == null) {
      setState(() => error = 'يرجى اختيار ملف (PDF أو صورة)');
      return;
    }
    final link = url.text.trim();
    if (type == 'link') {
      final uri = Uri.tryParse(link);
      if (link.isEmpty || uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        setState(() => error = 'يرجى إدخال رابط صحيح يبدأ بـ https://');
        return;
      }
    }

    setState(() => busy = true);
    try {
      var contentUrl = type == 'link' ? link : '';
      var uploadedName = '';
      int? size;
      if (type == 'file') {
        final name = fileName.isEmpty ? file!.name : fileName;
        contentUrl = await widget.service.uploadMaterial(
          bytes: fileBytes!,
          fileName: name,
          tenantId: widget.tenantId,
        );
        uploadedName = name;
        size = fileSize;
      }
      // تُبنى بمعرّفها هنا: المادة النصية والرابط والواجب تُنشأ بلا شبكة،
      // ويتولّى الرفع من فتح الورقة. الملف وحده يلزمه اتصال لرفع بايتاته.
      // تاريخ التسليم: إن لم يختر المعلم يوماً نستخدم المعروض (اليوم) لا فراغاً.
      final resolvedDue =
          type == 'assignment' ? (dueDate.isEmpty ? isoDate(DateTime.now()) : dueDate) : '';
      final item = CourseItem(
        id: const Uuid().v4(),
        tenantId: widget.tenantId,
        sectionId: widget.section.id,
        groupId: widget.section.groupId,
        title: title.text,
        type: type,
        contentUrl: contentUrl,
        fileName: uploadedName,
        fileSize: size,
        description: description.text,
        dueDate: resolvedDue,
        sortOrder: widget.section.items.length,
        createdAt: DateTime.now().toIso8601String(),
      );
      if (mounted) Navigator.pop(context, item);
    } on PortalException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          // رفع بايتات الملف لا يمكن تأجيله، بخلاف بقية الأنواع
          error = type == 'file' ? 'رفع الملف يحتاج اتصالاً بالإنترنت' : 'فشل إضافة العنصر';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = <Widget>[
        const _Label('نوع العنصر:'),
        _Select<String>(
          value: type,
          items: const [
            DropdownMenuItem(value: 'file', child: Text('ورقة عمل / ملخص (PDF أو صورة)')),
            DropdownMenuItem(value: 'link', child: Text('رابط فيديو / شرح (YouTube / Drive)')),
            DropdownMenuItem(value: 'assignment', child: Text('واجب منزلي')),
            DropdownMenuItem(value: 'note', child: Text('ملاحظة / توجيه تعليمي')),
          ],
          onChanged: (v) => setState(() {
            type = v ?? type;
            error = null;
            // العرض يظهر اليوم افتراضياً؛ نحفظه حتى لا يُرفع الواجب بلا تاريخ
            if (type == 'assignment' && dueDate.isEmpty) {
              dueDate = isoDate(DateTime.now());
            }
          }),
        ),
        const SizedBox(height: 12),
        const _Label('العنوان:'),
        _Input(
          controller: title,
          hint: 'عنوان الدرس أو ورقة العمل أو الواجب...',
          errorText: titleError,
          onChanged: (_) {
            if (titleError != null) setState(() => titleError = null);
          },
        ),
        if (type == 'file') ...[
          const SizedBox(height: 12),
          const _Label('الملف المرفق (PDF أو صورة - أقصى حد 10MB):'),
          Row(
            children: [
              _Soft(label: 'اختيار ملف', icon: Icons.attach_file, fg: _C.navy, bg: _C.soft, border: _C.soft, height: 36, radius: Corner.field, onTap: shrinking ? null : _pick),
              const SizedBox(width: 8),
              if (shrinking)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.muted)),
              if (shrinking) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shrinking ? 'جارٍ تصغير الصورة...' : (file?.name ?? 'لم يُختر ملف'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _C.muted, fontSize: 12),
                ),
              ),
            ],
          ),
          if (shrunkNotice != null) ...[
            const SizedBox(height: 4),
            Text(
              shrunkNotice!,
              style: const TextStyle(color: _C.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ],
        ],
        if (type == 'link') ...[
          const SizedBox(height: 12),
          const _Label('رابط الشرح أو المادة:'),
          _Input(controller: url, hint: 'https://...', keyboardType: TextInputType.url, ltr: true),
          const SizedBox(height: 4),
          const Text(
            'تنبيه: إذا كان الرابط من Google Drive تأكد من ضبطه على "متاح لأي شخص لديه الرابط".',
            style: TextStyle(color: _C.muted, fontSize: 10.5, height: 1.5),
          ),
        ],
        if (type == 'assignment') ...[
          const SizedBox(height: 12),
          const _Label('تاريخ التسليم في الحصة:'),
          _DateBox(
            date: dueDate.isEmpty ? isoDate(DateTime.now()) : dueDate,
            onPicked: (d) => setState(() => dueDate = d),
          ),
        ],
        const SizedBox(height: 12),
        const _Label('وصف أو تعليمات إضافية (اختياري):'),
        _Input(
          controller: description,
          hint: 'اكتب أرقام الصفحات أو ملاحظات الدراسة...',
          maxLines: widget.asPage ? 8 : 2,
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _C.rose50,
              borderRadius: BorderRadius.circular(Corner.box),
              border: Border.all(color: _C.rose200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 15, color: _C.rose700),
                const SizedBox(width: 6),
                Expanded(child: Text(error!, style: const TextStyle(color: _C.rose700, fontSize: 12, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
        ],
        _sheetActions(context, label: 'حفظ المادة', color: widget.color, busy: busy || shrinking, onSave: _save),
    ];
    if (widget.asPage) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        children: form,
      );
    }
    return _sheetFrame(context, title: 'إضافة مادة تعليمية / واجب', children: form);
  }
}

class _CopySectionSheet extends StatefulWidget {
  const _CopySectionSheet({
    required this.service,
    required this.tenantId,
    required this.section,
    required this.targets,
    required this.color,
  });

  final PortalService service;
  final String tenantId;
  final CourseSection section;
  final List<TeacherClass> targets;
  final Color color;

  @override
  State<_CopySectionSheet> createState() => _CopySectionSheetState();
}

class _CopySectionSheetState extends State<_CopySectionSheet> {
  final selected = <String>{};
  bool busy = false;

  Future<void> _copy() async {
    setState(() => busy = true);
    try {
      final count = await widget.service.copySectionToGroups(widget.section, selected.toList(), widget.tenantId);
      if (mounted) Navigator.pop(context, count);
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      showAppSnack(context, 'فشل نسخ القسم', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(
      context,
      title: 'نسخ القسم لمواد أخرى',
      children: [
        Text.rich(
          TextSpan(
            text: 'سيتم نسخ وحدة ',
            children: [
              TextSpan(
                text: '"${widget.section.title}"',
                style: const TextStyle(color: _C.text, fontWeight: FontWeight.w800),
              ),
              const TextSpan(text: ' وجميع موادها للشعب المختارة:'),
            ],
          ),
          style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.circular(Corner.box),
            border: Border.all(color: _C.line),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(6),
            children: [
              for (final t in widget.targets)
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: _C.navy,
                  value: selected.contains(t.group.id),
                  onChanged: (v) => setState(() => v == true ? selected.add(t.group.id) : selected.remove(t.group.id)),
                  title: Text(
                    [
                      t.roomName.trim().isNotEmpty
                          ? t.roomName.trim()
                          : cleanGroupName(t.group.name, t.group.gradeLevel),
                      if (t.subjectName.trim().isNotEmpty) '(${t.subjectName.trim()})',
                      if (t.group.gradeLevel.trim().isNotEmpty) '— ${t.group.gradeLevel.trim()}',
                    ].join(' '),
                    style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
        _sheetActions(
          context,
          label: busy ? 'جارٍ النسخ...' : 'نسخ إلى (${selected.length}) شعب',
          color: widget.color,
          busy: busy,
          onSave: selected.isEmpty ? null : _copy,
        ),
      ],
    );
  }
}

/// تقييم واحد في سجل المعلم: عنوانه ومعدّله، ويُفتح فتظهر درجات طلابه.
class _RecentEvaluationCard extends StatefulWidget {
  const _RecentEvaluationCard({
    required this.title,
    required this.meta,
    required this.average,
    required this.rows,
    required this.nameOf,
    required this.onDelete,
    required this.onEditScore,
  });

  final String title;
  final String meta;
  final int average;
  final List<StudentEvaluation> rows;
  final String Function(String studentId) nameOf;
  final void Function(StudentEvaluation) onDelete;
  final void Function(StudentEvaluation, double) onEditScore;

  @override
  State<_RecentEvaluationCard> createState() => _RecentEvaluationCardState();
}

class _RecentEvaluationCardState extends State<_RecentEvaluationCard> {
  bool open = false;

  Color get _tone {
    if (widget.average >= 85) return const Color(0xFF2E7D57);
    if (widget.average >= 60) return const Color(0xFF9A6700);
    return const Color(0xFFA5484A);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 8, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            color: AppColors.heading,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.faint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.average}%',
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: _tone,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Container(
                    decoration: const BoxDecoration(
                      color: AppColors.sunken,
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < widget.rows.length; i++)
                          Container(
                            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
                            decoration: BoxDecoration(
                              border: i == widget.rows.length - 1
                                  ? null
                                  : const Border(bottom: BorderSide(color: AppColors.hover)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.nameOf(widget.rows[i].studentId),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _EditableScore(
                                  row: widget.rows[i],
                                  onSave: (v) => widget.onEditScore(widget.rows[i], v),
                                ),
                                IconButton(
                                  tooltip: 'حذف',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline, size: 17, color: AppColors.danger),
                                  onPressed: () => widget.onDelete(widget.rows[i]),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// حالة المزامنة في ترويسة المعلم — مقابل زر المزامنة في ترويسة الإدارة.
///
/// سحابة مشطوبة بلا اتصال، وعدد ما ينتظر الرفع فوقها، وضغطة تفتح تفاصيل المعلّقات.
class _PortalSyncButton extends StatelessWidget {
  const _PortalSyncButton({
    required this.offline,
    required this.pending,
    required this.busy,
    required this.onTap,
  });

  final bool offline;
  final int pending;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tooltip = offline
        ? (pending > 0 ? 'لا يوجد اتصال · $pending بانتظار الرفع' : 'لا يوجد اتصال')
        : (pending > 0 ? '$pending بانتظار الرفع' : 'تفاصيل المزامنة');

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: busy ? null : onTap,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (busy)
                SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                )
              else
                Icon(
                  offline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                  size: 19,
                  color: offline ? const Color(0xFFF2C14E) : Colors.white.withValues(alpha: 0.85),
                ),
              if (pending > 0 && !busy)
                PositionedDirectional(
                  top: -4,
                  end: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2C14E),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '$pending',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF3A2A00),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ورقة تفاصيل مزامنة بوابة المعلم — ما ينتظر الرفع وآخر تحديث من السحابة.
Future<void> openPortalSyncSheet(
  BuildContext context, {
  required PortalOffline offline,
  required String userId,
  required DateTime? syncedAt,
  required Future<bool> Function() onSync,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    isScrollControlled: true,
    builder: (ctx) => _PortalSyncSheet(
      offline: offline,
      userId: userId,
      syncedAt: syncedAt,
      onSync: onSync,
    ),
  );
}

class _PortalSyncSheet extends StatefulWidget {
  const _PortalSyncSheet({
    required this.offline,
    required this.userId,
    required this.syncedAt,
    required this.onSync,
  });

  final PortalOffline offline;
  final String userId;
  final DateTime? syncedAt;
  final Future<bool> Function() onSync;

  @override
  State<_PortalSyncSheet> createState() => _PortalSyncSheetState();
}

class _PortalSyncSheetState extends State<_PortalSyncSheet> {
  bool running = false;
  String? resultMessage;
  bool? resultOk;

  List<Map<String, dynamic>> get _ops => widget.offline.pendingOf(widget.userId);

  String get _syncedLabel {
    final at = widget.syncedAt;
    if (at == null) return 'لم تُحدَّث البيانات من السحابة بعد';
    final local = at.toLocal();
    final d =
        '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    final t =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return 'آخر تحديث من السحابة: $d · $t';
  }

  Future<void> _run() async {
    setState(() {
      running = true;
      resultMessage = null;
      resultOk = null;
    });
    final ok = await widget.onSync();
    if (!mounted) return;
    setState(() {
      running = false;
      resultOk = ok;
      resultMessage = ok ? 'كل شيء محدّث' : 'تعذّرت المزامنة أو بقي رصد معلّق';
    });
    if (ok) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ops = _ops;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'تفاصيل المزامنة',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              Text(
                _syncedLabel,
                style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              if (ops.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.sunken,
                    borderRadius: BorderRadius.circular(Corner.box),
                  ),
                  child: const Text(
                    'لا يوجد رصد معلّق للرفع. البوابة تعمل من نسخة الجهاز عند انقطاع الشبكة.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45),
                  ),
                )
              else ...[
                Text(
                  '${ops.length} بانتظار الرفع',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.navy),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.35),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ops.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final op = ops[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.amber),
                        title: Text(
                          PortalOffline.pendingOpLabel(op),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (resultMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  resultMessage!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: resultOk == true ? AppColors.success : AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: running ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(ops.isEmpty ? 'تحديث من السحابة' : 'رفع المعلّقات وتحديث'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// زر الصف في كشف حضور المعلم — مقابل زر الصف في كشف الإدارة.
class _AttendanceClassButton extends StatelessWidget {
  const _AttendanceClassButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sunken,
      borderRadius: BorderRadius.circular(Corner.field),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corner.field),
        child: Container(
          height: 40,
          padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.field),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.groups_2_outlined, size: 17, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: AppColors.heading,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// اختيار الصف ثم شعبته في ورقة واحدة.
class _AttendanceClassSheet extends StatefulWidget {
  const _AttendanceClassSheet({
    required this.grades,
    required this.initialGrade,
    required this.sectionsOf,
    required this.currentSection,
  });

  final List<String> grades;
  final String initialGrade;
  final List<String> Function(String grade) sectionsOf;
  final String currentSection;

  @override
  State<_AttendanceClassSheet> createState() => _AttendanceClassSheetState();
}

class _AttendanceClassSheetState extends State<_AttendanceClassSheet> {
  late String grade = widget.initialGrade;

  @override
  Widget build(BuildContext context) {
    final sections = widget.sectionsOf(grade);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('المرحلة', style: AppText.cardTitle),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in widget.grades)
                  SheetChoiceChip(
                    label: g,
                    selected: g == grade,
                    onTap: () => setState(() => grade = g),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('الشعبة', style: AppText.cardTitle),
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'لا شعب مسندة لهذا الصف',
                  style: TextStyle(color: AppColors.faint, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )
            else
              for (final s in sections)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s,
                    style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  trailing: s == widget.currentSection
                      ? const Icon(Icons.check_rounded, size: 18, color: AppColors.success)
                      : null,
                  onTap: () => Navigator.pop(context, (grade: grade, section: s)),
                ),
          ],
        ),
      ),
    );
  }
}

/// علامة تُلمس فتُعدَّل — مقابل نقر خلية العلامة في كشف الويب.
///
/// الرصد يخطئ، والمعلم كان مضطراً لحذف التقييم وإعادة رصده كلّه لتصحيح رقم.
class _EditableScore extends StatefulWidget {
  const _EditableScore({required this.row, required this.onSave});

  final StudentEvaluation row;
  final ValueChanged<double> onSave;

  @override
  State<_EditableScore> createState() => _EditableScoreState();
}

class _EditableScoreState extends State<_EditableScore> {
  bool editing = false;
  late final TextEditingController ctl = TextEditingController(
    text: widget.row.score == null ? '' : trimNum(widget.row.score!),
  );

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _commit() {
    setState(() => editing = false);
    final v = double.tryParse(ctl.text.trim());
    if (v == null || v < 0 || v > widget.row.maxScore) {
      // خارج المدى: تُردّ إلى قيمتها ولا تُحفظ
      ctl.text = widget.row.score == null ? '' : trimNum(widget.row.score!);
      showAppSnack(context, 'العلامة بين 0 و ${trimNum(widget.row.maxScore)}', error: true);
      return;
    }
    if (v != widget.row.score) widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return SizedBox(
        width: 74,
        height: 30,
        child: TextField(
          controller: ctl,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            fontFamily: AppText.family,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppColors.heading,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            suffixText: '/${trimNum(widget.row.maxScore)}',
            suffixStyle: const TextStyle(color: AppColors.faint, fontSize: 10.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corner.field - 2)),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }

    return InkWell(
      onTap: () => setState(() => editing = true),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          '${widget.row.score == null ? '—' : trimNum(widget.row.score!)}'
          ' / ${trimNum(widget.row.maxScore)}',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: AppText.family,
            color: AppColors.heading,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
