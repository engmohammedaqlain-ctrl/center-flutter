/// المدرسة التجريبية — المقابل لـ `demoTenant.ts`: مدرسة منفصلة لكل مدير يجرّب نون، تُنشأ من لوحة
/// المطور وتُعبّأ ببيانات المولّد مباشرة في السحابة، وتُحذف تلقائياً بعد مدتها.
///
/// لا تمسّ جهاز المطور ولا أي مدرسة أخرى: لا حذف هنا، والتعبئة ترفض ما ليس تجريبياً أو ما فيه
/// طلاب، وكل صف يُختم بمعرّف المدرسة الجديدة.
library;

import 'dart:math' as math;

import '../models/models.dart';
import 'app_settings.dart';
import 'demo_dataset.dart';
import 'supabase.dart';
import 'sync.dart';
import 'user_message.dart';

/// مدة التجربة بالأيام — `DEMO_DAYS`.
const demoDays = 14;

/// تمديد التجريبية بكبسة — `DEMO_EXTEND_DAYS`.
const demoExtendDays = 7;

/// كلمات سهلة لأن بياناتها وهمية، والهويات وحدها عشوائية.
const _adminPassword = '12345678';
const _teacherCode = '111111';
const _parentCode = '222222';

/// التطبيق على الويب: الرابط الذي يُرسل للمدير — `DEMO_APP_URL`.
const demoAppUrl = 'https://noonschool.app/app/';

const _insertChunk = 200;
const _uploadParallel = 6;

/// الأيام الباقية على حذفها، للأعلى؛ صفر إن انتهت — `demoDaysLeft`.
int demoDaysLeft(DateTime? expiresAt, [DateTime? now]) {
  if (expiresAt == null) return 0;
  final ms = expiresAt.difference(now ?? DateTime.now()).inMilliseconds;
  return math.max(0, (ms / 86400000).ceil());
}

/// رسالة جاهزة للمدير باللهجة الفلسطينية — `demoInviteMessage`.
String demoInviteMessage({required String school, required String username, required String password, required DemoLogins logins}) {
  final lines = [
    'أهلين، هاي نسخة تجريبية من نون لـ«$school»، فيها بيانات وهمية عشان تجرّبها براحتك:',
    demoAppUrl,
    '',
    'الإدارة (من «دخول الإدارة»):',
    'اسم المستخدم: $username',
    'كلمة المرور: $password',
    '',
    'معلم (${logins.teacher.name}):',
    'رقم الهوية: ${logins.teacher.nationalId}',
    'كلمة المرور: ${logins.teacher.portalCode}',
    '',
    'ولي أمر لطالبين:',
    'رقم الهوية: ${logins.parent.nationalId}',
    'كلمة المرور: ${logins.parent.parentPortalCode}',
    '',
    'النسخة بتنحذف لحالها بعد $demoDays يوم.',
  ];
  return lines.join('\n');
}

class DemoSchoolResult {
  const DemoSchoolResult({required this.tenant, required this.username, required this.password, required this.message});

  final Tenant tenant;
  final String username;
  final String password;
  final String message;
}

/// تنفيذ مهام بعدد محدود في الوقت نفسه — `inPool`.
Future<void> _inPool(List<Future<void> Function()> jobs) async {
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      await jobs[next++]();
    }
  }

  await Future.wait([for (var i = 0; i < math.min(_uploadParallel, jobs.length); i++) worker()]);
}

/// صورة PNG في حاويتها؛ الفشل يترك الصف بلا صورة — `uploadPng`.
Future<bool> _uploadPng(String bucket, String path, List<int> bytes) async {
  try {
    await storageUpload(bucket, path, bytes, 'image/png', upsert: true);
    return true;
  } catch (_) {
    return false;
  }
}

/// إدراج لا تحديث، بدفعات بحسب أعمدة صفوفها: PostgREST يملأ العمود الغائب عن صف بـ null — `insertRows`.
Future<void> _insertRows(String table, List<Map<String, dynamic>> rows) async {
  final bySignature = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key = (row.keys.toList()..sort()).join('|');
    (bySignature[key] ??= []).add(row);
  }
  for (final list in bySignature.values) {
    for (var i = 0; i < list.length; i += _insertChunk) {
      try {
        await supabaseInsert(table, list.sublist(i, math.min(i + _insertChunk, list.length)));
      } catch (e) {
        throw StoreException('تعذّرت تعبئة ${tableLabelsAr[table] ?? table}: ${userMessage(e, 'رفضت السحابة الحفظ')}');
      }
    }
  }
}

/// تعبئة مدرسة تجريبية جديدة ببيانات المولّد في السحابة — `seedDemoTenant`. ترفض ما ليس تجريبياً وما فيه طلاب.
Future<DemoLogins> seedDemoTenant({
  required String tenantId,
  required String name,
  String? logo,
  Map<String, dynamic>? colors,
}) async {
  final tenant = await supabaseSelect('tenants', columns: 'id,is_demo', filters: {'id': 'eq.$tenantId'}, limit: 1);
  if (tenant == null || tenant.isEmpty) throw StoreException('المدرسة غير موجودة');
  if (tenant.first['is_demo'] != true) throw StoreException('ليست مدرسة تجريبية');
  final existing = await supabaseSelect('students', columns: 'id', filters: {'tenant_id': 'eq.$tenantId'}, limit: 1);
  if (existing == null) throw StoreException('تعذّر فحص المدرسة');
  if (existing.isNotEmpty) throw StoreException('المدرسة فيها بيانات');

  final demo = await buildDemoDataset(tenantId: tenantId);
  final rows = demo.rows;

  // كلمات سهلة يكتبها المدير من الرسالة؛ الهويات وحدها عشوائية لأنها فريدة بين المدارس
  final teacherId = demo.logins.teacher.nationalId;
  for (final t in rows['teachers']!) {
    if (t['national_id'] == teacherId) t['portal_code'] = _teacherCode;
  }
  final parentId = demo.logins.parent.nationalId;
  for (final s in rows['students']!) {
    if (s['parent_national_id'] == parentId) s['parent_portal_code'] = _parentCode;
  }
  final logins = demo.logins
    ..parent = (
      name: demo.logins.parent.name,
      nationalId: parentId,
      parentPortalCode: _parentCode,
      children: demo.logins.parent.children,
    );
  final teacherLogin = (name: logins.teacher.name, nationalId: teacherId, portalCode: _teacherCode);

  // الصور: إشعارات طلبات الدفع، وصور الطلاب ووثائقهم، وإشعارات السندات، في حاوياتها الخاصة
  final jobs = <Future<void> Function()>[];
  for (final pr in rows['payment_requests']!) {
    final paths = pr['image_paths'] as List;
    if (paths.isEmpty) continue;
    jobs.add(() async {
      if (!await _uploadPng('payment-requests', '${paths.first}', demo.transferImage)) pr['image_paths'] = <String>[];
    });
  }
  for (final a in rows['student_attachments']!) {
    for (final field in const ['student_id_photo', 'birth_certificate']) {
      final png = a.remove('_png_$field') as List<int>?;
      if (png == null) continue;
      jobs.add(() async {
        final path = '$tenantId/${a['id']}/$field.png';
        if (await _uploadPng('student-docs', path, png)) a['${field}_path'] = path;
      });
    }
  }
  for (final f in rows['finance_attachments']!) {
    final png = f.remove('_png') as List<int>?;
    if (png == null) continue;
    jobs.add(() async {
      final path = '$tenantId/${f['id']}.png';
      if (await _uploadPng('finance-notices', path, png)) f['storage_path'] = path;
    });
  }
  await _inPool(jobs);

  final now = DateTime.now().toUtc().toIso8601String();
  await _insertRows('institution_settings', [
    {
      'id': tenantId,
      'tenant_id': tenantId,
      'institution_type': 'school',
      'institution_name': name,
      'logo': logo,
      'colors': {...?colors, '__custom_payment_methods': demoPaymentMethods},
      'settings': AppSettings.fromMap({'seat_fee': demo.seatFee}).toMap(),
      'created_at': now,
      'updated_at': now,
    },
  ]);

  // ترتيب المزامنة نفسه: الأب قبل ابنه
  for (final table in syncedTables) {
    final list = rows[table];
    if (list == null || list.isEmpty) continue;
    await _insertRows(table, [for (final r in list) sanitizePayload(table, r, tenantId)]);
  }
  if (demo.moodleSections.isNotEmpty) {
    await _insertRows('course_sections', demo.moodleSections);
    await _insertRows('course_items', demo.moodleItems);
  }

  return DemoLogins(teacher: teacherLogin, student: logins.student, overdue: logins.overdue, parent: logins.parent);
}

String _digits(int n) {
  final r = math.Random();
  return List.generate(n, (_) => r.nextInt(10)).join();
}

/// إنشاء مدرسة تجريبية كاملة: الاشتراك وحساب الإدارة (admin-tenants) ثم التعبئة — `createDemoSchool`.
/// فشل التعبئة يحذف التجريبية التي أُنشئت للتو، فلا تبقى مدرسة ناقصة.
Future<DemoSchoolResult> createDemoSchool({required String name, String? logo, Map<String, dynamic>? colors}) async {
  final clean = name.trim();
  if (clean.isEmpty) throw StoreException('اسم المدرسة مطلوب');

  var username = '';
  Tenant? tenant;
  var lastError = '';
  for (var attempt = 0; attempt < 4 && tenant == null; attempt++) {
    username = 'demo${_digits(5)}';
    final data = await supabaseInvoke('admin-tenants', {
      'action': 'create_tenant',
      'tenant': {'name': clean, 'code': username, 'plan_type': 'rental', 'notes': 'تجريبية', 'demo_days': demoDays},
      'username': username,
      'password': _adminPassword,
    });
    final row = data['tenant'];
    if (data['error'] == null && row is Map) {
      tenant = Tenant.fromCloud(Map<String, dynamic>.from(row));
    } else {
      lastError = '${data['error'] ?? ''}';
      // تكرار المعرّف أو اسم المستخدم وحده يُعاد بغيره
      if (!lastError.contains('مستخدم')) break;
    }
  }
  if (tenant == null) throw StoreException(lastError.isEmpty ? 'تعذّر إنشاء المدرسة' : lastError);

  // دالة admin-tenants قديمة تتجاهل demo_days فتنشئ مدرسة عادية: تُحذف فوراً
  if (!tenant.isDemo) {
    await supabaseInvoke('admin-tenants', {'action': 'delete_tenant', 'tenant_id': tenant.id});
    throw StoreException('حدّث دالة admin-tenants أولاً');
  }

  try {
    final logins = await seedDemoTenant(tenantId: tenant.id, name: clean, logo: logo, colors: colors);
    return DemoSchoolResult(
      tenant: tenant,
      username: username,
      password: _adminPassword,
      message: demoInviteMessage(school: clean, username: username, password: _adminPassword, logins: logins),
    );
  } catch (_) {
    try {
      await supabaseInvoke('admin-tenants', {'action': 'purge_demo', 'tenant_id': tenant.id});
    } catch (_) {}
    rethrow;
  }
}
