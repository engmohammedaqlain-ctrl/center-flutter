import 'dart:convert';

import 'package:http/http.dart' as http;

/// إعدادات الاتصال بـ Supabase — المقابل لـ `lib/supabase.ts`.
///
/// النسخة المكتبية تقرأ العنوان والمفتاح من `.env` مع إمكانية تجاوزهما من
/// localStorage. تثبيتهما في الكود هنا كان يمنع أي تغيير بعد البناء.
class SupabaseConfig {
  static const defaultUrl = 'https://tmybbunguiurisdcvrqo.supabase.co';
  static const defaultKey = 'sb_publishable_TowjoMRcd5BJtaUqmCs6Sw_IHhVd3Jj';

  static const urlSettingKey = 'supabase_custom_url';
  static const keySettingKey = 'supabase_custom_key';

  static String url = defaultUrl;
  static String key = defaultKey;

  static void applyOverrides(Map<String, String> settings) {
    final u = settings[urlSettingKey]?.trim();
    final k = settings[keySettingKey]?.trim();
    url = (u == null || u.isEmpty) ? defaultUrl : u;
    key = (k == null || k.isEmpty) ? defaultKey : k;
  }

  static bool get isCustom => url != defaultUrl || key != defaultKey;

  static Map<String, String> get headers => {
        'apikey': key,
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };
}

/// استعلام `select` عام على أي جدول.
Future<List<Map<String, dynamic>>?> supabaseSelect(
  String table, {
  Map<String, String> filters = const {},
  String columns = '*',
  String? order,
  int? limit,
  Map<String, String> extraHeaders = const {},
}) async {
  final params = <String, String>{'select': columns, ...filters};
  if (order != null) params['order'] = order;
  if (limit != null) params['limit'] = '$limit';
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(queryParameters: params);
  try {
    final res = await http.get(uri, headers: {...SupabaseConfig.headers, ...extraHeaders});
    if (res.statusCode >= 400) return null;
    final data = jsonDecode(res.body);
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } catch (_) {
    return null;
  }
}

/// إدراج أو تحديث صفوف مع الدمج على `id`.
Future<void> supabaseUpsert(String table, List<Map<String, dynamic>> rows) async {
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(
    queryParameters: {'on_conflict': 'id'},
  );
  final res = await http.post(
    uri,
    headers: {
      ...SupabaseConfig.headers,
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    },
    body: jsonEncode(rows),
  );
  if (res.statusCode >= 400) {
    throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  }
}

Future<void> supabaseDelete(String table, Map<String, String> filters) async {
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(queryParameters: filters);
  final res = await http.delete(uri, headers: SupabaseConfig.headers);
  if (res.statusCode >= 400) {
    throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  }
}
