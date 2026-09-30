/// هوية المدرسة التي نُزّلت هذه النسخة من صفحتها.
///
/// كل مدرسة تنزّل من `/d/<الكود>` نسختها الخاصة: أيقونتها شعار المدرسة، وفي
/// داخلها ملف `assets/school.json` بكودها واسمها وشعارها وألوانها (يكتبه
/// `tool/school_apk.dart` عند النشر). النسخة العامة ملفها فارغ. بها تعرض شاشة
/// الإقلاع وشاشة الدخول هوية المدرسة من أول فتح — بلا إنترنت وقبل أي حساب —
/// ويطلب التطبيق تحديثاته من نسخة مدرسته فتبقى أيقونتها.
///
/// الكود تسهيلٌ لا صلاحية: الدخول والبيانات تحكمها الحسابات كما قبل.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'institution.dart';
import 'supabase.dart';

/// اسم المدرسة وشعارها وألوانها كما في صفحة تحميلها.
typedef SchoolIdentity = ({String name, String logo, InstitutionColors? colors});

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

/// الهوية المكتوبة مع الكود في ملف النسخة، أو `null` إن لم تُكتب (نسخٌ أقدم فيها الكود وحده).
SchoolIdentity? parseSchoolAssetIdentity(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return null;
    final name = '${data['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    return (name: name, logo: '${data['logo'] ?? ''}'.trim(), colors: _colorsFrom(data['colors']));
  } catch (_) {
    return null;
  }
}

/// ألوان المدرسة إن كانت مضبوطة — لا تُفترض ألوان النظام بدلها.
InstitutionColors? _colorsFrom(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  const keys = ['sidebarBg', 'activeItem', 'primaryButton', 'actionButton', 'appBg'];
  if (!keys.any((k) => parseHexColor('${map[k] ?? ''}') != null)) return null;
  return InstitutionColors.fromMap(map);
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
  static const _kColors = 'school_brand_colors';
  static const _kCode = 'school_brand_code';

  final Future<String> Function() _readAsset;
  final Future<SchoolIdentity?> Function(String code) _fetch;

  /// كود المدرسة المكتوب في هذه النسخة.
  String? code;

  /// آخر ما عُرف عنها — من ملف النسخة، ثم المحفوظ على الجهاز، ثم السحابة.
  String name = '';
  String logo = '';

  /// ألوان المدرسة، أو `null` للنسخة العامة أو مدرسةٍ بلا ألوان مضبوطة.
  InstitutionColors? colors;

  Future<void>? _bundled;
  Future<void>? _loading;

  /// ملف النسخة وحده — سريع ومحلي، فيُنتظر قبل أول إطار: شاشة الإقلاع تُرسم
  /// بشعار المدرسة مباشرة بدل أن تومض بشعار النظام ثم تتبدّل.
  Future<void> readBundled() => _bundled ??= _readBundled();

  Future<void> _readBundled() async {
    String raw;
    try {
      raw = await _readAsset();
    } catch (_) {
      return;
    }
    code = parseSchoolAsset(raw);
    if (code == null) return;
    final identity = parseSchoolAssetIdentity(raw);
    if (identity != null) _set(identity);
  }

  /// ملف النسخة، ثم الهوية المحفوظة، ثم تحديثها من السحابة في الخلفية.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    await readBundled();
    final c = code;
    if (c == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // هوية مدرسةٍ أخرى من نسخةٍ سابقة على الجهاز لا تُعرض تحت هذا الكود
      if (prefs.getString(_kCode) == c && (prefs.getString(_kName) ?? '').isNotEmpty) {
        InstitutionColors? saved;
        try {
          saved = _colorsFrom(jsonDecode(prefs.getString(_kColors) ?? ''));
        } catch (_) {}
        _set((name: prefs.getString(_kName) ?? '', logo: prefs.getString(_kLogo) ?? '', colors: saved ?? colors));
      }
    } catch (_) {}
    notifyListeners();
    unawaited(_refresh(c));
  }

  void _set(SchoolIdentity identity) {
    name = identity.name;
    if (identity.logo.isNotEmpty) logo = identity.logo;
    colors = identity.colors ?? colors;
  }

  static String _colorsKey(InstitutionColors? c) => c == null ? '' : jsonEncode(c.toMap());

  Future<void> _refresh(String c) async {
    final identity = await _fetch(c);
    if (identity == null || identity.name.isEmpty) return;
    if (identity.name == name && identity.logo == logo && _colorsKey(identity.colors) == _colorsKey(colors)) return;
    _set(identity);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCode, c);
      await prefs.setString(_kName, name);
      await prefs.setString(_kLogo, logo);
      await prefs.setString(_kColors, _colorsKey(colors));
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
  return (name: name, logo: '${data['logo'] ?? ''}'.trim(), colors: _colorsFrom(data['colors']));
}
