import 'dart:async';
import 'dart:convert';

import 'package:center_mobile/data/realtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(Map<String, dynamic>.from(jsonDecode('$data') as Map));

  @override
  Future<void> close([int? closeCode, String? closeReason]) async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final fakeSink = _FakeSink();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Iterable<Map<String, dynamic>> get heartbeats => fakeSink.sent.where((m) => m['event'] == 'heartbeat');

  void reply(Map<String, dynamic> heartbeat) => incoming.add(jsonEncode({
        'event': 'phx_reply',
        'topic': 'phoenix',
        'ref': heartbeat['ref'],
        'payload': {'status': 'ok', 'response': {}},
      }));
}

RealtimeListener _listener(List<_FakeChannel> channels, {void Function()? onJoined}) => RealtimeListener(
      tables: const ['students'],
      onChange: (_) {},
      onJoined: onJoined,
      connector: (_) {
        final c = _FakeChannel();
        channels.add(c);
        return c;
      },
    );

void main() {
  group('حياة الاتصال اللحظي', () {
    test('نبضٌ بلا رد يعيد الاتصال — المقبس الميت بصمت لا يبقى «متصلاً»', () async {
      final channels = <_FakeChannel>[];
      final listener = _listener(channels);
      await listener.connect('t1');

      // نبضة يُرد عليها: الاتصال حي، لا إعادة
      listener.heartbeatTick();
      channels.single.reply(channels.single.heartbeats.last);
      await Future<void>.delayed(Duration.zero);
      listener.heartbeatTick();
      expect(channels, hasLength(1));

      // النبضة الأخيرة بلا رد: التالية تُغلق المقبس وتفتح غيره
      listener.heartbeatTick();
      expect(channels.first.fakeSink.closed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(channels, hasLength(2));
      expect(channels.last.fakeSink.sent.where((m) => m['event'] == 'phx_join'), isNotEmpty);

      await listener.disconnect();
    });

    test('العودة إلى التطبيق بعد صمتٍ طويل تعيد الاتصال فوراً', () async {
      final channels = <_FakeChannel>[];
      final listener = _listener(channels);
      await listener.connect('t1');

      // رسالة حديثة: لا إعادة
      listener.ensureAlive(DateTime.now().add(const Duration(seconds: 10)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(channels, hasLength(1));

      // صمتٌ أطول من نبضة وهامش
      listener.ensureAlive(DateTime.now().add(RealtimeListener.silenceLimit + const Duration(seconds: 1)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(channels, hasLength(2));

      await listener.disconnect();
    });

    test('إغلاق الخادم لقناةٍ يعيد الاتصال بدل البقاء بلا تغييرات', () async {
      final channels = <_FakeChannel>[];
      final listener = _listener(channels);
      await listener.connect('t1');

      channels.single.incoming.add(jsonEncode({
        'event': 'phx_close',
        'topic': 'realtime:public:students:tenant_id=eq.t1',
        'payload': {},
        'ref': null,
      }));
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(channels, hasLength(2));

      await listener.disconnect();
    });

    test('التوكن المجدَّد يُرسل لكل قناة مفتوحة', () async {
      final channels = <_FakeChannel>[];
      final listener = _listener(channels);
      await listener.connect('t1');

      listener.updateAccessToken('new-token');
      final sent = channels.single.fakeSink.sent.where((m) => m['event'] == 'access_token').toList();
      expect(sent.map((m) => m['topic']), ['realtime:public:students:tenant_id=eq.t1', 'realtime:tenant-t1']);
      expect(sent.every((m) => (m['payload'] as Map)['access_token'] == 'new-token'), isTrue);

      await listener.disconnect();
    });
  });
}
