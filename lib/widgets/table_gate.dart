import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

/// بوابة تحميل كسول: تنتظر [ensureTables] ثم تعرض المحتوى، أو مؤشر تحميل عصري.
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
      // إفساح قبل كشف الشاشة حتى يكتمل دوران آخر إطار للمؤشر
      await yieldUi(2);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('TableGate ensureTables(${widget.tables}): $e\n$st');
      if (!mounted) return;
      if (store.tablesReady(widget.tables)) {
        setState(() {
          _ready = true;
          _loading = false;
          _error = null;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل البيانات';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final store = StoreScope.of(context);
      if (store.tablesReady(widget.tables)) {
        _ready = true;
        _error = null;
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
                style: TextStyle(fontFamily: AppText.family, color: AppColors.muted, fontWeight: FontWeight.w600),
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
      return AppLoader(message: widget.message);
    }

    return widget.child;
  }
}
