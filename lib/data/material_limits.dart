import 'dart:io';
import 'dart:typed_data';

/// حدود ملفات المودل — العقد المشترك مع الويب (`materialLimits.ts` و
/// `docs/dev/FEATURES.md` في مستودع الويب).
///
/// الحاوية `course_materials` ترفض ما فوق 25 ميجا وأي نوع خارج القائمة
/// (`20261025_course_storage_quota.sql`)، وتوقف الرفع حين تبلغ ملفات المدرسة
/// حصتها. الصورة تُفحص بعد ضغطها لا قبله: صورة جوال 12 ميجا تصير ~500 KB.

const materialMaxBytes = 25 * 1024 * 1024;

/// الصورة الخام قبل الضغط؛ فوقها يتعثر فكّها على أجهزة ضعيفة.
const materialMaxRawImageBytes = 40 * 1024 * 1024;

/// ملفات الدفعة الواحدة.
const materialBatchMax = 10;

/// الحصة حين لا يحدد المطور `max_storage_mb` — مطابقة لـ SQL.
const defaultStorageQuotaMb = 2048;

const storageFullMessage = 'امتلأت مساحة المدرسة. احذف ملفات قديمة أو اطلب مساحة إضافية';

enum MaterialKind { image, pdf, word, powerpoint, excel }

const _office = <String, ({MaterialKind kind, String mime})>{
  'doc': (kind: MaterialKind.word, mime: 'application/msword'),
  'docx': (kind: MaterialKind.word, mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  'ppt': (kind: MaterialKind.powerpoint, mime: 'application/vnd.ms-powerpoint'),
  'pptx': (kind: MaterialKind.powerpoint, mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation'),
  'xls': (kind: MaterialKind.excel, mime: 'application/vnd.ms-excel'),
  'xlsx': (kind: MaterialKind.excel, mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
};

/// الصور كما تقبلها الحاوية بلا تحويل.
const _uploadableImages = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// صور تُقبل للضغط ثم تُرفع JPEG.
const _convertibleImages = {'gif', 'heic', 'heif'};

/// امتدادات منتقي الملفات وأنواعه.
const materialPickerExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'];
List<String> get materialPickerMimes => [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp',
      for (final o in _office.values) o.mime,
    ];

/// امتداد الاسم بحروف صغيرة، أو فارغ.
String materialExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  final ext = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : '';
}

/// امتداد من النوع حين يأتي الملف بلا امتداد (مشاركة من تطبيق آخر).
String extensionForMime(String mime) {
  final m = mime.toLowerCase();
  if (m == 'application/pdf') return 'pdf';
  for (final e in _office.entries) {
    if (e.value.mime == m) return e.key;
  }
  return switch (m) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    _ => '',
  };
}

class MaterialCheck {
  const MaterialCheck.ok(this.kind, this.mime) : error = null;
  const MaterialCheck.rejected(this.error)
      : kind = null,
        mime = null;

  final MaterialKind? kind;

  /// النوع الذي يُرفع به — صريح من الامتداد، فأندرويد قد يترك نوع أوفيس فارغاً.
  final String? mime;
  final String? error;

  bool get ok => error == null;
}

/// فحص ملف قبل رفعه: النوع من الامتداد (أو من [mime])، والحجم بحسب النوع.
/// الصورة تُفحص بحدها الخام هنا، ثم بحد الملف بعد ضغطها.
MaterialCheck checkMaterial({required String name, required int size, String mime = ''}) {
  var ext = materialExtension(name);
  if (ext.isEmpty) ext = extensionForMime(mime);

  if (_uploadableImages.containsKey(ext) || _convertibleImages.contains(ext)) {
    if (size > materialMaxRawImageBytes) return const MaterialCheck.rejected('الصورة أكبر من 40 ميجا');
    return const MaterialCheck.ok(MaterialKind.image, 'image/jpeg');
  }
  if (mime.toLowerCase().startsWith('image/')) return const MaterialCheck.rejected('صيغة الصورة غير مدعومة');

  final MaterialCheck check;
  if (ext == 'pdf') {
    check = const MaterialCheck.ok(MaterialKind.pdf, 'application/pdf');
  } else if (_office[ext] case final o?) {
    check = MaterialCheck.ok(o.kind, o.mime);
  } else {
    return const MaterialCheck.rejected('نوع غير مدعوم: PDF أو صورة أو Word أو PowerPoint أو Excel');
  }
  if (size > materialMaxBytes) return const MaterialCheck.rejected('الملف أكبر من 25 ميجا');
  return check;
}

/// نوع ما يُرفع فعلاً من اسمه بعد الضغط، أو `null` لغير المقبول في الحاوية.
String? uploadMime(String fileName) {
  final ext = materialExtension(fileName);
  return _uploadableImages[ext] ?? (ext == 'pdf' ? 'application/pdf' : _office[ext]?.mime);
}

/// عنوان الدرس الافتراضي: اسم الملف بلا امتداده.
String titleFromFileName(String name) {
  final ext = materialExtension(name);
  final base = ext.isEmpty ? name : name.substring(0, name.length - ext.length - 1);
  final title = base.replaceAll(RegExp(r'_+'), ' ').trim();
  if (title.isEmpty) return 'ملف';
  return title.length > 200 ? title.substring(0, 200) : title;
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} جيجا';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميجا';
  final kb = (bytes / 1024).round();
  return '${kb < 1 ? 1 : kb} كيلو';
}

/// مساحة المدرسة: المستخدَم والحصة بالبايت — `course_storage_status()`.
class StorageStatus {
  const StorageStatus({required this.usedBytes, required this.quotaBytes});

  final int usedBytes;
  final int quotaBytes;

  bool get full => usedBytes >= quotaBytes;

  double get ratio => quotaBytes <= 0 ? 1 : (usedBytes / quotaBytes).clamp(0, 1).toDouble();

  static StorageStatus? fromRpc(Object? data) {
    final row = data is List && data.isNotEmpty ? data.first : data;
    if (row is! Map) return null;
    int number(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final used = number(row['used_bytes']);
    final quota = number(row['quota_bytes']);
    return StorageStatus(usedBytes: used, quotaBytes: quota > 0 ? quota : defaultStorageQuotaMb * 1024 * 1024);
  }
}

/// ملف اختاره المعلم للرفع: من المنتقي (بايتاته معه) أو من مشاركة (على القرص).
/// يُقرأ ويُضغط عند رفعه، فلا تبقى عشرة ملفات خام في الذاكرة.
class MaterialDraft {
  MaterialDraft({required this.name, required this.size, this.mime = '', this.path, this.bytes, String? error})
      : error = error ?? checkMaterial(name: name, size: size, mime: mime).error;

  /// الاسم كما اختاره المعلم — منه عنوان الدرس.
  final String name;
  final int size;
  final String mime;
  final String? path;
  final Uint8List? bytes;

  /// سبب الرفض، أو `null` لملف صالح.
  final String? error;

  bool get ok => error == null;

  bool get isImage => checkMaterial(name: name, size: 0, mime: mime).kind == MaterialKind.image;

  Future<Uint8List> read() async => bytes ?? await File(path!).readAsBytes();

  /// الاسم بامتداد صحيح: ملف مشارَك قد يصل بلا امتداد.
  String get nameWithExtension {
    if (materialExtension(name).isNotEmpty) return name;
    final ext = extensionForMime(mime);
    return ext.isEmpty ? name : '$name.$ext';
  }
}
