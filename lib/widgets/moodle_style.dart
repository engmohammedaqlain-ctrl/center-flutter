import 'package:flutter/material.dart';

import '../data/portal.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

// تنسيق المودل — المقابل لـ `features/moodle/moodleStyle.tsx`: لون لكل وحدة، ولون
// وخط عريض لعنوان الدرس.
//
// لوحة ثابتة لا منتقي ألوان حر: ثمانية ألوان مقروءة على الأبيض، متباعدة بما يكفي
// لتمييز الوحدات المتجاورة. الوحدة بلا لون تأخذ لوناً بترتيبها، فالصفحة مرتبة
// حتى لو لم يختر المعلم شيئاً.

const unitColors = <({String hex, String label})>[
  (hex: '#2563EB', label: 'أزرق'),
  (hex: '#059669', label: 'أخضر'),
  (hex: '#7C3AED', label: 'بنفسجي'),
  (hex: '#D97706', label: 'برتقالي'),
  (hex: '#E11D48', label: 'أحمر'),
  (hex: '#0D9488', label: 'فيروزي'),
  (hex: '#4F46E5', label: 'نيلي'),
  (hex: '#475569', label: 'رمادي'),
];

final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// لون من `#RRGGBB`، أو `null` لغير ذلك.
Color? hexColor(String value) => _hex.hasMatch(value) ? Color(int.parse('FF${value.substring(1)}', radix: 16)) : null;

/// لون الوحدة: المختار، وإلا بترتيبها في الصفحة.
Color unitColor(CourseSection section, int index) =>
    hexColor(section.color) ?? hexColor(unitColors[index % unitColors.length].hex)!;

/// إطار بطاقة الوحدة من لونها.
Color unitBorder(Color color) => color.withAlpha(0x55);

/// خلفية ترويسة الوحدة من لونها.
Color unitHeaderBg(Color color) => color.withAlpha(0x12);

/// رقم الوحدة بلونها: «1»، «2»...
class UnitNumber extends StatelessWidget {
  const UnitNumber({super.key, required this.n, required this.color});

  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// رقم الدرس داخل وحدته.
class ItemNumber extends StatelessWidget {
  const ItemNumber({super.key, required this.n, required this.color});

  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withAlpha(0x1F), shape: BoxShape.circle),
      child: Text('$n', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// عنوان الدرس بتنسيقه.
class ItemTitle extends StatelessWidget {
  const ItemTitle({super.key, required this.title, this.color = '', this.bold = false, this.fontSize = 13, this.maxLines = 1});

  ItemTitle.of(CourseItem item, {Key? key, double fontSize = 13, int maxLines = 1})
      : this(key: key, title: item.title, color: item.titleColor, bold: item.titleBold, fontSize: fontSize, maxLines: maxLines);

  final String title;
  final String color;
  final bool bold;
  final double fontSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppText.family,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
        color: hexColor(color) ?? AppColors.heading,
      ),
    );
  }
}

/// اختيار لون من اللوحة، وأوله «بلا لون» (تلقائي للوحدة، النص العادي للدرس).
class ColorSwatches extends StatelessWidget {
  const ColorSwatches({super.key, required this.value, required this.onChanged, required this.noneLabel});

  final String value;
  final ValueChanged<String> onChanged;
  final String noneLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GestureDetector(
          onTap: () => onChanged(''),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value.isEmpty ? AppColors.hover : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: value.isEmpty ? AppColors.heading : AppColors.line),
            ),
            child: Text(
              noneLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: value.isEmpty ? AppColors.heading : AppColors.muted),
            ),
          ),
        ),
        for (final c in unitColors)
          Tooltip(
            message: c.label,
            child: GestureDetector(
              onTap: () => onChanged(c.hex),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: hexColor(c.hex),
                  borderRadius: BorderRadius.circular(8),
                  border: value == c.hex ? Border.all(color: Colors.white, width: 2) : null,
                  boxShadow: value == c.hex ? [BoxShadow(color: hexColor(c.hex)!, spreadRadius: 2)] : null,
                ),
                child: value == c.hex ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// لون العنوان وعرضه: في نافذة الإضافة وفي نافذة التعديل.
class ItemTitleStyleFields extends StatelessWidget {
  const ItemTitleStyleFields({super.key, required this.color, required this.bold, required this.onColor, required this.onBold});

  final String color;
  final bool bold;
  final ValueChanged<String> onColor;
  final ValueChanged<bool> onBold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('تنسيق العنوان'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => onBold(!bold),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bold ? AppColors.heading : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: bold ? AppColors.heading : AppColors.line),
                ),
                child: Icon(Icons.format_bold_rounded, size: 18, color: bold ? Colors.white : AppColors.muted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: ColorSwatches(value: color, onChanged: onColor, noneLabel: 'عادي')),
          ],
        ),
      ],
    );
  }
}

// ── نوافذ التعديل ────────────────────────────────────────────────────────────

class _StyleSheet extends StatelessWidget {
  const _StyleSheet({
    required this.title,
    required this.children,
    required this.busy,
    required this.error,
    required this.accent,
    required this.onSave,
  });

  final String title;
  final List<Widget> children;
  final bool busy;
  final String error;
  final Color accent;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: AppText.title)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20, color: AppColors.muted)),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...children,
            if (error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            PrimaryButton(label: busy ? 'جارٍ الحفظ...' : 'حفظ', color: accent, onPressed: busy ? null : onSave),
          ],
        ),
      ),
    );
  }
}

String _errorText(Object e) => e is PortalException ? e.message : 'تعذّر الحفظ';

/// تعديل عنوان الوحدة ولونها — `SectionStyleModal`. يعيد الوحدة بعد حفظها.
Future<CourseSection?> showSectionStyleSheet(
  BuildContext context, {
  required CourseSection section,
  required int index,
  required Color accent,
  required Future<void> Function(String title, String color) save,
}) {
  return showModalBottomSheet<CourseSection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (_) => _SectionStyleBody(section: section, index: index, accent: accent, save: save),
  );
}

class _SectionStyleBody extends StatefulWidget {
  const _SectionStyleBody({required this.section, required this.index, required this.accent, required this.save});

  final CourseSection section;
  final int index;
  final Color accent;
  final Future<void> Function(String title, String color) save;

  @override
  State<_SectionStyleBody> createState() => _SectionStyleBodyState();
}

class _SectionStyleBodyState extends State<_SectionStyleBody> {
  late final title = TextEditingController(text: widget.section.title);
  late String color = widget.section.color;
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.save(title.text.trim(), color);
      if (mounted) Navigator.pop(context, widget.section.copyWith(title: title.text.trim(), color: color));
    } catch (e) {
      if (mounted) setState(() => error = _errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = unitColor(widget.section.copyWith(color: color), widget.index);
    return _StyleSheet(
      title: 'تنسيق الوحدة',
      busy: busy,
      error: error,
      accent: widget.accent,
      onSave: title.text.trim().isEmpty ? null : _save,
      children: [
        const FieldLabel('العنوان'),
        TextField(controller: title, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        const FieldLabel('لون الوحدة'),
        ColorSwatches(value: color, onChanged: (v) => setState(() => color = v), noneLabel: 'تلقائي'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: unitHeaderBg(preview),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: unitBorder(preview)),
          ),
          child: Row(
            children: [
              UnitNumber(n: widget.index + 1, color: preview),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.text.trim().isEmpty ? 'عنوان الوحدة' : title.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: preview, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// تعديل الدرس: عنوانه ورابطه وموعده ووصفه وتنسيق عنوانه — `ItemStyleModal`.
///
/// [save] يستلم الحقول المتغيرة بأسماء السحابة، والفارغ فيها `null` ليُمسح في القاعدة.
Future<CourseItem?> showItemStyleSheet(
  BuildContext context, {
  required CourseItem item,
  required Color accent,
  required Future<void> Function(Map<String, dynamic> patch) save,
}) {
  return showModalBottomSheet<CourseItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (_) => _ItemStyleBody(item: item, accent: accent, save: save),
  );
}

class _ItemStyleBody extends StatefulWidget {
  const _ItemStyleBody({required this.item, required this.accent, required this.save});

  final CourseItem item;
  final Color accent;
  final Future<void> Function(Map<String, dynamic> patch) save;

  @override
  State<_ItemStyleBody> createState() => _ItemStyleBodyState();
}

class _ItemStyleBodyState extends State<_ItemStyleBody> {
  late final title = TextEditingController(text: widget.item.title);
  late final description = TextEditingController(text: widget.item.description);
  late final url = TextEditingController(text: widget.item.contentUrl);
  late String dueDate = widget.item.dueDate;
  late String color = widget.item.titleColor;
  late bool bold = widget.item.titleBold;
  bool busy = false;
  String error = '';

  bool get _isLink => widget.item.type == 'link';
  bool get _isAssignment => widget.item.type == 'assignment';

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    url.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(dueDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => dueDate = picked.toIso8601String().split('T').first);
  }

  Future<void> _save() async {
    if (_isLink && !RegExp(r'^https?://', caseSensitive: false).hasMatch(url.text.trim())) {
      setState(() => error = 'الرابط يبدأ بـ http:// أو https://');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    final desc = description.text.trim();
    final patch = <String, dynamic>{
      'title': title.text.trim(),
      'description': desc.isEmpty ? null : desc,
      'title_color': color.isEmpty ? null : color,
      'title_bold': bold,
      if (_isLink) 'content_url': url.text.trim(),
      if (_isAssignment) 'due_date': dueDate.isEmpty ? null : dueDate,
    };
    try {
      await widget.save(patch);
      if (!mounted) return;
      Navigator.pop(
        context,
        widget.item.copyWith(
          title: title.text.trim(),
          description: desc,
          titleColor: color,
          titleBold: bold,
          contentUrl: _isLink ? url.text.trim() : null,
          dueDate: _isAssignment ? dueDate : null,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = _errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StyleSheet(
      title: 'تعديل الدرس',
      busy: busy,
      error: error,
      accent: widget.accent,
      onSave: title.text.trim().isEmpty ? null : _save,
      children: [
        const FieldLabel('العنوان'),
        TextField(controller: title, onChanged: (_) => setState(() {})),
        if (_isLink) ...[
          const SizedBox(height: 12),
          const FieldLabel('الرابط'),
          TextField(controller: url, textDirection: TextDirection.ltr, keyboardType: TextInputType.url),
        ],
        if (_isAssignment) ...[
          const SizedBox(height: 12),
          const FieldLabel('تاريخ التسليم'),
          OutlinedButton.icon(
            onPressed: _pickDue,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(dueDate.isEmpty ? 'اختر' : dueDate),
          ),
        ],
        const SizedBox(height: 12),
        const FieldLabel('الوصف'),
        TextField(controller: description, minLines: 1, maxLines: 3),
        const SizedBox(height: 12),
        ItemTitleStyleFields(
          color: color,
          bold: bold,
          onColor: (v) => setState(() => color = v),
          onBold: (v) => setState(() => bold = v),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.sunken,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: ItemTitle(title: title.text.trim().isEmpty ? 'عنوان الدرس' : title.text.trim(), color: color, bold: bold),
        ),
      ],
    );
  }
}
