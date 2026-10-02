import 'dart:typed_data';

import 'package:flutter/material.dart';

/// صورةٌ تُفتح بلمسة على الشاشة كاملة وتُكبَّر وتُصغَّر — `ZoomableImage` في الويب.
///
/// إشعار التحويل المرفق بالسند يُقرأ منه الرقم المرجعي والمبلغ، وكان يُعرض مقصوصاً
/// بارتفاعٍ ثابت لا يُفتح.
class ZoomableImage extends StatelessWidget {
  const ZoomableImage({super.key, required this.bytes, this.height = 144, this.title = 'إشعار التحويل'});

  final Uint8List bytes;

  /// أقصى ارتفاعٍ للمصغَّرة داخل المستند.
  final double height;

  /// عنوان شاشة العرض الكاملة.
  final String title;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => open(context, bytes, title: title),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              cacheHeight: (height * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
            ),
          ),
          // تلميح أن الصورة تُفتح — يختفي من نسخة الطباعة لأنه صغير وشفاف
          PositionedDirectional(
            bottom: 4,
            start: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.zoom_in, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> open(BuildContext context, Uint8List bytes, {String title = 'إشعار التحويل'}) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _ImageViewer(bytes: bytes, title: title),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.bytes, required this.title});

  final Uint8List bytes;
  final String title;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoom = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final a = _animation;
      if (a != null) _transform.value = a.value;
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// لمستان: تكبيرٌ ثلاثي حول موضع اللمس، ولمستان أخريان تعيدان الحجم الأصلي.
  void _toggleZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 target;
    if (zoomed) {
      target = Matrix4.identity();
    } else {
      final p = _doubleTapAt?.localPosition ?? Offset.zero;
      const scale = 3.0;
      target = Matrix4.identity()
        ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _animation = Matrix4Tween(begin: _transform.value, end: target).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOut));
    _zoom.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 15, color: Colors.white)),
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _doubleTapAt = d,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 8,
          child: SizedBox.expand(
            child: Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      ),
    );
  }
}
