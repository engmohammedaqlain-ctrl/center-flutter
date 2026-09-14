import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// تخزين في الذاكرة يحاكي القرص: يحتفظ بما كُتب ويعيده عند التحميل التالي.
/// يثبت أن دورة (تعديل → كتابة → إقلاع جديد → قراءة) تعمل فعلاً.
class FakeDisk implements Persistence {
  final Map<String, String> _tables = {};

  @override
  final Map<String, String> settings = {};

  int writes = 0;

  @override
  Future<void> open() async {}

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    return _tables.map(
      (k, v) => MapEntry(
        k,
        (jsonDecode(v) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      ),
    );
  }

  @override
  Future<void> saveTable(String table, List<Map<String, dynamic>> rows) async {
    writes++;
    _tables[table] = jsonEncode(rows);
  }

  @override
  Future<void> saveRecords(String table, List<Map<String, dynamic>> rows) async {
    writes++;
    final current = _tables[table] == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(_tables[table]!) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    for (final row in rows) {
      final i = current.indexWhere((e) => '${e['id']}' == '${row['id']}');
      if (i >= 0) {
        current[i] = row;
      } else {
        current.add(row);
      }
    }
    _tables[table] = jsonEncode(current);
  }

  @override
  Future<void> deleteRecords(String table, List<String> ids) async {
    if (_tables[table] == null) return;
    writes++;
    final current = (jsonDecode(_tables[table]!) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => !ids.contains('${e['id']}'))
        .toList();
    _tables[table] = jsonEncode(current);
  }

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
  }

  @override
  Future<void> wipeData() async => _tables.clear();

  @override
  Future<void> close() async {}
}

void main() {
  test('data survives an app restart', () async {
    final disk = FakeDisk();

    // الجلسة الأولى: تسجيل طالب ودفعة
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    final student = first.students.firstWhere((s) => s.balance < 0);
    final studentId = student.id;
    final payment = first.addPayment(
      studentId: studentId,
      amount: 75,
      method: 'cash',
      date: DateTime.now(),
    );
    final balanceAfter = student.balance;
    await first.flush();
    expect(disk.writes, greaterThan(0));

    // إقلاع جديد على نفس القرص
    final second = AppStore.forTesting();
    await second.bootstrap(disk);

    expect(second.students.length, first.students.length);
    expect(second.payments.length, first.payments.length);
    expect(second.installments.length, first.installments.length);
    expect(second.teachers.length, first.teachers.length);
    expect(second.gradeFees.length, first.gradeFees.length);

    final reloaded = second.studentById(studentId);
    expect(reloaded, isNotNull);
    expect(reloaded!.balance, balanceAfter);
    expect(second.payments.any((p) => p.receiptNumber == payment.receiptNumber), isTrue);
  });

  test('الإقلاع يصحّح رصيداً كتبه إصدار أقدم بقاعدة حساب أخرى', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    final student = first.students.first;

    // طالبٌ سدّد القسطين المستحقين عليه، والثالث لم يحن موعده: رصيده صفر
    first.installments.removeWhere((i) => i.studentId == student.id);
    first.payments.removeWhere((p) => p.studentId == student.id);
    final today = DateTime.now();
    for (var i = 0; i < 3; i++) {
      first.installments.add(Installment(
        id: 'inst-$i',
        studentId: student.id,
        title: 'القسط المدرسي (${i + 1})',
        amount: 162,
        dueDate: today.add(Duration(days: 30 * (i - 1))),
      ));
    }
    for (var i = 0; i < 2; i++) {
      first.payments.add(Payment(
        id: 'pay-$i',
        receiptNumber: '2026/200$i',
        studentId: student.id,
        amount: 162,
        method: 'cash',
        date: today,
        createdAt: today.toIso8601String(),
      ));
    }
    // رقم من القاعدة القديمة: الأقساط المستحقة وحدها ورسم الحجز يعود للرصيد
    student.balance = 198;
    first.markAllDirty();
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    final reloaded = second.studentById(student.id)!;
    expect(reloaded.balance, closeTo(0, 0.01), reason: 'سدّد ما استُحق عليه، والثالث لم يحن');
    expect(reloaded.balance, closeTo(second.computeStudentBalance(student.id), 0.01));
  });

  test('the pending sync queue survives a restart', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    first.upsertTeacher(Teacher(id: first.newId(), name: 'أ. تجريبي', phone: '0599000123', subject: 'الرياضيات'));
    final queued = first.pendingSyncs.length;
    expect(queued, greaterThan(0));
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.pendingSyncs.length, queued);
    expect(second.pendingSyncs.any((a) => a.tableName == 'teachers'), isTrue);
  });

  test('the session and institution identity survive a restart', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    await first.login('amal', 'amal2026');
    await first.saveInstitution(name: 'مدرسة مخصصة', type: 'center');
    await first.flush();
    expect(first.loggedIn, isTrue);

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.loggedIn, isTrue, reason: 'الجلسة تُستعاد بلا إعادة تسجيل دخول');
    expect(second.isMasterAdmin, isFalse);
    expect(second.currentTenant?.username, 'amal');
    expect(second.institutionName, 'مدرسة مخصصة');
    expect(second.institutionType, 'center');
    expect(second.lastUsername, 'amal');
  });

  test('الجلسة تُستعاد بلا إنترنت: المنشأة محفوظة على الجهاز', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    await first.login('amal', 'amal2026');
    final tenantId = first.currentTenant!.id;
    await first.flush();

    // إقلاع جديد بلا أي اتصال: لا جلب للمنشآت من السحابة
    final second = AppStore.forTesting();
    await second.bootstrap(disk);

    expect(second.tenants.any((t) => t.id == tenantId), isTrue, reason: 'المنشأة على القرص');
    expect(second.loggedIn, isTrue, reason: 'لا يُطالَب بتسجيل دخول جديد بعد كل إغلاق');
    expect(second.currentTenant?.id, tenantId);
  });

  test('logging out clears the stored session but keeps the data', () async {
    final disk = FakeDisk();
    final first = AppStore.forTesting();
    await first.bootstrap(disk);
    injectDemoData(first);
    await first.login('amal', 'amal2026');
    await first.logout();
    await first.flush();

    final second = AppStore.forTesting();
    await second.bootstrap(disk);
    expect(second.loggedIn, isFalse);
    expect(second.students, isNotEmpty, reason: 'الخروج لا يمسح البيانات');
  });
}
