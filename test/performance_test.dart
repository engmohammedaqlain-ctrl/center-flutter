import 'package:center_mobile/data/balance.dart';
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


/// مخزن بحجم المدارس الكبيرة: ~1200 طالب و50 ألف رصد حضور وآلاف الأقساط.
///
/// [bigSchool] يبني 8800 سجل — وهو حجمٌ تمرّ عنده علل O(n) بلا أن تُلاحظ.
/// مدرسة فعلية تجاوزت الخمسين ألفاً، فظهرت عندها علل لم تُمسكها الاختبارات.
Future<AppStore> hugeSchool(FakeDisk disk) async {
  final s = AppStore.forTesting();
  await s.bootstrap(disk);
  injectDemoData(s);
  await s.login('amal', 'amal2026');

  final room = s.rooms.first;
  const students = 1200;
  final today = DateTime.now();

  for (var i = 0; i < students; i++) {
    s.students.add(
      Student(
        id: 'huge-$i',
        fullName: 'طالب رقم $i محمد',
        gradeLevel: room.gradeLevel,
        section: room.name,
        phone: '05991${i.toString().padLeft(5, '0')}',
        parentName: 'ولي $i',
        parentPhone: '05981${i.toString().padLeft(5, '0')}',
        balance: i.isEven ? -120 : 0,
        nationalId: '${800000000 + i}',
      )..createdAt = isoDate(today.subtract(Duration(days: i % 400))),
    );

    // أقساط السنة: عشرة لكل طالب ≈ 12 ألف قسط
    for (var k = 0; k < 10; k++) {
      s.installments.add(
        Installment(
          id: 'huge-inst-$i-$k',
          studentId: 'huge-$i',
          title: 'قسط ${k + 1}',
          amount: 250,
          dueDate: today.subtract(Duration(days: (k * 30) - 60)),
          paidAmount: k.isEven ? 250 : 0,
        ),
      );
    }
  }

  // حضور 42 يوماً لكل طالب ≈ 50 ألف رصد، مع جلساتها
  for (var d = 0; d < 42; d++) {
    final date = isoDate(today.subtract(Duration(days: d)));
    final sid = 'huge-ses-$d';
    s.sessions.add(ClassSession(id: sid, groupId: '', roomId: room.id, sessionDate: date));
    for (var i = 0; i < students; i++) {
      s.attendance.add(
        AttendanceMark(
          id: 'att_${sid}_huge-$i',
          studentId: 'huge-$i',
          date: date,
          status: i % 7 == 0 ? 'absent' : 'present',
          sessionId: sid,
        ),
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

    // إخطارٌ لتغيّر في جدول آخر لا يُسقطها: رصد حضور لا يغيّر طلاب العام
    s.notifyListeners();
    s.markDirty('attendance');
    expect(identical(s.studentsInViewedYear, first), isTrue, reason: 'تغيّر جدول آخر لا يعيد بناء الطلاب');

    // تغيّر الطلاب أنفسهم يُسقطها
    s.markDirty('students');
    expect(identical(s.studentsInViewedYear, first), isFalse, reason: 'تغيّر الطلاب يبطل التخزين');
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

  // ── بحجم مدرسة كبيرة: 50 ألف رصد و12 ألف قسط ───────────────────────────────

  test('فلترة الطلاب وترتيبهم تبقى دون ميزانية إطار', () async {
    final s = await hugeSchool(FakeDisk());
    final year = s.studentsInViewedYear;
    expect(year.length, greaterThan(1000));

    // ما تفعله شاشة الطلاب في كل إعادة بناء: تصفية بالبحث ثم ترتيب
    final sw = Stopwatch()..start();
    for (var pass = 0; pass < 20; pass++) {
      final q = pass.isEven ? 'محمد' : '0599';
      year
          .where((st) =>
              st.status != 'archived' &&
              (st.fullName.contains(q) || st.phone.contains(q) || st.nationalId.contains(q)))
          .toList()
        ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    }
    sw.stop();

    // 20 إعادة بناء = 20 إطاراً؛ الميزانية 16ms للإطار
    expect(
      sw.elapsedMilliseconds,
      lessThan(320),
      reason: 'فلترة ${year.length} طالب × 20: ${sw.elapsedMilliseconds}ms',
    );
  });

  test('تصفية المالية على آلاف الأقساط تبقى سريعة', () async {
    final s = await hugeSchool(FakeDisk());
    expect(s.installments.length, greaterThan(10000));

    // كما تفعله الشاشة: اليوم يُحسب مرة، ثم تُصفّى الأقساط وتُرتَّب
    final today = startOfToday();
    final sw = Stopwatch()..start();
    for (var pass = 0; pass < 20; pass++) {
      s.installments.where((i) => unpaidOf(i) > 0 && isInstallmentDue(i, today)).toList()
        ..sort(compareInstallments);
    }
    sw.stop();

    // الميزانية واسعة عمداً: الملف يبني قاعدة الخمسين ألفاً مراراً في العملية
    // نفسها، فيتفاوت القياس بضغط جامع القمامة. ما تحرسه هذه الحدود انحدارٌ
    // بأضعاف — كان القياس 6129ms حين كان الترتيب يُنسّق التاريخ نصّاً.
    expect(
      sw.elapsedMilliseconds,
      lessThan(900),
      reason: '${s.installments.length} قسط × 20: ${sw.elapsedMilliseconds}ms',
    );
  });

  test('القراءة بعد كل تعديل لا تُعيد بناء الفهارس', () async {
    // العلّة التي عُثر عليها في الميدان: كل رصد يُبطل الفهارس، فتُعاد على عشرات
    // الآلاف. القراءة وحدها كانت تُقاس فتمرّ، والعلّة في «عدّل ثم اقرأ».
    final s = await hugeSchool(FakeDisk());
    final room = s.rooms.first;
    final roster = s.studentsOf(room);
    final date = isoDate(DateTime.now());
    expect(s.attendance.length, greaterThan(40000));
    expect(roster.length, greaterThan(1000));

    // بناء الفهارس أولاً كي يُقاس ما بعده لا هو
    s.attendanceInSession(room.id, roster.first.id, date);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      s.setAttendance(roster[i].id, date, i.isEven ? 'absent' : 'present', ownerId: room.id);
      for (final st in roster) {
        s.attendanceInSession(room.id, st.id, date);
      }
    }
    sw.stop();

    expect(
      sw.elapsedMilliseconds,
      lessThan(200),
      reason: '10 لمسات مع إعادة رسم كشف ${roster.length} طالب: ${sw.elapsedMilliseconds}ms',
    );
  });

  test('«الكل حاضر» لا يُعيد بناء الفهارس لكل طالب', () async {
    final s = await hugeSchool(FakeDisk());
    final room = s.rooms.first;
    final roster = s.studentsOf(room);
    final date = isoDate(DateTime.now().add(const Duration(days: 1)));

    s.attendanceInSession(room.id, roster.first.id, date);

    final sw = Stopwatch()..start();
    s.markAllPresent(date, roster, ownerId: room.id);
    sw.stop();

    expect(
      sw.elapsedMilliseconds,
      lessThan(300),
      reason: 'رصد ${roster.length} طالباً دفعة: ${sw.elapsedMilliseconds}ms',
    );
  });

  test('شارة المستحقات لا تُحسب مع كل إعادة بناء', () async {
    final s = await hugeSchool(FakeDisk());

    final sw = Stopwatch()..start();
    for (var i = 0; i < 500; i++) {
      s.installmentBuckets;
    }
    sw.stop();

    // 500 قراءة بلا تغيير = حسبة واحدة والباقي من المحفوظ
    expect(
      sw.elapsedMilliseconds,
      lessThan(120),
      reason: '500 قراءة على ${s.installments.length} قسط: ${sw.elapsedMilliseconds}ms',
    );
  });


  test('الواجهة تبقى مستجيبة أثناء المزامنة', () async {
    // أثقل ما يجري فعلاً: دفعات تصل من السحابة بينما المستخدم يمرّر الشاشة.
    // كل دفعة كانت تُبطل كل الذاكرات المحفوظة، فيُعاد حساب المستحقات على آلاف
    // الأقساط في كل إطار — ستّة إطارات في الثانية بدل ستين.
    final s = await hugeSchool(FakeDisk());
    final year = s.studentsInViewedYear;

    /// ما ترسمه شاشة الطلاب في إطار واحد أثناء التمرير
    int frame() {
      final sw = Stopwatch()..start();
      year.where((st) => st.status != 'archived' && st.fullName.contains('محمد')).toList()
        ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      s.dueItems();
      s.installmentBuckets;
      sw.stop();
      return sw.elapsedMicroseconds;
    }

    final room = s.rooms.first;
    final incoming = [
      for (var i = 0; i < 1500; i++)
        {
          'id': 'huge-$i',
          'full_name': 'طالب رقم $i محمد',
          'grade_level': room.gradeLevel,
          'section': room.name,
          'phone': '0599100000',
          'parent_name': 'ولي',
          'parent_phone': '0598100000',
          'balance': 0,
          'status': 'active',
          'sync_status': 'synced',
        },
    ];

    frame(); // تسخين الذاكرات المحفوظة

    var worst = 0;
    for (var batch = 0; batch < 10; batch++) {
      s.putRows('students', incoming);
      final f = frame();
      if (f > worst) worst = f;
    }

    // ميزانية الإطار 16ms؛ نترك هامشاً لبطء أجهزة البناء
    expect(
      worst ~/ 1000,
      lessThan(40),
      reason: 'أسوأ إطار أثناء المزامنة: ${worst ~/ 1000}ms (${worst}µs)',
    );
  });

  test('حساب المستحقات لا يُعيد بناء فهرس الطلاب لكل قسط', () async {
    final s = await hugeSchool(FakeDisk());
    expect(s.installments.length, greaterThan(10000));

    s.dueItems();
    s.putRows('students', const [
      {'id': 'huge-0', 'full_name': 'طالب صفر', 'status': 'active', 'sync_status': 'synced'},
    ]);

    final sw = Stopwatch()..start();
    final dues = s.dueItems();
    sw.stop();

    expect(dues, isNotEmpty);
    expect(
      sw.elapsedMilliseconds,
      lessThan(40),
      reason: 'حساب المستحقات على ${s.installments.length} قسط: ${sw.elapsedMilliseconds}ms',
    );
  });


  test('دفعة سحب لا تُسقط فهرس الحضور ولا تُثقل الإطار التالي', () async {
    // وصول رصودٍ من السحابة كان يُسقط فهرس الحضور كاملاً، فيُعاد بناؤه على
    // خمسين ألف سجل في الإطار الذي يلي كل دفعة أثناء المزامنة.
    final s = await hugeSchool(FakeDisk());
    final room = s.rooms.first;
    final roster = s.studentsOf(room);
    final date = isoDate(DateTime.now());
    final sess = s.sessions.first;
    final chunk = [
      for (var i = 0; i < 300; i++)
        {
          'id': 'att_${sess.id}_huge-$i',
          'student_id': 'huge-$i',
          'session_id': sess.id,
          'status': i.isEven ? 'present' : 'absent',
          'sync_status': 'synced',
        },
    ];

    s.attendanceInSession(room.id, roster.first.id, date); // الفهرس مبني
    s.putRows('attendance', chunk); // أول دفعة تبني خريطة المعرّفات

    final sw = Stopwatch()..start();
    for (var b = 0; b < 10; b++) {
      s.putRows('attendance', chunk);
      for (final st in roster) {
        s.attendanceInSession(room.id, st.id, date);
      }
    }
    sw.stop();

    expect(
      sw.elapsedMilliseconds,
      lessThan(250),
      reason: '10 دفعات سحب مع إعادة رسم الكشف: ${sw.elapsedMilliseconds}ms',
    );
    // والفهرس المرقَّع يعطي ما يعطيه البناء الكامل
    expect(s.attendanceInSession(sess.roomId, 'huge-1', sess.sessionDate), 'absent');
  });

  test('تعديل طالب لا يعيد بناء فهرس الحضور', () async {
    final s = await hugeSchool(FakeDisk());
    final room = s.rooms.first;
    final roster = s.studentsOf(room);
    final date = isoDate(DateTime.now());
    s.attendanceInSession(room.id, roster.first.id, date);

    s.markRecord('students', roster.first.id); // تعديل في جدول الطلاب

    final sw = Stopwatch()..start();
    for (final st in roster) {
      s.attendanceInSession(room.id, st.id, date);
    }
    sw.stop();

    expect(
      sw.elapsedMilliseconds,
      lessThan(15),
      reason: 'قراءة الكشف بعد تعديل طالب: ${sw.elapsedMilliseconds}ms',
    );
  });

}
