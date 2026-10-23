import 'package:flutter/material.dart';

import '../data/material_limits.dart';
import '../data/portal.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'moodle_style.dart';
import 'noon_ui.dart';

// المودل بهوية نون — المقابل لـ `MoodleParts.tsx` و`lessonKinds.tsx` و`StorageMeter.tsx`
// في الويب: رقم الوحدة، وبطاقتها بلونها، وسطر الدرس بلون نوعه، ومقياس مساحة المدرسة.
// مشترك بين الطالب وولي الأمر والمعلم.

/// خيارات الفصل في المودل.
const noonTermOptions = <(String, String)>[
  ('term_1', 'الفصل الأول'),
  ('term_2', 'الفصل الثاني'),
  ('other', 'أخرى'),
];

// ── نوع الدرس ────────────────────────────────────────────────────────────────

/// نوع الدرس للعرض: أيقونته ولونه وتسميته القصيرة (`KIND_META`).
typedef LessonKindMeta = ({String label, IconData icon, Color fg, Color bg});

const _kinds = <String, LessonKindMeta>{
  'pdf': (label: 'PDF', icon: Icons.description_outlined, fg: Color(0xFFB91C1C), bg: Color(0xFFFEF2F2)),
  'word': (label: 'Word', icon: Icons.text_snippet_outlined, fg: Color(0xFF1D4ED8), bg: Color(0xFFEFF6FF)),
  'powerpoint': (label: 'PowerPoint', icon: Icons.co_present_outlined, fg: Color(0xFFC2410C), bg: Color(0xFFFFF7ED)),
  'excel': (label: 'Excel', icon: Icons.table_chart_outlined, fg: Color(0xFF047857), bg: Color(0xFFECFDF5)),
  'image': (label: 'صورة', icon: Icons.image_outlined, fg: Color(0xFF6D28D9), bg: Color(0xFFF5F3FF)),
  'file': (label: 'ملف', icon: Icons.attach_file_rounded, fg: Color(0xFF0F6E74), bg: Color(0xFFDDF1F0)),
  'link': (label: 'رابط', icon: Icons.link_rounded, fg: Color(0xFF0F6E74), bg: Color(0xFFDDF1F0)),
  'assignment': (label: 'واجب', icon: Icons.assignment_outlined, fg: Color(0xFF8A5B00), bg: Color(0xFFFEF1D2)),
  'note': (label: 'ملاحظة', icon: Icons.sticky_note_2_outlined, fg: Color(0xFF51696B), bg: Color(0xFFF4F7F7)),
};

const _byExt = {
  'pdf': 'pdf',
  'doc': 'word',
  'docx': 'word',
  'ppt': 'powerpoint',
  'pptx': 'powerpoint',
  'xls': 'excel',
  'xlsx': 'excel',
  'jpg': 'image',
  'jpeg': 'image',
  'png': 'image',
  'webp': 'image',
  'gif': 'image',
  'heic': 'image',
  'heif': 'image',
};

String _ext(String name) {
  final n = name.trim().toLowerCase();
  final dot = n.lastIndexOf('.');
  return dot < 0 || dot == n.length - 1 ? '' : n.substring(dot + 1);
}

/// الملف يُعرف من امتداد اسمه (أو من رابطه إن غاب الاسم)، والباقي من نوع الدرس.
String lessonKind(CourseItem item) {
  if (item.type != 'file') return _kinds.containsKey(item.type) ? item.type : 'note';
  var ext = _ext(item.fileName);
  if (ext.isEmpty) ext = _ext(Uri.decodeComponent(item.contentUrl.split('?').first.split('/').last));
  return _byExt[ext] ?? 'file';
}

LessonKindMeta lessonKindMeta(CourseItem item) => _kinds[lessonKind(item)]!;

// ── الوحدة ───────────────────────────────────────────────────────────────────

/// رقم الوحدة بلونها: مربع 32 بزاوية 8 ورقم أبيض.
class NUnitChip extends StatelessWidget {
  const NUnitChip({super.key, required this.n, required this.color});

  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(NoonRadius.tile)),
      child: Text('$n', style: nText(14, weight: FontWeight.w700, color: Colors.white, height: 1)),
    );
  }
}

/// بطاقة بلون [color]: خلفية فاتحة جداً منه (5%)، وحد خفيف (20%)، وطرف بلونه الكامل 4px
/// (`unitCardStyle`). تُستعمل للوحدة، وللدرس بلون نوعه.
class NTintCard extends StatelessWidget {
  const NTintCard({
    super.key,
    required this.color,
    required this.child,
    this.background,
    this.borderAlpha = 0x33,
    this.onTap,
    this.padding = const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
    this.shadow = true,
    this.dim = false,
  });

  final Color color;
  final Color? background;
  final int borderAlpha;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  /// وحدة مخفية عن الطلاب: تُخفَّف لتُعرف.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(NoonRadius.panel);
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: body));
    }
    final card = Container(
      decoration: BoxDecoration(
        color: background ?? color.withAlpha(0x0D),
        borderRadius: radius,
        boxShadow: shadow ? nShadow : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: color.withAlpha(borderAlpha)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
    return dim ? Opacity(opacity: 0.8, child: card) : card;
  }
}

/// حقائق الوحدة: الفصل وعدد الدروس (والشعب للمعلم)، ووسم «مخفي» وحده.
class NUnitMeta extends StatelessWidget {
  const NUnitMeta({super.key, required this.section, this.rooms = '', this.showHidden = false});

  final CourseSection section;
  final String rooms;
  final bool showHidden;

  @override
  Widget build(BuildContext context) {
    final meta = NMetaLine(
      items: [
        ('الفصل', academicTermLabels[section.term] ?? section.term, null),
        ('الدروس', '${section.items.length}', null),
        ('الشعب', rooms, null),
      ],
    );
    if (!showHidden || section.isVisible) return meta;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [meta, const NBadge('مخفي', tone: NTone.sun)],
    );
  }
}

/// وحدة في قائمة الجوال: رقمها بلونها، وعنوانها 16 عريض، وحقائقها، وسهم يفتح صفحتها.
/// [trailing] سهما الترتيب عند المعلم.
class NUnitRow extends StatelessWidget {
  const NUnitRow({
    super.key,
    required this.section,
    required this.index,
    required this.color,
    required this.onOpen,
    this.meta,
    this.trailing,
  });

  final CourseSection section;
  final int index;
  final Color color;
  final VoidCallback onOpen;
  final Widget? meta;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final main = InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(12, trailing == null ? 14 : 12, trailing == null ? 12 : 0, trailing == null ? 14 : 12),
        child: Row(
          children: [
            NUnitChip(n: index + 1, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(section.title, style: nText(16, weight: FontWeight.w700, height: 1.375)),
                  const SizedBox(height: 4),
                  meta ?? NUnitMeta(section: section),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_left_rounded, size: 22, color: Noon.muted, textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
    return NTintCard(
      color: color,
      padding: EdgeInsets.zero,
      dim: !section.isVisible && trailing != null,
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(child: main),
            if (trailing != null) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: trailing),
          ],
        ),
      ),
    );
  }
}

/// وحدة بلا دروس.
class NNoLessons extends StatelessWidget {
  const NNoLessons({super.key, this.text = 'لا دروس'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Noon.band,
        borderRadius: BorderRadius.circular(NoonRadius.tile),
        border: Border.all(color: Noon.line),
      ),
      child: Text(text, style: nText(14, weight: FontWeight.w500, color: Noon.muted)),
    );
  }
}

/// درس: بطاقة بخلفية فاتحة من لون نوعه وطرف بلونه الكامل، وبلاطة أيقونة مملوءة، والعنوان
/// بتنسيقه، وسطر «النوع · الحجم · التسليم»، والوصف. لمس البطاقة يفتح المادة.
/// [trailing] قائمة إجراءات المعلم، وإلا سهم الفتح.
class NLessonRow extends StatelessWidget {
  const NLessonRow({
    super.key,
    required this.item,
    this.onOpen,
    this.trailing,
    this.student = true,
    this.dueLabel,
  });

  final CourseItem item;
  final VoidCallback? onOpen;
  final Widget? trailing;
  final bool student;
  final String Function(String date)? dueLabel;

  @override
  Widget build(BuildContext context) {
    final meta = lessonKindMeta(item);
    final canOpen = item.contentUrl.isNotEmpty && onOpen != null;
    final overdue = item.isOverdue();
    final size = item.type == 'file' && (item.fileSize ?? 0) > 0 ? formatBytes(item.fileSize!) : '';
    final due = item.type == 'assignment' && item.dueDate.isNotEmpty
        ? '${dueLabel?.call(item.dueDate) ?? item.dueDate}${overdue ? ' (منتهٍ)' : ''}'
        : '';
    return NTintCard(
      color: meta.fg,
      background: meta.bg,
      borderAlpha: 0x26,
      shadow: false,
      onTap: canOpen ? onOpen : null,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: meta.fg, borderRadius: BorderRadius.circular(NoonRadius.tile)),
            child: Icon(meta.icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: nText(
                        15,
                        weight: item.titleBold ? FontWeight.w700 : FontWeight.w600,
                        color: hexColor(item.titleColor) ?? Noon.text,
                        height: 1.375,
                      ),
                    ),
                    if (student && item.isNew()) const NBadge('جديد', tone: NTone.sun),
                  ],
                ),
                const SizedBox(height: 4),
                NMetaLine(
                  items: [
                    ('النوع', meta.label, meta.fg),
                    ('الحجم', size, null),
                    ('التسليم', due, overdue ? Noon.muted : Noon.green700),
                  ],
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.description.trim(),
                    maxLines: student ? null : 2,
                    overflow: student ? null : TextOverflow.ellipsis,
                    style: nText(13, color: Noon.muted, height: 1.625),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (canOpen)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, top: 10),
              child: Icon(Icons.chevron_left_rounded, size: 22, color: Noon.muted, textDirection: TextDirection.ltr),
            ),
        ],
      ),
    );
  }
}

/// دروس الوحدة بطاقات متتالية بفراغ 8.
class NLessonsList extends StatelessWidget {
  const NLessonsList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const NNoLessons();
    return NColumn(gap: 8, children: children);
  }
}

// ── مساحة المدرسة ────────────────────────────────────────────────────────────

/// شريط رفيع بمساحة ملفات المدرسة؛ من 90% فأكثر بلون التحذير.
class NStorageMeter extends StatelessWidget {
  const NStorageMeter({super.key, required this.status});

  final StorageStatus status;

  static String _size(int bytes) => formatBytes(bytes).replaceAll('.0 ', ' ');

  @override
  Widget build(BuildContext context) {
    final ratio = status.quotaBytes > 0 ? (status.usedBytes / status.quotaBytes).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100).round();
    final warn = ratio >= 0.9;
    return Tooltip(
      message: '$pct% مستخدم${warn ? ' - اقتربت المساحة من الامتلاء' : ''}',
      child: Row(
        children: [
          Icon(Icons.storage_rounded, size: 16, color: warn ? Noon.warn : Noon.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مساحة المدرسة ${_size(status.usedBytes)} من ${_size(status.quotaBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nText(12, weight: FontWeight.w700, color: warn ? Noon.warn : Noon.text),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: Noon.mist)),
                        FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: (pct < 2 ? 2 : pct) / 100,
                          child: ColoredBox(color: warn ? Noon.action : Noon.teal),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// مواد الطالب كبسولات قابلة للتمرير: المختارة بلون الإجراء في ثيم المدرسة.
class NSubjectPills<T> extends StatelessWidget {
  const NSubjectPills({super.key, required this.items, required this.selected, required this.onSelect});

  final List<(T, String)> items;
  final T? selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 1),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final on = items[i].$1 == selected;
          final radius = BorderRadius.circular(NoonRadius.btn);
          return Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: on ? const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2), spreadRadius: -2)] : null,
            ),
            child: Material(
              color: on ? Noon.action : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: on ? Noon.action : Noon.line)),
              child: InkWell(
                borderRadius: radius,
                onTap: () => onSelect(items[i].$1),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: Text(
                    items[i].$2,
                    maxLines: 1,
                    style: nText(12.5, weight: FontWeight.w700, color: on ? Noon.onAction : Noon.text),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
