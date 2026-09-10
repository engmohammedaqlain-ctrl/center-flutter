import 'dart:async';
import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/realtime.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];

  @override
  void add(dynamic data) => sent.add(Map<String, dynamic>.from(jsonDecode('$data') as Map));

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

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
}

String _change(String table, String type, Map<String, dynamic> record, {Map<String, dynamic>? old}) {
  return jsonEncode({
    'event': 'postgres_changes',
    'topic': 'realtime:public:$table:tenant_id=eq.t1',
    'payload': {
      'data': {'table': table, 'type': type, 'record': record, 'old_record': old ?? {}},
      'ids': [1],
    },
  });
}

void main() {
  group('اتصال التحديث اللحظي', () {
    test('الاتصال يُفتح فعلاً ويشترك في كل جدول', () async {
      final channels = <_FakeChannel>[];
      final listener = RealtimeListener(
        tables: const ['students', 'attendance'],
        onChange: (_) {},
        connector: (_) {
          final c = _FakeChannel();
          channels.add(c);
          return c;
        },
      );

      await listener.connect('t1');

      // ترتيب علامة الإيقاف كان يمنع فتح الاتصال أبداً
      expect(channels, hasLength(1));
      expect(listener.isConnected, isTrue);
      final joins = channels.single.fakeSink.sent.where((m) => m['event'] == 'phx_join');
      expect(joins.map((m) => m['topic']), [
        'realtime:public:students:tenant_id=eq.t1',
        'realtime:public:attendance:tenant_id=eq.t1',
      ]);

      await listener.disconnect();
    });

    test('الاتصال يعود بعد الفصل ولمنشأة أخرى', () async {
      final channels = <_FakeChannel>[];
      final listener = RealtimeListener(
        tables: const ['attendance'],
        onChange: (_) {},
        connector: (_) {
          final c = _FakeChannel();
          channels.add(c);
          return c;
        },
      );

      await listener.connect('t1');
      await listener.disconnect();
      expect(listener.isConnected, isFalse);

      await listener.connect('t2');
      expect(channels, hasLength(2));
      expect(listener.isConnected, isTrue);
      expect(channels.last.fakeSink.sent.first['topic'], 'realtime:public:attendance:tenant_id=eq.t2');

      await listener.disconnect();
    });

    test('التغيير يصل بجدوله ونوعه وصفّه', () async {
      final events = <RealtimeEvent>[];
      late _FakeChannel channel;
      final listener = RealtimeListener(
        tables: const ['attendance'],
        onChange: events.add,
        connector: (_) => channel = _FakeChannel(),
      );
      await listener.connect('t1');

      channel.incoming.add(_change('attendance', 'UPDATE', {'id': 'a1', 'status': 'excused'}));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.table, 'attendance');
      expect(events.single.type, 'UPDATE');
      expect(events.single.record['status'], 'excused');

      await listener.disconnect();
    });

    test('قبول الاشتراك يُبلَّغ، ونبض القلب لا', () async {
      var joined = 0;
      late _FakeChannel channel;
      final listener = RealtimeListener(
        tables: const ['attendance'],
        onChange: (_) {},
        onJoined: () => joined++,
        connector: (_) => channel = _FakeChannel(),
      );
      await listener.connect('t1');

      channel.incoming.add(jsonEncode({
        'event': 'phx_reply',
        'topic': 'realtime:public:attendance:tenant_id=eq.t1',
        'payload': {'status': 'ok', 'response': {}},
      }));
      channel.incoming.add(jsonEncode({
        'event': 'phx_reply',
        'topic': 'phoenix',
        'payload': {'status': 'ok', 'response': {}},
      }));
      await Future<void>.delayed(Duration.zero);

      expect(joined, 1);
      await listener.disconnect();
    });

    test('الحذف يُقرأ من الصف القديم', () {
      final e = RealtimeListener.parse(
        jsonDecode(_change('attendance', 'DELETE', {}, old: {'id': 'a1'})) as Map,
      );
      expect(e?.type, 'DELETE');
      expect(e?.record['id'], 'a1');
    });

    test('ما ليس تغييراً لا يُقرأ تغييراً', () {
      expect(RealtimeListener.parse({'event': 'system', 'payload': {'status': 'ok'}}), isNull);
    });
  });

  group('تنبيه السحب من الحدث', () {
    AppStore seeded() {
      final s = AppStore.forTesting();
      injectDemoData(s);
      s.sync.remotePendingIds.clear();
      s.pendingSyncs.clear();
      return s;
    }

    RealtimeEvent update(String table, String id, String at) =>
        RealtimeEvent(table: table, type: 'UPDATE', record: {'id': id, 'updated_at': at});

    test('تعديل من جهاز آخر أحدث من نسختنا يُظهر سحباً', () {
      final s = seeded();
      final st = s.students.first..updatedAt = '2026-09-10T18:00:00.000Z';
      s.handleRemoteEvent(update('students', st.id, '2026-09-10T18:56:00.735Z'));
      expect(s.pendingPull, 1);
    });

    test('صدى تعديلنا نحن لا يُحسب', () {
      final s = seeded();
      final st = s.students.first..updatedAt = '2026-09-10T18:56:00.735Z';
      s.handleRemoteEvent(update('students', st.id, '2026-09-10T18:56:00.735Z'));
      expect(s.pendingPull, 0);
    });

    test('سجل ينتظر الرفع عندنا لا يُحسب قادماً', () {
      final s = seeded();
      final st = s.students.first..updatedAt = '2026-09-10T18:00:00.000Z';
      queuePendingSync(s.pendingSyncs, tableName: 'students', recordId: st.id, action: 'UPDATE', payload: {'id': st.id});
      s.handleRemoteEvent(update('students', st.id, '2026-09-10T18:56:00.000Z'));
      expect(s.pendingPull, 0);
    });

    test('صف جديد لم نره يُحسب', () {
      final s = seeded();
      s.handleRemoteEvent(update('attendance', 'c4a6d578', '2026-09-10T18:56:00.735Z'));
      expect(s.pendingPull, 1);
    });

    test('الحذف يُحسب فقط إن كان السجل عندنا', () {
      final s = seeded();
      s.handleRemoteEvent(const RealtimeEvent(table: 'students', type: 'DELETE', record: {'id': 'not-here'}));
      expect(s.pendingPull, 0);
      s.handleRemoteEvent(RealtimeEvent(table: 'students', type: 'DELETE', record: {'id': s.students.first.id}));
      expect(s.pendingPull, 1);
    });

    test('تغيير منشأة أخرى أو جدول غير مزامَن يُتجاهل', () {
      final s = seeded();
      s.handleRemoteEvent(const RealtimeEvent(
        table: 'attendance',
        type: 'INSERT',
        record: {'id': 'x1', 'tenant_id': 'another-tenant'},
      ));
      s.handleRemoteEvent(const RealtimeEvent(table: 'tenants', type: 'INSERT', record: {'id': 'x2'}));
      expect(s.pendingPull, 0);
    });

    test('أحداث متلاحقة لا يسقط منها شيء، والسجل الواحد يُحسب مرة', () {
      // التجميع السابق كان يُسقط كل حدث يلي آخر بأقل من ثانية
      final s = seeded();
      for (final st in s.students.take(3)) {
        st.updatedAt = '2026-09-10T18:00:00.000Z';
        s.handleRemoteEvent(update('students', st.id, '2026-09-10T18:56:00.000Z'));
      }
      s.handleRemoteEvent(update('students', s.students.first.id, '2026-09-10T18:57:00.000Z'));
      expect(s.pendingPull, 3);
    });
  });
}
