/// إنذار الأعطال: كل خطأ غير معالج يُسجَّل في السحابة (`report_client_error`،
/// الهجرة 20261103_client_errors.sql في مستودع الويب)، ويصل المطورَ إشعار على جواله.
///
/// المدرسة والدور من الجلسة على الخادم؛ من هنا المنصة والإصدار والشاشة (أول ملف من
/// التطبيق في مسار الخطأ) ونص الخطأ مختصراً بلا بيانات شخصية. أخطاء الشبكة والجلسة
/// وإلغاء الطلب ليست أعطالاً فلا تُرسل. التشغيل الواحد لا يرسل نفس الخطأ أكثر من مرة
/// في 10 دقائق، ولا أكثر من 10 أخطاء، والخادم يحدّ أيضاً. فشل الإرسال صامت.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update.dart';
import 'supabase.dart';

const _networkTypes = {
  'SocketException',
  'HttpException',
  'ClientException',
  'TimeoutException',
  'HandshakeException',
  'TlsException',
  'NetworkImageLoadException',
};

final _network = RegExp(
  r'failed to fetch|network ?error|network request failed|aborted|cancell?ed|jwt expired|invalid jwt'
  r'|refresh token|not authenticated|\b401\b|socketexception|clientexception|connection (closed|refused|reset|timed out|abort)'
  r'|handshakeexception|failed host lookup|timeoutexception|xmlhttprequest error|software caused connection abort',
  caseSensitive: false,
);

/// نوع الخطأ كما يُكتب: `_TypeError` يصير `TypeError`.
String errorKind(Object error) {
  final name = error.runtimeType.toString().replaceFirst(RegExp(r'^_+'), '');
  return name.length > 80 ? name.substring(0, 80) : name;
}

/// ليس عطلاً: انقطاع الشبكة، انتهاء الجلسة، إلغاء طلب.
bool isIgnorableError(String kind, String message) {
  if (message.trim().isEmpty) return true;
  if (_networkTypes.contains(kind)) return true;
  return _network.hasMatch(message);
}

/// بلا بيانات شخصية: البريد والتوكنات وقيم مفاتيح القاعدة والأرقام الطويلة (هوية، جوال).
String scrubText(String text, int max) {
  final out = text
      .replaceAll(RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '<email>')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]+)*'), '<token>')
      .replaceAll(RegExp(r'\)=\([^)]*\)'), ')=(…)')
      .replaceAll(RegExp(r'\d{5,}'), '#')
      .trim();
  return out.length > max ? out.substring(0, max) : out;
}

/// الشاشة: أول ملف من التطبيق نفسه في مسار الخطأ (`screens/finance_screen.dart`).
String screenOf(String stack) {
  final match = RegExp(r'package:center_mobile/([\w/]+\.dart)').firstMatch(stack);
  return match?.group(1) ?? '';
}

class ErrorReport {
  ErrorReport._();

  static final instance = ErrorReport._();

  static const _maxPerRun = 10;
  static const _repeat = Duration(minutes: 10);

  var _sent = 0;
  final _last = <String, DateTime>{};
  Future<String>? _version;

  /// أول ما في `main`: أخطاء الإطار (البناء والرسم) وما يفلت من أي `Future`.
  /// السلوك المعتاد يبقى كما هو: العرض في السجل، ولا يتوقف التطبيق.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      // الصامت (صورة شبكة لم تُحمَّل مثلاً) ليس عطلاً
      if (!details.silent) report(details.exception, details.stack);
    };
    final previousDispatcher = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return previousDispatcher?.call(error, stack) ?? false;
    };
  }

  /// يرسل الخطأ مرة، بلا انتظار وبلا أي أثر عند الفشل.
  void report(Object error, StackTrace? stack) {
    try {
      final kind = errorKind(error);
      final message = scrubText('$error', 500);
      if (isIgnorableError(kind, message)) return;
      final trace = (stack ?? StackTrace.empty).toString().split('\n').take(12).join('\n');
      final screen = screenOf(trace);
      final key = '$kind|${message.split('\n').first}|$screen';
      final now = DateTime.now();
      final last = _last[key];
      if (_sent >= _maxPerRun || (last != null && now.difference(last) < _repeat)) return;
      _sent++;
      _last[key] = now;
      unawaited(_send(kind, message, scrubText(trace, 1500), screen));
    } catch (_) {
      // الإنذار لا يولّد عطلاً
    }
  }

  Future<void> _send(String kind, String message, String stack, String screen) async {
    try {
      final version = await (_version ??= _readVersion());
      await supabaseRpc('report_client_error', {
        'p_kind': kind,
        'p_message': message,
        'p_stack': stack,
        'p_route': screen,
        'p_platform': kIsWeb ? 'flutter-web' : defaultTargetPlatform.name,
        'p_version': version,
      });
    } catch (_) {
      // بلا شبكة أو قبل تنفيذ الهجرة
    }
  }

  static Future<String> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final patch = await currentPatchNumber();
      return '${info.version}+${info.buildNumber}${patch > 0 ? '.$patch' : ''}';
    } catch (_) {
      return '';
    }
  }
}
