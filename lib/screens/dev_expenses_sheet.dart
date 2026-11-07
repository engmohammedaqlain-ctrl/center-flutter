import 'package:flutter/material.dart';

import '../data/supabase.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

/// مصاريف المطور بجانب الإيراد — `DevExpenses`: الإيراد والمصاريف والصافي منذ البداية،
/// وتسجيل مصروف وحذفه (`dev_expenses_list`).
Future<void> showDevExpensesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => const _DevExpensesSheet(),
  );
}

class _DevExpensesSheet extends StatefulWidget {
  const _DevExpensesSheet();

  @override
  State<_DevExpensesSheet> createState() => _DevExpensesSheetState();
}

class _DevExpensesSheetState extends State<_DevExpensesSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String date = isoDate(DateTime.now());
  bool busy = false;
  bool failed = false;
  double income = 0;
  double spent = 0;
  List<Map<String, dynamic>>? rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await supabaseRpcOrThrow('dev_expenses_list', const {});
      if (!mounted) return;
      final map = data is Map ? data : const {};
      setState(() {
        failed = false;
        income = (map['income'] as num?)?.toDouble() ?? 0;
        spent = (map['spent'] as num?)?.toDouble() ?? 0;
        rows = [
          if (map['items'] is List)
            for (final r in map['items'] as List)
              if (r is Map) Map<String, dynamic>.from(r),
        ];
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _add() async {
    final n = double.tryParse(_amount.text.trim()) ?? 0;
    if (n <= 0 || busy) return;
    await _run(() async {
      await supabaseRpcOrThrow('dev_expense_add', {
        'p_amount': n,
        'p_spent_on': date,
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      _amount.clear();
      _note.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    return NoonSheetFrame(
      title: 'الإيراد والمصاريف',
      footer: [
        NoonButton(label: 'إضافة', icon: Icons.add, tone: NoonTone.sun, busy: busy, onPressed: busy ? null : _add),
      ],
      children: [
        Text(
          'الإيراد ${trimNum(income)} · مصاريف ${trimNum(spent)} · صافي ${trimNum(income - spent)}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, labelText: 'المبلغ ₪'),
              ),
            ),
            const SizedBox(width: 8),
            GhostButton(
              label: date,
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: parseIsoDate(date) ?? DateTime.now(),
                  firstDate: DateTime(2024),
                  lastDate: DateTime(DateTime.now().year + 1),
                );
                if (picked != null) setState(() => date = isoDate(picked));
              },
            ),
          ],
        ),
        TextField(
          controller: _note,
          maxLength: 200,
          decoration: const InputDecoration(isDense: true, labelText: 'ملاحظة', counterText: ''),
        ),
        if (failed)
          const Text('تعذّر جلب المصاريف', style: TextStyle(color: AppColors.danger, fontSize: 12))
        else if (list == null)
          const Center(child: AppLoader(compact: true, size: 22))
        else if (list.isEmpty)
          const Text('لا مصاريف', style: TextStyle(color: AppColors.muted, fontSize: 12))
        else
          Column(
            children: [
              for (final r in list)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${trimNum((r['amount'] as num?) ?? 0)} ₪ · ${'${r['spent_on'] ?? ''}'.split('T').first}'),
                  subtitle: '${r['note'] ?? ''}'.isEmpty ? null : Text('${r['note']}'),
                  trailing: IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await confirmSheet(
                              context,
                              title: 'حذف المصروف',
                              message: 'حذف المصروف؟',
                              confirmLabel: 'حذف',
                            );
                            if (ok) await _run(() => supabaseRpcOrThrow('dev_expense_delete', {'p_id': r['id']}));
                          },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
