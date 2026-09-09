import 'package:flutter/material.dart';

import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'attendance_screen.dart';
import 'classes_screen.dart';
import 'finance_screen.dart';
import 'settings_screen.dart';
import 'students_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  static const titles = [
    'الطلاب والتسجيل',
    'الحضور والغياب',
    'المالية والصندوق',
    'الصفوف والشعب',
    'الإعدادات العامة',
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _Header(title: titles[index]),
          Expanded(
            child: IndexedStack(
              index: index,
              children: const [
                StudentsScreen(),
                AttendanceScreen(),
                FinanceScreen(),
                ClassesScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        index: index,
        onSelect: (i) => setState(() => index = i),
        dueCount: store.dueItems().length,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(14, top + 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        border: Border(bottom: BorderSide(color: AppColors.navyMid)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.amberSoft,
              border: Border.all(color: AppColors.amber),
            ),
            child: const Icon(Icons.school, color: AppColors.amber, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const Text('إدارة المدارس', style: TextStyle(color: AppColors.amber, fontSize: 10)),
              ],
            ),
          ),
          _SyncPair(
            push: store.pendingPush,
            pull: store.pendingPull,
            onPush: () => _syncSheet(context, push: true),
            onPull: () => _syncSheet(context, push: false),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () async {
              final ok = await confirmSheet(
                context,
                title: 'تسجيل الخروج',
                message: 'هل ترغب في تسجيل الخروج والعودة لبوابة الدخول؟',
                confirmLabel: 'خروج',
              );
              if (ok && context.mounted) store.logout();
            },
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4C0519).withValues(alpha: 0.6),
                border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout, size: 14, color: Color(0xFFFB7185)),
                  SizedBox(width: 4),
                  Text('خروج', style: TextStyle(color: Color(0xFFFECDD3), fontSize: 10, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncSheet(BuildContext context, {required bool push}) async {
    final store = StoreScope.of(context);
    if (!push) {
      await store.sync.checkRemoteChanges();
      if (context.mounted) store.notifySync();
    }
    if (!context.mounted) return;
    final summary = push ? store.sync.getPendingSummary() : null;
    final remote = push ? null : await store.sync.checkRemoteChanges();
    if (!context.mounted) return;
    final total = push ? summary!.total : (remote?.total ?? store.pendingPull);
    final rows = push ? summary!.rows : (remote?.rows ?? const <SyncRow>[]);
    final items = push ? summary!.items : (remote?.items ?? const <PendingSummaryItem>[]);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(ctx).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    push ? 'رفع التعديلات المحلية' : 'سحب التعديلات من السحابة',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total == 0
                        ? (push ? 'لا توجد تعديلات محلية معلقة للرفع' : 'لا توجد تعديلات جديدة في السحابة')
                        : (push ? 'سيتم رفع $total تعديلاً إلى السحابة.' : 'سيتم سحب $total تعديلاً وتحديث الشاشة.'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  if (rows.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${tableLabelsAr[r.table] ?? r.table}${r.action.isNotEmpty ? ' · ${r.action}' : ''}: ${r.count}',
                          style: const TextStyle(fontSize: 12, color: AppColors.heading),
                        ),
                      ),
                  ],
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final item in items.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text('• ${item.label}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: GhostButton(label: 'إغلاق', onPressed: () { if (!busy) Navigator.pop(ctx); })),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PrimaryButton(
                          label: push ? 'تأكيد الرفع' : 'تأكيد السحب',
                          color: push ? AppColors.amber : AppColors.info,
                          busy: busy,
                          onPressed: total == 0 || busy
                              ? null
                              : () async {
                                  setSt(() => busy = true);
                                  final result = push ? await store.sync.push() : await store.sync.pull();
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  if (context.mounted) showAppSnack(context, result.message, error: !result.success);
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SyncPair extends StatelessWidget {
  const _SyncPair({required this.push, required this.pull, required this.onPush, required this.onPull});
  final int push;
  final int pull;
  final VoidCallback onPush;
  final VoidCallback onPull;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.navyMid.withValues(alpha: 0.8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _chip('رفع', Icons.arrow_upward, push > 0, push, AppColors.amber, onPush),
          const SizedBox(width: 2),
          _chip('سحب', Icons.arrow_downward, pull > 0, pull, AppColors.info, onPull),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, bool on, int count, Color color, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: on ? color : Colors.white.withValues(alpha: 0.08),
        child: Row(
          children: [
            Icon(icon, size: 12, color: on ? Colors.white : color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(color: on ? Colors.white : Colors.white.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w800)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.white,
                child: Text('$count', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onSelect, required this.dueCount});
  final int index;
  final ValueChanged<int> onSelect;
  final int dueCount;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    const items = [
      (Icons.groups_outlined, Icons.groups, 'الطلاب'),
      (Icons.fact_check_outlined, Icons.fact_check, 'الحضور'),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'المالية'),
      (Icons.apartment_outlined, Icons.apartment, 'الصفوف'),
      (Icons.settings_outlined, Icons.settings, 'الإعدادات'),
    ];

    return Container(
      height: 56 + (bottom > 0 ? bottom : 6),
      padding: EdgeInsets.only(bottom: bottom > 0 ? bottom : 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.lineStrong)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 2,
                      width: index == i ? 28 : 0,
                      margin: const EdgeInsets.only(bottom: 4),
                      color: AppColors.amber,
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(index == i ? items[i].$2 : items[i].$1, size: 18, color: index == i ? AppColors.amber : AppColors.muted),
                        if (i == 2 && dueCount > 0)
                          Positioned(
                            left: -10,
                            top: -5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              color: AppColors.danger,
                              child: Text('$dueCount', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].$3,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: index == i ? FontWeight.w800 : FontWeight.w500,
                        color: index == i ? AppColors.amber : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
