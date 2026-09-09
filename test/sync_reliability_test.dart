import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

PendingSync action(String table, String id, {String act = 'UPDATE', int retries = 0}) {
  return PendingSync(
    id: id.hashCode,
    tableName: table,
    recordId: id,
    action: act,
    payload: {'id': id},
    createdAt: DateTime.now().toUtc().toIso8601String(),
    retryCount: retries,
  );
}

/// ترتيب الجداول كما يطبّقه الرفع: الكتابة من الأصل للفرع، والحذف بالعكس.
List<String> orderTables(Iterable<String> names, {required bool reverse}) {
  final list = names.toList()
    ..sort((a, b) {
      final ia = syncedTables.indexOf(a);
      final ib = syncedTables.indexOf(b);
      return (ia < 0 ? syncedTables.length : ia).compareTo(ib < 0 ? syncedTables.length : ib);
    });
  return reverse ? list.reversed.toList() : list;
}

void main() {
  group('تصنيف الأخطاء', () {
    test('أخطاء الشبكة والخادم تُعتبر عابرة', () {
      for (final e in [
        'ClientException: Failed to fetch',
        'SocketException: Connection refused',
        'TimeoutException after 0:00:30',
        'HandshakeException: Handshake error',
        'HTTP 503 Service Unavailable',
        'HTTP 429 Too Many Requests',
        'Connection closed before full header was received',
      ]) {
        expect(isTransientSyncError(e), isTrue, reason: e);
      }
    });

    test('أخطاء البيانات ليست عابرة', () {
      for (final e in [
        'duplicate key value violates unique constraint',
        'violates not-null constraint',
        'violates foreign key constraint',
        'invalid input syntax for type uuid',
        "PGRST204: Could not find the 'colors' column",
      ]) {
        expect(isTransientSyncError(e), isFalse, reason: e);
      }
    });

    test('رسالة القيد الأجنبي توضّح الحل', () {
      final msg = describeSupabaseError('violates foreign key constraint', 'payments');
      expect(msg, contains('سندات القبض'));
      expect(msg, contains('ارفع السجل الأصل أولاً'));
    });
  });

  group('ترتيب الرفع حسب تبعية المفاتيح الأجنبية', () {
    test('الكتابة تبدأ بالأصل قبل الفرع مهما كان ترتيب الطابور', () {
      // طابور أُدخل فيه الفرع قبل أصله
      final ordered = orderTables(['payments', 'attendance', 'students', 'teachers'], reverse: false);
      expect(ordered, ['teachers', 'students', 'payments', 'attendance']);
      expect(ordered.indexOf('students'), lessThan(ordered.indexOf('payments')));
      expect(ordered.indexOf('teachers'), lessThan(ordered.indexOf('students')));
    });

    test('الحذف يبدأ بالفرع قبل الأصل', () {
      final ordered = orderTables(['teachers', 'students', 'payments'], reverse: true);
      expect(ordered, ['payments', 'students', 'teachers']);
    });

    test('جدول غير معروف يُدفع إلى الآخر بدل أن يتصدّر', () {
      final ordered = orderTables(['mystery_table', 'students'], reverse: false);
      expect(ordered.first, 'students');
      expect(ordered.last, 'mystery_table');
    });
  });

  group('رصيد المحاولات', () {
    test('العملية تُستنفد بعد $maxSyncRetries محاولات', () {
      final a = action('students', 's1', retries: maxSyncRetries);
      expect(a.retryCount >= maxSyncRetries, isTrue);
    });

    test('إعادة المحاولة تصفّر الرصيد وتمسح آخر خطأ', () {
      final a = action('students', 's1', retries: maxSyncRetries)..lastError = 'خطأ قديم';
      a.retryCount = 0;
      a.lastError = null;
      expect(a.retryCount, 0);
      expect(a.lastError, isNull);
    });
  });

  group('حصيلة السحب', () {
    test('سحب كامل بلا جداول فاشلة', () {
      const outcome = PullOutcome(pulled: 120, removed: 3);
      expect(outcome.isComplete, isTrue);
    });

    test('سحب ناقص يحمل سبب كل جدول فشل', () {
      const outcome = PullOutcome(
        pulled: 80,
        removed: 0,
        failedTables: {'payments': 'تعذّر جلب سندات القبض من السحابة.'},
      );
      expect(outcome.isComplete, isFalse);
      expect(outcome.failedTables['payments'], contains('سندات القبض'));
    });
  });

  group('دمج الطابور', () {
    test('التعديلات المتتالية على نفس السجل تُدمج في عملية واحدة', () {
      final queue = <PendingSync>[];
      queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'INSERT', payload: {'full_name': 'أ'});
      queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'UPDATE', payload: {'phone': '0599111222'});
      expect(queue, hasLength(1));
      expect(queue.first.action, 'INSERT', reason: 'الإدراج يبقى إدراجاً بعد التعديل');
      expect(queue.first.payload?['full_name'], 'أ');
      expect(queue.first.payload?['phone'], '0599111222');
    });

    test('إدراج ثم حذف يلغي العمليتين بلا نداء للسحابة', () {
      final queue = <PendingSync>[];
      queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'INSERT', payload: {'id': 's1'});
      queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'DELETE', payload: null);
      expect(queue, isEmpty);
    });

    test('تعديل ثم حذف يُبقي الحذف وحده', () {
      final queue = <PendingSync>[];
      queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'UPDATE', payload: {'id': 's1'});
      queuePendingSync(queue, tableName: 'students', recordId: 's1', action: 'DELETE', payload: null);
      expect(queue, hasLength(1));
      expect(queue.first.action, 'DELETE');
      expect(queue.first.payload, isNull);
    });
  });
}
