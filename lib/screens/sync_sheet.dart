import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/permissions.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';

const _sheetBg = AppColors.navy;
const _sheetPanel = Color(0xCC123963);

/// غلاف موحّد للأوراق السفلية الداكنة — مقبض سحب وحواف علوية دائرية.
Future<T?> _darkSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: _sheetBg,
        border: Border(top: BorderSide(color: Color(0xFF1E3A5F))),
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
            const Icon(Icons.cloud_outlined, size: 15, color: Color(0xFFF39C12)),
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
                color: AppColors.info,
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

/// ورقة تأكيد الرفع أو السحب — تعرض ما سيجري قبل تنفيذه، ثم تُظهر النتيجة
/// والرقم وهو ينزل إلى الصفر بدل أن يختفي فجأة.
Future<void> openSyncSheet(BuildContext context, AppStore store, {required bool push}) async {
  if (!push) await store.sync.checkRemoteChanges();
  if (!context.mounted) return;

  final summary = push ? store.sync.getPendingSummary() : null;
  final remote = push ? null : await store.sync.checkRemoteChanges();
  if (!context.mounted) return;

  final total = push ? summary!.total : (remote?.total ?? store.pendingPull);
  final rows = push ? summary!.rows : (remote?.rows ?? const <SyncRow>[]);
  final items = push ? summary!.items : (remote?.items ?? const <PendingSummaryItem>[]);

  if (!context.mounted) return;
  await _darkSheet(context, (ctx) => _SyncConfirm(
        store: store,
        push: push,
        total: total,
        rows: rows,
        items: items,
      ));
}

class _SyncConfirm extends StatefulWidget {
  const _SyncConfirm({
    required this.store,
    required this.push,
    required this.total,
    required this.rows,
    required this.items,
  });

  final AppStore store;
  final bool push;
  final int total;
  final List<SyncRow> rows;
  final List<PendingSummaryItem> items;

  @override
  State<_SyncConfirm> createState() => _SyncConfirmState();
}

class _SyncConfirmState extends State<_SyncConfirm> {
  bool busy = false;
  int remaining = 0;
  SyncResult? result;

  @override
  void initState() {
    super.initState();
    remaining = widget.total;
  }

  Color get _accent => widget.push ? AppColors.amber : AppColors.info;

  Future<void> _run() async {
    setState(() {
      busy = true;
      result = null;
    });
    HapticFeedback.mediumImpact();

    final res = widget.push ? await widget.store.sync.push() : await widget.store.sync.pull();
    if (!mounted) return;

    setState(() {
      busy = false;
      result = res;
      // العدّاد ينزل إلى ما تبقّى فعلاً، فيرى المستخدم أثر العملية
      remaining = widget.push ? widget.store.pendingPush : widget.store.pendingPull;
    });
    HapticFeedback.lightImpact();

    // إغلاق تلقائي بعد نجاح كامل، ليقرأ المستخدم النتيجة أولاً
    if (res.success) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.push ? 'رفع التعديلات المحلية' : 'سحب التعديلات من السحابة';
    final done = result != null && result!.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (done ? AppColors.success : _accent).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.zero,
                ),
                child: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: _accent),
                      )
                    : Icon(
                        done
                            ? Icons.check_circle
                            : (widget.push ? Icons.arrow_upward : Icons.arrow_downward),
                        color: done ? AppColors.success : _accent,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'المتبقي: ',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
                        ),
                        AnimatedCount(
                          remaining,
                          duration: const Duration(milliseconds: 900),
                          style: TextStyle(color: _accent, fontSize: 15, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          ' من $widget.total',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // شريط تقدّم يمتلئ كلما نقص المتبقي
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: widget.total == 0 ? 1 : 1 - (remaining / widget.total)),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v.clamp(0, 1),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(done ? AppColors.success : _accent),
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (result != null)
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: (result!.success ? AppColors.success : AppColors.danger).withValues(alpha: 0.14),
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: (result!.success ? AppColors.success : AppColors.danger).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    result!.success ? Icons.check_circle_outline : Icons.error_outline,
                    size: 16,
                    color: result!.success ? const Color(0xFF6EE7B7) : const Color(0xFFFDA4AF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result!.message,
                      style: TextStyle(
                        color: result!.success ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Text(
              widget.total == 0
                  ? (widget.push ? 'لا توجد تعديلات محلية معلّقة للرفع' : 'لا توجد تعديلات جديدة في السحابة')
                  : (widget.push
                      ? 'سيتم رفع $widget.total تعديلاً إلى السحابة.'
                      : 'سيتم سحب $widget.total تعديلاً وتحديث الشاشة.'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.6),
            ),
            if (widget.rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in widget.rows)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      child: Text(
                        '${tableLabelsAr[r.table] ?? r.table} · ${r.count}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ],
            if (widget.items.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final item in widget.items.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${item.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                  ),
                ),
            ],
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PressableScale(
                  onTap: busy ? null : () => Navigator.pop(context),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      done ? 'تم' : 'إغلاق',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 2,
                child: PressableScale(
                  onTap: (widget.total == 0 || busy || done) ? null : _run,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (widget.total == 0 || done) ? 0.45 : 1,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: done ? AppColors.success : _accent,
                        borderRadius: BorderRadius.zero,
                        boxShadow: [
                          BoxShadow(
                            color: (done ? AppColors.success : _accent).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (busy)
                            const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            Icon(
                              done ? Icons.check : (widget.push ? Icons.cloud_upload_outlined : Icons.cloud_download_outlined),
                              size: 16,
                              color: Colors.white,
                            ),
                          const SizedBox(width: 7),
                          Text(
                            busy
                                ? (widget.push ? 'جارِ الرفع...' : 'جارِ السحب...')
                                : done
                                    ? 'اكتملت'
                                    : (widget.push ? 'تأكيد الرفع' : 'تأكيد السحب'),
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
