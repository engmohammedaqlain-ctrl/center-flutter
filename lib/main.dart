import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/db_platform.dart';
import 'data/local_db.dart';
import 'data/portal.dart';
import 'data/store.dart';
import 'data/supabase.dart';
import 'models/models.dart';
import 'screens/developer_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/portal_screens.dart';
import 'screens/shell.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_frame.dart';
import 'widgets/animated_count.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // الرسم يبدأ فوراً بشاشة إقلاع، والتحميل يجري خلفها.
  // انتظار فتح قاعدة البيانات قبل `runApp` كان يترك الشاشة بيضاء تماماً حتى
  // تنتهي تهيئة SQLite — وهي بطيئة على الويب — فيبدو التطبيق معطّلاً.
  runApp(StoreScope(store: AppStore.instance, child: const CenterApp()));

  unawaited(_bootstrap());
}

Future<void> _bootstrap() async {
  final store = AppStore.instance;
  try {
    await store.bootstrap(SqflitePersistence());
  } catch (_) {
    // تعذّر فتح التخزين الدائم: نُكمل في الذاكرة بدل أن يتوقف التطبيق
    await store.bootstrap(NoPersistence());
  }
  SupabaseConfig.applyOverrides(store.db.settings);
  // جلسة مستعادة: نفس ما يجري بعد تسجيل الدخول
  unawaited(store.afterEnter());
}

class CenterApp extends StatefulWidget {
  const CenterApp({super.key});

  @override
  State<CenterApp> createState() => _CenterAppState();
}

/// السمة تُعاد بناؤها حين تتغيّر ألوان الهوية — وحينها فقط.
///
/// كانت تُبنى مرة واحدة عند الإقلاع بالألوان الافتراضية، قبل أن تصل ألوان
/// المنشأة من القرص أو السحابة، فبقي شريط العنوان في كل شاشة فرعية كحلياً
/// مهما اختارت الإدارة. المخزن يُخطر عند كل تعديل، فتُقارَن بصمة الألوان أولاً
/// بدل إعادة بناء التطبيق كله مع كل لمسة حضور.
class _CenterAppState extends State<CenterApp> {
  AppStore? _store;
  String _palette = _currentPalette();
  ThemeData _theme = AppTheme.build();

  static String _currentPalette() => [
        AppColors.navy,
        AppColors.amber,
        AppColors.heading,
        AppColors.bg,
        AppColors.accent,
      ].map((c) => c.toARGB32()).join('|');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // قراءة بلا اشتراك: الاشتراك في StoreScope يعيد بناء التطبيق مع كل إخطار
    final store = context.getInheritedWidgetOfExactType<StoreScope>()?.notifier;
    if (identical(store, _store)) return;
    _store?.removeListener(_onStoreChanged);
    _store = store?..addListener(_onStoreChanged);
    _onStoreChanged();
  }

  void _onStoreChanged() {
    final next = _currentPalette();
    if (next == _palette) return;
    setState(() {
      _palette = next;
      _theme = AppTheme.build();
    });
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام الإدارة المدرسي',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink());
      },
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

/// يعيد فحص السحابة عند العودة إلى التطبيق.
///
/// بلا ذلك يبقى عدّاد السحب على آخر قيمة عُرفت قبل ساعات، فيظهر «متزامن»
/// بينما جهاز آخر أضاف تعديلات في الأثناء.
class _RootState extends State<_Root> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final store = AppStore.instance;
    if (!store.loggedIn || store.isMasterAdmin || !store.networkEnabled) return;
    unawaited(store.sync.checkRemoteChanges().then((_) => store.notifySync()));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final Widget screen;
        if (!store.ready) {
          screen = const SplashScreen();
        } else if (!store.loggedIn) {
          screen = const LoginScreen();
        } else if (store.isMasterAdmin) {
          screen = const DeveloperScreen();
        } else if (store.needsInitialSetup) {
          // جهاز جديد: التهيئة وتحديد الصلاحية تسبقان أي شاشة عمل
          screen = const DeviceSetupScreen();
        } else {
          screen = const AppShell();
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOut,
          child: KeyedSubtree(key: ValueKey(screen.runtimeType), child: screen),
        );
      },
    );
  }
}

/// شاشة الإقلاع — تظهر فوراً بينما تُفتح قاعدة البيانات المحلية وتُقرأ الجلسة.
///
/// امتداد لشاشة البداية الأصلية (`launch_background` و`splash_icon`): الصندوق
/// نفسه بمقاسه ولونه في منتصف الشاشة تماماً، فلا قفزة لحظة تسليم النظام لـ Flutter.
/// الاسم والمؤشر تحته لا يزحزحانه.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  /// مقاس الصندوق في الموارد الأصلية (84dp) — يُغيَّران معاً.
  static const logoBox = 84.0;

  @override
  Widget build(BuildContext context) {
    // تظهر قبل أن تُقرأ ألوان المنشأة من القرص، فتبقى محايدة: خلفية بيضاء بلا لون
    // هوية كان سيومض بالافتراضي ثم يتبدّل حين تُحمَّل ألوان المنشأة
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Center(
              child: Container(
                width: logoBox,
                height: logoBox,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Corner.card),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Icon(Icons.school_outlined, color: AppColors.muted, size: logoBox / 2),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: box.maxHeight / 2 + logoBox / 2 + 18,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appName, style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
                  SizedBox(height: 16),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lineStrong),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final user = TextEditingController();
  final pass = TextEditingController();
  final portalId = TextEditingController();
  final portalCode = TextEditingController();

  /// `true` = بوابة الطلاب والمعلمين، `false` = دخول الإدارة.
  bool portalTab = true;
  String? error;
  bool busy = false;

  /// حسابات مطابقة لرقم الهوية والرمز — قد يكون الرقم في أكثر من منشأة.
  List<PortalUser> choices = const [];

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    portalId.dispose();
    portalCode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // آخر اسم مستخدم أُدخل على هذا الجهاز — مطابق لسلوك LandingPage
    user.text = AppStore.instance.lastUsername;
  }

  Future<void> _portalSubmit() async {
    if (busy) return;
    setState(() {
      error = null;
      choices = const [];
      busy = true;
    });

    final result = await const PortalService().login(portalId.text, portalCode.text);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        busy = false;
        error = result.error;
      });
      return;
    }

    // حساب واحد: ندخل مباشرةً. أكثر من واحد: يختار المستخدم منشأته أو دوره.
    if (result.users.length == 1) {
      setState(() => busy = false);
      _openPortal(result.users.first);
      return;
    }
    setState(() {
      busy = false;
      choices = result.users;
    });
  }

  void _openPortal(PortalUser account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => account.isTeacher
            ? TeacherPortalScreen(user: account, onExit: () => Navigator.of(context).pop())
            : StudentPortalScreen(user: account, onExit: () => Navigator.of(context).pop()),
      ),
    );
  }

  Future<void> _submit() async {
    if (busy) return;
    setState(() {
      error = null;
      busy = true;
    });
    final err = await StoreScope.of(context).login(user.text, pass.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
  }

  static const _fieldText = TextStyle(color: AppColors.text, fontSize: 13.5);

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return AuthFrame(
      title: store.institutionName.isEmpty ? appName : store.institutionName,
      subtitle: 'بوابة تسجيل الدخول الرسمية',
      logo: store.institutionLogo,
      footer: Text('الإصدار $appVersion', style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
      children: [
        _tabs(),
        const SizedBox(height: 12),
        AuthCard(child: portalTab ? _portalForm() : _adminForm()),
      ],
    );
  }

  /// شريط اختيار البوابة — مطابق لـ LandingPage: بوابة الطلاب والمعلمين إلى جانب
  /// دخول الإدارة، بشكل مفتاح مقسوم يمتلئ خياره المختار بلون الهوية.
  Widget _tabs() {
    Widget tab(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: PressableScale(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(Corner.box),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 5),
                // «بوابة الطلاب والمعلمين» أطول من نصف الشاشة على الأجهزة الضيقة،
                // فيلزم أن ينكمش بدل أن يفيض
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(Corner.field),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          tab('بوابة الطلاب والمعلمين', Icons.school_outlined, portalTab, () {
            setState(() {
              portalTab = true;
              error = null;
              choices = const [];
            });
          }),
          const SizedBox(width: 4),
          tab('دخول الإدارة', Icons.lock_outline, !portalTab, () {
            setState(() {
              portalTab = false;
              error = null;
              choices = const [];
            });
          }),
        ],
      ),
    );
  }

  /// نموذج دخول الإدارة: اسم المستخدم وكلمة المرور.
  Widget _adminForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        authLabel('اسم المستخدم:'),
        const SizedBox(height: 6),
        TextField(
          controller: user,
          autofocus: true,
          textInputAction: TextInputAction.next,
          style: _fieldText,
          decoration: authFieldDecoration('أدخل اسم المستخدم...', Icons.person_outline),
        ),
        const SizedBox(height: 14),
        authLabel('كلمة المرور:'),
        const SizedBox(height: 6),
        TextField(
          controller: pass,
          obscureText: true,
          onSubmitted: (_) => _submit(),
          style: _fieldText.copyWith(fontFamily: 'monospace'),
          decoration: authFieldDecoration('أدخل كلمة المرور...', Icons.lock_outline),
        ),
        AuthErrorBox(message: error),
        const SizedBox(height: 16),
        AuthSubmitButton(
          busy: busy,
          label: busy ? 'جارِ التحقق...' : 'تسجيل الدخول',
          icon: Icons.login,
          onTap: busy ? null : _submit,
        ),
      ],
    );
  }

  /// نموذج دخول البوابة: رقم الهوية ورمز الدخول.
  Widget _portalForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        authLabel('رقم الهوية:'),
        const SizedBox(height: 6),
        TextField(
          controller: portalId,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          style: _fieldText,
          decoration: authFieldDecoration('أدخل رقم الهوية...', Icons.badge_outlined),
        ),
        const SizedBox(height: 14),
        authLabel('رمز الدخول (الكود):'),
        const SizedBox(height: 6),
        TextField(
          controller: portalCode,
          keyboardType: TextInputType.number,
          obscureText: true,
          onSubmitted: (_) => _portalSubmit(),
          style: _fieldText.copyWith(fontFamily: 'monospace'),
          decoration: authFieldDecoration('أدخل رمز الدخول...', Icons.vpn_key_outlined),
        ),
        AuthErrorBox(message: error),
        // أكثر من حساب لنفس الرقم: يختار المستخدم منشأته أو دوره
        if (choices.isNotEmpty) ...[
          const SizedBox(height: 12),
          authLabel('اختر الحساب:'),
          const SizedBox(height: 6),
          for (final account in choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: PressableScale(
                onTap: () => _openPortal(account),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Corner.box),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(account.isTeacher ? Icons.school : Icons.person, size: 16, color: AppColors.amber),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.heading, fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${account.isTeacher ? 'معلم' : 'طالب'} · ${account.tenantName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward, size: 15, color: AppColors.faint),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        AuthSubmitButton(
          busy: busy,
          label: busy ? 'جارِ التحقق...' : 'دخول البوابة',
          icon: Icons.login,
          onTap: busy ? null : _portalSubmit,
        ),
      ],
    );
  }
}
