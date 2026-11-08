// صور شاشات التطبيق ببيانات المدرسة التجريبية، لمراجعة الواجهة صفحة صفحة دون بناء التطبيق.
//
// لا تجري مع الاختبارات العادية: تُشغَّل من `.github/workflows/screens.yml`
//   flutter test test/screens --dart-define=SCREENSHOTS=true
// فتُكتب في build/screens/*.png، ومعها build/screens/_errors.txt بما رماه الرسم
// (فيض خارج الإطار وغيره) لكل شاشة.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/attendance_screen.dart';
import 'package:center_mobile/screens/classes_screen.dart';
import 'package:center_mobile/screens/evaluations_screen.dart';
import 'package:center_mobile/screens/finance_screen.dart';
import 'package:center_mobile/screens/home_screen.dart';
import 'package:center_mobile/screens/moodle_admin_screen.dart';
import 'package:center_mobile/screens/payroll_screen.dart';
import 'package:center_mobile/screens/reports_screen.dart';
import 'package:center_mobile/screens/settings_forms.dart';
import 'package:center_mobile/screens/settings_screen.dart';
import 'package:center_mobile/screens/shell.dart';
import 'package:center_mobile/screens/student_detail_screen.dart';
import 'package:center_mobile/screens/student_form_screen.dart';
import 'package:center_mobile/screens/students_screen.dart';
import 'package:center_mobile/screens/teacher_detail_screen.dart';
import 'package:center_mobile/screens/timetable_screen.dart';
import 'package:center_mobile/theme/app_theme.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');
const _out = 'build/screens';

/// جوال شائع: 412×915 نقطة.
const _size = Size(412, 915);

Future<void> _loadFonts() async {
  final family = FontLoader(AppText.family);
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    family.addFont(rootBundle.load('assets/fonts/ThmanyahSans-$w.ttf'));
  }
  await family.load();
  // أيقونات ماتيريال من حزمة Flutter نفسها، وإلا رُسمت مربعات
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final file = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (file.existsSync()) {
      final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await icons.load();
    }
  }
}

AppStore _school() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  return s;
}

final _errors = <String>[];

/// يرسم [screen] ويحفظ صورته باسم [name]. [act] ينفّذ لمسة (فتح تبويب أو نافذة) قبل الالتقاط.
Future<void> _shot(WidgetTester tester, String name, Widget screen, {AppStore? store, Future<void> Function(WidgetTester t)? act}) async {
  final s = store ?? _school();
  final boundary = GlobalKey();
  final previous = FlutterError.onError;
  final mine = <String>[];
  FlutterError.onError = (details) => mine.add(details.exceptionAsString().split('\n').first);
  try {
    tester.view.physicalSize = _size * 2;
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      StoreScope(
        store: s,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // مقياس الخط كما في التطبيق
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.93)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: RepaintBoundary(key: boundary, child: child ?? const SizedBox.shrink()),
            ),
          ),
          home: screen,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (act != null) {
      await act(tester);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('$_out/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  } catch (e) {
    mine.add('تعذّر الالتقاط: $e');
  } finally {
    FlutterError.onError = previous;
    tester.view.reset();
    if (mine.isNotEmpty) _errors.add('## $name\n${mine.toSet().map((m) => '- $m').join('\n')}');
  }
}

/// قسم يومي داخل الهيكل كما يراه المستخدم: الترويسة والشريط السفلي.
Future<void> _tab(WidgetTester t, String label) async {
  final target = find.text(label);
  if (target.evaluate().isNotEmpty) await t.tap(target.last);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  tearDownAll(() {
    File('$_out/_errors.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(_errors.isEmpty ? 'بلا أخطاء رسم\n' : '${_errors.join('\n\n')}\n');
  });

  final skip = !_enabled;
  void shot(String name, Widget Function() screen, {Future<void> Function(WidgetTester t)? act, AppStore Function()? store}) =>
      testWidgets(name, (t) => _shot(t, name, screen(), act: act, store: store?.call()), skip: skip);

  Widget page(String title, Widget body) => Scaffold(appBar: AppBar(titleSpacing: 0, title: Text(title)), body: body);

  // الأقسام اليومية داخل الهيكل
  shot('01_home', () => const AppShell());
  shot('02_students', () => const AppShell(), act: (t) => _tab(t, 'الطلاب'));
  shot('03_classes', () => const AppShell(), act: (t) => _tab(t, 'الصفوف'));
  shot('04_attendance', () => const AppShell(), act: (t) => _tab(t, 'الحضور'));
  shot('05_finance', () => const AppShell(), act: (t) => _tab(t, 'المالية'));
  shot('06_menu', () => const AppShell(), act: (t) async {
    final menu = find.byIcon(Icons.menu_rounded);
    if (menu.evaluate().isNotEmpty) await t.tap(menu.first);
  });

  // الشاشات منفردة
  shot('10_home_body', () => Scaffold(body: HomeScreen(onSection: (_) {}, onReport: (_) {}, active: ValueNotifier(true))));
  shot('11_students_body', () => const Scaffold(body: StudentsScreen()));
  shot('12_classes_body', () => const Scaffold(body: ClassesScreen()));
  shot('13_attendance_body', () => const Scaffold(body: AttendanceScreen()));
  shot('14_finance_body', () => const Scaffold(body: FinanceScreen()));
  shot('15_payroll', () => const PayrollScreen());
  shot('16_evaluations', () => const EvaluationsScreen());
  shot('17_timetable', () => const TimetableScreen());
  shot('18_moodle', () => const MoodleAdminScreen());
  shot('19_reports', () => page('التقارير', const ReportsScreen()));

  // ملف طالب ومعلم ونماذج الإضافة
  shot('20_student_detail', () => Builder(builder: (c) {
        final s = StoreScope.of(c);
        final st = s.students.firstWhere((x) => x.status == 'active');
        return StudentDetailScreen(studentId: st.id);
      }));
  shot('21_teacher_detail', () => Builder(builder: (c) => TeacherDetailScreen(teacherId: StoreScope.of(c).teachers.first.id)));
  shot('22_student_form', () => const StudentFormScreen());
  shot('23_teacher_form', () => const TeacherFormScreen());

  // الإعدادات تبويباً تبويباً
  for (final tab in ['school', 'academic_years', 'calendar', 'grade_fees', 'discounts', 'payment_methods', 'teachers', 'subjects', 'grading', 'followup', 'users', 'backup']) {
    shot('30_settings_$tab', () => SettingsScreen(initialTab: tab));
  }

  // التقارير تقريراً تقريراً
  for (final id in ['absence', 'results', 'analysis', 'completion', 'students', 'data', 'arrears', 'staff', 'usage', 'edits']) {
    shot('40_report_$id', () => Builder(builder: (c) {
          final item = reportGroups(StoreScope.of(c)).expand((g) => g.items).where((i) => i.id == id).firstOrNull;
          return item == null ? page(id, const Center(child: Text('غير متاح'))) : ReportPage(item: item);
        }));
  }
}
