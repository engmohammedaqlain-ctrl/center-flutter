/// تحديث نسخة Google Play من داخل التطبيق — واجهة Google الرسمية (In-App Updates).
///
/// نسخة المتجر لا تنزّل حزماً بنفسها (سياسة Google)، فكان الجهاز يبقى على القديم
/// حتى يحدّثه المتجر متى شاء. الآن: إصدارٌ جديد على المتجر يُنزَّل في الخلفية من
/// المتجر نفسه، ثم يُعرض «تحديث الآن» فيُثبَّت ويُعاد فتح التطبيق.
/// التحديث الصامت (Shorebird) للتصليحات الصغيرة يبقى كما هو بجانبه.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_update/in_app_update.dart';

import 'play_store.dart';

class PlayUpdate {
  /// على نسخة المتجر في أندرويد وحدها.
  static bool get supported => playStore && !kIsWeb && Platform.isAndroid;

  static DateTime? _checkedAt;
  static bool _downloading = false;

  /// اكتمل تنزيل إصدار جديد ينتظر التثبيت.
  static bool ready = false;

  /// يُفحص عند الإقلاع وعند العودة للتطبيق، ولا يُعاد قبل ساعة.
  /// [onReady] يُنادى حين يكتمل التنزيل ليُعرض «تحديث الآن».
  static Future<void> check({required void Function() onReady}) async {
    if (!supported || _downloading || ready) return;
    final last = _checkedAt;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return;
    _checkedAt = DateTime.now();
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        ready = true;
        onReady();
        return;
      }
      if (info.updateAvailability != UpdateAvailability.updateAvailable || !info.flexibleUpdateAllowed) return;
      // تنزيل مرن: المستخدم يكمل عمله والمتجر ينزّل في الخلفية
      _downloading = true;
      final result = await InAppUpdate.startFlexibleUpdate();
      _downloading = false;
      if (result == AppUpdateResult.success) {
        ready = true;
        onReady();
      }
    } catch (_) {
      // جهاز بلا متجر Google أو بلا اتصال: لا شيء يُعرض، والمتجر يحدّثه لاحقاً
      _downloading = false;
    }
  }

  /// تثبيت ما نزل: يُغلق التطبيق ويُعاد فتحه على الإصدار الجديد.
  static Future<void> install() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {}
  }
}
