import 'package:flutter/material.dart';

import '../data/discount_policy.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// خصم الإخوة والتفوق والفئات — `DiscountSettings`: يقترحه نموذج التسجيل للطالب الجديد،
/// ولا يُطبَّق على من سُجّل من قبل.
class DiscountSettingsTab extends StatefulWidget {
  const DiscountSettingsTab({super.key});

  @override
  State<DiscountSettingsTab> createState() => _DiscountSettingsTabState();
}

class _Draft {
  _Draft(DiscountPolicy p)
      : siblingOn = p.sibling.enabled,
        meritOn = p.merit.enabled,
        sibling = [for (final t in p.sibling.tiers) _TierCtl(t)],
        merit = [for (final t in p.merit.tiers) _TierCtl(t)],
        categories = [for (final c in p.categories) _CategoryCtl(c)];

  bool siblingOn;
  bool meritOn;
  final List<_TierCtl> sibling;
  final List<_TierCtl> merit;
  final List<_CategoryCtl> categories;
}

class _TierCtl {
  _TierCtl(DiscountTier t)
      : min = TextEditingController(text: trimNum(t.min)),
        percent = TextEditingController(text: trimNum(t.percent));

  final TextEditingController min;
  final TextEditingController percent;
}

class _CategoryCtl {
  _CategoryCtl(DiscountCategory c)
      : id = c.id,
        when = c.when,
        name = TextEditingController(text: c.name),
        percent = TextEditingController(text: trimNum(c.percent));

  final String id;
  String when;
  final TextEditingController name;
  final TextEditingController percent;
}

class _DiscountSettingsTabState extends State<DiscountSettingsTab> {
  _Draft? draft;
  bool dirty = false;

  void _touch() => setState(() => dirty = true);

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save(AppStore store) async {
    final d = draft!;
    DiscountRule clean(bool on, List<_TierCtl> tiers) => DiscountRule(
          enabled: on,
          tiers: ([
            for (final t in tiers)
              if (_num(t.percent) > 0) DiscountTier(min: _num(t.min), percent: _num(t.percent)),
          ])
            ..sort((a, b) => a.min.compareTo(b.min)),
        );
    final policy = DiscountPolicy(
      sibling: clean(d.siblingOn, d.sibling),
      merit: clean(d.meritOn, d.merit),
      categories: [
        for (final c in d.categories)
          if (c.name.text.trim().isNotEmpty && _num(c.percent) > 0 && _num(c.percent) <= 100)
            DiscountCategory(id: c.id, name: c.name.text.trim(), when: c.when, percent: _num(c.percent)),
      ],
    );
    await store.writeSchoolOption({'discounts': policy.toMap()});
    if (!mounted) return;
    setState(() {
      draft = null;
      dirty = false;
    });
    showAppSnack(context, 'تم الحفظ');
  }

  Widget _numField(TextEditingController c, String hint, {double width = 74}) => SizedBox(
        width: width,
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _touch(),
          decoration: InputDecoration(isDense: true, hintText: hint),
        ),
      );

  Widget _rule({
    required String label,
    required bool on,
    required ValueChanged<bool> onToggle,
    required List<_TierCtl> tiers,
    required String minHint,
    required DiscountTier newTier,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                value: on,
                onChanged: onToggle,
              ),
            ),
            if (on)
              IconButton(
                tooltip: 'شريحة',
                icon: const Icon(Icons.add, size: 18),
                onPressed: () {
                  tiers.add(_TierCtl(newTier));
                  _touch();
                },
              ),
          ],
        ),
        if (on)
          for (final t in tiers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _numField(t.min, minHint),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('←')),
                  _numField(t.percent, '%', width: 60),
                  const SizedBox(width: 4),
                  const Text('%'),
                  if (tiers.length > 1)
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                      onPressed: () {
                        tiers.remove(t);
                        _touch();
                      },
                    ),
                ],
              ),
            ),
        const Divider(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final d = draft ??= _Draft(store.settings.discounts);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _rule(
          label: 'خصم الإخوة',
          on: d.siblingOn,
          onToggle: (v) {
            d.siblingOn = v;
            _touch();
          },
          tiers: d.sibling,
          minHint: 'الترتيب',
          newTier: DiscountTier(
            min: (d.sibling.isEmpty ? 1 : (double.tryParse(d.sibling.last.min.text) ?? 1)) + 1,
            percent: 10,
          ),
        ),
        _rule(
          label: 'خصم التفوق (معدل السنة الماضية)',
          on: d.meritOn,
          onToggle: (v) {
            d.meritOn = v;
            _touch();
          },
          tiers: d.merit,
          minHint: 'المعدل',
          newTier: const DiscountTier(min: 95, percent: 15),
        ),
        Row(
          children: [
            const Expanded(child: Text('خصم الفئات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            IconButton(
              tooltip: 'فئة',
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                d.categories.add(_CategoryCtl(DiscountCategory(
                  id: 'dc_${DateTime.now().millisecondsSinceEpoch}',
                  name: '',
                  when: 'orphan_father',
                  percent: 25,
                )));
                _touch();
              },
            ),
          ],
        ),
        for (final c in d.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: c.name,
                  maxLength: 40,
                  onChanged: (_) => _touch(),
                  decoration: const InputDecoration(isDense: true, hintText: 'اسم الفئة', counterText: ''),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: c.when,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in discountCriterionLabels.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12.5))),
                        ],
                        onChanged: (v) {
                          c.when = v ?? c.when;
                          _touch();
                        },
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('←')),
                    _numField(c.percent, '%', width: 60),
                    const SizedBox(width: 4),
                    const Text('%'),
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                      onPressed: () {
                        d.categories.remove(c);
                        _touch();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (dirty) ...[
          const SizedBox(height: 8),
          PrimaryButton(label: 'حفظ', expand: true, onPressed: () => _save(store)),
        ],
      ],
    );
  }
}
