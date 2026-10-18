/// نسخة Google Play (`com.noonschool.app`) أو نسخ GitHub (`com.center.center_mobile`).
///
/// تُبنى نسخة المتجر بـ `--dart-define=STORE=play` مع `NOON_STORE=play` لـ Gradle
/// (`.github/workflows/play-store.yml`). نسخ GitHub تُبنى بدونهما فتبقى كما هي.
///
/// الفرق في نسخة المتجر: لا تحديث ذاتي (التحديث من المتجر، وسياسة Google تمنع
/// تثبيت حزم من خارجه)، وكود المدرسة من رابط التنزيل (Install Referrer) لا من
/// `assets/school.json`، ورابط صغير لإدارات المدارس في شاشة الدخول.
library;

import 'package:flutter/services.dart';

const bool playStore = String.fromEnvironment('STORE') == 'play';

/// رقم طلب النظام لإدارات المدارس (واتساب).
const salesWhatsApp = '0599024136';

/// كود المدرسة من نص الإحالة: `school=CODE` (قد يصل مشفّراً `school%3DCODE`)، أو `null`.
String? parseReferrerSchool(String? referrer) {
  if (referrer == null || referrer.trim().isEmpty) return null;
  var raw = referrer.trim();
  try {
    if (!raw.contains('=')) raw = Uri.decodeComponent(raw);
  } catch (_) {}
  Map<String, String> params;
  try {
    params = Uri.splitQueryString(raw);
  } catch (_) {
    return null;
  }
  final code = (params['school'] ?? '').trim().toUpperCase();
  return RegExp(r'^[A-Z0-9_-]{1,50}$').hasMatch(code) ? code : null;
}

/// نص الإحالة الذي حمله رابط التنزيل من المتجر (`MainActivity` ← `StoreReferrer`).
Future<String?> readInstallReferrer() async {
  try {
    return await const MethodChannel('center/install_referrer').invokeMethod<String>('get');
  } catch (_) {
    return null;
  }
}
