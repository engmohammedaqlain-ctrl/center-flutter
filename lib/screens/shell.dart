import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';
import 'app_update_sheet.dart';
import 'attendance_screen.dart';
import 'classes_screen.dart';
import 'finance_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'students_screen.dart';
import 'sync_sheet.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// قسم في شريط التنقّل — مطابق لـ `MobileBottomNav` مع حراسة الصلاحيات.
class Section {
  const Section(this.id, this.title, this.label, this.icon, this.activeIcon, this.screen);
  final String id;
  final String title;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;
}

class _AppShellState extends State<AppShell> {
  String current = 'students';

  /// الأقسام المتاحة لهذا المستخدم على هذا الجهاز.
  ///
  /// القسم الرابع يتبع نوع المنشأة: «الصفوف» للمدرسة و«الجدول» للمركز —
  /// تثبيته على الصفوف كان يخفي قسم المجموعات كلياً عن المراكز التعليمية.
  List<Section> _sections(AppStore store) {
    final school = store.isSchool;
    final all = [
      const Section('students', 'الطلاب', 'الطلاب', Icons.groups_outlined, Icons.groups, StudentsScreen()),
      const Section('attendance', 'الحضور', 'الحضور', Icons.fact_check_outlined, Icons.fact_check, AttendanceScreen()),
      const Section('finance', 'المالية', 'المالية', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, FinanceScreen()),
      if (school)
        const Section('classes', 'الصفوف', 'الصفوف', Icons.apartment_outlined, Icons.apartment, ClassesScreen())
      else
        const Section('schedule', 'الجداول', 'الجدول', Icons.calendar_month_outlined, Icons.calendar_month, ScheduleScreen()),
      const Section('settings', 'الإعدادات', 'الإعدادات', Icons.settings_outlined, Icons.settings, SettingsScreen()),
    ];
    final allowed = all.where((s) => store.canOpenSection(s.id)).toList();
    return allowed.isEmpty ? [all.first] : allowed;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final sections = _sections(store);
        var index = sections.indexWhere((s) => s.id == current);
        if (index < 0) index = 0;

        return Scaffold(
          backgroundColor: Colors.white,
          body: Column(
            children: [
              _Header(title: sections[index].title),
              // تنزيل التحديث وتحديثه الصامت يُتابَعان من أي قسم دون فتح القائمة
              const UpdateStatusStrip(),
              Expanded(
                child: IndexedStack(
                  index: index,
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      _FrozenWhenHidden(visible: i == index, child: sections[i].screen),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _BottomNav(
            sections: sections,
            index: index,
            onSelect: (i) => setState(() => current = sections[i].id),
            dueCount: store.can('finance.view') ? store.dueItems().length : 0,
          ),
        );
      },
    );
  }
}

/// ترويسة الهاتف — مطابقة لـ `MobileHeader`: شعار المنشأة، ثم عنوان القسم
/// واسم المنشأة، ثم حبّة المزامنة الذكية، ثم زر القائمة السريعة.
class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(14, top + 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        border: Border(bottom: BorderSide(color: AppColors.navyMid)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          InstitutionBadge(logo: store.institutionLogo, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  store.institutionName.isEmpty ? 'إدارة المدارس' : store.institutionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.headerMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SyncPill(store: store),
          const SizedBox(width: 8),
          PressableScale(
            onTap: () => showActionSheet(context, store),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(Icons.more_vert, size: 17, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// حبّة المزامنة الذكية: حالة واحدة فقط بحسب الأولوية — رفع معلّق، ثم سحب
/// متاح، ثم «متزامن». الرقم يتحرّك بدل أن يقفز، فيُرى أثر العملية.
class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final push = store.pendingPush;
    final pull = store.pendingPull;
    final busy = store.sync.isSyncing;
    // من لا يملك الرفع أو السحب لا يُعرض عليه زرّه
    final canPush = store.can('sync.push');
    final canPull = store.can('sync.pull');

    if (push > 0 && canPush) {
      return _pill(
        context,
        color: AppColors.amber,
        icon: Icons.arrow_upward,
        label: 'رفع',
        count: push,
        busy: busy,
        onTap: () => openSyncSheet(context, store, push: true),
      );
    }
    if (pull > 0 && canPull) {
      return _pill(
        context,
        color: AppColors.accent,
        icon: Icons.arrow_downward,
        label: 'سحب',
        count: pull,
        busy: busy,
        onTap: () => openSyncSheet(context, store, push: false),
      );
    }
    // «متزامن» تُقال فقط حين تكون السحابة قد فُحصت للتوّ. قولها بلا فحص
    // كانت تطمئن المستخدم بينما في السحابة تعديلات لم يعلم بها.
    final known = store.sync.remoteStateKnown;
    return PressableScale(
      onTap: canPull ? () => openSyncSheet(context, store, push: false) : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              known ? Icons.check_circle : Icons.cloud_sync_outlined,
              size: 13,
              color: known ? const Color(0xFF34D399) : Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 5),
            Text(
              known ? 'متزامن' : 'مزامنة',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String label,
    required int count,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return PulsingBadge(
      trigger: count,
      child: PressableScale(
        onTap: busy ? null : onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Corner.box),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
                )
              else
                Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              AnimatedCount(
                count,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط التنقّل السفلي — مطابق لـ `MobileBottomNav`: خط كهرماني فوق القسم
/// المفتوح وحبّة خلف أيقونته.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.sections,
    required this.index,
    required this.onSelect,
    required this.dueCount,
  });

  final List<Section> sections;
  final int index;
  final ValueChanged<int> onSelect;
  final int dueCount;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(top: 4, bottom: bottom > 0 ? bottom : 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++)
            Expanded(
              child: _NavItem(
                section: sections[i],
                active: index == i,
                badge: sections[i].id == 'finance' ? dueCount : 0,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  final Section section;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.92,
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 2,
              width: active ? 34 : 0,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(Corner.box),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 38,
                      height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.amberSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(Corner.box),
                      ),
                      child: Icon(
                        active ? section.activeIcon : section.icon,
                        size: 19,
                        color: active ? AppColors.accent : AppColors.muted,
                      ),
                    ),
                    if (badge > 0)
                      Positioned(
                        left: -4,
                        top: -3,
                        child: PulsingBadge(
                          trigger: badge,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 15),
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(Corner.box),
                              border: Border.all(color: Colors.white, width: 1.2),
                            ),
                            child: Text(
                              '$badge',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? AppColors.accent : AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// يُجمّد الشاشة المخفية بدل إعادة بنائها.
///
/// `IndexedStack` يُبقي الأقسام الخمسة في الشجرة، وكلٌّ منها يستمع للمخزن،
/// فأي رصد حضور كان يُعيد بناء الطلاب والمالية والصفوف والإعدادات معه.
/// حفظ الشجرة المبنية وإعادتها كما هي يُبقي الحالة ويُلغي ذلك العمل.
class _FrozenWhenHidden extends StatefulWidget {
  const _FrozenWhenHidden({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_FrozenWhenHidden> createState() => _FrozenWhenHiddenState();
}

class _FrozenWhenHiddenState extends State<_FrozenWhenHidden> {
  Widget? _frozen;

  @override
  Widget build(BuildContext context) {
    if (widget.visible) {
      _frozen = null;
      return widget.child;
    }
    // أول إخفاء بعد الظهور: نحتفظ بآخر شجرة ونعيدها دون إعادة بناء
    return _frozen ??= widget.child;
  }
}
