/// إشعارات الجوال لولي الأمر وللمدير (Firebase Cloud Messaging) — أندرويد وحده.
///
/// المدير (المالك أو موظف بدور مدير) يُسجَّل جهازه بعد دخوله، فتصله الحوالات وطلبات
/// الموافقة (`kind: approval`). والخادم يرفض تسجيل بقية الأدوار.
///
/// بعد دخول ولي الأمر، ومع كل ابن يبدّل إليه، يُسجَّل توكن الجهاز على الخادم
/// (`register_push_device`) بجلسته؛ والخادم يأخذ المنشأة والطالب من الجلسة لا من
/// الجهاز. الخروج يحذف التوكن قبل إنهاء الجلسة. الخادم يبعث الغياب والأقساط من
/// دالة `push-notify` (مستودع الويب)، والإشعار يحمل `{kind, tenant_id, student_id}`.
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

  /// بعد دخول ولي الأمر وبعد كل تبديل لابن: الجلسة الآن على هذا الابن.
  /// تعذّر الإذن أو الشبكة لا يوقف البوابة.
  Future<void> register() async {
    if (!await _init()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      // نافذة الإذن (أندرويد 13+) مرة في كل تشغيل، بعد الدخول لا عند الإقلاع
      if (!_asked) {
        _asked = true;
        await messaging.requestPermission();
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      _token = token;
      await _send(token);
      _refresh ??= messaging.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(_send(t));
      });
    } catch (e) {
      debugPrint('push register: $e');
    }
  }

  /// بلا أي أثر عند الفشل: قاعدة لم تُنفَّذ عليها الهجرة بعد، أو بلا شبكة، والبوابة
  /// تعمل كما كانت. الدخول التالي أو تبديل الابن يعيد المحاولة.
  Future<void> _send(String token) async {
    try {
      await supabaseRpc('register_push_device', {'p_token': token, 'p_platform': 'android', 'p_app_id': pushAppId});
    } catch (e) {
      debugPrint('push register: $e');
    }
  }

  /// عند الخروج، قبل إنهاء الجلسة: الجهاز لا يستقبل إشعارات من كان عليه.
  Future<void> unregister() async {
    if (!_ready) return;
    await _refresh?.cancel();
    _refresh = null;
    // شبكة ضعيفة لا تعلّق الخروج: بعد المهلة يكمل، ويبقى الجهاز مسجلاً حتى يدخل عليه أحد فيُكتب فوقه
    try {
      await () async {
        final token = _token ?? await FirebaseMessaging.instance.getToken();
        _token = null;
        if (token != null && token.isNotEmpty) {
          await supabaseRpc('unregister_push_device', {'p_token': token});
        }
      }()
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('push unregister: $e');
    }
  }
}
