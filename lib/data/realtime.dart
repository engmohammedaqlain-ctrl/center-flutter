import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'supabase.dart';

/// تغيير واحد وصل من السحابة.
class RealtimeEvent {
  const RealtimeEvent({required this.table, required this.type, required this.record});

  final String table;

  /// `INSERT` أو `UPDATE` أو `DELETE`.
  final String type;

  /// الصف الجديد، أو القديم في الحذف — وهو يحمل المفتاح وحده غالباً.
  final Map<String, dynamic> record;
}

/// الاستماع اللحظي لتغييرات السحابة — المقابل لـ `setupRealtimeListeners`
/// في `sync.ts` و `useRealtimeListener` في الشاشات.
///
/// بدونه لا يعلم الجهاز بأي تعديل من جهاز آخر حتى يضغط المستخدم «سحب» يدوياً.
class RealtimeListener {
  RealtimeListener({
    required this.onChange,
    required this.tables,
    this.onJoined,
    this.onBroadcast,
    @visibleForTesting WebSocketChannel Function(Uri uri)? connector,
  }) : _connector = connector ?? WebSocketChannel.connect;

  /// يُستدعى حين يُعلن جهازٌ آخر في المنشأة أن بياناتها تغيّرت.
  final void Function()? onBroadcast;

  /// قناة المنشأة كما يفتحها sync.ts: `supabase.channel('tenant-<id>')`.
  static String broadcastTopic(String tenantId) => 'realtime:tenant-$tenantId';

  /// يُستدعى لكل تغيير بجدوله وصفّه.
  final void Function(RealtimeEvent event) onChange;

  /// يُستدعى عند قبول الاشتراك — بعد الاتصال الأول وبعد كل إعادة اتصال.
  final void Function()? onJoined;

  final List<String> tables;
  final WebSocketChannel Function(Uri uri) _connector;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  String? _tenantId;
  int _ref = 0;
  bool _stopped = false;

  bool get isConnected => _channel != null;

  /// فتح الاتصال لمنشأة محددة. استدعاؤه مرة أخرى يعيد الاتصال.
  Future<void> connect(String tenantId) async {
    if (_tenantId == tenantId && _channel != null && !_stopped) return;
    await disconnect();
    // `disconnect` يرفع علامة الإيقاف، فتُنزل بعده لا قبله. الترتيب المعكوس
    // كان يجعل `_open` يعود فوراً فلا يُفتح الاتصال أبداً، ولا يصل أي تعديل
    // من جهاز آخر إلا بفحص يدوي.
    _stopped = false;
    _tenantId = tenantId;
    _open();
  }

  void _open() {
    final tenantId = _tenantId;
    if (tenantId == null || _stopped) return;

    final base = SupabaseConfig.url.replaceFirst(RegExp(r'^https?'), 'wss');
    final uri = Uri.parse('$base/realtime/v1/websocket?apikey=${SupabaseConfig.key}&vsn=1.0.0');

    try {
      final channel = _connector(uri);
      _channel = channel;

      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );

      // اشتراك واحد لكل جدول، مقيّد بمعرّف المنشأة حتى لا تصل تغييرات غيرها
      for (final table in tables) {
        _send({
          'topic': 'realtime:public:$table:tenant_id=eq.$tenantId',
          'event': 'phx_join',
          'payload': {
            'config': {
              'postgres_changes': [
                {'event': '*', 'schema': 'public', 'table': table, 'filter': 'tenant_id=eq.$tenantId'},
              ],
            },
            // سياسات RLS تحكم التغييرات اللحظية أيضاً: بلا توكن الجلسة لا يصل
            // الجهازَ تعديلٌ واحد من الأجهزة الأخرى
            if (SupabaseAuth.accessToken != null) 'access_token': SupabaseAuth.accessToken,
          },
          'ref': '${_ref++}',
        });
      }

      // قناة الإشارة: الويب يُعلن فيها بعد كل رفع ويستمع لها وحدها، فبلا
      // الانضمام إليها لا يصل الجهازَ رفعُ الويب ولا يصل الويبَ رفعُ الجهاز
      _send({
        'topic': broadcastTopic(tenantId),
        'event': 'phx_join',
        'payload': {
          'config': {
            'broadcast': {'ack': false, 'self': false},
            'presence': {'key': ''},
            'postgres_changes': <Object>[],
          },
          if (SupabaseAuth.accessToken != null) 'access_token': SupabaseAuth.accessToken,
        },
        'ref': '${_ref++}',
      });

      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'topic': 'phoenix', 'event': 'heartbeat', 'payload': {}, 'ref': '${_ref++}'});
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode('$raw');
      if (decoded is! Map) return;

      // قبول الاشتراك. ردود نبض القلب تحمل الموضوع `phoenix` فتُستثنى.
      if (decoded['event'] == 'phx_reply') {
        final payload = decoded['payload'];
        if (payload is Map && payload['status'] == 'ok' && '${decoded['topic']}'.startsWith('realtime:')) {
          onJoined?.call();
        }
        return;
      }

      if (decoded['event'] == 'broadcast') {
        final payload = decoded['payload'];
        if (payload is Map && payload['event'] == 'changed') onBroadcast?.call();
        return;
      }

      final event = parse(decoded);
      if (event != null) onChange(event);
    } catch (_) {
      // رسالة غير متوقعة لا تُسقط الاتصال
    }
  }

  /// قراءة تغيير من رسالة الخادم، أو `null` إن لم تكن تغييراً.
  @visibleForTesting
  static RealtimeEvent? parse(Map<dynamic, dynamic> message) {
    final event = '${message['event'] ?? ''}';
    final payload = message['payload'];
    if (payload is! Map) return null;

    final Map<dynamic, dynamic> data;
    if (event == 'postgres_changes') {
      final inner = payload['data'];
      if (inner is! Map) return null;
      data = inner;
    } else if (event == 'INSERT' || event == 'UPDATE' || event == 'DELETE') {
      data = payload; // صيغة البروتوكول القديمة
    } else {
      return null;
    }

    final table = '${data['table'] ?? ''}';
    final type = '${data['type'] ?? event}'.toUpperCase();
    final record = data['record'];
    final old = data['old_record'];
    final source = record is Map && record.isNotEmpty ? record : old;
    if (table.isEmpty || source is! Map) return null;

    return RealtimeEvent(table: table, type: type, record: Map<String, dynamic>.from(source));
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _channel = null;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    // الخادم يُغلق القناة حين ينتهي توكن الجلسة: يُجدَّد قبل إعادة الانضمام،
    // وإلا عادت القناة بالتوكن المنتهي نفسه فأُغلقت فوراً في حلقة لا تنتهي
    _reconnect = Timer(const Duration(seconds: 8), () async {
      await SupabaseAuth.ensureFresh();
      _open();
    });
  }

  /// إعلام أجهزة المنشأة بأن بياناتها تغيّرت — `notifyPeers` في sync.ts.
  void broadcastChanged() {
    final tenantId = _tenantId;
    if (tenantId == null || _channel == null) return;
    _send({
      'topic': broadcastTopic(tenantId),
      'event': 'broadcast',
      'payload': {'type': 'broadcast', 'event': 'changed', 'payload': <String, dynamic>{}},
      'ref': '${_ref++}',
    });
  }

  Future<void> disconnect() async {
    _stopped = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _heartbeat = null;
    _reconnect = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {
      // الاتصال مغلق أصلاً
    }
    _channel = null;
    _tenantId = null;
  }
}
