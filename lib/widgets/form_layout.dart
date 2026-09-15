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
  const SelectField({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    this.placeholder = false,
    this.errorText,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool placeholder;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 20),
          suffixIcon: Icon(icon, size: 16, color: AppColors.faint),
          errorText: errorText,
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
  const FormActionBar({
    super.key,
    required this.label,
    required this.onSave,
    this.icon = Icons.check,
    this.busy = false,
    this.onCancel,
  });

  final String label;
  final VoidCallback? onSave;
  final IconData icon;
  final bool busy;

  /// ما يجري عند «إلغاء» — لنموذج يسأل قبل أن يُهمل ما كُتب فيه.
  final VoidCallback? onCancel;

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
            Expanded(child: GhostButton(label: 'إلغاء', onPressed: onCancel ?? () => Navigator.pop(context))),
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

/// أخطاء الحقول في نموذج واحد: رسالة تحت كل حقل مطلوب تُرك فارغاً، وتمرير إلى أولها.
///
/// تنبيه منفصل عن الحقل لا يكفي: قد يختفي خلف الورقة السفلية أو لوحة المفاتيح، ولا
/// يقول أين المشكلة. هنا يُلوَّن الحقل نفسه وتظهر رسالته تحته.
class FieldErrors {
  final _messages = <String, String>{};
  final _keys = <String, GlobalKey>{};

  /// مفتاح يوضع على عنوان الحقل كي يُمرَّر إليه.
  GlobalKey key(String field) => _keys.putIfAbsent(field, () => GlobalKey());

  String? operator [](String field) => _messages[field];

  bool get isEmpty => _messages.isEmpty;

  /// يبدأ فحصاً جديداً ويُسقط أخطاء الفحص السابق.
  void reset() => _messages.clear();

  /// يسجّل [message] للحقل إن كان [invalid]. ترتيب الاستدعاء = ترتيب الحقول على الشاشة.
  void check(String field, bool invalid, String message) {
    if (invalid) _messages.putIfAbsent(field, () => message);
  }

  /// يُسقط خطأ الحقل حين يبدأ المستخدم تصحيحه. يعيد `true` إن كان فيه خطأ.
  bool clear(String field) => _messages.remove(field) != null;

  /// اسم أول حقل ناقص — ترتيب `check` هو ترتيب الحقول على الشاشة.
  String? get firstField => _messages.keys.firstOrNull;

  /// إن وُجدت أخطاء: يمرّر إلى أول حقل ناقص وينبّه باسمه، ويعيد `true`.
  ///
  /// [reveal] لنموذج يطوي بعض حقوله: يُفتح قسم الحقل قبل التمرير إليه، وإلا
  /// بقيت الرسالة تشير إلى حقل لا يراه المستخدم.
  bool report(BuildContext context, {void Function(String field)? reveal}) {
    final field = firstField;
    if (field == null) return false;
    reveal?.call(field);

    void scrollToFirst() {
      for (final f in _messages.keys) {
        final target = _keys[f]?.currentContext;
        if (target == null) continue;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
        return;
      }
    }

    // الحقل المطويّ لا يوجد في الشجرة قبل أن يُبنى قسمه
    if (reveal == null) {
      scrollToFirst();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToFirst());
    }

    // الرسالة تسمّي الحقل: «يرجى استكمال الحقول» كانت تترك المستخدم يبحث عنه
    showAppSnack(context, _messages[field]!, error: true);
    return true;
  }
}

/// رسالة خطأ تحت عنصر ليس حقلاً نصياً (أيام، اختيار طالب) بشكل رسالة الحقل نفسها.
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6, start: 2),
      child: Text(
        message!,
        style: const TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
      ),
    );
  }
}
