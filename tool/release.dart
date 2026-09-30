/// قائمة النشر: أمرٌ واحد، ثم اختيارٌ من قائمة بدل حفظ المعاملات.
///
///     dart run tool/release.dart
///
/// لا ينشر بنفسه: يسأل، ثم يشغّل `tool/publish_release.dart` بالمعاملات الصحيحة.
/// المدارس تُعرض بأسمائها ويُختار منها بالأرقام، وبناءٌ لكل المدارس لا يُعرض
/// لمدارس بعينها — بناءٌ كهذا يكتب قائمة النسخ من جديد، فتفقد بقية المدارس
/// أيقوناتها عند التحديث.
///
/// حساب المطور يُقرأ من DEV_USERNAME / DEV_PASSWORD إن وُجدا، وإلا يُسأل عنه مرة
/// ويُعرض حفظه في `%APPDATA%\center-release\dev_account.json` — خارج المستودع.
library;

import 'dart:convert';
import 'dart:io';

import 'publish_release.dart' show latestManifestUrl, supabaseKey, supabaseUrl;
import 'school_apk.dart' show normalizeSchoolCode, schoolCodePattern;

typedef School = ({String code, String name});
typedef DevAccount = ({String user, String password});

Future<void> main() async {
  if (!File('tool/publish_release.dart').existsSync()) {
    stderr.writeln('Run this from the project folder: dart run tool/release.dart');
    exit(64);
  }

  final published = await _fetchJson(latestManifestUrl);
  final publishedSchools = published?['schools'] is Map ? (published!['schools'] as Map).keys.map((k) => '$k').toSet() : <String>{};

  stdout.writeln();
  stdout.writeln('=== Center release ===');
  if (published != null) {
    stdout.writeln('Published now: ${published['version']} (build ${published['versionCode']}), '
        '${publishedSchools.length} school copies');
  }
  stdout.writeln();
  stdout.writeln('  1  New build for ALL schools    (APK - users install it)');
  stdout.writeln('  2  Silent update for everyone   (Shorebird patch - Dart code changes only)');
  stdout.writeln('  3  Add schools to last build    (a school added after the last build)');
  stdout.writeln('  4  Test copy for one school     (builds only, uploads nothing)');
  stdout.writeln('  0  Exit');
  stdout.writeln();

  switch (_ask('Choose', fallback: '0')) {
    case '1':
      await _newBuild();
    case '2':
      await _silentUpdate();
    case '3':
      await _addSchools(publishedSchools, hasBuild: published != null);
    case '4':
      await _testCopy();
    default:
      stdout.writeln('Bye');
  }
}

// ── الخيارات ─────────────────────────────────────────────────────────────────────

Future<void> _newBuild() async {
  final account = await _devAccount();
  final schools = await _listSchools(account);
  if (schools == null) exit(1);
  stdout.writeln('\nCopies will be built for ${schools.length} schools: ${schools.map((s) => s.code).join(', ')}');

  final notes = _askNotes();
  final optional = _yes('Let users skip this update? (mandatory if you say no)', fallback: false);
  if (!_yes('\nStart the build and publish it to everyone?', fallback: false)) return;
  if (!await _ensureCommitted(notes)) return;
  await _publish([
    '--notes', notes, //
    if (optional) '--optional',
  ], account: account);
}

Future<void> _silentUpdate() async {
  stdout.writeln('\nOnly for Dart code changes. A new package, Android setting, icon or permission needs option 1.');
  final notes = _askNotes();
  if (!_yes('\nPublish the silent update to everyone?', fallback: false)) return;
  if (!await _ensureCommitted(notes)) return;
  await _publish(['--patch', '--notes', notes]);
}

Future<void> _addSchools(Set<String> haveCopy, {required bool hasBuild}) async {
  if (!hasBuild) {
    stdout.writeln('Nothing is published yet - use option 1 first.');
    return;
  }
  final account = await _devAccount();
  final schools = await _listSchools(account);
  if (schools == null) exit(1);

  final missing = schools.where((s) => !haveCopy.contains(s.code)).toList();
  _printSchools(schools, haveCopy);
  stdout.writeln('\n${missing.length} schools have no copy yet.');
  final picked = _pickSchools(schools, prompt: 'Numbers (e.g. 1,4,7), "new" for all without a copy, or empty to cancel', missing: missing);
  if (picked.isEmpty) return;

  stdout.writeln('\nAdding: ${picked.map((s) => '${s.code} (${s.name})').join(', ')}');
  if (!_yes('Continue?', fallback: true)) return;
  await _publish(['--add-schools', picked.map((s) => s.code).join(',')], account: account);
}

Future<void> _testCopy() async {
  final account = await _devAccount(optional: true);
  final schools = account == null ? null : await _listSchools(account);

  String code;
  if (schools == null) {
    code = normalizeSchoolCode(_ask('School code'));
  } else {
    _printSchools(schools, const {});
    final picked = _pickSchools(schools, prompt: 'Number of the school', single: true);
    if (picked.isEmpty) return;
    code = picked.single.code;
  }
  if (!schoolCodePattern.hasMatch(code)) {
    stdout.writeln('Not a school code: $code');
    return;
  }

  final ok = await _publish(['--dry-run', '--schools', code, '--notes', 'Test build'], allowDirty: true);
  if (ok) {
    final apk = Directory('build/release')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toUpperCase().endsWith('-$code.APK'))
        .toList();
    if (apk.isNotEmpty) stdout.writeln('\nInstall this on a phone to check it:\n  ${apk.first.absolute.path}');
  }
}

// ── حفظ التعديلات ────────────────────────────────────────────────────────────────

/// المنشور يجب أن يطابق كوميتاً: التحديث الصامت يُبنى لاحقاً فوقه. تعديلاتٌ غير
/// محفوظة تُعرض ويُعرض حفظها ورفعها بدل أن يتوقف النشر بخطأ.
Future<bool> _ensureCommitted(String notes) async {
  final status = await _git(['status', '--porcelain']);
  if (status == null) {
    stdout.writeln('Could not read git status.');
    return false;
  }
  if (status.trim().isEmpty) return true;

  stdout.writeln('\nThese changes are not committed yet:');
  for (final line in const LineSplitter().convert(status)) {
    if (line.trim().isNotEmpty) stdout.writeln('  $line');
  }
  stdout.writeln('The release must match a saved commit, so later silent updates build on the same code.');
  if (!_yes('Commit and push them now?', fallback: true)) {
    stdout.writeln('Stopped - nothing was published.');
    return false;
  }

  final message = 'Release: $notes';
  if (await _git(['add', '-A']) == null || await _git(['commit', '-m', message]) == null) {
    stdout.writeln('The commit failed - nothing was published.');
    return false;
  }
  stdout.writeln('Committed: $message');
  // الرفع لا يوقف النشر: الكوميت محليٌّ على الأقل، ويُرفع لاحقاً بـ git push
  if (await _git(['push']) == null) {
    stdout.writeln('Push failed - the commit is saved here; run "git push" later so the team has this code.');
  } else {
    stdout.writeln('Pushed.');
  }
  return true;
}

/// مخرجات أمر git، أو `null` إن فشل (ويُطبع سببه).
Future<String?> _git(List<String> args) async {
  final result = await Process.run('git', args, stdoutEncoding: utf8, stderrEncoding: utf8);
  if (result.exitCode != 0) {
    stdout.write('${result.stderr}${result.stdout}');
    return null;
  }
  return '${result.stdout}';
}

// ── تشغيل النشر ──────────────────────────────────────────────────────────────────

/// يشغّل سكربت النشر بمخرجاته في هذه النافذة نفسها.
Future<bool> _publish(List<String> args, {DevAccount? account, bool allowDirty = false}) async {
  stdout.writeln();
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'tool/publish_release.dart', ...args, if (allowDirty) '--allow-dirty'],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      if (account != null) 'DEV_USERNAME': account.user,
      if (account != null) 'DEV_PASSWORD': account.password,
    },
  );
  final code = await process.exitCode;
  stdout.writeln(code == 0 ? '\nDone.' : '\nStopped with an error - read the lines above.');
  return code == 0;
}

// ── حساب المطور والمدارس ─────────────────────────────────────────────────────────

File get _accountFile {
  final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '.';
  return File('$base${Platform.pathSeparator}center-release${Platform.pathSeparator}dev_account.json');
}

/// من البيئة، ثم الملف المحفوظ، ثم سؤال المستخدم. [optional]: يُسمح بالتخطي.
Future<DevAccount?> _devAccount({bool optional = false}) async {
  final env = Platform.environment;
  final envUser = env['DEV_USERNAME']?.trim() ?? '';
  final envPass = env['DEV_PASSWORD'] ?? '';
  if (envUser.isNotEmpty && envPass.isNotEmpty) return (user: envUser, password: envPass);

  try {
    final saved = jsonDecode(_accountFile.readAsStringSync());
    if (saved is Map && '${saved['user'] ?? ''}'.isNotEmpty && '${saved['password'] ?? ''}'.isNotEmpty) {
      return (user: '${saved['user']}', password: '${saved['password']}');
    }
  } catch (_) {}

  stdout.writeln('\nDeveloper account (the one you use to sign in to the system as developer)');
  if (optional) stdout.writeln('Leave empty to type the school code yourself.');
  final user = _ask('Username').trim();
  if (user.isEmpty) {
    if (optional) return null;
    stdout.writeln('The developer account is needed to list the schools.');
    exit(1);
  }
  final password = _askHidden('Password');
  final account = (user: user, password: password);

  if (await _signIn(account) == null) {
    stdout.writeln('Sign-in failed - check the username and password.');
    exit(1);
  }
  if (_yes('Save it on this computer so you are not asked again?', fallback: true)) {
    _accountFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'user': user, 'password': password}));
    stdout.writeln('Saved in ${_accountFile.path} (delete the file to forget it)');
  }
  return account;
}

Future<String?> _signIn(DevAccount account) async {
  final session = await _postJson(
    '$supabaseUrl/auth/v1/token?grant_type=password',
    {'email': '${account.user.toLowerCase()}@login.center-system.app', 'password': account.password},
  );
  final token = session is Map ? '${session['access_token'] ?? ''}' : '';
  return token.isEmpty ? null : token;
}

/// المدارس النشطة بأسمائها، كما يراها سكربت النشر.
Future<List<School>?> _listSchools(DevAccount? account) async {
  if (account == null) return null;
  stdout.writeln('\nReading schools...');
  final token = await _signIn(account);
  if (token == null) {
    stdout.writeln('Developer sign-in failed. If the password changed, delete ${_accountFile.path} and try again.');
    return null;
  }
  final rows = await _getJson(
    '$supabaseUrl/rest/v1/tenants?select=code&status=eq.active&order=code',
    headers: {'Authorization': 'Bearer $token'},
  );
  if (rows is! List) {
    stdout.writeln('Could not read the schools list.');
    return null;
  }
  final codes = [
    for (final row in rows)
      if (row is Map && schoolCodePattern.hasMatch('${row['code'] ?? ''}'.trim())) normalizeSchoolCode('${row['code']}'),
  ];
  // الاسم من الدالة العامة نفسها التي يقرأ منها سكربت النشر الشعار
  final names = await Future.wait([
    for (final code in codes) _postJson('$supabaseUrl/rest/v1/rpc/get_school_download_page', {'p_code': code}),
  ]);
  return [
    for (var i = 0; i < codes.length; i++) (code: codes[i], name: names[i] is Map ? '${(names[i] as Map)['name'] ?? ''}'.trim() : ''),
  ];
}

void _printSchools(List<School> schools, Set<String> haveCopy) {
  stdout.writeln();
  final width = '${schools.length}'.length;
  for (var i = 0; i < schools.length; i++) {
    final s = schools[i];
    final mark = haveCopy.isEmpty ? '' : (haveCopy.contains(s.code) ? '  [has copy]' : '  [NEW]');
    stdout.writeln('  ${'${i + 1}'.padLeft(width)}  ${s.code.padRight(10)} ${s.name}$mark');
  }
}

List<School> _pickSchools(List<School> schools, {required String prompt, List<School>? missing, bool single = false}) {
  while (true) {
    final raw = _ask(prompt).trim().toLowerCase();
    if (raw.isEmpty) return const [];
    if (!single && raw == 'new' && missing != null) {
      if (missing.isEmpty) stdout.writeln('Every school already has a copy.');
      return missing;
    }
    final parts = raw.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null || n < 1 || n > schools.length) || (single && numbers.length != 1)) {
      stdout.writeln(single ? 'Type one number from 1 to ${schools.length}' : 'Type numbers from 1 to ${schools.length}');
      continue;
    }
    return {for (final n in numbers) schools[n! - 1]}.toList();
  }
}

// ── إدخال ────────────────────────────────────────────────────────────────────────

String _ask(String prompt, {String fallback = ''}) {
  stdout.write('$prompt: ');
  final line = stdin.readLineSync(encoding: utf8);
  final value = line?.trim() ?? '';
  return value.isEmpty ? fallback : value;
}

String _askHidden(String prompt) {
  stdout.write('$prompt: ');
  var echo = true;
  try {
    echo = stdin.echoMode;
    stdin.echoMode = false;
  } catch (_) {}
  try {
    return stdin.readLineSync(encoding: utf8) ?? '';
  } finally {
    try {
      stdin.echoMode = echo;
    } catch (_) {}
    stdout.writeln();
  }
}

bool _yes(String prompt, {required bool fallback}) {
  final answer = _ask('$prompt ${fallback ? '[Y/n]' : '[y/N]'}').toLowerCase();
  if (answer.isEmpty) return fallback;
  return answer.startsWith('y');
}

String _askNotes() {
  while (true) {
    final notes = _ask('\nWhat changed? (users see this, one line)');
    if (notes.isNotEmpty) return notes;
    stdout.writeln('Write a short note about the update.');
  }
}

// ── شبكة ─────────────────────────────────────────────────────────────────────────

Future<Map<String, dynamic>?> _fetchJson(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) return null;
    final data = jsonDecode(await response.transform(utf8.decoder).join());
    return data is Map ? Map<String, dynamic>.from(data) : null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<Object?> _postJson(String url, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers
      ..set('apikey', supabaseKey)
      ..contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400 || text.isEmpty) return null;
    return jsonDecode(text);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

Future<Object?> _getJson(String url, {Map<String, String> headers = const {}}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('apikey', supabaseKey);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) return null;
    return jsonDecode(text);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
