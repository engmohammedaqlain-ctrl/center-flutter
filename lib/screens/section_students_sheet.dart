import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// إضافة طلاب إلى شعبة — المقابل لـ `AddSectionStudentsModal`.
///
/// الشعبة تبدأ فارغة ولا تبتلع طلاب مرحلتها: من يدخلها يُختار هنا صراحةً.
/// تُعيد عدد من أُضيف.
Future<int> showSectionStudentsSheet(BuildContext context, Classroom room) async {
  final added = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _SectionStudentsSheet(room: room),
  );
  return added ?? 0;
}

class _SectionStudentsSheet extends StatefulWidget {
  const _SectionStudentsSheet({required this.room});
  final Classroom room;

  @override
  State<_SectionStudentsSheet> createState() => _SectionStudentsSheetState();
}

class _SectionStudentsSheetState extends State<_SectionStudentsSheet> {
  final search = TextEditingController();
  final selected = <String>{};
  bool saving = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _save(AppStore store) async {
    if (selected.isEmpty) return;
    setState(() => saving = true);
    try {
      final moved = store.assignSection(selected, widget.room.name);
      if (mounted) Navigator.pop(context, moved);
    } on StoreException catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showAppSnack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final q = search.text.trim().toLowerCase();
    final candidates = store
        .sectionCandidates(widget.room)
        .where((s) => q.isEmpty || s.fullName.toLowerCase().contains(q) || s.nationalId.contains(q))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'إضافة طلاب إلى ${widget.room.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                        ),
                        Text(
                          widget.room.gradeLevel.trim().isEmpty ? 'كل المراحل' : widget.room.gradeLevel,
                          style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  SquareIconButton(icon: Icons.close, onTap: () => Navigator.pop(context, 0)),
                ],
              ),
              const SizedBox(height: 12),
              SearchField(
                controller: search,
                hint: 'ابحث بالاسم أو رقم الهوية...',
                onChanged: (_) => setState(() {}),
                trailing: Text(
                  '${candidates.length}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 10),

              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 26),
                  child: Text(
                    'لا طلاب في هذه المرحلة خارج الشعبة',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final s = candidates[i];
                      final on = selected.contains(s.id);
                      final current = s.section.trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => setState(() => on ? selected.remove(s.id) : selected.add(s.id)),
                          borderRadius: BorderRadius.circular(Corner.box),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: on ? AppColors.amberSoft : AppColors.bg,
                              borderRadius: BorderRadius.circular(Corner.box),
                              border: Border.all(color: on ? AppColors.amber : AppColors.line),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  on ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                                  size: 18,
                                  color: on ? AppColors.amberDark : AppColors.faint,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        s.fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                                      ),
                                      Text(
                                        // من في شعبة أخرى يُنقل منها، ومن بلا شعبة يُسند لأول مرة
                                        current.isEmpty ? 'بلا شعبة' : 'ينتقل من $current',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: current.isEmpty ? AppColors.muted : AppColors.amberDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!s.isActiveStudent) StudentStatusChip(status: s.status, compact: true),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context, 0))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: saving
                          ? 'جارِ الإضافة...'
                          : selected.isEmpty
                              ? 'اختر طلاباً'
                              : 'إضافة ${selected.length}',
                      color: AppColors.navy,
                      busy: saving,
                      onPressed: selected.isEmpty || saving ? null : () => _save(store),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
