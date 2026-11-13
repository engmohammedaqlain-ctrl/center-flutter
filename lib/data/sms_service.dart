import '../models/models.dart';
import 'sms_text.dart';
import 'supabase.dart';

/// رسائل SMS عبر «بوابة الرسائل» — `sms.service.ts`: كله عن طريق دالة السيرفر `school-sms`
/// بجلسة المستخدم، وللمدير بس. ما في صلاحيات أندرويد: جوال الشريحة هو اللي بيبعث.

class SmsException implements Exception {
  const SmsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SmsTemplate {
  const SmsTemplate({required this.title, required this.body});
  final String title;
  final String body;

  factory SmsTemplate.fromJson(Map m) => SmsTemplate(title: '${m['title'] ?? ''}', body: '${m['body'] ?? ''}');
  Map<String, dynamic> toJson() => {'title': title, 'body': body};
}

/// حالة ربط المدرسة ببوابة الرسائل.
class SmsStatus {
  const SmsStatus({
    required this.connected,
    this.name = '',
    this.deviceModel,
    this.lastSeen,
    this.templates = const [],
    this.error,
  });

  final bool connected;
  final String name;

  /// جوال الشريحة: موديله وآخر ظهور. فاضي = الجوال ما دخل التطبيق لسا.
  final String? deviceModel;
  final DateTime? lastSeen;
  final List<SmsTemplate> templates;
  final String? error;

  bool get hasDevice => lastSeen != null;

  /// «متصل» لو ظهر آخر 20 دقيقة: بيفحص لحاله كل 15.
  bool get online => lastSeen != null && DateTime.now().difference(lastSeen!).inMinutes <= 20;

  SmsStatus withTemplates(List<SmsTemplate> list) => SmsStatus(
        connected: connected,
        name: name,
        deviceModel: deviceModel,
        lastSeen: lastSeen,
        templates: list,
        error: error,
      );

  factory SmsStatus.fromJson(Map<String, dynamic> m) {
    final device = m['device'];
    final seen = device is Map ? DateTime.tryParse('${device['last_seen'] ?? ''}') : null;
    final model = device is Map && device['model'] != null ? '${device['model']}' : null;
    return SmsStatus(
      connected: m['connected'] == true,
      name: '${m['name'] ?? ''}',
      deviceModel: model,
      lastSeen: seen?.toLocal(),
      templates: _templates(m['templates']),
      error: m['error'] == null ? null : '${m['error']}',
    );
  }
}

List<SmsTemplate> _templates(Object? raw) =>
    raw is List ? [for (final t in raw) if (t is Map) SmsTemplate.fromJson(t)] : const [];

enum SmsDelivery { pending, sent, failed }

/// رسالة انبعتت من البوابة بحالتها. `ref` = رقم الطالب.
class SentSms {
  const SentSms({
    required this.id,
    required this.phone,
    required this.body,
    required this.parts,
    required this.status,
    required this.error,
    required this.ref,
    required this.createdAt,
    required this.sentAt,
  });

  final int id;
  final String phone;
  final String body;

  /// كم رسالة انحسبت من الرصيد.
  final int parts;
  final SmsDelivery status;
  final String? error;
  final String? ref;
  final DateTime? createdAt;
  final DateTime? sentAt;

  DateTime? get time => sentAt ?? createdAt;

  factory SentSms.fromJson(Map m) {
    final st = '${m['status'] ?? ''}';
    return SentSms(
      id: (m['id'] as num?)?.toInt() ?? 0,
      phone: '${m['phone'] ?? ''}',
      body: '${m['body'] ?? ''}',
      parts: (m['parts'] as num?)?.toInt() ?? 1,
      status: st == 'sent' ? SmsDelivery.sent : (st == 'failed' ? SmsDelivery.failed : SmsDelivery.pending),
      error: m['error'] == null ? null : '${m['error']}',
      ref: m['ref'] == null ? null : '${m['ref']}',
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}')?.toLocal(),
      sentAt: DateTime.tryParse('${m['sent_at'] ?? ''}')?.toLocal(),
    );
  }
}

class SmsPeriod {
  const SmsPeriod({this.messages = 0, this.parts = 0, this.failed = 0});

  /// رسائل انبعثت.
  final int messages;

  /// اللي انحسب من الرصيد (الرسالة الطويلة أكثر من جزء).
  final int parts;
  final int failed;

  factory SmsPeriod.fromJson(Object? m) => m is Map
      ? SmsPeriod(
          messages: (m['messages'] as num?)?.toInt() ?? 0,
          parts: (m['parts'] as num?)?.toInt() ?? 0,
          failed: (m['failed'] as num?)?.toInt() ?? 0,
        )
      : const SmsPeriod();
}

/// رصيد الشريحة: عدد رسائله، والمستعمل منه، والباقي، ومدته بالأيام.
class SmsBundle {
  const SmsBundle({
    required this.size,
    required this.used,
    required this.remaining,
    required this.start,
    required this.daysLeft,
    required this.expired,
  });

  final int size;
  final int used;
  final int remaining;
  final DateTime? start;

  /// الباقي من مدته (فاضي = بلا مدة).
  final int? daysLeft;
  final bool expired;

  bool get low => expired || remaining <= (size * 0.1 > 20 ? size * 0.1 : 20);
}

class SmsUsage {
  const SmsUsage({required this.periods, required this.bundle});

  /// today / yesterday / week / month.
  final Map<String, SmsPeriod> periods;
  final SmsBundle? bundle;

  factory SmsUsage.fromJson(Map<String, dynamic> m) {
    final b = m['bundle'];
    return SmsUsage(
      periods: {for (final k in const ['today', 'yesterday', 'week', 'month']) k: SmsPeriod.fromJson(m[k])},
      bundle: b is Map
          ? SmsBundle(
              size: (b['size'] as num?)?.toInt() ?? 0,
              used: (b['used'] as num?)?.toInt() ?? 0,
              remaining: (b['remaining'] as num?)?.toInt() ?? 0,
              start: DateTime.tryParse('${b['start'] ?? ''}')?.toLocal(),
              daysLeft: (b['days_left'] as num?)?.toInt(),
              expired: b['expired'] == true,
            )
          : null,
    );
  }
}

class SmsService {
  const SmsService();

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final data = await supabaseInvoke('school-sms', body);
    final err = data['error'];
    if (err != null) throw SmsException('$err');
    return data;
  }

  Future<SmsStatus> status() async {
    final data = await supabaseInvoke('school-sms', {'action': 'status'});
    // «تعذّر الوصول لبوابة الرسائل» بيجي مع connected:false، مش خطأ
    if (data['error'] != null && data['connected'] == null) throw SmsException('${data['error']}');
    return SmsStatus.fromJson(data);
  }

  Future<SmsStatus> connect(String token) async => SmsStatus.fromJson(await _call({'action': 'connect', 'token': token.trim()}));

  Future<SmsStatus> disconnect() async => SmsStatus.fromJson(await _call({'action': 'disconnect'}));

  Future<int> send(List<SmsMessage> messages) async {
    final data = await _call({'action': 'send', 'messages': [for (final m in messages) m.toJson()]});
    final ids = data['ids'];
    return ids is List ? ids.length : messages.length;
  }

  Future<SmsUsage> usage() async => SmsUsage.fromJson(await _call({'action': 'usage'}));

  /// شحن +: بينضاف للرصيد، والأيام (لو في) من هلأ.
  Future<SmsUsage> topUp(int count, int? days) async =>
      SmsUsage.fromJson(await _call({'action': 'bundle', 'topup': count, 'days': days}));

  /// تصحيح الرصيد: الباقي فعلياً هلأ.
  Future<SmsUsage> setBalance(int balance) async =>
      SmsUsage.fromJson(await _call({'action': 'bundle', 'balance': balance}));

  /// آخر 150 رسالة للمدرسة، الأحدث أولاً.
  Future<List<SentSms>> history() async {
    final data = await _call({'action': 'history'});
    final list = data['messages'];
    return list is List ? [for (final m in list) if (m is Map) SentSms.fromJson(m)] : const [];
  }

  Future<List<SmsTemplate>> saveTemplates(List<SmsTemplate> templates) async {
    final data = await _call({'action': 'save_templates', 'templates': [for (final t in templates) t.toJson()]});
    return _templates(data['templates']);
  }
}

/// سبب فشل الإرسال من الجوال، بكلام مفهوم.
String smsErrorLabel(String? code) => switch (code) {
      'no_service' => 'ما في تغطية',
      'radio_off' => 'الجوال على وضع الطيران',
      'limit_exceeded' => 'أندرويد رفض: رسائل كثيرة',
      'no_confirmation' => 'ما وصل تأكيد من الشبكة',
      'sim_unavailable' => 'الشريحة مش موجودة',
      'no_sms_permission' => 'التطبيق بلا صلاحية الرسائل',
      'generic_failure' => 'رفضتها الشبكة (الرصيد؟)',
      null || '' => 'فشلت',
      final String c => c,
    };

String smsTimeAgo(DateTime? t) {
  if (t == null) return '';
  final m = (DateTime.now().difference(t).inSeconds / 60).round();
  if (m < 1) return 'هلأ';
  if (m < 60) return 'قبل $m د';
  if (m < 1440) return 'قبل ${(m / 60).round()} س';
  return 'قبل ${(m / 1440).round()} يوم';
}

/// «يوم» «يومين» «3 أيام» «32 يوم».
String smsDays(int n) => n == 1 ? 'يوم' : (n == 2 ? 'يومين' : (n <= 10 ? '$n أيام' : '$n يوم'));

/// الطالب كما يحتاجه نص الرسالة. الاسم الأول من الاسم الكامل لو مش محفوظ لحاله.
SmsStudent smsStudentOf(Student s) {
  final first = s.firstName.trim().isNotEmpty ? s.firstName.trim() : s.fullName.trim().split(RegExp(r'\s+')).first;
  return SmsStudent(
    id: s.id,
    firstName: first,
    fullName: s.fullName,
    parentName: s.parentName,
    parentPhone: s.parentPhone,
    phone: s.phone,
    gradeLevel: s.gradeLevel.trim(),
    section: s.section.trim(),
  );
}
