import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// بوابة تحميل كسول: تنتظر [ensureTables] ثم تعرض المحتوى، أو مؤشر تحميل بسيط.
class TableGate extends StatefulWidget {
  const TableGate({
    super.key,
    required this.tables,
    required this.child,
    this.message = 'جارٍ تحميل البيانات...',
  });

  final List<String> tables;
  final Widget child;
  final String message;

  @override
  State<TableGate> createState() => _TableGateState();
}

class _TableGateState extends State<TableGate> {
  var _ready = false;
  var _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TableGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.tables, widget.tables)) {
      _ready = false;
      _loading = false;
      _error = null;
      _sync();
    }
  }

  void _sync() {
    final store = StoreScope.of(context);
    if (store.tablesReady(widget.tables)) {
      // بلا setState هنا إن أمكن — أول بناء يقرأ الحقل مباشرة
      _ready = true;
      _error = null;
      return;
    }
    if (_loading || _ready) return;
    _loading = true;
    _error = null;
    unawaited(_load(store));
  }

  Future<void> _load(AppStore store) async {
    try {
      await store.ensureTables(widget.tables);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل البيانات';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // إن اكتمل التحميل بين الإطارات دون setState
    if (!_ready) {
      final store = StoreScope.of(context);
      if (store.tablesReady(widget.tables)) {
        _ready = true;
      }
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AppText.family, color: AppColors.muted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _ready = false;
                    _loading = false;
                    _error = null;
                  });
                  _sync();
                },
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.amber,
                // قيمة ثابتة: مؤشر واضح بلا Ticker يعيق الاختبارات
                value: 0.7,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.message,
              style: TextStyle(
                fontFamily: AppText.family,
                color: AppColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return widget.child;
  }
}
