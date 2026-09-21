import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

/// مخزن بحجم مدرسة حقيقية: 400 طالب و12 صفاً وحضور شهر كامل.
Future<AppStore> bigSchool(FakeDisk disk) async {
  final s = AppStore.forTesting();
  await s.bootstrap(disk);
  injectDemoData(s);
  await s.login('amal', 'amal2026');

  final room = s.rooms.first;
  for (var i = 0; i < 400; i++) {
    s.students.add(
      Student(
        id: 'perf-$i',
        fullName: 'طالب رقم $i',
        gradeLevel: room.gradeLevel,
        section: room.name,
        phone: '05991${i.toString().padLeft(5, '0')}',
        parentName: 'ولي $i',
        parentPhone: '05981${i.toString().padLeft(5, '0')}',
        balance: i.isEven ? -120 : 0,
        nationalId: '${900000000 + i}',
      ),
    );
  }

  // حضور 22 يوماً لكل طالب ≈ 8800 سجل
  final today = DateTime.now();
  for (var d = 0; d < 22; d++) {
    final date = isoDate(today.subtract(Duration(days: d)));
    for (var i = 0; i < 400; i++) {
      s.attendance.add(
        AttendanceMark(studentId: 'perf-$i', date: date, status: i % 7 == 0 ? 'absent' : 'present'),
      );
    }
  }
  return s;
}

void main() {
  test('attendance lookups stay flat as the record count grows', () async {
    final s = await bigSchool(FakeDisk());
    final room = s.rooms.first;
    final list = s.studentsOf(room);
    final date = isoDate(DateTime.now());

    expect(s.attendance.length, greaterThan(8000));
    expect(list.length, greaterThan(300));

    // ما تفعله الشاشة في كل إعادة رسم: قراءتان لكل طالب
    final sw = Stopwatch()..start();
    for (var pass = 0; pass < 20; pass++) {
      for (final student in list) {
        s.attendanceInSession(room.id, student.id, date);
        s.attendanceInSession(room.id, student.id, date);
      }
    }
    sw.stop();

    // البحث الخطي كان يستغرق ثوانيَ لهذا الحجم
    expect(
      sw.elapsedMilliseconds,
      lessThan(400),
      reason: 'قراءة الحضور عبر الفهرس، لا بمسح القائمة: ${sw.elapsedMilliseconds}ms',
    );
  });

  test('the dues badge is computed once per change, not per rebuild', () async {
    final s = await bigSchool(FakeDisk());

    final first = s.dueItems();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 500; i++) {
      s.dueItems();
    }
    sw.stop();

    expect(identical(s.dueItems(), first), isTrue, reason: 'النتيجة نفسها بلا إعادة حساب');
    expect(sw.elapsedMilliseconds, lessThan(50), reason: '${sw.elapsedMilliseconds}ms لـ 500 قراءة');
  });

  test('a change invalidates the cached dues', () async {
    final s = await bigSchool(FakeDisk());
    final before = s.dueItems().length;

    // طالب مديونيته رصيد عام بلا أقساط مجدولة: سداده يُسقطه من القائمة.
    // من عليه قسط يبقى مستحقاً حتى يُسدَّد القسط نفسه.
    final debtor = s.students.firstWhere(
      (x) => x.balance < 0 && s.installmentsOf(x.id).isEmpty,
    );
    s.addPayment(
      studentId: debtor.id,
      amount: debtor.balance.abs(),
      method: 'cash',
      date: DateTime.now(),
    );

    expect(s.dueItems().length, lessThan(before), reason: 'السداد يُسقط الطالب من المستحقات');
  });

  test('marking attendance writes only the touched record', () async {
    final disk = FakeDisk();
    final s = await bigSchool(disk);
    // ترحيلات الدخول (لقطات السندات وتنقية أسماء الشعب) تجري بعد الدخول بلا
    // انتظار، فتُترك لتنتهي قبل قياس كتابات الرصد وحدها
    await Future<void>.delayed(Duration.zero);
    await s.flush();

    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final date = isoDate(DateTime.now());

    disk.writes = 0;
    s.setAttendance(student.id, date, 'absent', ownerId: room.id);
    await s.flush();

    // كتابة السجل وحده وطابور المزامنة، لا إعادة كتابة 8800 سجل
    expect(disk.writes, lessThanOrEqualTo(4), reason: '${disk.writes} عملية كتابة');
  });

  test('student lookup by id does not scan the list', () async {
    final s = await bigSchool(FakeDisk());
    final sw = Stopwatch()..start();
    for (var pass = 0; pass < 200; pass++) {
      for (var i = 0; i < 400; i += 40) {
        expect(s.studentById('perf-$i'), isNotNull);
      }
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(120), reason: '${sw.elapsedMilliseconds}ms');
  });

  test('putRows upsert stays linear for thousands of students', () {
    final s = AppStore.forTesting();
    for (var i = 0; i < 5000; i++) {
      s.students.add(
        Student(
          id: 'u-$i',
          fullName: 'طالب $i',
          gradeLevel: 'عاشر',
          section: 'أ',
          phone: '0599$i',
          parentName: 'ولي',
          parentPhone: '0598$i',
          balance: 0,
        ),
      );
    }

    final batch = [
      for (var i = 0; i < 2000; i++)
        {
          'id': i.isEven ? 'u-$i' : 'new-$i',
          'full_name': 'محدث $i',
          'grade_level': 'عاشر',
          'section': 'أ',
          'phone': '0599$i',
          'parent_name': 'ولي',
          'parent_phone': '0598$i',
          'balance': 0,
          'sync_status': 'synced',
        },
    ];

    final sw = Stopwatch()..start();
    s.putRows('students', batch);
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(500), reason: 'putRows ${sw.elapsedMilliseconds}ms لـ 2k فوق 5k');
    expect(s.students.length, greaterThan(5000));
  });

  test('studentsInViewedYear is cached until data changes', () async {
    final s = await bigSchool(FakeDisk());
    final first = s.studentsInViewedYear;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      expect(identical(s.studentsInViewedYear, first), isTrue);
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(30), reason: '${sw.elapsedMilliseconds}ms');

    s.notifyListeners();
    expect(identical(s.studentsInViewedYear, first), isFalse, reason: 'تغيّر البيانات يبطل التخزين');
  });

  test('local attendance mark stays under a frame budget', () async {
    final s = await bigSchool(FakeDisk());
    await Future<void>.delayed(Duration.zero);
    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    final date = isoDate(DateTime.now());

    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      s.setAttendance(student.id, date, i.isEven ? 'absent' : 'present', ownerId: room.id);
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(800), reason: '50 رصدة محلية: ${sw.elapsedMilliseconds}ms');
  });
}
