import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// صورة صغيرة بصيغة `data:` كما تصل من منتقي الصور.
const _png = 'data:image/png;base64,iVBORw0KGgo=';

AppStore _store({bool online = true}) {
  SharedPreferences.setMockInitialValues({});
  final s = AppStore.forTesting()..networkEnabled = online;
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  SupabaseAuth.restore(
    access: 'token',
    refresh: 'refresh',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    savedClaims: {'role': 'tenant_admin', 'tenant_id': s.currentTenant!.id},
  );
  return s;
}

/// سحابة تقبل كل شيء وتسجّل ما وصلها.
MockClient _cloud(List<http.BaseRequest> seen, {int storageStatus = 200, String selectBody = '[]'}) =>
    MockClient((request) async {
      seen.add(request);
      final path = request.url.path;
      if (path.startsWith('/storage/')) {
        return http.Response('{}', storageStatus);
      }
      if (request.method == 'GET') {
        return http.Response(selectBody, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('[]', 201, headers: {'content-type': 'application/json; charset=utf-8'});
    });

void main() {
  tearDown(SupabaseAuth.clear);

  test('بلا اتصال: المرفق يبقى على الجهاز موسوماً للرفع', () async {
    final s = _store(online: false);
    final student = s.students.first;

    s.upsertStudent(student, attachments: StudentAttachments(id: student.id, studentIdPhoto: _png));

    final saved = s.attachmentsOf(student.id)!;
    expect(saved.studentIdPhoto, _png, reason: 'الصورة محفوظة محلياً');
    expect(saved.syncStatus, 'pending');
    expect(saved.paths, isEmpty);
    await s.flush();
  });

  test('الرفع يضع الملف في الحاوية والصف يحمل مساره لا الصورة', () async {
    final s = _store();
    final student = s.students.first;
    final tenantId = s.currentTenant!.id;
    s.attachmentsByStudent[student.id] = StudentAttachments(
      id: student.id,
      studentIdPhoto: _png,
      syncStatus: 'pending',
    );

    final seen = <http.BaseRequest>[];
    expect(await http.runWithClient(s.retryPendingAttachments, () => _cloud(seen)), 1);

    final upload = seen.firstWhere((r) => r.url.path.contains('/storage/v1/object/student-docs/'));
    expect(upload.url.path, endsWith('$tenantId/${student.id}/student_id_photo.png'));
    expect(upload.headers['x-upsert'], 'true', reason: 'الصورة الجديدة تحلّ محل سابقتها');

    final row = seen.firstWhere((r) => r.url.path.endsWith('/rest/v1/student_attachments')) as http.Request;
    final sent = (jsonDecode(row.body) as List).first as Map<String, dynamic>;
    expect(sent['student_id_photo_path'], '$tenantId/${student.id}/student_id_photo.png');
    expect(sent.containsKey('student_id_photo'), isFalse, reason: 'العمود حُذف من القاعدة');

    final saved = s.attachmentsOf(student.id)!;
    expect(saved.syncStatus, 'synced');
    expect(saved.studentIdPhoto, _png, reason: 'النسخة المحلية تبقى للعرض');
    await s.flush();
  });

  test('تعثّر الرفع يُبقيه معلّقاً، وإعادة المحاولة تُنجحه', () async {
    final s = _store();
    final student = s.students.first;
    s.attachmentsByStudent[student.id] = StudentAttachments(
      id: student.id,
      birthCertificate: _png,
      syncStatus: 'pending',
    );

    final failed = <http.BaseRequest>[];
    expect(await http.runWithClient(s.retryPendingAttachments, () => _cloud(failed, storageStatus: 500)), 0);
    expect(s.attachmentsOf(student.id)!.syncStatus, 'pending');

    final ok = <http.BaseRequest>[];
    expect(await http.runWithClient(s.retryPendingAttachments, () => _cloud(ok)), 1);
    expect(s.attachmentsOf(student.id)!.syncStatus, 'synced');
    expect(s.attachmentsOf(student.id)!.birthCertificatePath, endsWith('birth_certificate.png'));
    await s.flush();
  });

  test('فتح ملف الطالب ينزّل الملف من مساره', () async {
    final s = _store();
    final student = s.students.first;
    final tenantId = s.currentTenant!.id;
    final path = '$tenantId/${student.id}/student_id_photo.png';

    final seen = <http.BaseRequest>[];
    final fetched = await http.runWithClient(
      () => s.loadAttachments(student.id),
      () => MockClient((request) async {
        seen.add(request);
        if (request.url.path.startsWith('/storage/')) {
          return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/png'});
        }
        return http.Response(
          jsonEncode([
            {'id': student.id, 'student_id_photo_path': path, 'birth_certificate_path': null},
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    expect(seen.any((r) => r.url.path.endsWith('/storage/v1/object/student-docs/$path')), isTrue);
    expect(fetched?.studentIdPhoto, startsWith('data:image/png;base64,'));
    expect(fetched?.studentIdPhotoPath, path);
    expect(s.attachmentsOf(student.id)?.studentIdPhoto, isNotEmpty, reason: 'يبقى مخبّأً بعدها');
    await s.flush();
  });

  test('المرفق المحفوظ محلياً لا يُنزَّل مرة أخرى', () async {
    final s = _store();
    final student = s.students.first;
    s.attachmentsByStudent[student.id] = StudentAttachments(id: student.id, studentIdPhoto: _png);

    final seen = <http.BaseRequest>[];
    final fetched = await http.runWithClient(() => s.loadAttachments(student.id), () => _cloud(seen));

    expect(seen, isEmpty, reason: 'لا شبكة لما هو حاضر');
    expect(fetched?.studentIdPhoto, _png);
    await s.flush();
  });

  test('حذف الطالب يحذف ملفاته ثم صفه', () async {
    final s = _store();
    final student = Student(
      id: s.newId(),
      fullName: 'طالب بلا ذمم',
      gradeLevel: s.gradeOptions.first,
      section: '',
      phone: '0599123123',
      parentName: 'ولي',
      parentPhone: '0598123123',
      nationalId: '401092581',
      balance: 0,
      status: 'active',
    );
    s.students.insert(0, student);
    final path = '${s.currentTenant!.id}/${student.id}/student_id_photo.png';
    s.attachmentsByStudent[student.id] = StudentAttachments(
      id: student.id,
      studentIdPhoto: _png,
      studentIdPhotoPath: path,
    );

    final seen = <http.BaseRequest>[];
    await http.runWithClient(() async {
      s.deleteStudent(student.id);
      // الحذف السحابي يجري بعد الحذف المحلي بلا انتظار
      await Future<void>.delayed(Duration.zero);
    }, () => _cloud(seen));

    final removal = seen.where((r) => r.method == 'DELETE').toList();
    expect(removal.any((r) => r.url.path.endsWith('/storage/v1/object/student-docs')), isTrue, reason: 'الملف');
    expect(removal.any((r) => r.url.path.endsWith('/rest/v1/student_attachments')), isTrue, reason: 'الصف');
    expect(s.attachmentsOf(student.id), isNull);
    await s.flush();
  });
}
