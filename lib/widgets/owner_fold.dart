import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/method_owners.dart';
import '../data/payment_methods.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import 'widgets.dart';

const _collapsedKey = 'finance_collapsed_owners';

/// خيارات حسابات في قائمة منسدلة: لكل صاحب عنوان باسمه، ومن بلا صاحب بعدها — `MethodOptions`.
List<DropdownMenuItem<String>> methodDropdownItems(Iterable<PaymentMethodItem> methods) {
  final grouping = groupMethodsByOwner<PaymentMethodItem>(methods, (m) => m.owner);
  DropdownMenuItem<String> option(PaymentMethodItem m) => DropdownMenuItem(value: m.id, child: Text(m.name));
  return [
    for (final g in grouping.groups) ...[
      DropdownMenuItem<String>(
        value: '__owner_${g.owner}',
        enabled: false,
        child: Text(g.owner, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ),
      for (final m in g.items) option(m),
    ],
    for (final m in grouping.ungrouped) option(m),
  ];
}

/// مربعات الحسابات مجمّعة بصاحبها — `OwnerTiles`: بطاقة لكل صاحب باسمه ومجموعه وسهم طيّ يُحفظ
/// على الجهاز، ومن بلا صاحب بعدها كما هي.
class OwnerTiles<T> extends StatefulWidget {
  const OwnerTiles({
    super.key,
    required this.items,
    required this.ownerOf,
    required this.amountOf,
    required this.tile,
    this.spacing = 6,
  });

  final List<T> items;
  final String? Function(T) ownerOf;
  final double Function(T) amountOf;
  final Widget Function(T) tile;
  final double spacing;

  @override
  State<OwnerTiles<T>> createState() => _OwnerTilesState<T>();
}

class _OwnerTilesState<T> extends State<OwnerTiles<T>> {
  Set<String> collapsed = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => collapsed = (p.getStringList(_collapsedKey) ?? const <String>[]).toSet());
    });
  }

  void _toggle(String owner) {
    setState(() => collapsed.contains(owner) ? collapsed.remove(owner) : collapsed.add(owner));
    SharedPreferences.getInstance().then((p) => p.setStringList(_collapsedKey, collapsed.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final grouping = groupMethodsByOwner<T>(widget.items, widget.ownerOf);
    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.spacing,
      children: [
        for (final g in grouping.groups)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _toggle(g.owner),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        collapsed.contains(g.owner) ? Icons.chevron_right : Icons.expand_more,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      Text(g.owner, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.heading)),
                      const SizedBox(width: 10),
                      Text(
                        money(g.items.fold<double>(0, (a, i) => a + widget.amountOf(i))),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (!collapsed.contains(g.owner)) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: widget.spacing,
                    runSpacing: widget.spacing,
                    children: [for (final i in g.items) widget.tile(i)],
                  ),
                ],
              ],
            ),
          ),
        for (final i in grouping.ungrouped) widget.tile(i),
      ],
    );
  }
}
