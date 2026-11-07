/// دوام الموظفين وإجازاتهم — المقابل لـ `staff.service.ts` و`types/staff.ts` و`approvedLeaveOn`.
///
/// الويب يحفظهما في جهازه ويزامنهما؛ الجوال يقرأ ويكتب في السحابة مباشرة (جدولا
/// `staff_attendance` و`leave_requests`)، فما يرصده أحدهما يراه الآخر بعد مزامنته.
/// ما جُلب يُحفظ في الذاكرة دقيقتين: الشاشة تتحدث مع كل مزامنة ولا تعيد الطلب.
library;

import 'supabase.dart';

/// `present` أو `absent` أو `late`.
const staffDayLabels = {'present': 'حاضر', 'absent': 'غائب', 'late': 'متأخر'};

/// المعرّف `sa_<الموظف>_<اليوم>`: يوم واحد لكل موظف، والتكرار آمن.
String staffAttendanceId(String teacherId, String date) => 'sa_${teacherId}_$date';

class StaffDay {
  const StaffDay({required this.teacherId, required this.date, required this.status, this.periods});

  final String teacherId;
  final String date;
  final String status;

  /// حصص اليوم حين تُرصد يومياً (إعدادات الرواتب في الويب).
  final double? periods;

  factory StaffDay.fromMap(Map<String, dynamic> m) =>
      StaffDay(teacherId: '${m['teacher_id'] ?? ''}', date: '${m['date'] ?? ''}'.substring(0, 10), status: '${m['status'] ?? ''}', periods: m['periods'] is num ? (m['periods'] as num).toDouble() : double.tryParse('${m['periods'] ?? ''}'));
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.teacherId,
    required this.fromDate,
    required this.toDate,
    this.reason = '',
    this.status = 'pending',
    this.paid,
  });

  final String id;
  final String teacherId;
  final String fromDate;
  final String toDate;
  final String reason;

  /// `pending` أو `approved` أو `rejected`
  final String status;
  final bool? paid;

  String get statusLabel => status == 'pending'
      ? 'معلّق'
      : status == 'rejected'
          ? 'مرفوض'
          : paid == false
              ? 'بلا راتب'
              : 'موافق';

  factory LeaveRequest.fromMap(Map<String, dynamic> m) => LeaveRequest(
        id: '${m['id']}',
        teacherId: '${m['teacher_id'] ?? ''}',
        fromDate: '${m['from_date'] ?? ''}',
        toDate: '${m['to_date'] ?? m['from_date'] ?? ''}',
        reason: '${m['reason'] ?? ''}',
        status: '${m['status'] ?? 'pending'}',
        paid: m['paid'] is bool ? m['paid'] as bool : null,
      );
}

LeaveRequest? approvedLeaveOn(List<LeaveRequest> leaves, String teacherId, String date) => leaves
    .where((l) => l.teacherId == teacherId && l.status == 'approved' && l.fromDate.compareTo(date) <= 0 && date.compareTo(l.toDate) <= 0)
    .firstOrNull;

class StaffService {
  StaffService._();

  static const _ttl = Duration(minutes: 2);
  static final _days = <String, ({DateTime at, List<StaffDay> rows})>{};
  static ({DateTime at, List<LeaveRequest> rows})? _leaves;

  static bool _fresh(DateTime at) => DateTime.now().difference(at) < _ttl;

  /// أيام الموظفين من [from] إلى [to] شاملاً. null عند تعذّر الشبكة.
  static Future<List<StaffDay>?> days(String from, String to, {bool force = false}) async {
    final key = '$from|$to';
    final hit = _days[key];
    if (!force && hit != null && _fresh(hit.at)) return hit.rows;
    final rows = await supabaseSelect(
      'staff_attendance',
      columns: 'teacher_id,date,status,periods',
      filters: {'and': '(date.gte.$from,date.lte.$to)'},
      limit: 5000,
    );
    if (rows == null) return hit?.rows;
    final list = [for (final r in rows) StaffDay.fromMap(r)];
    _days[key] = (at: DateTime.now(), rows: list);
    return list;
  }

  static Future<List<LeaveRequest>?> leaves({bool force = false}) async {
    final hit = _leaves;
    if (!force && hit != null && _fresh(hit.at)) return hit.rows;
    final rows = await supabaseSelect('leave_requests', order: 'from_date.desc', limit: 1000);
    if (rows == null) return hit?.rows;
    final list = [for (final r in rows) LeaveRequest.fromMap(r)];
    _leaves = (at: DateTime.now(), rows: list);
    return list;
  }

  /// يوم موظف: حالة أو مسح (null). يُحدَّث المحفوظ في الذاكرة بلا طلب جديد.
  static Future<void> setDay(String tenantId, String teacherId, String date, String? status) async {
    final id = staffAttendanceId(teacherId, date);
    if (status == null) {
      await supabaseDelete('staff_attendance', {'id': 'eq.$id'});
    } else {
      final now = DateTime.now().toUtc().toIso8601String();
      await supabaseUpsert('staff_attendance', [
        {'id': id, 'tenant_id': tenantId, 'teacher_id': teacherId, 'date': date, 'status': status, 'updated_at': now},
      ]);
    }
    for (final e in _days.entries.toList()) {
      final p = e.key.split('|');
      if (date.compareTo(p[0]) < 0 || date.compareTo(p[1]) > 0) continue;
      _days[e.key] = (
        at: e.value.at,
        rows: [
          for (final d in e.value.rows)
            if (!(d.teacherId == teacherId && d.date == date)) d,
          if (status != null) StaffDay(teacherId: teacherId, date: date, status: status),
        ],
      );
    }
  }

  /// الموافقة (مدفوعة أو لا) أو الرفض.
  static Future<void> decideLeave(String id, {required bool approve, bool paid = false, String decidedBy = 'الإدارة'}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await supabaseUpdate('leave_requests', {'id': 'eq.$id'}, {
      'status': approve ? 'approved' : 'rejected',
      'paid': approve ? paid : null,
      'decided_by': decidedBy,
      'decided_at': now,
      'updated_at': now,
    });
    _leaves = null;
  }
}

/// راتب موظف في شهر — `payroll_entries` (`types/payroll.ts`). المعرّف `pe_<الموظف>_<الشهر>`.
class PayrollEntryRow {
  const PayrollEntryRow({
    required this.id,
    required this.teacherId,
    required this.month,
    this.sessions,
    this.adjustments = const [],
    this.advanceRecovered,
    this.netOverride,
    this.payoutId = '',
    this.hasSnapshot = false,
    this.paid,
    this.absentDays,
  });

  final String id;
  final String teacherId;
  final String month;
  final double? sessions;
  final List<({String label, double amount})> adjustments;
  final double? advanceRecovered;
  final double? netOverride;
  final String payoutId;
  final bool hasSnapshot;

  /// المصروف كما ثُبّت مع الحساب (`snapshot.paid`): صفر = شهر سُوّي بلا سند حين أكلت السلفة راتبه
  final double? paid;

  /// أيام الغياب المخصومة إن عدّلها المدير عن الدوام
  final double? absentDays;

  static double? _n(Object? v) => v == null ? null : v is num ? v.toDouble() : double.tryParse('$v');

  factory PayrollEntryRow.fromMap(Map<String, dynamic> m) => PayrollEntryRow(
        id: '${m['id']}',
        teacherId: '${m['teacher_id'] ?? ''}',
        month: '${m['month'] ?? ''}',
        sessions: _n(m['sessions']),
        adjustments: [
          if (m['adjustments'] is List)
            for (final a in m['adjustments'] as List)
              if (a is Map) (label: '${a['label'] ?? ''}', amount: _n(a['amount']) ?? 0),
        ],
        advanceRecovered: _n(m['advance_recovered']),
        netOverride: _n(m['net_override']),
        payoutId: '${m['payout_id'] ?? ''}',
        hasSnapshot: m['snapshot'] != null,
        paid: m['snapshot'] is Map ? _n((m['snapshot'] as Map)['paid']) : null,
        absentDays: _n(m['absent_days']),
      );
}

String payrollEntryId(String teacherId, String month) => 'pe_${teacherId}_$month';

/// سطور الرواتب في السحابة: تُقرأ كلها لرصيد السلف، ويُكتب سطر الشهر عند الصرف.
class PayrollEntries {
  PayrollEntries._();

  static Future<List<PayrollEntryRow>?> all() async {
    final rows = await supabaseSelect(
      'payroll_entries',
      columns: 'id,teacher_id,month,sessions,absent_days,adjustments,advance_recovered,net_override,payout_id,snapshot',
      limit: 5000,
    );
    return rows == null ? null : [for (final r in rows) PayrollEntryRow.fromMap(r)];
  }

  /// إلغاء سند راتب يعيد شهره مفتوحاً: يفك السند والحساب المثبّت ومقتطع السلفة
  /// من سطره — `FinanceService.cancelSpend`.
  static Future<void> clearPayout(String payoutId) => supabaseUpdate(
        'payroll_entries',
        {'payout_id': 'eq.$payoutId'},
        {
          'payout_id': null,
          'snapshot': null,
          'advance_recovered': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

  /// يُثبّت الحساب كما صُرف ومقتطع السلفة وربط السند في سطر الشهر. بلا سند (`payoutId` فارغ):
  /// شهر أكلت السلفة راتبه كله، يُسوّى بلا نقد ويُقتطع من رصيدها.
  static Future<void> markPaid({
    required String tenantId,
    required String teacherId,
    required String month,
    required String payoutId,
    required Map<String, dynamic> snapshot,
    required double advanceRecovered,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await supabaseUpsert('payroll_entries', [
      {
        'id': payrollEntryId(teacherId, month),
        'tenant_id': tenantId,
        'teacher_id': teacherId,
        'month': month,
        'payout_id': payoutId.isEmpty ? null : payoutId,
        'snapshot': snapshot,
        'advance_recovered': advanceRecovered,
        'updated_at': now,
      },
    ]);
  }
}
