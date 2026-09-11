import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'widgets.dart';

// تخطيط النماذج الموحّد — نموذج الطالب ونموذج الدفعة: الحقول على الصفحة مباشرة لا
// داخل بطاقات، والأقسام يفصلها عنوان وخط، والحقول القصيرة متجاورة، والحفظ ثابت
// أسفل الشاشة فلا حاجة للنزول إلى آخر النموذج.

/// عنوان قسم: أيقونة واسم وخط رفيع — بديل البطاقة التي كانت تحبس الحقول.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.icon, required this.title, this.note});

  final IconData icon;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.heading)),
              ),
              if (note != null) Text(note!, style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.line),
        ],
      ),
    );
  }
}

/// حقلان متجاوران بعنوانيهما — للحقول القصيرة التي تهدر سطراً كاملاً وحدها.
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.start, required this.end, this.startFlex = 1, this.endFlex = 1});

  final List<Widget> start;
  final List<Widget> end;
  final int startFlex;
  final int endFlex;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: startFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: start)),
        const SizedBox(width: 10),
        Expanded(flex: endFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: end)),
      ],
    );
  }
}

/// حقل اختيار يُفتح بلمسة (تاريخ، حي) بشكل الحقول النصية نفسه.
class SelectField extends StatelessWidget {
  const SelectField({super.key, required this.text, required this.icon, required this.onTap, this.placeholder = false});

  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 20),
          suffixIcon: Icon(icon, size: 16, color: AppColors.faint),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: placeholder ? AppColors.faint : AppColors.text),
        ),
      ),
    );
  }
}

/// شريط الحفظ الثابت أسفل النموذج: إلغاء، ثم زر الحفظ أعرض منه.
class FormActionBar extends StatelessWidget {
  const FormActionBar({super.key, required this.label, required this.onSave, this.icon = Icons.check, this.busy = false});

  final String label;
  final VoidCallback? onSave;
  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PrimaryButton(label: label, icon: icon, height: 44, busy: busy, onPressed: onSave),
            ),
          ],
        ),
      ),
    );
  }
}
