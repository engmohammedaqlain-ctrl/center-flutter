/// إشعار تنزيل التحديث أو تهيئة البيانات — يُبقي العمل يعمل بعد الخروج من التطبيق.
///
/// أندرويد يجمّد عملية تطبيقٍ لا شيء له في المقدمة بعد ثوانٍ من إخفائه، فينقطع
/// التنزيل ويبقى معلّقاً حتى يُفتح ثانيةً. خدمةٌ في المقدمة بإشعارٍ ظاهر تُعفي
/// العملية من ذلك، والإشعار نفسه هو ما يرى منه المستخدم النسبة وهو في غيره.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ما يحتاجه التحديث من نظام التشغيل، مجرَّداً كي يُختبر بلا جهاز.
abstract class DownloadNotifier {
  /// إشعارٌ ثابت بشريط تقدّم، ومعه ما يُبقي التنزيل يعمل خارج التطبيق.
  /// [percent] سالبة حين لا تُعرف النسبة، فيتحرّك الشريط بلا قيمة.
  Future<void> show(String text, {int percent, String title});

  /// إشعارٌ أخير يُلمس فيُفتح التطبيق، والخدمة تتوقف.
  Future<void> finish(String text, {String title});

  /// لا إشعار ولا خدمة.
  Future<void> hide();
}

/// لا نظام يستقبل: سطح المكتب والاختبارات.
class SilentDownloadNotifier implements DownloadNotifier {
  const SilentDownloadNotifier();

  @override
  Future<void> show(String text, {int percent = -1, String title = 'تحديث التطبيق'}) async {}

  @override
  Future<void> finish(String text, {String title = 'تحديث التطبيق'}) async {}

  @override
  Future<void> hide() async {}
}

class AndroidDownloadNotifier implements DownloadNotifier {
  const AndroidDownloadNotifier();

  static const _channel = MethodChannel('center/update_download');

  @override
  Future<void> show(String text, {int percent = -1, String title = 'تحديث التطبيق'}) =>
      _send('show', {'text': text, 'percent': percent, 'title': title});

  @override
  Future<void> finish(String text, {String title = 'تحديث التطبيق'}) =>
      _send('finish', {'text': text, 'title': title});

  @override
  Future<void> hide() => _send('hide', const {});

  /// إشعارٌ تعذّر لا يُوقف عملاً جارياً: الإذن قد يكون مرفوضاً، والتنزيل يكمل
  /// ما دام التطبيق على الشاشة.
  Future<void> _send(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {}
  }
}

/// المتاح على هذا الجهاز.
DownloadNotifier defaultDownloadNotifier() =>
    !kIsWeb && Platform.isAndroid ? const AndroidDownloadNotifier() : const SilentDownloadNotifier();
