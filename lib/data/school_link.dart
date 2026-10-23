/// رابط المدرسة يفتح التطبيق عليها، واختصارها على الشاشة الرئيسية.
///
/// المدرسة تشارك رابطها `https://noonschool.app/d/<الكود>` أو رمزه. نسخة المتجر تفتح هذه
/// الروابط بنفسها (App Links: `android/app/src/play/AndroidManifest.xml` و
/// `.well-known/assetlinks.json` في الموقع)، فتُعرض شاشة الدخول باسم المدرسة وشعارها. ومن
/// ليس عنده التطبيق تأخذه الصفحة إلى المتجر بالكود نفسه (Install Referrer: `school_brand.dart`).
///
/// الاختصار المثبّت (`SchoolLinks.kt`) يحمل الرابط نفسه، فيمرّ من الطريق ذاته.
/// نسخة GitHub الخاصة بمدرسة لا تحتاج شيئاً من هذا: اسمها وأيقونتها مدرستها أصلاً.
///
/// الكود تسهيلٌ لا صلاحية: الدخول والبيانات تحكمها الحسابات كما قبل.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'school_brand.dart';

/// دومينات الموقع: الأساسي والقديم الباقي (نفس مشروع Pages).
const schoolLinkHosts = {'noonschool.app', 'www.noonschool.app', 'noon-school.pages.dev'};

/// كود المدرسة من رابط صفحتها `https://<الموقع>/d/<الكود>[/...]`، أو `null`.
String? parseSchoolLink(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'https' || !schoolLinkHosts.contains(uri.host.toLowerCase())) return null;
  final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (parts.length < 2 || parts[0] != 'd') return null;
  final code = parts[1].toUpperCase();
  return RegExp(r'^[A-Z0-9_-]{1,50}$').hasMatch(code) ? code : null;
}

const _channel = MethodChannel('center/school_link');

/// الجهاز نفسه لا `defaultTargetPlatform`: الاختبارات تعدّ نفسها أندرويد.
bool get _android => !kIsWeb && Platform.isAndroid;

class SchoolLinks {
  SchoolLinks._();

  /// يستمع للروابط أثناء العمل، ويطبّق رابط الإقلاع إن فُتح التطبيق به.
  static Future<void> start(SchoolBrand brand) async {
    if (!_android) return;
    await brand.readBundled();
    if (brand.bundled) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') return;
      final code = parseSchoolLink('${call.arguments ?? ''}');
      if (code != null) await brand.openLink(code);
    });
    try {
      final code = parseSchoolLink(await _channel.invokeMethod<String>('initial'));
      if (code != null) await brand.openLink(code);
    } catch (_) {}
  }
}

/// اختصار المدرسة على الشاشة الرئيسية: شعارها واسمها، ويفتح التطبيق عليها.
class HomeShortcut {
  HomeShortcut._();

  static const _kOffered = 'home_shortcut_offered';

  /// أندرويد، وليست نسخة مدرسة خاصة.
  static bool get available => _android && !SchoolBrand.instance.bundled;

  /// الشاشة الرئيسية تقبل تثبيت الاختصارات.
  static Future<bool> supported() async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('canPin') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// يطلب من النظام تثبيت الاختصار (يسأل المستخدم بنافذته). `false` = غير مدعوم.
  static Future<bool> pin({required String code, required String name, Uint8List? logo}) async {
    if (!available || name.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('pin', {'code': code, 'name': name.trim(), 'logo': logo}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool _claimed = false;

  /// يُعرض العرض مرة واحدة على الجهاز: `true` إن حان وقته الآن (ويُسجَّل أنه عُرض).
  static Future<bool> claimOffer() async {
    if (_claimed || !available) return false;
    _claimed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kOffered) == true) return false;
      if (!await supported()) return false;
      await prefs.setBool(_kOffered, true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
