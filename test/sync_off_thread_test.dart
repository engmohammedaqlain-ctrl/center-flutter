import 'dart:convert';

import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'performance_test.dart' show bigSchool;
import 'persistence_test.dart' show FakeDisk;

/// المزامنة لا تلمس خيط الواجهة: فكّ الردود وترميزها خارجه، وخريطة المعرّفات
/// تُبنى قبل التطبيق على شرائح — بلا أن يتغيّر ما يُكتب في الذاكرة.
void main() {
  group('JSON خارج خيط الواجهة', () {
    test('ردٌّ كبير يُفكّ خارجه إلى الصفوف نفسها', () async {
      final rows = [
        for (var i = 0; i < 2000; i++) {'id': 'r$i', 'n': i, 'x': i.isEven ? null : 'نص $i', 'f': i / 3},
      ];
      final body = jsonEncode(rows);
      expect(body.length, greaterThan(16 * 1024), reason: 'يتجاوز حدّ الفكّ على الواجهة');

      final decoded = await decodeRowsOffThread(body);
      expect(decoded, jsonDecode(body));
    });

    test('ردٌّ صغير أو ليس قائمة', () async {
      expect(await decodeRowsOffThread('[{"id":"a"}]'), [
        {'id': 'a'},
      ]);
      expect(await decodeRowsOffThread('{"error":"x"}'), isEmpty);
    });

    test('ترميز جسم الرفع خارج الخيط يطابق الترميز المباشر', () async {
      final rows = [
        for (var i = 0; i < 500; i++) {'id': 'r$i', 'v': i},
      ];
      expect(await encodeRowsOffThread(rows), jsonEncode(rows));
    });
  });

  group('تهيئة الجدول قبل التطبيق', () {
    test('دفعة بعد التهيئة تستبدل السجل الموجود ولا تكرّره', () async {
      final s = await bigSchool(FakeDisk());
      final existing = s.attendance.first;
      final before = s.attendance.length;

      await s.prepareApply('attendance');
      s.putRows('attendance', [
        {...existing.toCloud(), 'status': 'excused', 'sync_status': 'synced'},
      ]);

      expect(s.attendance.length, before, reason: 'استبدال لا إضافة');
      expect(s.attendance.where((a) => a.id == existing.id).single.status, 'excused');
    });

    test('تعديلٌ محلي بين التهيئة والدفعة لا يُنتج سجلاً مكرراً', () async {
      final s = await bigSchool(FakeDisk());
      await s.prepareApply('attendance');

      // سجل يُضاف محلياً بعد بناء الخريطة — الخريطة لا تعرفه
      final room = s.rooms.first;
      final student = s.studentsOf(room).first;
      final date = isoDate(DateTime.now().add(const Duration(days: 3)));
      s.setAttendance(student.id, date, 'absent', ownerId: room.id);
      final local = s.attendance.last;
      final before = s.attendance.length;

      // ثم يصل السجل نفسه من السحابة
      s.putRows('attendance', [
        {...local.toCloud(), 'status': 'present', 'sync_status': 'synced'},
      ]);

      expect(s.attendance.length, before, reason: 'الخريطة القديمة كانت ستضيفه مرة ثانية');
      expect(s.attendance.where((a) => a.id == local.id), hasLength(1));
      expect(s.attendance.where((a) => a.id == local.id).single.status, 'present');
    });

    test('جدولٌ تغيّر أثناء التهيئة لا تُحفظ له خريطة قديمة', () async {
      final s = await bigSchool(FakeDisk());
      final existing = s.attendance.first;

      final prep = s.prepareApply('attendance');
      // تعديل يصل أثناء البناء المجزّأ
      s.attendance.add(AttendanceMark(id: 'mid-build', studentId: existing.studentId, date: '2030-01-01', status: 'absent'));
      s.markRecord('attendance', 'mid-build');
      await prep;

      s.putRows('attendance', [
        {'id': 'mid-build', 'student_id': existing.studentId, 'session_id': '', 'status': 'present', 'sync_status': 'synced'},
      ]);
      expect(s.attendance.where((a) => a.id == 'mid-build'), hasLength(1));
    });
  });
}
