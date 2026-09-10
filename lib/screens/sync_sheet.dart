import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/permissions.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';

Color get _sheetBg => AppColors.navy;
Color get _sheetPanel => AppColors.navyMid.withValues(alpha: 0.8);

/// غلاف موحّد للأوراق السفلية الداكنة — مقبض سحب وحواف علوية دائرية.
Future<T?> _darkSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: _sheetBg,
        border: Border(top: BorderSide(color: AppColors.navyMid)),
        borderRadius: BorderRadius.zero,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// القائمة السريعة — مطابقة لـ Action Bottom Sheet في `MobileHeader`:
/// هوية الجهاز، ثم المزامنة السحابية، ثم تسجيل الخروج.
Future<void> showActionSheet(BuildContext context, AppStore store) {
  return _darkSheet(context, (ctx) {
    return ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final me = store.deviceUser;
        final isAdmin = normalizeRole(me?.role) == 'admin';
        final name = me?.name ?? (isAdmin ? 'جهاز الإدارة' : 'جهاز السكرتير');

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // هوية المنشأة والجهاز
              Row(
                children: [
                  InstitutionBadge(logo: store.institutionLogo, size: 42, radius: 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          store.institutionName.isEmpty ? appName : store.institutionName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
                        ),
                        const SizedBox(height: 5),
                        _identityChip(isAdmin: isAdmin, name: name),
                      ],
                    ),
                  ),
                  PressableScale(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Icon(Icons.close, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
              const SizedBox(height: 14),

              _syncPanel(ctx, store),
              const SizedBox(height: 12),

              _menuTile(
                icon: Icons.badge_outlined,
                iconColor: AppColors.amber,
                label: 'تغيير المستخدم على هذا الجهاز',
                trailing: 'تبديل',
                onTap: () async {
                  Navigator.pop(ctx);
                  await store.resetInitialSetup();
                },
              ),
              const SizedBox(height: 8),
              _menuTile(
                icon: Icons.logout,
                iconColor: const Color(0xFFFB7185),
                label: 'تسجيل الخروج من النظام',
                danger: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await confirmSheet(
                    context,
                    title: 'تسجيل الخروج',
                    message: 'هل أنت متأكد من رغبتك في تسجيل الخروج من النظام؟',
                    confirmLabel: 'خروج',
                  );
                  if (ok) await store.logout();
                },
              ),
            ],
          ),
        );
      },
    );
  });
}

Widget _identityChip({required bool isAdmin, required String name}) {
  final fg = isAdmin ? const Color(0xFFD8B4FE) : const Color(0xFF6EE7B7);
  final bg = isAdmin ? const Color(0x992E1065) : const Color(0x99064E3B);
  final border = isAdmin ? const Color(0x996B21A8) : const Color(0x99065F46);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isAdmin ? Icons.verified_user : Icons.check_circle, size: 11, color: fg),
        const SizedBox(width: 4),
        Text(name, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

Widget _syncPanel(BuildContext ctx, AppStore store) {
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: _sheetPanel,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_outlined, size: 15, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              'المزامنة السحابية المباشرة',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            if (store.realtimeConnected)
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle),
              ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: _syncButton(
                ctx,
                store,
                push: true,
                count: store.pendingPush,
                color: AppColors.amber,
                icon: Icons.arrow_upward,
                label: 'رفع',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _syncButton(
                ctx,
                store,
                push: false,
                count: store.pendingPull,
                color: AppColors.accent,
                icon: Icons.arrow_downward,
                label: 'سحب',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _syncButton(
  BuildContext ctx,
  AppStore store, {
  required bool push,
  required int count,
  required Color color,
  required IconData icon,
  required String label,
}) {
  final on = count > 0;
  return PressableScale(
    onTap: store.sync.isSyncing
        ? null
        : () {
            Navigator.pop(ctx);
            openSyncSheet(ctx, store, push: push);
          },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? color : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: on ? color : Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: on ? Colors.white : Colors.white.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: on ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          AnimatedCount(
            count,
            style: TextStyle(
              color: on ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _menuTile({
  required IconData icon,
  required Color iconColor,
  required String label,
  String? trailing,
  bool danger = false,
  VoidCallback? onTap,
}) {
  return PressableScale(
    scale: 0.98,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: danger ? const Color(0x1AF43F5E) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: danger ? const Color(0x4DF43F5E) : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: danger ? const Color(0xFFFDA4AF) : Colors.white,
                fontSize: 12,
                fontWeight: danger ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
            ),
        ],
      ),
    ),
  );
}

/// ورقة تأكيد الرفع أو السحب — مطابقة لـ `SyncConfirmModal` في Center.
///
/// تُفتح فوراً وتفحص بداخلها. كان الفحص يسبق الفتح — وهو جولة كاملة على كل
/// الجداول — فتبقى الشاشة بلا استجابة حتى ينتهي، ويبدو الزر معطّلاً.
Future<void> openSyncSheet(BuildContext context, AppStore store, {required bool push}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    isScrollControlled: true,
    builder: (ctx) => _SyncConfirm(store: store, push: push),
  );
}

class _SyncConfirm extends StatefulWidget {
  const _SyncConfirm({required this.store, required this.push});

  final AppStore store;
  final bool push;

  @override
  State<_SyncConfirm> createState() => _SyncConfirmState();
}

class _SyncConfirmState extends State<_SyncConfirm> {
  bool loading = true;
  bool running = false;
  SyncResult? result;
  String? lastPullAt;

  int total = 0;
  List<SyncRow> rows = const [];
  List<PendingSummaryItem> items = const [];

  bool get _push => widget.push;
  Color get _accent => _push ? AppColors.amber : AppColors.accent;
  IconData get _icon => _push ? Icons.arrow_upward : Icons.arrow_downward;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// حصر ما سيجري. الرفع محلي وفوري؛ السحب يسأل السحابة.
  Future<void> _load() async {
    setState(() => loading = true);
    final sync = widget.store.sync;

    if (_push) {
      final summary = sync.getPendingSummary();
      if (!mounted) return;
      setState(() {
        total = summary.total;
        rows = summary.rows;
        items = summary.items;
        loading = false;
      });
      return;
    }

    lastPullAt = await sync.getLastPullAt();
    final remote = await sync.checkRemoteChanges();
    if (!mounted) return;
    setState(() {
      total = remote.total;
      rows = remote.rows;
      items = remote.items;
      loading = false;
    });
  }

  Future<void> _run() async {
    setState(() {
      running = true;
      result = null;
    });
    HapticFeedback.mediumImpact();

    final res = _push ? await widget.store.sync.push() : await widget.store.sync.pull();
    if (!mounted) return;

    setState(() {
      running = false;
      result = res;
      total = _push ? widget.store.pendingPush : widget.store.pendingPull;
    });
    HapticFeedback.lightImpact();

    if (res.success) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = result != null && result!.success;

    return Container(
      decoration: const BoxDecoration(color: Colors.white),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // شريط تمييز علوي بلون العملية، كما في النسخة المكتبية
              Container(height: 3, color: _accent),
              _header(),
              if (result != null) _resultBanner(),
              Flexible(child: _body(done)),
              _footer(done),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 17, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _push ? 'رفع التعديلات إلى السحابة' : 'سحب التعديلات من السحابة',
              style: AppText.cardTitle,
            ),
          ),
          PressableScale(
            onTap: running ? null : () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 17, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultBanner() {
    final ok = result!.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFF0FDF4) : const Color(0xFFFFFAF9),
        border: Border(bottom: BorderSide(color: ok ? AppColors.successBorder : AppColors.dangerBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 16,
            color: ok ? const Color(0xFF166534) : const Color(0xFFBA1A1A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result!.message,
              style: TextStyle(
                color: ok ? const Color(0xFF166534) : const Color(0xFFBA1A1A),
                fontSize: 11.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(bool done) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
            const SizedBox(width: 10),
            Text(
              _push ? 'جارٍ حصر التعديلات…' : 'جارٍ فحص السحابة…',
              style: AppText.muted,
            ),
          ],
        ),
      );
    }

    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 34, color: AppColors.success),
            const SizedBox(height: 10),
            Text(
              _push
                  ? 'لا توجد تعديلات على هذا الجهاز بانتظار الرفع. كل شيء وصل السحابة.'
                  : 'لا توجد تعديلات جديدة في السحابة. بياناتك محدَّثة.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.7),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        // الملخّص: كم عملية ولأي جدول
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: const Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_push ? 'سيُرفع' : 'سيُسحب'}: $total عملية',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.heading),
              ),
              const SizedBox(height: 8),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${row.action.isEmpty ? '' : '${actionLabelsAr[row.action] ?? row.action} '}'
                          '${tableLabelsAr[row.table] ?? row.table}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155)),
                        ),
                      ),
                      Text(
                        '${row.count}',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _accent),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // التفصيل: كل عملية باسم سجلها
        for (var i = 0; i < items.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: items[i].action.isEmpty
                              ? 'تحديث'
                              : actionLabelsAr[items[i].action] ?? items[i].action,
                          style: TextStyle(fontWeight: FontWeight.w800, color: _accent),
                        ),
                        TextSpan(
                          text: ' · ${tableLabelsAr[items[i].table] ?? items[i].table} · ',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        TextSpan(
                          text: items[i].label,
                          style: const TextStyle(color: AppColors.text),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 11.5, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        if (total > items.length)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(
              'و${total - items.length} عملية أخرى…',
              textAlign: TextAlign.center,
              style: AppText.label,
            ),
          ),
      ],
    );
  }

  Widget _footer(bool done) {
    final disabled = loading || running || total == 0 || done;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _push
                  ? 'تعديلات هذا الجهاز التي لم تصل السحابة'
                  : lastPullAt == null
                      ? 'لم يُنفَّذ سحب على هذا الجهاز بعد'
                      : 'آخر سحب: ${_when(lastPullAt!)}',
              maxLines: 2,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          GhostButton(
            label: done ? 'تم' : 'إغلاق',
            onPressed: running ? null : () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          PressableScale(
            onTap: disabled ? null : _run,
            child: Opacity(
              opacity: disabled ? 0.5 : 1,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: done ? AppColors.success : _accent),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (running)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    else
                      Icon(done ? Icons.check : _icon, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      running
                          ? (_push ? 'جارٍ الرفع…' : 'جارٍ السحب…')
                          : done
                              ? 'اكتملت'
                              : '${_push ? 'تأكيد رفع' : 'تأكيد سحب'} $total',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _when(String iso) {
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return iso;
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '${formatDate(at)} · $h:$m';
  }
}
