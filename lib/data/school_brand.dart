/// هوية المدرسة التي نُزّلت هذه النسخة من صفحتها.
///
/// كل مدرسة تنزّل من `/d/<الكود>` نسختها الخاصة: أيقونتها شعار المدرسة، وفي
/// داخلها ملف `assets/school.json` بكودها (يكتبه `tool/school_apk.dart` عند
/// النشر). النسخة العامة ملفها فارغ. بالكود يعرض التطبيق اسم المدرسة وشعارها
/// من أول فتح قبل تسجيل الدخول، ويطلب تحديثاته من نسخة مدرسته فتبقى أيقونتها.
///
/// الكود تسهيلٌ لا صلاحية: الدخول والبيانات تحكمها الحسابات كما قبل.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase.dart';

/// اسم المدرسة وشعارها كما في صفحة تحميلها.
typedef SchoolIdentity = ({String name, String logo});

/// الكود من محتوى `assets/school.json`، أو `null` للنسخة العامة.
String? parseSchoolAsset(String raw) {
  try {
    final data = jsonDecode(raw);
    final code = data is Map ? '${data['code'] ?? ''}'.trim().toUpperCase() : '';
    return RegExp(r'^[A-Z0-9_-]{1,50}$').hasMatch(code) ? code : null;
  } catch (_) {
    return null;
  }
}

class SchoolBrand extends ChangeNotifier {
  SchoolBrand({
    Future<String> Function()? readAsset,
    Future<SchoolIdentity?> Function(String code)? fetch,
  })  : _readAsset = readAsset ?? (() => rootBundle.loadString('assets/school.json')),
        _fetch = fetch ?? _fetchIdentity;

  static final instance = SchoolBrand();

  static const _kName = 'school_brand_name';
  static const _kLogo = 'school_brand_logo';
  static const _kCode = 'school_brand_code';

  final Future<String> Function() _readAsset;
  final Future<SchoolIdentity?> Function(String code) _fetch;

  /// كود المدرسة المكتوب في هذه النسخة.
  String? code;

  /// آخر ما عُرف عنها — محفوظ على الجهاز فيظهر بلا إنترنت.
  String name = '';
  String logo = '';

  Future<void>? _loading;

  /// قراءة الكود والهوية المحفوظة، ثم تحديثها من السحابة في الخلفية.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      code = parseSchoolAsset(await _readAsset());
    } catch (_) {
      code = null;
    }
    final c = code;
    if (c == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // هوية مدرسةٍ أخرى من نسخةٍ سابقة على الجهاز لا تُعرض تحت هذا الكود
      if (prefs.getString(_kCode) == c) {
        name = prefs.getString(_kName) ?? '';
        logo = prefs.getString(_kLogo) ?? '';
        notifyListeners();
      }
    } catch (_) {}
    unawaited(_refresh(c));
  }

  Future<void> _refresh(String c) async {
    final identity = await _fetch(c);
    if (identity == null || identity.name.isEmpty) return;
    if (identity.name == name && identity.logo == logo) return;
    name = identity.name;
    logo = identity.logo;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCode, c);
      await prefs.setString(_kName, name);
      await prefs.setString(_kLogo, logo);
    } catch (_) {}
  }
}

/// الدالة نفسها التي تبني صفحة التحميل: عامةٌ لا تحتاج دخولاً، ولا تعيد إلا
/// الاسم والشعار والألوان لمدرسة نشطة.
Future<SchoolIdentity?> _fetchIdentity(String code) async {
  final data = await supabaseRpc('get_school_download_page', {'p_code': code});
  if (data is! Map) return null;
  final name = '${data['name'] ?? ''}'.trim();
  if (name.isEmpty) return null;
  return (name: name, logo: '${data['logo'] ?? ''}'.trim());
}
