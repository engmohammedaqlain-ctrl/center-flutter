/// إشعارات الجوال لولي الأمر والطالب والمعلم والمدير (Firebase Cloud Messaging) — أندرويد وحده.
///
/// المدير (المالك أو موظف بدور مدير) يُسجَّل جهازه بعد دخوله، فتصله الحوالات وطلبات
/// الموافقة (`kind: approval`) وردود الأهل على ملاحظات الإدارة (`note_reply`).
/// والخادم يرفض تسجيل بقية موظفي الإدارة.
///
/// بعد دخول ولي الأمر أو الطالب أو المعلم (ومع كل ابن يبدّل إليه ولي الأمر) يُسجَّل
/// توكن الجهاز على الخادم (`register_push_device`) بجلسته؛ والخادم يأخذ المنشأة
/// والدور والطالب أو المعلم من الجلسة لا من الجهاز. الخروج يحذف التوكن قبل إنهاء
/// الجلسة. الخادم يبعث من دالة `push-notify` (مستودع الويب)، والإشعار يحمل
/// `{kind, tenant_id, student_id}`، ومع الملاحظات `note_id`.
///
/// من يصله ماذا (الخادم يقرر): ولي الأمر كل شيء عن ابنه، والطالب الملاحظة الموجّهة
/// له والإعلان، والمعلم رد ولي الأمر على ملاحظته.
///
/// قناة الإشعارات `school` («المدرسة») تُنشأ في MainActivity، وهي القناة التي
/// يذكرها الخادم في كل رسالة.
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'play_store.dart';
import 'supabase.dart';

/// معرّف التطبيق الذي يُسجَّل به الجهاز: نسخة المتجر أو نسخ GitHub.
const pushAppId = playStore ? 'com.noonschool.app' : 'com.center.center_mobile';

/// إشعار لُمس أو وصل والتطبيق مفتوح.
class PushNotice {
  const PushNotice({
    required this.kind,
    required this.studentId,
    this.noteId = '',
    this.title = '',
    this.body = '',
  });

  /// `absence` أو `installments` أو `payment` لولي الأمر، و`note` للأسرة،
  /// و`announcement` لولي الأمر والطالب، و`note_reply` للمعلم والمدير،
  /// و`approval` للمدير، أو `test`.
  final String kind;
  final String studentId;

  /// الملاحظة الأصل (المحادثة) مع `note` و`note_reply`.
  final String noteId;
  final String title;
  final String body;

  /// التبويب الذي يُفتح عليه ملف الطالب. الملاحظة: «المواد»، وعليها محادثة المعلم.
  String? get tab => switch (kind) {
        'absence' => 'attendance',
        'installments' || 'payment' => 'financial',
        'note' => 'subjects',
        _ => null,
      };

  static PushNotice fromMessage(RemoteMessage m) => PushNotice(
        kind: '${m.data['kind'] ?? ''}',
        studentId: '${m.data['student_id'] ?? ''}',
        noteId: '${m.data['note_id'] ?? ''}',
        title: m.notification?.title ?? '',
        body: m.notification?.body ?? '',
      );
}

class ParentPush {
  ParentPush._();

  static final instance = ParentPush._();

  /// خارج أندرويد (الويب والاختبارات وسطح المكتب) كل شيء بلا أثر.
  bool get supported => !kIsWeb && Platform.isAndroid;

  bool _ready = false;
  bool _asked = false;
  String? _token;
  StreamSubscription<String>? _refresh;

  final _opened = StreamController<PushNotice>.broadcast();
  final _received = StreamController<PushNotice>.broadcast();

  /// إشعار لمسه المستخدم: والتطبيق في الخلفية، أو مغلق ففتحه (يصل بعد أول
  /// [register]، والبوابة تستمع قبل أن تستدعيه).
  Stream<PushNotice> get opened => _opened.stream;

  /// إشعار وصل والتطبيق على الشاشة: أندرويد لا يعرضه، فتعرضه البوابة.
  Stream<PushNotice> get received => _received.stream;

  PushNotice? _pendingOpen;

  /// إشعار لُمس ولا شاشة تستمع بعد (بوابة المعلم تُفتح بعد صفحة التجهيز التي
  /// تسجّل الجهاز): يبقى لأول شاشة تأخذه بـ [takePendingOpen].
  void _open(PushNotice n) {
    if (_opened.hasListener) {
      _opened.add(n);
    } else {
      _pendingOpen = n;
    }
  }

  PushNotice? takePendingOpen() {
    final n = _pendingOpen;
    _pendingOpen = null;
    return n;
  }

  Future<bool> _init() async {
    if (_ready) return true;
    if (!supported) return false;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(PushNotice.fromMessage(m)));
      FirebaseMessaging.onMessage.listen((m) => _received.add(PushNotice.fromMessage(m)));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _open(PushNotice.fromMessage(initial));
      _ready = true;
    } catch (e) {
      debugPrint('push init: $e');
    }
    return _ready;
  }

  /// التسجيل والحذف بالترتيب: الحذف ينتهي على الخادم قبل أي تسجيل بعده، فلا يصل
  /// حذف متأخر (خروج على شبكة بطيئة) بعد دخول جديد فيمسحه.
  Future<void> _queue = Future.value();

  Future<void> _serial(Future<void> Function() op) {
    final run = _queue.then((_) => op());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// أقصى انتظار للحذف قبل أن يُسمح بتسجيل بعده. بعده يحمي الخادمُ التسجيلَ
  /// الجديد: الحذف يتجاهل جهازاً سُجّل في آخر 15 ثانية (20261101_push_unregister_guard.sql).
  static const _unregisterCap = Duration(seconds: 12);

  /// بعد دخول ولي الأمر أو الطالب أو المعلم أو المدير، وبعد كل تبديل لابن: الجلسة
  /// الآن على هذا الحساب. تعذّر الإذن أو الشبكة لا يوقف البوابة.
  Future<void> register() async {
    if (!await _init()) return;
    try {
      // نافذة الإذن (أندرويد 13+) مرة في كل تشغيل، بعد الدخول لا عند الإقلاع
      if (!_asked) {
        _asked = true;
        await FirebaseMessaging.instance.requestPermission();
      }
    } catch (e) {
      debugPrint('push permission: $e');
    }
    await _serial(_register);
  }

  Future<void> _register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      _token = token;
      await _send(token);
      _refresh ??= messaging.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(_serial(() => _send(t)));
      });
    } catch (e) {
      debugPrint('push register: $e');
    }
  }

  /// بلا أي أثر عند الفشل: قاعدة لم تُنفَّذ عليها الهجرة بعد، أو بلا شبكة، والبوابة
  /// تعمل كما كانت. الدخول التالي أو تبديل الابن يعيد المحاولة.
  /// المطور جهازه بلا منشأة، فتسجيله بدالة وحدها (`register_dev_push_device`):
  /// تصله إنذارات الأعطال (`kind: client_error`، 20261103_client_errors.sql).
  Future<void> _send(String token) async {
    try {
      final fn = SupabaseAuth.isDeveloper ? 'register_dev_push_device' : 'register_push_device';
      await supabaseRpc(fn, {'p_token': token, 'p_platform': 'android', 'p_app_id': pushAppId});
    } catch (e) {
      debugPrint('push register: $e');
    }
  }

  /// عند الخروج، قبل إنهاء الجلسة: الجهاز لا يستقبل إشعارات من كان عليه.
  ///
  /// الخروج لا ينتظر شبكة ضعيفة أكثر من 4 ثوانٍ، لكن أي تسجيل بعده ينتظر انتهاء
  /// الحذف نفسه (حتى [_unregisterCap]).
  Future<void> unregister() async {
    if (!supported) return;
    try {
      await _serial(_unregister).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('push unregister: $e');
    }
  }

  Future<void> _unregister() async {
    await _refresh?.cancel();
    _refresh = null;
    try {
      await () async {
        // جلسة رُفضت قبل أن تسجّل البوابة الجهاز في هذا التشغيل: التوكن من Firebase
        // مباشرة، بلا [_init] كي لا يُستهلك إشعار فتح التطبيق قبل أن تستمع البوابة
        if (!_ready) await Firebase.initializeApp();
        final token = _token ?? await FirebaseMessaging.instance.getToken();
        _token = null;
        if (token != null && token.isNotEmpty) {
          await supabaseRpc('unregister_push_device', {'p_token': token});
        }
      }()
          .timeout(_unregisterCap);
    } catch (e) {
      debugPrint('push unregister: $e');
    }
  }
}
