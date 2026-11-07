/// قراءة الجدول وكتابته — المقابل لـ `timetable.service.ts` و`PortalService.getTeacherTimetable`.
///
/// صفّان لكل عام بمعرّف حتمي: المسودة يُحرَّر عليها، والمعتمد نسخة منها عند «اعتماد» وهو ما يراه
/// المعلم. في الموبايل مباشرة على السحابة كالرواتب والدوام، فتحتاج اتصالاً.
library;

import 'dart:convert';

import '../models/models.dart';
import 'supabase.dart';
import 'timetable_model.dart';

String timetableId(String yearId, String status) => 'tt_${yearId}_$status';
String coverId(String date, String roomId, int period) => 'cov_${date}_${roomId}_$period';

class TimetableRow {
  const TimetableRow({
    required this.id,
    required this.yearId,
    required this.status,
    required this.entries,
    required this.rules,
    this.publishedAt,
    this.publishedBy,
    this.createdAt,
  });

  factory TimetableRow.fromMap(Map<String, dynamic> m) => TimetableRow(
        id: '${m['id'] ?? ''}',
        yearId: '${m['academic_year_id'] ?? ''}',
        status: '${m['status'] ?? 'draft'}',
        entries: entriesFromJson(m['entries']),
        rules: TimetableRules.fromMap(m['rules']),
        publishedAt: m['published_at']?.toString(),
        publishedBy: m['published_by']?.toString(),
        createdAt: m['created_at']?.toString(),
      );

  final String id;
  final String yearId;
  final String status;
  final List<TimetableEntry> entries;
  final TimetableRules rules;
  final String? publishedAt;
  final String? publishedBy;
  final String? createdAt;

  Map<String, dynamic> _row(String tenantId, String now) => {
        'id': id,
        'tenant_id': tenantId,
        'academic_year_id': yearId,
        'status': status,
        'entries': [for (final e in entries) e.toJson()],
        'rules': rules.raw,
        'published_at': publishedAt,
        'published_by': publishedBy,
        'created_at': createdAt ?? now,
        'updated_at': now,
      };
}

/// «المسودة تختلف عن المعتمد».
String entriesSignature(List<TimetableEntry> entries) => jsonEncode([for (final e in entries) e.toJson()]);

class TimetableService {
  TimetableService._();

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// جدولا العام، و`null` إن لم تُجب السحابة.
  static Future<({TimetableRow? draft, TimetableRow? live})?> load(String yearId) async {
    final rows = await supabaseSelect('timetables', filters: {'academic_year_id': 'eq.$yearId'});
    if (rows == null) return null;
    final list = [for (final r in rows) TimetableRow.fromMap(r)];
    return (
      draft: list.where((t) => t.status == 'draft').firstOrNull,
      live: list.where((t) => t.status == 'live').firstOrNull,
    );
  }

  /// يكتب حصص المسودة و/أو قيودها، وينشئها أول مرة.
  static Future<TimetableRow> saveDraft({
    required String tenantId,
    required String yearId,
    required TimetableRow? existing,
    List<TimetableEntry>? entries,
    TimetableRules? rules,
  }) async {
    final now = _now();
    final row = TimetableRow(
      id: existing?.id ?? timetableId(yearId, 'draft'),
      yearId: yearId,
      status: 'draft',
      entries: entries ?? existing?.entries ?? const [],
      rules: rules ?? existing?.rules ?? const TimetableRules({}),
      publishedAt: existing?.publishedAt,
      publishedBy: existing?.publishedBy,
      createdAt: existing?.createdAt ?? now,
    );
    await supabaseUpsert('timetables', [row._row(tenantId, now)]);
    return row;
  }

  /// «اعتماد»: المعتمد نسخة من المسودة، وهو ما يراه المعلمون.
  static Future<({TimetableRow draft, TimetableRow live})> publish({
    required String tenantId,
    required TimetableRow draft,
    required TimetableRow? live,
    required String actor,
  }) async {
    final now = _now();
    final nextLive = TimetableRow(
      id: live?.id ?? timetableId(draft.yearId, 'live'),
      yearId: draft.yearId,
      status: 'live',
      entries: draft.entries,
      rules: draft.rules,
      publishedAt: now,
      publishedBy: actor,
      createdAt: live?.createdAt ?? now,
    );
    final nextDraft = TimetableRow(
      id: draft.id,
      yearId: draft.yearId,
      status: 'draft',
      entries: draft.entries,
      rules: draft.rules,
      publishedAt: now,
      publishedBy: actor,
      createdAt: draft.createdAt,
    );
    await supabaseUpsert('timetables', [nextLive._row(tenantId, now), nextDraft._row(tenantId, now)]);
    return (draft: nextDraft, live: nextLive);
  }

  /// احتياط الشهر، و`null` إن لم تُجب السحابة.
  static Future<List<TimetableCover>?> coversOfMonth(String month) async {
    final rows = await supabaseSelect(
      'timetable_covers',
      filters: {'and': '(date.gte.$month-01,date.lte.$month-31)'},
      limit: 2000,
    );
    return rows == null ? null : [for (final r in rows) TimetableCover.fromMap(r)];
  }

  static Future<void> saveCover({required String tenantId, required String yearId, required TimetableCover cover}) async {
    final now = _now();
    await supabaseUpsert('timetable_covers', [
      {
        'id': coverId(cover.date, cover.roomId, cover.period),
        'tenant_id': tenantId,
        'academic_year_id': yearId,
        'date': cover.date,
        'period': cover.period,
        'room_id': cover.roomId,
        'group_id': cover.groupId.isEmpty ? null : cover.groupId,
        'absent_teacher_id': cover.absentTeacherId,
        'cover_teacher_id': cover.coverTeacherId.isEmpty ? null : cover.coverTeacherId,
        'updated_at': now,
      },
    ]);
  }

  static Future<void> removeCover(TimetableCover cover) =>
      supabaseDelete('timetable_covers', {'id': 'eq.${coverId(cover.date, cover.roomId, cover.period)}'});

  /// بوابة المعلم: السياسات تعيد المعتمد وحده واحتياطه هو. `null` إن لم تُجب السحابة.
  static Future<({List<TimetableEntry> entries, List<TimetableCover> covers})?> teacherView() async {
    final tables = await supabaseSelect('timetables', columns: 'academic_year_id,entries,published_at', filters: {'status': 'eq.live'});
    final covers = await supabaseSelect(
      'timetable_covers',
      filters: {'date': 'gte.${isoDate(DateTime.now())}'},
      order: 'date',
      limit: 50,
    );
    if (tables == null || covers == null) return null;
    return (
      entries: [
        for (final t in tables) ...entriesFromJson(t['entries']),
      ],
      covers: [for (final c in covers) TimetableCover.fromMap(c)],
    );
  }
}
