import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';
import 'app_update_sheet.dart';
import 'attendance_screen.dart';
import 'classes_screen.dart';
import 'developer_settings_screen.dart';
import 'evaluations_screen.dart';
import 'finance_screen.dart';
import 'moodle_admin_screen.dart';
import 'settings_screen.dart';
import 'students_screen.dart';
import 'sync_sheet.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// قسم يومي في الشريط السفلي — الإعدادات والدرجات في القائمة الجانبية.
class Section {
  const Section(
    this.id,
    this.title,
    this.label,
    this.icon,
    this.activeIcon,
    this.screen,
  );
  final String id;
  final String title;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;
}

class _AppShellState extends State<AppShell> {
  String current = 'students';
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _wasOffline = false;

  /// الأقسام اليومية فقط — بقية الإدارة من القائمة الجانبية.
  /// الترتيب: طلاب → صفوف → حضور → مالية.
  List<Section> _sections(AppStore store) {
    final all = [
      const Section(
        'students',
        'الطلاب',
        'الطلاب',
        Icons.people_alt_outlined,
        Icons.people_alt_rounded,
        StudentsScreen(),
      ),
      const Section(
        'classes',
        'الصفوف',
        'الصفوف',
        Icons.school_outlined,
        Icons.school_rounded,
        ClassesScreen(),
      ),
      const Section(
        'attendance',
        'الحضور',
        'الحضور',
        Icons.event_available_outlined,
        Icons.event_available_rounded,
        AttendanceScreen(),
      ),
      const Section(
        'finance',
        'المالية',
        'المالية',
        Icons.payments_outlined,
        Icons.payments_rounded,
        FinanceScreen(),
      ),
    ];
    final allowed = all.where((s) => store.canOpenSection(s.id)).toList();
    return allowed.isEmpty ? [all.first] : allowed;
  }

  void _openSettings(String? tab) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => Material(
          color: AppColors.bg,
          child: SettingsScreen(initialTab: tab),
        ),
      ),
    );
  }

  void _openPage(Widget page) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => Material(
          color: AppColors.bg,
          child: page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // تنبيه واحد عند انقطاع الاتصال وعند عودته — لا مؤشر يدور بلا نهاية
        if (store.offline != _wasOffline) {
          _wasOffline = store.offline;
          final offline = store.offline;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showAppSnack(context, offline ? 'لا يوجد اتصال بالإنترنت' : 'عاد الاتصال', error: offline);
          });
        }
        // قائمة بلا بنود لا تُفتح: من لا يملك إعدادات ولا درجات ولا مودل ليس
        // له فيها إلا الخروج، فيُنقل إلى الترويسة ويُخفى زر القائمة
        final hasMenu = store.canOpenSection('settings') ||
            (store.isFeatureOn('evaluations') && store.can('evaluations')) ||
            (store.isFeatureOn('moodle') && store.can('moodle')) ||
            store.isMasterAdmin;
        final sections = _sections(store);
        var index = sections.indexWhere((s) => s.id == current);
        if (index < 0) index = 0;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.bg,
          drawer: !hasMenu
              ? null
              : _SideMenu(
            store: store,
            onClose: () => Navigator.of(context).maybePop(),
            onOpenEvaluations: () {
              Navigator.of(context).pop();
              _openPage(const EvaluationsScreen());
            },
            onOpenMoodle: () {
              Navigator.of(context).pop();
              _openPage(const MoodleAdminScreen());
            },
            onOpenSettings: (tab) {
              Navigator.of(context).pop();
              _openSettings(tab);
            },
            onOpenDeveloper: () {
              Navigator.of(context).pop();
              _openPage(const DeveloperSettingsScreen());
            },
            onLogout: () async {
              Navigator.of(context).pop();
              if (!context.mounted) return;
              if (await confirmLogout(context)) await store.logout();
            },
          ),
          body: Column(
            children: [
              _Header(
                title: sections[index].title,
                onOpenMenu: hasMenu ? () => _scaffoldKey.currentState?.openDrawer() : null,
                onLogout: hasMenu
                    ? null
                    : () async {
                        if (await confirmLogout(context)) await store.logout();
                      },
              ),
              Expanded(
                child: IndexedStack(
                  index: index,
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      _FrozenWhenHidden(
                        visible: i == index,
                        child: sections[i].screen,
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const UpdateStatusStrip(),
              _BottomNav(
                sections: sections,
                index: index,
                onSelect: (i) => setState(() => current = sections[i].id),
                dueCount: store.can('finance') ? store.dueItems().length : 0,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// قائمة جانبية: تفتح من اليمين (بداية الشاشة في RTL) وزر القائمة معها.
class _SideMenu extends StatelessWidget {
  const _SideMenu({
    required this.store,
    required this.onClose,
    required this.onOpenEvaluations,
    required this.onOpenMoodle,
    required this.onOpenSettings,
    required this.onOpenDeveloper,
    required this.onLogout,
  });

  final AppStore store;
  final VoidCallback onClose;
  final VoidCallback onOpenEvaluations;
  final VoidCallback onOpenMoodle;
  final ValueChanged<String?> onOpenSettings;
  final VoidCallback onOpenDeveloper;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final name = store.institutionName.trim().isEmpty ? 'إدارة المدارس' : store.institutionName.trim();
    final me = store.deviceUser;
    final role = me?.name.trim().isNotEmpty == true ? me!.name : store.roleName;
    final top = MediaQuery.paddingOf(context).top;

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppText.family,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.faint,
            ),
          ),
        );

    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? color,
    }) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (color ?? AppColors.heading).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Corner.box),
          ),
          child: Icon(icon, size: 18, color: color ?? AppColors.heading),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: AppColors.text,
          ),
        ),
        // سهم «التالي» ينعكس مع العربية (matchTextDirection)
        trailing: const AppChevron(size: 22),
        onTap: onTap,
      );
    }

    final canSettings = store.canOpenSection('settings');
    final showAcademic = (store.isFeatureOn('evaluations') && store.can('evaluations')) ||
        (store.isFeatureOn('moodle') && store.can('moodle'));

    return Drawer(
      backgroundColor: Colors.white,
      width: MediaQuery.sizeOf(context).width * 0.82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, top + 16, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [AppColors.navy, AppColors.navyMid],
              ),
            ),
            child: Row(
              children: [
                InstitutionBadge(logo: store.institutionLogo, size: 44, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (showAcademic) ...[
                  sectionLabel('الأكاديمي'),
                  if (store.isFeatureOn('evaluations') && store.can('evaluations'))
                    item(
                      icon: Icons.workspace_premium_rounded,
                      label: 'الدرجات والتقييمات',
                      color: AppColors.amber,
                      onTap: onOpenEvaluations,
                    ),
                  if (store.isFeatureOn('moodle') && store.can('moodle'))
                    item(
                      icon: Icons.auto_stories_rounded,
                      label: 'المودل',
                      color: AppColors.amber,
                      onTap: onOpenMoodle,
                    ),
                ],
                if (canSettings) ...[
                  sectionLabel('إدارة المدرسة'),
                  item(
                    icon: Icons.badge_outlined,
                    label: 'المعلمون',
                    onTap: () => onOpenSettings('teachers'),
                  ),
                  item(
                    icon: Icons.menu_book_rounded,
                    label: 'المواد',
                    onTap: () => onOpenSettings('subjects'),
                  ),
                  if (store.isFeatureOn('evaluations'))
                    item(
                      icon: Icons.grid_view_rounded,
                      label: 'نظام العلامات',
                      onTap: () => onOpenSettings('grading'),
                    ),
                  item(
                    icon: Icons.calendar_month_rounded,
                    label: 'الأعوام الدراسية',
                    onTap: () => onOpenSettings('academic_years'),
                  ),
                  item(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'المراحل والرسوم',
                    onTap: () => onOpenSettings('grade_fees'),
                  ),
                  item(
                    icon: Icons.credit_card_rounded,
                    label: 'وسائل الدفع',
                    onTap: () => onOpenSettings('payment_methods'),
                  ),
                  if (store.can('settings.users'))
                    item(
                      icon: Icons.manage_accounts_rounded,
                      label: 'المستخدمون',
                      onTap: () => onOpenSettings('users'),
                    ),
                  if (store.can('settings.backup'))
                    item(
                      icon: Icons.cloud_sync_rounded,
                      label: 'البيانات والنسخ',
                      onTap: () => onOpenSettings('backup'),
                    ),
                ],
                if (store.isMasterAdmin) ...[
                  sectionLabel('المنصة'),
                  item(
                    icon: Icons.developer_mode_rounded,
                    label: 'إعدادات المطور',
                    color: AppColors.amber,
                    onTap: onOpenDeveloper,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          SafeArea(
            top: false,
            child: ListTile(
              leading: Icon(Icons.logout_rounded, color: AppColors.danger),
              title: Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontFamily: AppText.family,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                  fontSize: 13.5,
                ),
              ),
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

/// ترويسة: زر القائمة على اليمين مع فتح الـ Drawer من اليمين (RTL صحيح).
class _Header extends StatelessWidget {
  const _Header({required this.title, this.onOpenMenu, this.onLogout});
  final String title;

  /// `null` حين لا تحمل القائمة الجانبية شيئاً لهذا المستخدم.
  final VoidCallback? onOpenMenu;

  /// يظهر بدل زر القائمة حين تُخفى، فيبقى الخروج في متناول اليد.
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final name = store.institutionName.trim().isEmpty ? 'إدارة المدارس' : store.institutionName.trim();

    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 10, 8, 12),
      color: AppColors.navy,
      child: Row(
        children: [
          // قائمة بلا خلفية مربّعة — الأيقونة وحدها لا تسرق مساحة الترويسة
          if (onOpenMenu != null)
            Tooltip(
              message: 'القائمة',
              child: PressableScale(
                onTap: onOpenMenu,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.menu_rounded,
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ),
            )
          else if (onLogout != null)
            Tooltip(
              message: 'تسجيل الخروج',
              child: PressableScale(
                onTap: onLogout,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.logout_rounded,
                    size: 22,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
          const SizedBox(width: 6),
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
                    fontFamily: AppText.family,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            tooltip: store.viewedAcademicYear?.label ?? 'العام الدراسي',
            icon: Icons.calendar_today_rounded,
            onTap: store.academicYears.isEmpty ? null : () => _showYearPicker(context, store),
          ),
          _SyncIcon(store: store),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 20, color: Colors.white.withValues(alpha: onTap == null ? 0.35 : 0.9)),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

Future<void> _showYearPicker(BuildContext context, AppStore store) {
  final years = [...store.academicYears]
    ..sort((a, b) => b.startsOn.compareTo(a.startsOn));
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'عرض عام دراسي',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.heading,
              ),
            ),
            const SizedBox(height: 8),
            for (final year in years)
              RadioListTile<String>(
                dense: true,
                value: year.id,
                groupValue: store.viewedAcademicYearId,
                activeColor: AppColors.amber,
                title: Text(
                  year.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                subtitle: Text(
                  year.isCurrent
                      ? 'عام التشغيل الحالي'
                      : (year.status == 'closed' ? 'مغلق' : 'مفتوح'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                  ),
                ),
                onChanged: (id) {
                  if (id != null) store.viewedAcademicYearId = id;
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// مزامنة: أيقونة هادئة عند السكون، وشارة ملونة فقط حين يوجد رفع/سحب معلّق.
class _SyncIcon extends StatelessWidget {
  const _SyncIcon({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final push = store.pendingPush;
    final pull = store.pendingPull;
    final busy = store.sync.isSyncing && !store.offline;

    // بلا اتصال: سحابة مشطوبة ثابتة، وما ينتظر الرفع يبقى عدده ظاهراً عليها
    if (store.offline) {
      return _HeaderIconButton(
        tooltip: push > 0 ? 'لا يوجد اتصال · $push بانتظار الرفع' : 'لا يوجد اتصال',
        icon: Icons.cloud_off_outlined,
        onTap: () => openSyncSheet(context, store, push: push > 0),
      );
    }

    if (push > 0) {
      return _SyncActionBadge(
        color: AppColors.amber,
        icon: Icons.arrow_upward_rounded,
        count: push,
        busy: busy,
        onTap: () => openSyncSheet(context, store, push: true),
      );
    }
    if (pull > 0) {
      return _SyncActionBadge(
        color: AppColors.accent,
        icon: Icons.arrow_downward_rounded,
        count: pull,
        busy: busy,
        onTap: () => openSyncSheet(context, store, push: false),
      );
    }

    final known = store.sync.remoteStateKnown;
    return _HeaderIconButton(
      tooltip: known ? 'متزامن' : 'مزامنة',
      icon: known ? Icons.cloud_done_outlined : Icons.cloud_outlined,
      onTap: () => openSyncSheet(context, store, push: false),
    );
  }
}

class _SyncActionBadge extends StatelessWidget {
  const _SyncActionBadge({
    required this.color,
    required this.icon,
    required this.count,
    required this.busy,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final int count;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PulsingBadge(
      trigger: count,
      child: PressableScale(
        onTap: busy ? null : onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Corner.field),
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
                Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              AnimatedCount(
                count,
                style: const TextStyle(
                  fontFamily: AppText.family,
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط التنقّل السفلي — أسلوب Jira: أيقونة + تسمية بفواصل بينها، والنشط بلون
/// الإجراءات في الثيم كبقية عناصر الواجهة التفاعلية.
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
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            // فاصل رفيع بين كل قسمين
            if (i > 0) Container(width: 1, height: 28, color: AppColors.line),
            Expanded(
              child: _NavItem(
                section: sections[i],
                active: index == i,
                badge: sections[i].id == 'finance' ? dueCount : 0,
                onTap: () => onSelect(i),
              ),
            ),
          ],
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
      scale: 0.96,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(
                    active ? section.activeIcon : section.icon,
                    size: 24,
                    color: active ? AppColors.amber : AppColors.faint,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    left: -6,
                    top: -4,
                    child: PulsingBadge(
                      trigger: badge,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(Corner.chip),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: AppText.family,
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              section.label,
              style: TextStyle(
                fontFamily: AppText.family,
                fontSize: 10.5,
                height: 1.1,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.amber : AppColors.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// يُجمّد الشاشة المخفية بدل إعادة بنائها، ولا يبني تبويباً لم يُفتح بعد.
///
/// `IndexedStack` يُبقي الأقسام في الشجرة؛ بناء الكل عند الإقلاع كان يشغّل
/// `TableGate` للحضور والمالية معاً فيثقل القرص ويفشل التحميل أحياناً.
/// التبويب يُبنى أول زيارة فقط، ثم يُجمَّد عند الإخفاء.
class _FrozenWhenHidden extends StatefulWidget {
  const _FrozenWhenHidden({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_FrozenWhenHidden> createState() => _FrozenWhenHiddenState();
}

class _FrozenWhenHiddenState extends State<_FrozenWhenHidden> {
  Widget? _frozen;
  var _visited = false;

  @override
  Widget build(BuildContext context) {
    if (widget.visible) {
      _visited = true;
      _frozen = null;
      return widget.child;
    }
    if (!_visited) return const SizedBox.shrink();
    // إخفاء بعد زيارة: نحتفظ بآخر شجرة دون إعادة بناء
    return _frozen ??= widget.child;
  }
}
