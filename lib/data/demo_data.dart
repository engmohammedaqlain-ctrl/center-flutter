import '../models/models.dart';
import 'permissions.dart';
import 'store.dart';

/// البيانات التجريبية — المقابل لـ `lib/demoData.ts` في النسخة المكتبية.
///
/// لا تُحقن تلقائياً. النسخة المكتبية تحقنها بضغطة زر صريحة من
/// «الإعدادات ← البيانات والمطور ← توليد بيانات تجريبية»، ويقابلها زر تصفير.
/// زرعها في مُنشئ المخزن كان يُظهر مدرسة وهمية وطلاباً وهميين لكل مستخدم
/// عند كل إقلاع، وتُرفع إلى نفس قاعدة Supabase التي يستعملها التطبيق المكتبي.
void injectDemoData(AppStore store) {

    store.tenants.addAll([
      Tenant(
        id: 'tn1',
        name: 'مدرسة الأمل الخاصة',
        code: 'AMAL-01',
        username: 'amal',
        password: 'amal2026',
        expiresAt: DateTime.now().add(const Duration(days: 280)),
        ownerPhone: '0599000001',
      ),
      Tenant(
        id: 'tn2',
        name: 'مدرسة النور',
        code: 'NOOR-02',
        username: 'noor',
        password: 'noor2026',
        expiresAt: DateTime.now().add(const Duration(days: 40)),
        ownerPhone: '0599000002',
      ),
    ]);

    store.users.addAll([
      AppUser(id: 'u1', name: 'أحمد عبد الله', role: 'admin', capabilities: [...allCapabilities]),
      AppUser(id: 'u2', name: 'سارة خالد', role: 'receptionist', capabilities: [...receptionistCapabilities]),
    ]);

    store.teachers.addAll([
      Teacher(id: 't1', name: 'أ. محمود الزهار', phone: '0599123456', subject: 'الرياضيات', rate: 70, paymentType: 'percentage', email: 'mahmoud@school.ps', subjectIds: ['s1']),
      Teacher(id: 't2', name: 'أ. وفاء عاشور', phone: '0568112233', subject: 'اللغة العربية', rate: 70, paymentType: 'percentage', subjectIds: ['s2']),
      Teacher(id: 't3', name: 'أ. رامي البيطار', phone: '0598776655', subject: 'اللغة الإنجليزية', rate: 70, paymentType: 'percentage', subjectIds: ['s3']),
      Teacher(id: 't4', name: 'د. كمال الشرفا', phone: '0592881122', subject: 'الفيزياء', rate: 70, paymentType: 'percentage', subjectIds: ['s4']),
      Teacher(id: 't5', name: 'أ. مريم النجار', phone: '0569443322', subject: 'الكيمياء', rate: 70, paymentType: 'percentage', subjectIds: ['s5']),
    ]);

    store.subjects.addAll([
      SubjectItem(id: 's1', name: 'الرياضيات', code: 'MATH'),
      SubjectItem(id: 's2', name: 'اللغة العربية', code: 'ARB'),
      SubjectItem(id: 's3', name: 'اللغة الإنجليزية', code: 'ENG'),
      SubjectItem(id: 's4', name: 'الفيزياء', code: 'PHY', gradeLevel: 'حادي عشر علمي'),
      SubjectItem(id: 's5', name: 'الكيمياء', code: 'CHM', gradeLevel: 'ثاني عشر علمي'),
    ]);

    store.gradeFees.addAll([
      GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: 180, orderIndex: 1),
      GradeFee(id: 'g2', gradeName: 'حادي عشر علمي', monthlyFee: 220, orderIndex: 2),
      GradeFee(id: 'g3', gradeName: 'حادي عشر أدبي', monthlyFee: 200, orderIndex: 3),
      GradeFee(id: 'g4', gradeName: 'ثاني عشر علمي', monthlyFee: 250, orderIndex: 4),
      GradeFee(id: 'g5', gradeName: 'ثاني عشر أدبي', monthlyFee: 230, orderIndex: 5),
    ]);

    store.rooms.addAll([
      Classroom(id: 'r1', name: 'عاشر (أ)', gradeLevel: 'عاشر', teacherId: 't1', notes: 'الطابق الأول - قاعة 1'),
      Classroom(id: 'r2', name: 'عاشر (ب)', gradeLevel: 'عاشر', teacherId: 't2', notes: 'الطابق الأول - قاعة 2'),
      Classroom(id: 'r3', name: '11 علمي', gradeLevel: 'حادي عشر علمي', teacherId: 't4', notes: 'الطابق الثاني - قاعة 3'),
      Classroom(id: 'r4', name: '11 أدبي', gradeLevel: 'حادي عشر أدبي', teacherId: 't3', notes: 'الطابق الثاني - قاعة 4'),
      Classroom(id: 'r5', name: '12 علمي', gradeLevel: 'ثاني عشر علمي', teacherId: 't1', notes: 'الطابق الثالث - قاعة 5'),
      Classroom(id: 'r6', name: '12 أدبي', gradeLevel: 'ثاني عشر أدبي', teacherId: 't2', notes: 'الطابق الثالث - قاعة 6'),
    ]);

    const names = [
      ['محمد أحمد النجار', 'عاشر', 'عاشر (أ)', 'خالد النجار', 0],
      ['سارة محمود خضير', 'عاشر', 'عاشر (أ)', 'محمود خضير', 1],
      ['عمر يوسف الشوا', 'عاشر', 'عاشر (ب)', 'يوسف الشوا', 2],
      ['مريم وليد اليازجي', 'عاشر', 'عاشر (ب)', 'وليد اليازجي', 3],
      ['أحمد سامي الريس', 'حادي عشر علمي', '11 علمي', 'سامي الريس', 0],
      ['ياسمين كمال شعت', 'حادي عشر علمي', '11 علمي', 'كمال شعت', 1],
      ['بلال فؤاد حرز الله', 'حادي عشر أدبي', '11 أدبي', 'فؤاد حرز الله', 2],
      ['سلمى نبيل أبو حصيرة', 'حادي عشر أدبي', '11 أدبي', 'نبيل أبو حصيرة', 0],
      ['عبد الله حسن صيام', 'ثاني عشر علمي', '12 علمي', 'حسن صيام', 1],
      ['آية رامي الجعبري', 'ثاني عشر علمي', '12 علمي', 'رامي الجعبري', 4],
      ['ماجد هاني عابد', 'ثاني عشر أدبي', '12 أدبي', 'هاني عابد', 0],
      ['رنا سليم أبو لبن', 'ثاني عشر أدبي', '12 أدبي', 'سليم أبو لبن', 2],
    ];

    final today = DateTime.now();
    for (var i = 0; i < names.length; i++) {
      final row = names[i];
      final id = 'st$i';
      final grade = row[1] as String;
      final fee = store.feeFor(grade)?.monthlyFee ?? 200;
      final pattern = row[4] as int;
      var totalPaid = 0.0;
      const instCount = 4;

      for (var p = 1; p <= instCount; p++) {
        final due = DateTime(today.year, today.month + (p - 3), 10);
        var paid = 0.0;
        if (pattern == 0) {
          paid = fee;
        } else if (pattern == 1 && p <= 2) {
          paid = fee;
        } else if (pattern == 2 && p == 1) {
          paid = fee;
        } else if (pattern == 3 && p <= 1) {
          paid = fee;
        }
        totalPaid += paid;
        store.installments.add(
          Installment(
            id: 'in$i$p',
            studentId: id,
            title: 'القسط الدراسي ($p)',
            amount: fee,
            dueDate: due,
            paidAmount: paid,
          ),
        );
        if (paid > 0) {
          store.payments.add(
            Payment(
              id: 'pay$i$p',
              receiptNumber: '${today.year}/${1001 + store.payments.length}',
              studentId: id,
              amount: paid,
              method: p.isEven ? 'cash' : 'jawwal_pay',
              date: due.subtract(const Duration(days: 2)),
              purpose: 'installment',
              notes: 'سداد القسط الدراسي ($p)',
              reference: p.isOdd ? 'TRX-${9000 + i * 10 + p}' : '',
              installmentId: 'in$i$p',
              remainingAfter: ((fee * instCount) - totalPaid).clamp(0, fee * instCount).toDouble(),
            ),
          );
        }
      }

      final student = Student(
        id: id,
        fullName: row[0] as String,
        gradeLevel: grade,
        section: row[2] as String,
        phone: '0599${(100000 + i * 137).toString().padLeft(6, '0')}',
        phonePrefix: '059',
        parentName: row[3] as String,
        parentPhone: '0598${(200000 + i * 137).toString().padLeft(6, '0')}',
        parentPhonePrefix: '059',
        nationalId: '${400000000 + i * 1357}',
        neighborhood: neighborhoods[i % (neighborhoods.length - 1)],
        detailedAddress: i == 0 ? 'شارع النفق، بجوار مسجد الهدى' : '',
        referralSource: referralSources[i % referralSources.length],
        balance: totalPaid - (fee * instCount),
        gender: i.isOdd ? 'أنثى' : 'ذكر',
        notes: i == 3 ? 'لديه شقيق في المدرسة - خصم إخوة' : 'طالب منتظم في الدوام',
        enrolledAt: today.subtract(const Duration(days: 60)),
        birthPlace: 'غزة',
        nationality: 'فلسطينية',
      );
      student.splitNameIfNeeded();
      store.students.add(student);

      final d0 = isoDate(today);
      final d1 = isoDate(today.subtract(const Duration(days: 1)));
      if (i % 5 == 0) {
        store.attendance.add(AttendanceMark(studentId: id, date: d0, status: 'absent'));
      } else if (i % 2 == 0) {
        store.attendance.add(AttendanceMark(studentId: id, date: d0, status: 'present'));
      }
      if (i % 3 != 0) {
        store.attendance.add(AttendanceMark(studentId: id, date: d1, status: 'present'));
      }
    }

    store.payments.sort((a, b) => b.date.compareTo(a.date));

  store.markAllDirty();
  store.notifySync();
}
