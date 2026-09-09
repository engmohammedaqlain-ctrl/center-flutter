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
import 'screens/developer_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/shell.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // sqflite لا يعمل على الويب افتراضياً — نستخدم تنفيذ WASM عبر IndexedDB.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final store = AppStore.instance;
  // تحميل قاعدة البيانات المحلية قبل رسم أي شاشة، وإلا ظهر التطبيق فارغاً
  // للحظة ثم امتلأ — وهو ما كان يبدو كأن البيانات ضاعت.
  await store.bootstrap(SqflitePersistence());
  SupabaseConfig.applyOverrides(store.db.settings);
  // جلسة مستعادة: نفس ما يجري بعد تسجيل الدخول
  unawaited(store.afterEnter());

  runApp(StoreScope(store: store, child: const CenterApp()));
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
        if (!store.loggedIn) return const LoginScreen();
        if (store.isMasterAdmin) return const DeveloperScreen();
        // جهاز جديد: التهيئة وتحديد الصلاحية تسبقان أي شاشة عمل
        if (store.needsInitialSetup) return const DeviceSetupScreen();
        return const AppShell();
      },
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
    return Scaffold(
      backgroundColor: AppColors.navyDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.amberSoft,
                      border: Border.all(color: AppColors.amber, width: 2),
                    ),
                    child: const Icon(Icons.school, color: AppColors.amber, size: 64),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'نظام الإدارة المدرسي',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'بوابة تسجيل الدخول الرسمية',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.9),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('اسم المستخدم:', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: user,
                          autofocus: true,
                          style: const TextStyle(color: AppColors.text, fontSize: 13),
                          decoration: _deco('أدخل اسم المستخدم...', Icons.person_outline),
                        ),
                        const SizedBox(height: 12),
                        Text('كلمة المرور:', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: pass,
                          obscureText: true,
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(color: AppColors.text, fontSize: 13, fontFamily: 'monospace'),
                          decoration: _deco('أدخل كلمة المرور...', Icons.lock_outline),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4C0519).withValues(alpha: 0.8),
                              border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFFB7185), size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(error!, style: const TextStyle(color: Color(0xFFFECDD3), fontSize: 12))),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        PrimaryButton(
                          expand: true,
                          height: 40,
                          busy: busy,
                          icon: Icons.login,
                          label: busy ? 'جارِ التحقق...' : 'تسجيل الدخول',
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 16, color: AppColors.faint),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
