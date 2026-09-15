import 'package:flutter/material.dart';

import '../data/grading.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// مخطط علامات المدرسة — المقابل لـ `GradingSchemeSettings.tsx`.
///
/// لكل فصل مكوّناته وأوزانها، والاسم والوزن حرّان: لا نسبة «رسمية» واحدة تصلح
/// لكل مدرسة ومنهاج. ما دام الفصل بلا مكوّنات يبقى الرصد على حاله: تقييمٌ حرّ
/// بلا وزن ومتوسطٌ بسيط.
class GradingSchemeTab extends StatefulWidget {
  const GradingSchemeTab({super.key});

  @override
  State<GradingSchemeTab> createState() => _GradingSchemeTabState();
}

class _GradingSchemeTabState extends State<GradingSchemeTab> {
  String term = 'term_1';
  late GradingScheme scheme;
  bool loaded = false;
  bool dirty = false;

  /// المستخدم غيّر شيئاً بيده: عندها وحدها يتوقف التبويب عن متابعة ما يصل.
  bool userEdited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // تُستدعى مع كل إخطار من المخزن: مخططٌ ضُبط على جهاز آخر يصل بالسحب، وكان
    // لا يظهر حتى يُعاد فتح التبويب. وتعديلٌ لم يُحفظ بعد لا يُدهس.
    if (loaded && userEdited) return;
    final store = StoreScope.of(context);
    final stored = store.gradingScheme;
    if (stored.isEmpty) {
      // مدرسة لم تعرّف نظامها بعد تبدأ بالنموذج الافتراضي جاهزاً للتعديل —
      // كما في GradingSchemeSettings. ولا يصير نظامها حتى تحفظه.
      scheme = defaultGradingScheme(store.newId);
      dirty = true;
    } else {
      scheme = stored;
      dirty = false;
    }
    loaded = true;
  }

  List<GradingComponent> get components => scheme.of(term);

  double get total => components.fold<double>(0, (a, c) => a + c.weight);

  void _update(List<GradingComponent> next) {
    setState(() {
      scheme = term == 'term_2' ? scheme.copyWith(term2: next) : scheme.copyWith(term1: next);
      dirty = true;
      userEdited = true;
    });
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    try {
      await store.saveGradingScheme(scheme);
      if (!mounted) return;
      setState(() {
        dirty = false;
        userEdited = false;
      });
      showAppSnack(context, 'تم حفظ نظام العلامات');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final complete = (total - 100).abs() < 0.01;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        // الفصل المعروض
        Row(
          children: [
            for (final entry in gradingTermLabels.entries) ...[
              Expanded(
                child: _TermButton(
                  label: entry.value,
                  on: term == entry.key,
                  onTap: () => setState(() => term = entry.key),
                ),
              ),
              if (entry.key != gradingTermLabels.keys.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 12),

        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'مجموع الأوزان',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                    ),
                  ),
                  Text(
                    '${trimNum(total)}%',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: complete ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                complete
                    ? 'معدل الفصل يُحسب بهذه الأوزان'
                    : 'المجموع يجب أن يكون 100%',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: complete ? AppColors.muted : AppColors.danger,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (components.isEmpty)
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'لا مكوّنات — الرصد تقييم حرّ بمتوسط بسيط.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < components.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ComponentCard(
                component: components[i],
                onChanged: (next) {
                  final list = [...components];
                  list[i] = next;
                  _update(list);
                },
                onDelete: () => _update([...components]..removeAt(i)),
              ),
            ),

        const SizedBox(height: 6),
        GhostButton(
          label: 'إضافة مكوّن',
          icon: Icons.add,
          onPressed: () => _update([
            ...components,
            GradingComponent(id: store.newId(), name: '', weight: 0),
          ]),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: 'الافتراضي',
                icon: Icons.refresh,
                onPressed: () => _update(defaultTermComponents(store.newId)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: PrimaryButton(
                label: dirty ? 'حفظ' : 'محفوظ',
                icon: Icons.save_outlined,
                color: AppColors.navy,
                onPressed: dirty ? _save : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TermButton extends StatelessWidget {
  const _TermButton({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.heading : Colors.white,
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: on ? AppColors.heading : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: on ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// مكوّن واحد: اسمه ووزنه وزر حذفه.
class _ComponentCard extends StatefulWidget {
  const _ComponentCard({required this.component, required this.onChanged, required this.onDelete});

  final GradingComponent component;
  final ValueChanged<GradingComponent> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ComponentCard> createState() => _ComponentCardState();
}

class _ComponentCardState extends State<_ComponentCard> {
  late final name = TextEditingController(text: widget.component.name);
  late final weight = TextEditingController(
    text: widget.component.weight == 0 ? '' : trimNum(widget.component.weight),
  );

  @override
  void didUpdateWidget(covariant _ComponentCard old) {
    super.didUpdateWidget(old);
    // مكوّن تغيّر على جهاز آخر: لا يُكتب فوق ما يكتبه المستخدم الآن
    if (old.component.name != widget.component.name && !name.value.composing.isValid) {
      name.text = widget.component.name;
    }
    final shown = widget.component.weight == 0 ? '' : trimNum(widget.component.weight);
    if (old.component.weight != widget.component.weight && !weight.value.composing.isValid) {
      weight.text = shown;
    }
  }

  @override
  void dispose() {
    name.dispose();
    weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: name,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'اسم المكوّن (شهري، نصفي…)'),
              onChanged: (v) => widget.onChanged(widget.component.copyWith(name: v.trim())),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(hintText: '%', suffixText: '%'),
              onChanged: (v) => widget.onChanged(
                widget.component.copyWith(weight: double.tryParse(v.trim()) ?? 0),
              ),
            ),
          ),
          SquareIconButton(icon: Icons.delete_outline, color: AppColors.danger, onTap: widget.onDelete),
        ],
      ),
    );
  }
}
