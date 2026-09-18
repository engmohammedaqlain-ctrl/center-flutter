/// إشعار تنزيل التحديث — وهو أيضاً ما يُبقي التنزيل يعمل بعد الخروج من التطبيق.
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
  Future<void> show(String text, {int percent});

  /// إشعارٌ أخير يُلمس فيُفتح التطبيق، والخدمة تتوقف: تنزيلٌ اكتمل والمستخدم
  /// في تطبيقٍ آخر لا يُفتح له المثبِّت من الخلفية، فيُنادى بالإشعار.
  Future<void> finish(String text);

  /// لا إشعار ولا خدمة.
  Future<void> hide();
}

/// لا نظام يستقبل: سطح المكتب والاختبارات.
class SilentDownloadNotifier implements DownloadNotifier {
  const SilentDownloadNotifier();

  @override
  Future<void> show(String text, {int percent = -1}) async {}

  @override
  Future<void> finish(String text) async {}

  @override
  Future<void> hide() async {}
}

class AndroidDownloadNotifier implements DownloadNotifier {
  const AndroidDownloadNotifier();

  static const _channel = MethodChannel('center/update_download');

  @override
  Future<void> show(String text, {int percent = -1}) =>
      _send('show', {'text': text, 'percent': percent});

  @override
  Future<void> finish(String text) => _send('finish', {'text': text});

  @override
  Future<void> hide() => _send('hide', const {});

  /// إشعارٌ تعذّر لا يُوقف تحديثاً يعمل: الإذن قد يكون مرفوضاً، والتنزيل يكمل
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
