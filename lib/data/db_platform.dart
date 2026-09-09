library;

/// تهيئة محرك قاعدة البيانات بحسب المنصة.
///
/// الاستيراد الشرطي يمنع دخول كود الويب (WASM/IndexedDB) في حزمة أندرويد،
/// فاستيراده مباشرةً كان يجرّه إلى البناء وإن لم يُستعمل.
export 'db_platform_io.dart' if (dart.library.js_interop) 'db_platform_web.dart';
