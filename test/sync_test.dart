import 'package:center_mobile/data/phone.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queuePendingSync merges consecutive updates and cancels insert-then-delete', () {
    final queue = <PendingSync>[];
    queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'INSERT', payload: {'full_name': 'أ'});
    expect(queue.length, 1);
    expect(queue.first.action, 'INSERT');

    queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'UPDATE', payload: {'full_name': 'ب', 'phone': '0599111222'});
    expect(queue.length, 1);
    expect(queue.first.action, 'INSERT');
    expect(queue.first.payload?['full_name'], 'ب');
    expect(queue.first.payload?['phone'], '0599111222');
    expect(queue.first.payload?['id'], 's1');
    expect(queue.first.retryCount, 0);

    queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'DELETE', payload: null);
    expect(queue, isEmpty);

    queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'UPDATE', payload: {'full_name': 'ج'});
    queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'DELETE', payload: null);
    expect(queue.length, 1);
    expect(queue.first.action, 'DELETE');
    expect(queue.first.payload, isNull);
  });

  test('sanitizePayload keeps allowed student columns, nulls empty dates, stamps tenant', () {
    final clean = sanitizePayload(
      'students',
      {
        'id': 'x',
        'full_name': 'محمد',
        'birth_date': '',
        'balance': 0,
        'sync_status': 'pending',
        'unknown_field': 'drop me',
      },
      'tenant-1',
    );
    expect(clean['full_name'], 'محمد');
    expect(clean.containsKey('unknown_field'), isFalse);
    expect(clean.containsKey('sync_status'), isFalse);
    expect(clean['birth_date'], isNull);
    expect(clean['tenant_id'], 'tenant-1');
    expect(clean['balance'], 0);
  });

  test('sanitizePayload maps enrollments enrolled_at to enrollment_date', () {
    final clean = sanitizePayload(
      'enrollments',
      {'id': 'e1', 'enrolled_at': '2026-09-01T10:00:00.000Z'},
      't1',
    );
    expect(clean['enrollment_date'], '2026-09-01');
    expect(clean['tenant_id'], 't1');
  });

  test('toTimestamp compares instants not string formats', () {
    final a = toTimestamp('2026-09-07T20:22:01.123Z');
    final b = toTimestamp('2026-09-07T20:22:01.123456+00:00');
    expect((a - b).abs() < stampToleranceMs, isTrue);
    expect(toTimestamp(null), 0);
    expect(toTimestamp(''), 0);
  });

  test('الترشيح التزايدي لا يُسأل عنه إلا جدول يملك updated_at', () {
    // سؤال جدول بلا العمود يردّه PostgREST بـ 400 فيسقط الجدول من السحب
    expect(tableHasUpdatedAt('students'), isTrue);
    expect(tableHasUpdatedAt('attendance'), isTrue);
    expect(tableHasUpdatedAt('student_evaluations'), isTrue);
    expect(tableHasUpdatedAt('class_announcements'), isFalse);

    for (final t in syncedTables) {
      if (tableHasUpdatedAt(t)) {
        expect(tableAllowedColumns[t], contains('updated_at'), reason: t);
      }
    }
  });

  test('phone prefix helpers match Center phoneUtils', () {
    expect(combinePhoneAndPrefix('9111222', '059'), '0599111222');
    expect(parsePhoneAndPrefix('0599111222').prefix, '059');
    expect(parsePhoneAndPrefix('0599111222').number, '9111222');
    expect(phoneTargetLength('059'), 7);
    expect(phoneTargetLength('+970'), 9);
    expect(isPhoneComplete('9111222', '059'), isTrue);
    expect(getWhatsAppPhone('0599111222'), '970599111222');
    expect(digitsOnly('٠٥٩'), '059');
  });
}
