import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'supabase.dart';

/// الاستماع اللحظي لتغييرات السحابة — المقابل لـ `setupRealtimeListeners`
/// في `sync.ts` و `useRealtimeListener` في الشاشات.
///
/// بدونه لا يعلم الجهاز بأي تعديل من جهاز آخر حتى يضغط المستخدم «سحب» يدوياً.
class RealtimeListener {
  RealtimeListener({required this.onChange, required this.tables});

  /// يُستدعى باسم الجدول الذي تغيّر في السحابة.
  final void Function(String table) onChange;
  final List<String> tables;

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
    _stopped = false;
    if (_tenantId == tenantId && _channel != null) return;
    await disconnect();
    _tenantId = tenantId;
    _open();
  }

  void _open() {
    final tenantId = _tenantId;
    if (tenantId == null || _stopped) return;

    final base = SupabaseConfig.url.replaceFirst(RegExp(r'^https?'), 'wss');
    final uri = Uri.parse('$base/realtime/v1/websocket?apikey=${SupabaseConfig.key}&vsn=1.0.0');

    try {
      final channel = WebSocketChannel.connect(uri);
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
          },
          'ref': '${_ref++}',
        });
      }

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
      final event = '${decoded['event'] ?? ''}';
      if (event != 'postgres_changes' && event != 'INSERT' && event != 'UPDATE' && event != 'DELETE') {
        return;
      }
      final payload = decoded['payload'];
      String? table;
      if (payload is Map) {
        final data = payload['data'];
        if (data is Map) table = data['table']?.toString();
        table ??= payload['table']?.toString();
      }
      table ??= _tableFromTopic('${decoded['topic'] ?? ''}');
      if (table != null && table.isNotEmpty) onChange(table);
    } catch (_) {
      // رسالة غير متوقعة لا تُسقط الاتصال
    }
  }

  String? _tableFromTopic(String topic) {
    // realtime:public:<table>:<filter>
    final parts = topic.split(':');
    if (parts.length >= 3) return parts[2];
    return null;
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _channel = null;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 8), _open);
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
