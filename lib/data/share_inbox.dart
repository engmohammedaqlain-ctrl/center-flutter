import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'material_limits.dart';

/// ملف وصل بـ«مشاركة» من تطبيق آخر، منسوخ في ذاكرة التطبيق المؤقتة
/// (`ShareActivity.kt`).
class SharedFile {
  const SharedFile({required this.path, required this.name, required this.mime, required this.size, this.unreadable = false});

  factory SharedFile.fromMap(Map<Object?, Object?> m) {
    final size = m['size'];
    return SharedFile(
      path: '${m['path'] ?? ''}',
      name: '${m['name'] ?? ''}',
      mime: '${m['mime'] ?? ''}'.toLowerCase(),
      size: size is num ? size.toInt() : 0,
      unreadable: '${m['error'] ?? ''}'.isNotEmpty || ('${m['path'] ?? ''}'.isEmpty && size != -1),
    );
  }

  final String path;
  final String name;
  final String mime;

  /// -1: أكبر مما يُنسخ (40 ميجا).
  final int size;
  final bool unreadable;

  bool get tooLarge => size < 0;

  bool get isImage => mime.startsWith('image/') || const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif'}.contains(materialExtension(name));

  bool get isPdf => mime == 'application/pdf' || materialExtension(name) == 'pdf';

  /// ملف مادة للمعلم، بسبب رفضه إن وُجد.
  MaterialDraft toDraft() => MaterialDraft(
        name: name,
        // الكبير لم يُنسخ: حجمه فوق الحد فيُرفض بسببه الصحيح
        size: tooLarge ? materialMaxRawImageBytes + 1 : size,
        mime: mime,
        path: path.isEmpty ? null : path,
        error: unreadable ? 'تعذّر قراءة الملف' : null,
      );
}

/// صندوق المشاركات الواردة: يستقبلها من أندرويد عند الإقلاع وأثناء العمل،
/// ويحفظها حتى تأخذها شاشةٌ تعرف ما تفعل بها (بوابة المعلم أو ولي الأمر).
/// قبل الدخول تبقى هنا، فتُكمل بعده.
class ShareInbox extends ChangeNotifier {
  ShareInbox._();

  static final instance = ShareInbox._();

  static const _channel = MethodChannel('center/share');

  List<SharedFile> _files = const [];
  bool _started = false;

  List<SharedFile> get files => _files;

  bool get hasFiles => _files.isNotEmpty;

  /// يُستدعى مرة عند الإقلاع.
  void start() {
    if (_started || kIsWeb || !Platform.isAndroid) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'ready') await _take();
      return null;
    });
    unawaited(_take());
  }

  Future<void> _take() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('take');
      final list = [
        for (final e in raw ?? const <Object?>[])
          if (e is Map) SharedFile.fromMap(e),
      ];
      if (list.isEmpty) return;
      // مشاركة جديدة تحل محل ما لم يُؤخذ
      _files = list;
      notifyListeners();
    } catch (_) {
      // نسخة أصلية قديمة بلا القناة
    }
  }

  /// يأخذ الملفات ويفرغ الصندوق.
  List<SharedFile> take() {
    final out = _files;
    if (out.isEmpty) return out;
    _files = const [];
    notifyListeners();
    return out;
  }

  /// للاختبارات.
  @visibleForTesting
  void debugPut(List<SharedFile> files) {
    _files = files;
    notifyListeners();
  }
}
