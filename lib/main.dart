import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/app_update.dart';
import 'data/db_platform.dart';
import 'data/local_db.dart';
import 'data/portal.dart';
import 'data/phone.dart';
import 'data/portal_offline.dart';
import 'data/school_brand.dart';
import 'data/store.dart';
import 'data/supabase.dart';
import 'models/models.dart';
import 'screens/app_update_sheet.dart';
import 'screens/developer_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/portal_screens.dart';
import 'screens/teacher_resources_screen.dart';
import 'screens/shell.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_frame.dart';
import 'widgets/animated_count.dart';
import 'widgets/subscription_banner.dart';
import 'widgets/widgets.dart' show decodeLogo;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // الرسم يبدأ فوراً بشاشة إقلاع، والتحميل يجري خلفها.
  // انتظار فتح قاعدة البيانات قبل `runApp` كان يترك الشاشة بيضاء تماماً حتى
  // تنتهي تهيئة SQLite — وهي بطيئة على الويب — فيبدو التطبيق معطّلاً.
  // هوية المدرسة من ملفٍ داخل النسخة نفسها (ميلي ثوانٍ، بلا قرص ولا شبكة): شاشة
  // الإقلاع تُرسم من أول إطار بشعار المدرسة وألوانها بدل شعار النظام ثم التبدّل
  await SchoolBrand.instance.readBundled();
  AppStore.instance.applyBrandColors();
  // ألوان أحدث من السحابة تُطبع فور وصولها — ما لم تكن للجهاز ألوان محفوظة من دخول
  SchoolBrand.instance.addListener(AppStore.instance.applyBrandColors);

  runApp(StoreScope(store: AppStore.instance, child: const CenterApp()));

  unawaited(_bootstrap());
  // الهوية المحفوظة ثم تحديثها من السحابة: شاشة الدخول تعرض مدرستها قبل أي حساب
  unawaited(SchoolBrand.instance.load());
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
      title: appName,
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
        // خط ثمانية عريض الرسم، فيبدو أكبر من قياسه عند حجمه الاسمي. ومقياس
        // النظام يُقصّ عند 1: هاتف ضُبط على «خط كبير» كان يفرده على كل شاشة
        // حتى تتزاحم البطاقات ويُقصّ ما فيها.
        final mq = MediaQuery.of(context);
        final device = mq.textScaler.scale(1).clamp(0.85, 1.0);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(device * 0.93)),
          child: Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
        );
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
  final updater = AppUpdater.instance;
  bool _prompting = false;

  /// بعد أول إقلاع ناجح لا نُعيد شاشة الشعار إن ومضت الجاهزية عند العودة من الخلفية.
  bool _booted = false;

  /// ما يهمّ الإقلاعَ من حالة التحديث. ما عداه — نسبة التنزيل وسرعته — يتغيّر
  /// مئات المرات في الدقيقة، وإعادةُ بناء التطبيق كلّه لأجله تُبطئ التنزيل نفسه
  /// وتُقطّع الحركة. الشريط أعلى الشاشة يستمع وحده لذلك.
  bool _loaded = false;
  UpdateAction _action = UpdateAction.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    updater.addListener(_onUpdater);
    AppStore.instance.addListener(_maybePrompt);
    // قبل تثبيت بناء جديد: ارفع المعلّق حتى لا تضيع البيانات بعد المسح
    updater.beforeInstall = AppStore.instance.prepareForBuildUpdate;
    // التحديث من نسخة المدرسة كي تبقى أيقونتها: مدرسة الحساب الداخل أولاً،
    // ثم المكتوبة في هذه النسخة
    updater.schoolCode = () async {
      final tenant = AppStore.instance.currentTenant?.code.trim() ?? '';
      if (AppStore.instance.loggedIn && tenant.isNotEmpty) return tenant;
      await SchoolBrand.instance.load();
      return SchoolBrand.instance.code;
    };
    unawaited(updater.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updater.removeListener(_onUpdater);
    AppStore.instance.removeListener(_maybePrompt);
    super.dispose();
  }

  void _onUpdater() {
    if (!mounted) return;
    if (updater.loaded != _loaded || updater.action != _action) {
      setState(() {
        _loaded = updater.loaded;
        _action = updater.action;
      });
    }
    if (updater.action == UpdateAction.mandatory) {
      _clearRoutesAboveHome();
    } else {
      _maybePrompt();
    }
  }

  /// جلسة بوابة أو أي مسار دُفع فوق الشاشة الجذرية كان يغطي التحديث الإجباري.
  void _clearRoutesAboveHome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || updater.action != UpdateAction.mandatory) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.popUntil((route) => route.isFirst);
    });
  }

  /// إصدار اختياري جديد يُعرض وحده مرة واحدة عند الدخول، بعد استقرار الشاشة.
  void _maybePrompt() {
    if (_prompting || !mounted || !AppStore.instance.ready || !updater.shouldPrompt) return;
    if (updater.action == UpdateAction.mandatory) return;
    _prompting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(_settle);
      if (mounted && updater.shouldPrompt && updater.action != UpdateAction.mandatory) {
        await showUpdateSheet(context, checkNow: false);
      }
      _prompting = false;
    });
  }

  /// ما يكفي لانتهاء انتقال شاشة الإقلاع قبل أن تُرفع ورقة التحديث فوقها.
  static const _settle = Duration(milliseconds: 600);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    updater.inForeground = state == AppLifecycleState.resumed;
    AppStore.instance.inForeground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) return;
    // فحص بناء APK وتحديث صامت عند العودة — كلٌّ يحترم فاصلة، ويكشف ما نُشر أثناء الغياب
    unawaited(updater.check(silent: true).then((_) {
      if (mounted) _maybePrompt();
    }));
    unawaited(updater.checkPatch());
    final store = AppStore.instance;
    if (!store.loggedIn || store.isMasterAdmin || !store.networkEnabled) return;
    if (store.autoSync) {
      store.pullOnResume();
      return;
    }
    unawaited(store.sync.checkRemoteChanges().then((_) => store.notifySync()));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, updater]),
      builder: (context, _) {
        final Widget screen;
        // قرار التحديث يُنتظر مع إقلاع المخزن: بدونه تُعرض شاشة الدخول ثم تُقلب
        // بعد جزءٍ من الثانية إلى شاشة التحديث، فيرى المستخدم واجهتين لا واحدة
        if (!store.ready || !updater.loaded) {
          // بعد الإقلاع الأول: خلفية بيضاء بدل إعادة الشعار عند العودة من الخلفية
          screen = _booted
              ? const ColoredBox(color: Colors.white, child: SizedBox.expand())
              : const SplashScreen();
        } else if (updater.action == UpdateAction.mandatory) {
          _booted = true;
          _clearRoutesAboveHome();
          // قبل الدخول وبعده: إصدارٌ لم يعد مقبولاً لا يرفع ولا يسحب
          screen = const MandatoryUpdateScreen();
        } else if (!store.loggedIn) {
          _booted = true;
          screen = const LoginScreen();
        } else if (store.isMasterAdmin) {
          _booted = true;
          screen = const DeveloperScreen();
        } else if (store.needsInitialSetup) {
          _booted = true;
          // جهاز جديد: التهيئة وتحديد الصلاحية تسبقان أي شاشة عمل
          screen = const DeviceSetupScreen();
        } else {
          _booted = true;
          screen = const AppShell();
        }

        Widget body = KeyedSubtree(key: ValueKey(screen.runtimeType), child: screen);
        // كالويب: شريط الاشتراك فوق الشاشة دون منع العمل
        if (store.loggedIn && !store.isMasterAdmin) {
          body = Column(
            children: [
              SubscriptionStatusBanner(store: store),
              Expanded(child: body),
            ],
          );
        }

        return AnimatedSwitcher(
          duration: _booted ? Duration.zero : const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOut,
          child: body,
        );
      },
    );
  }
}

/// شاشة الإقلاع — تظهر فوراً بينما تُفتح قاعدة البيانات المحلية وتُقرأ الجلسة.
///
/// امتداد لشاشة البداية الأصلية (`launch_background` و`splash_icon`): الشعار
/// الأصلي نفسه بمقاسه في منتصف الشاشة تماماً، فلا قفزة لحظة تسليم النظام لـ Flutter.
/// الاسم والمؤشر تحته لا يزحزحانه.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  /// مقاس الشعار في الموارد الأصلية (120dp) — يُغيَّران معاً.
  static const logoSize = 120.0;

  @override
  Widget build(BuildContext context) {
    // تظهر قبل أن تُقرأ ألوان المنشأة من القرص، فتبقى محايدة: خلفية بيضاء بلا لون
    // هوية كان سيومض بالافتراضي ثم يتبدّل حين تُحمَّل ألوان المنشأة.
    // نسخة المدرسة تحمل شعارها واسمها في داخلها، فتظهر هنا من أول فتح
    final brand = SchoolBrand.instance;
    final schoolLogo = decodeLogo(brand.logo);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Center(
              child: schoolLogo != null
                  ? Image.memory(
                      schoolLogo,
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      cacheWidth: (logoSize * dpr).round(),
                    )
                  : Image.asset(
                      'assets/logo.png',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      // الأصل 1254px: فكّه بمقاس العرض يُظهره من أول إطار بدل انتظار
                      // فكّ صورة بحجم أكبر بعشر مرات
                      cacheWidth: (logoSize * dpr).round(),
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: box.maxHeight / 2 + logoSize / 2 + 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    brand.name.isNotEmpty ? brand.name : appName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
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

  /// `true` = الدخول برقم الهوية للجميع (طلاب وأولياء أمور ومعلمون وموظفو الإدارة)،
  /// `false` = دخول الإدارة بحساب المنشأة — خلف رابط صغير كما في الويب.
  bool portalTab = true;

  /// رقم الهوية 9 خانات وكلمة المرور 6: أرقام فقط، والعربية تُحوَّل.
  static const _idLength = 9;
  static const _codeLength = 6;
  static final _digitsOnly = FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]'));

  /// اكتمل رقم الهوية: المؤشر ينتقل لكلمة المرور، كالويب.
  final _codeFocus = FocusNode();

  /// اسم المستخدم في دخول الإدارة — يُركَّز بعد إغلاق لوحة الأرقام (`_switchTab`).
  final _userFocus = FocusNode();

  bool get _portalReady =>
      digitsOnly(portalId.text).length == _idLength && digitsOnly(portalCode.text).length == _codeLength;

  /// إظهار كلمة المرور ورمز البوابة — الكتابة العمياء تُفشل المحاولة بلا سبب ظاهر.
  bool showPass = false;
  bool showCode = false;
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
    _codeFocus.dispose();
    _userFocus.dispose();
    super.dispose();
  }

  /// استعادة جلسة بوابة محفوظة جارية — تبقى شاشة الإقلاع ظاهرة حتى تنتهي،
  /// فلا يرى الطالب نموذج الدخول يومض قبل أن تُفتح بوابته.
  bool restoring = false;

  /// المخزن من محيط الشاشة، لا المفرد العام: هكذا تُفتح الشاشة في الاختبارات
  /// بمخزن مستقلّ، ويبقى في التشغيل هو المفرد نفسه.
  late final AppStore _appStore =
      context.getInheritedWidgetOfExactType<StoreScope>()?.notifier ?? AppStore.instance;

  @override
  void initState() {
    super.initState();
    // آخر اسم مستخدم أُدخل على هذا الجهاز — مطابق لسلوك LandingPage
    user.text = _appStore.lastUsername;
    portalId.text = _appStore.lastPortalNationalId;
    restoring = _appStore.portalSession != null;
    unawaited(_restorePortal());
  }

  /// جلسة بوابة محفوظة: تُفتح فوراً بالحساب على الجهاز، ثم يُجدَّد التحقق
  /// في الخلفية. انتظار الشبكة كان يُبطئ الإقلاع ويعطي انطباع دخولٍ جديد.
  Future<void> _restorePortal() async {
    final saved = _appStore.portalSession;
    if (saved == null) return;

    // فتح فوري إن وُجد حساب محفوظ — بعد إطار الرسم حتى لا يُقفل الملاح
    if (saved.user != null) {
      portalId.text = saved.nationalId;
      portalCode.text = saved.code;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openPortal(saved.user!, code: saved.code, restored: true);
      });
      unawaited(_refreshPortalInBackground(saved));
      return;
    }

    PortalLoginResult result;
    try {
      result = await const PortalService().login(saved.nationalId, saved.code);
    } catch (_) {
      result = const PortalLoginResult(error: 'offline', offline: true);
    }
    if (!mounted) return;

    final account = result.ok
        ? (result.users.where((u) => u.id == saved.userId).firstOrNull ??
            (result.users.length == 1 ? result.users.first : null))
        : null;

    if (account == null) {
      if (!result.ok && !result.offline) await _appStore.clearPortalSession();
      setState(() => restoring = false);
      return;
    }

    portalId.text = saved.nationalId;
    portalCode.text = saved.code;
    _openPortal(account, code: saved.code, restored: true);
  }

  /// تجديد صامت: يحدّث بيانات الحساب، أو يُخرج عند رفض السيرفر للهوية.
  Future<void> _refreshPortalInBackground(
    ({String nationalId, String code, String userId, PortalUser? user}) saved,
  ) async {
    PortalLoginResult result;
    try {
      result = await const PortalService().login(saved.nationalId, saved.code);
    } catch (_) {
      return; // بلا شبكة: الجلسة المحلية كافية
    }
    if (!mounted) return;

    if (!result.ok) {
      if (result.offline) return;
      await _appStore.clearPortalSession();
      await PortalOffline(_appStore.db).clear();
      await supabaseSignOut();
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }

    final account = result.users.where((u) => u.id == saved.userId).firstOrNull ??
        (result.users.length == 1 ? result.users.first : null);
    if (account == null) return;

    await _appStore.savePortalSession(
      nationalId: account.nationalId.isEmpty ? saved.nationalId : account.nationalId,
      code: saved.code,
      userId: account.id,
      user: account,
    );
  }

  Future<void> _portalSubmit() async {
    if (busy || !_portalReady) return;
    setState(() {
      error = null;
      choices = const [];
      busy = true;
    });

    final result = await const PortalService().login(digitsOnly(portalId.text), digitsOnly(portalCode.text));
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        busy = false;
        error = result.error;
      });
      return;
    }

    await _appStore.rememberPortalNationalId(portalId.text);

    // حساب واحد: فُتحت جلسته فندخل مباشرةً. أكثر من واحد: يختار المستخدم
    // منشأته أو دوره، ثم يُعاد التحقق بالخيار لتُفتح جلسته هو
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

  /// اختيار حساب من عدّة: يُعاد التحقق بالخيار فتُفتح جلسته هو لا غيره.
  Future<void> _chooseAccount(PortalUser account) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final result = await const PortalService().login(digitsOnly(portalId.text), digitsOnly(portalCode.text), choice: account);
    if (!mounted) return;
    setState(() => busy = false);
    if (!result.ok || result.users.length != 1) {
      setState(() => error = result.error ?? 'تعذّر فتح جلسة البوابة، حاول مجدداً');
      return;
    }
    setState(() => choices = const []);
    _openPortal(result.users.first);
  }

  /// [restored] جلسة محفوظة تُفتح عند الإقلاع: بلا حركة انتقال، وشاشة الإقلاع
  /// تبقى تحتها حتى يخرج المستخدم. بغير ذلك تنزلق البوابة فوق نموذج الدخول
  /// فيراه المستخدم ثانيةً كاملة بعد الشعار وكأنه مطالَب بالدخول من جديد.
  void _openPortal(PortalUser account, {String? code, bool restored = false}) {
    // موظف إدارة: يفتح النظام بصلاحياته لا البوابة
    if (account.isStaff) {
      unawaited(_openStaff(account));
      return;
    }
    // الجلسة تبقى بعد إغلاق التطبيق، كجلسة الإدارة
    unawaited(_appStore.savePortalSession(
      nationalId: account.nationalId.isEmpty ? portalId.text : account.nationalId,
      code: code ?? portalCode.text,
      userId: account.id,
      user: account,
    ));

    // الخروج يُنهي جلسة البوابة: لا تبقى صلاحيات طالب أو ولي أمر على الجهاز
    Future<void> exit() async {
      await _appStore.clearPortalSession();
      // ولا تبقى كشوف صفوفه معروضة لمن يدخل بعده
      await PortalOffline(_appStore.db).clear();
      await supabaseSignOut();
      if (mounted) {
        setState(() => restoring = false);
        Navigator.of(context).pop();
      }
    }

    Widget page(BuildContext _) => account.isTeacher
        ? TeacherResourcesScreen(user: account, onExit: exit)
        : StudentPortalScreen(user: account, onExit: exit);

    final route = restored
        ? PageRouteBuilder<void>(
            pageBuilder: (context, _, __) => page(context),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          )
        : MaterialPageRoute<void>(builder: page);

    // شاشة الإقلاع تبقى تحت البوابة حتى تُدفع فوقها، ثم تُطفأ كي لا تُعاد عند الخروج
    Navigator.of(context).push(route).then((_) {
      if (mounted) setState(() => restoring = false);
    });
    if (restored && restoring) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => restoring = false);
      });
    }
  }

  /// موظف دخل برقم هويته — `openLoginResult` بـ `res.staff`: صف المنشأة كاملاً بجلسة
  /// الموظف، واشتراكها يُفحص كدخول المالك.
  Future<void> _openStaff(PortalUser account) async {
    setState(() {
      busy = true;
      error = null;
    });
    final tenant = await _appStore.tenantApi.findById(account.tenantId);
    if (!mounted) return;
    if (tenant == null) {
      await supabaseSignOut();
      setState(() {
        busy = false;
        error = 'هذا الحساب غير مرتبط بمنشأة';
      });
      return;
    }
    final err = await _appStore.startStaffSession(tenant, userId: account.id, role: account.staffRole, name: account.name);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
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
    final store = _appStore;
    // جلسة محفوظة: خلفية بيضاء قصيرة لا شعار ثانٍ — الشعار ظهر في إقلاع المخزن
    if (restoring) {
      return const ColoredBox(color: Colors.white, child: SizedBox.expand());
    }
    return ListenableBuilder(
      listenable: SchoolBrand.instance,
      builder: (context, _) => _frame(store),
    );
  }

  /// هوية الجهاز إن عُرفت من دخولٍ سابق، وإلا مدرسة هذه النسخة.
  Widget _frame(AppStore store) {
    final brand = SchoolBrand.instance;
    final name = store.institutionName.isNotEmpty ? store.institutionName : brand.name;
    final logo = store.institutionLogo.isNotEmpty ? store.institutionLogo : brand.logo;
    return AuthFrame(
      title: name.isEmpty ? appName : name,
      subtitle: portalTab ? 'تسجيل الدخول' : 'دخول الإدارة',
      logo: logo,
      // الرقم المثبَّت فعلاً مع تحديثه الصامت (1.2.7.3)، والثابت حيث لا يُعرف
      footer: Text(
        'الإصدار ${AppUpdater.instance.installedName.isEmpty ? appVersion : AppUpdater.instance.installedName}',
        style: const TextStyle(color: AppColors.faint, fontSize: 10.5),
      ),
      children: [
        AuthCard(child: portalTab ? _portalForm() : _adminForm()),
        const SizedBox(height: 10),
        // حساب المنشأة خلف رابط: الدخول اليومي للجميع برقم الهوية
        Center(
          child: TextButton.icon(
            onPressed: busy ? null : _switchTab,
            // arrow_back يُعكس مع الاتجاه: في العربية يشير يميناً، اتجاه الرجوع
            icon: Icon(portalTab ? Icons.lock_outline : Icons.arrow_back, size: 15),
            label: Text(portalTab ? 'دخول الإدارة' : 'رجوع'),
            style: TextButton.styleFrom(foregroundColor: AppColors.navy, textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  /// التبديل بين دخول البوابة ودخول الإدارة.
  ///
  /// لوحة المفاتيح تُغلق أولاً ثم يُركَّز اسم المستخدم: نقل التركيز مباشرةً من
  /// حقل رقم الهوية كان يُبقي لوحة الأرقام مفتوحة على حقل الاسم (شاومي وغيرها لا
  /// تبدّل نوعها)، فيُضطر المستخدم لإغلاقها وفتحها ليكتب حروفاً.
  void _switchTab() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      portalTab = !portalTab;
      error = null;
      choices = const [];
    });
    if (portalTab) return;
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted && !portalTab) _userFocus.requestFocus();
    });
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
          focusNode: _userFocus,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          // السحابة تعرف الحساب بأحرف إنجليزية صغيرة: حرف كبير أو مسافة من
          // التصحيح التلقائي كان يردّ «اسم المستخدم أو كلمة المرور غير صحيحة»
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
            TextInputFormatter.withFunction(
              (previous, next) => next.copyWith(text: next.text.toLowerCase()),
            ),
          ],
          textAlign: TextAlign.start,
          style: _fieldText,
          decoration: authFieldDecoration('أدخل اسم المستخدم...', Icons.person_outline),
        ),
        const SizedBox(height: 14),
        authLabel('كلمة المرور:'),
        const SizedBox(height: 6),
        TextField(
          controller: pass,
          obscureText: !showPass,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _submit(),
          textAlign: TextAlign.start,
          style: _fieldText.copyWith(fontFamily: 'monospace'),
          decoration: authFieldDecoration(
            'أدخل كلمة المرور...',
            Icons.lock_outline,
            suffix: AuthRevealButton(visible: showPass, onTap: () => setState(() => showPass = !showPass)),
          ),
        ),
        // جلسة انتهت أثناء العمل: يُقال للمستخدم لماذا عاد إلى هنا
        AuthErrorBox(message: error ?? StoreScope.of(context).sessionExpiredNotice),
        const SizedBox(height: 16),
        AuthSubmitButton(
          busy: busy,
          label: busy ? 'جارِ التحقق...' : 'دخول',
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
          maxLength: _idLength,
          inputFormatters: [_digitsOnly],
          onChanged: (v) {
            setState(() => error = null);
            if (digitsOnly(v).length == _idLength) _codeFocus.requestFocus();
          },
          textAlign: TextAlign.start,
          style: _fieldText.copyWith(fontFamily: 'monospace', letterSpacing: 1),
          decoration: authFieldDecoration('9 أرقام', Icons.badge_outlined).copyWith(counterText: ''),
        ),
        const SizedBox(height: 14),
        authLabel('كلمة المرور:'),
        const SizedBox(height: 6),
        TextField(
          controller: portalCode,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          obscureText: !showCode,
          maxLength: _codeLength,
          inputFormatters: [_digitsOnly],
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) => _portalSubmit(),
          textAlign: TextAlign.start,
          style: _fieldText.copyWith(fontFamily: 'monospace', letterSpacing: 2),
          decoration: authFieldDecoration(
            '6 أرقام',
            Icons.vpn_key_outlined,
            suffix: AuthRevealButton(visible: showCode, onTap: () => setState(() => showCode = !showCode)),
          ).copyWith(counterText: ''),
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
                onTap: () => _chooseAccount(account),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Corner.box),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        account.isStaff
                            ? Icons.badge_outlined
                            : account.isTeacher
                                ? Icons.school
                                : account.isParent
                                    ? Icons.family_restroom
                                    : Icons.person,
                        size: 16,
                        color: AppColors.amber,
                      ),
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
                              style: TextStyle(color: AppColors.heading, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              [
                                account.roleLabel,
                                if (account.isParent && account.studentName.isNotEmpty) 'لـ ${account.studentName}',
                                account.tenantName,
                              ].join(' · '),
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
          label: busy ? 'جارِ التحقق...' : 'تسجيل الدخول',
          icon: Icons.login,
          onTap: busy || !_portalReady ? null : _portalSubmit,
        ),
      ],
    );
  }
}
