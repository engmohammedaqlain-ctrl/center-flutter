import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

Future<AppStore> school() async {
  final s = AppStore.forTesting();
  await s.bootstrap(FakeDisk());
  injectDemoData(s);
  await s.login('amal', 'amal2026');
  return s;
}

void main() {
  test('the badge does not claim "synced" before the cloud was asked', () async {
    final s = await school();
    expect(
      s.sync.remoteStateKnown,
      isFalse,
      reason: 'بلا فحص لا نعرف حالة السحابة، فلا نطمئن المستخدم',
    );
  });

  test('a fresh check makes the state known', () async {
    final s = await school();
    s.sync.lastRemoteCheck = DateTime.now();
    expect(s.sync.remoteStateKnown, isTrue);
  });

  test('a stale check stops counting as known', () async {
    final s = await school();
    s.sync.lastRemoteCheck = DateTime.now().subtract(const Duration(minutes: 10));
    expect(
      s.sync.remoteStateKnown,
      isFalse,
      reason: 'فحص قديم لا يصلح دليلاً على أن كل شيء متزامن',
    );
  });

  test('the summary is available without touching the network', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    s.setAttendance(student.id, '2026-06-01', 'absent', ownerId: room.id);

    // ما تعرضه ورقة الرفع فور فتحها — بلا انتظار السحابة
    final summary = s.sync.getPendingSummary();
    expect(summary.total, greaterThan(0));
    expect(summary.rows, isNotEmpty);
    expect(summary.items, isNotEmpty);
  });

  test('operation names are labelled in Arabic for the confirm list', () {
    expect(actionLabelsAr['INSERT'], 'إضافة');
    expect(actionLabelsAr['UPDATE'], 'تعديل');
    expect(actionLabelsAr['DELETE'], 'حذف');
  });

  test('each queued operation names the record it touches', () async {
    final s = await school();
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    s.setAttendance(student.id, '2026-06-02', 'present', ownerId: room.id);

    final summary = s.sync.getPendingSummary();
    final attendance = summary.rows.firstWhere((r) => r.table == 'attendance');
    expect(tableLabelsAr[attendance.table], 'الحضور والغياب');
    expect(summary.items.every((i) => i.label.trim().isNotEmpty), isTrue);
  });
}
