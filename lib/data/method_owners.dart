/// تجميع الحسابات بصاحبها — المقابل لـ `methodOwners.ts`: منطق صرف يُستعمل في مربعات المالية
/// وقوائم اختيار الحساب وسجل الوسائل في الإعدادات.
library;

import 'arabic_search.dart';

const noOwner = 'بدون صاحب';

class OwnerGrouping<T> {
  const OwnerGrouping({required this.groups, required this.ungrouped});

  /// أصحاب الحسابات بترتيب الأبجدية، لكل صاحب حساباته بترتيبها الأصلي.
  final List<({String owner, List<T> items})> groups;

  /// من بلا صاحب بترتيبها الأصلي.
  final List<T> ungrouped;
}

/// يقسم القائمة إلى مجموعات بحسب الصاحب (المقارنة بعد قصّ المسافات) — `groupMethodsByOwner`.
OwnerGrouping<T> groupMethodsByOwner<T>(Iterable<T> items, String? Function(T item) ownerOf) {
  final map = <String, List<T>>{};
  final ungrouped = <T>[];
  for (final item in items) {
    final owner = (ownerOf(item) ?? '').trim();
    if (owner.isEmpty) {
      ungrouped.add(item);
    } else {
      map.putIfAbsent(owner, () => []).add(item);
    }
  }
  final owners = map.keys.toList()..sort(compareArabicNames);
  return OwnerGrouping(
    groups: [for (final o in owners) (owner: o, items: map[o]!)],
    ungrouped: ungrouped,
  );
}
