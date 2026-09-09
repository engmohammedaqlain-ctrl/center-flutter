import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/local_db.dart';
import 'data/store.dart';
import 'data/supabase.dart';
import 'models/models.dart';
import 'screens/developer_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/shell.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/animated_count.dart';
import 'widgets/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // sqflite لا يعمل على الويب افتراضياً — نستخدم تنفيذ WASM عبر IndexedDB.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
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

class CenterApp extends StatelessWidget {
  const CenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام الإدارة المدرسي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
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

class _Root extends StatelessWidget {
  const _Root();

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
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D2A50), AppColors.navyDark, Color(0xFF05162A)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.school, color: AppColors.amber, size: 50),
              ),
              const SizedBox(height: 22),
              Text(
                appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.amber.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
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
  String? error;
  bool busy = false;

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // آخر اسم مستخدم أُدخل على هذا الجهاز — مطابق لسلوك LandingPage
    user.text = AppStore.instance.lastUsername;
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

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final logo = decodeLogo(store.institutionLogo);

    return Scaffold(
      body: Container(
        // تدرّج هادئ بدل لون مصمت — العمق هو ما يميّز الشاشة الرسمية
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D2A50), AppColors.navyDark, Color(0xFF05162A)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  children: [
                    // شعار المنشأة إن رُفع، وإلا رمز النظام
                    Container(
                      width: 104,
                      height: 104,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 26,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: logo == null
                            ? const Icon(Icons.school, color: AppColors.amber, size: 56)
                            : Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      store.institutionName.isEmpty ? appName : store.institutionName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'بوابة تسجيل الدخول الرسمية',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _label('اسم المستخدم:'),
                          const SizedBox(height: 7),
                          TextField(
                            controller: user,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            decoration: _deco('أدخل اسم المستخدم...', Icons.person_outline),
                          ),
                          const SizedBox(height: 14),
                          _label('كلمة المرور:'),
                          const SizedBox(height: 7),
                          TextField(
                            controller: pass,
                            obscureText: true,
                            onSubmitted: (_) => _submit(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontFamily: 'monospace',
                            ),
                            decoration: _deco('أدخل كلمة المرور...', Icons.lock_outline),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: error == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Container(
                                      padding: const EdgeInsets.all(11),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4C0519).withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFF43F5E).withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: Color(0xFFFB7185), size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              error!,
                                              style: const TextStyle(
                                                color: Color(0xFFFECDD3),
                                                fontSize: 12,
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          PressableScale(
                            onTap: busy ? null : _submit,
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.amber.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (busy)
                                    const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                    )
                                  else
                                    const Icon(Icons.login, size: 18, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    busy ? 'جارِ التحقق...' : 'تسجيل الدخول',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'الإصدار $appVersion',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );

  InputDecoration _deco(String hint, IconData icon) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c, width: w),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 12.5),
      prefixIcon: Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.45)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
      focusedBorder: border(AppColors.amber, 1.4),
      border: border(Colors.white.withValues(alpha: 0.12)),
    );
  }
}
