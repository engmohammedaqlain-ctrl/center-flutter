import 'dart:async';

import 'package:flutter/material.dart';

import '../data/school_brand.dart';
import '../data/school_link.dart';
import '../models/models.dart' show appName;
import 'widgets.dart' show decodeLogo;

// اختصار المدرسة بشعارها واسمها على الشاشة الرئيسية (`school_link.dart`).
// يُعرض مرة بعد الدخول، ويبقى في القائمة (الإدارة) والترويسة (البوابات).

/// اسم مدرسة حقيقي، لا اسم النظام قبل وصول هويتها.
bool _realName(String name) => name.trim().isNotEmpty && name.trim() != appName;

/// يطلب من النظام تثبيت الاختصار — نافذته تسأل المستخدم.
Future<void> addSchoolShortcut(
  ScaffoldMessengerState? messenger, {
  required String code,
  required String name,
  required String logo,
}) async {
  final ok = await HomeShortcut.pin(code: code, name: name, logo: decodeLogo(logo));
  if (ok) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('الشاشة الرئيسية لا تدعم الإضافة')));
}

/// عرضٌ خفيف مرة واحدة على الجهاز، بعد الدخول.
Future<void> offerSchoolShortcut(
  ScaffoldMessengerState? messenger, {
  required String code,
  required String name,
  required String logo,
}) async {
  if (messenger == null || !_realName(name)) return;
  if (!await HomeShortcut.claimOffer()) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: const Text('أضف مدرستك للشاشة الرئيسية'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'إضافة',
        onPressed: () => unawaited(addSchoolShortcut(messenger, code: code, name: name, logo: logo)),
      ),
    ));
}

/// زر ترويسة البوابة (طالب وولي أمر ومعلم)، ويعرض الاختصار مرة حين تصل هوية المدرسة.
class HomeShortcutButton extends StatefulWidget {
  const HomeShortcutButton({super.key, required this.name, required this.logo, this.color, this.builder});

  final String name;
  final String logo;
  final Color? color;

  /// شكل الزر حين يخالف زر الأيقونة: «تثبيت» في ترويسة نون.
  final Widget Function(VoidCallback onTap)? builder;

  @override
  State<HomeShortcutButton> createState() => _HomeShortcutButtonState();
}

class _HomeShortcutButtonState extends State<HomeShortcutButton> {
  /// البوابة لا تعرف كود مدرستها: كود الرابط أو المتجر إن عُرف، وإلا يفتح الاختصار التطبيق وحده.
  String get _code => SchoolBrand.instance.code ?? '';

  @override
  void initState() {
    super.initState();
    _offer();
  }

  @override
  void didUpdateWidget(HomeShortcutButton old) {
    super.didUpdateWidget(old);
    if (!_realName(old.name)) _offer();
  }

  void _offer() {
    if (!HomeShortcut.available || !_realName(widget.name)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(offerSchoolShortcut(ScaffoldMessenger.maybeOf(context), code: _code, name: widget.name, logo: widget.logo));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!HomeShortcut.available || !_realName(widget.name)) return const SizedBox.shrink();
    void pin() => unawaited(
          addSchoolShortcut(ScaffoldMessenger.maybeOf(context), code: _code, name: widget.name, logo: widget.logo),
        );
    if (widget.builder != null) return widget.builder!(pin);
    return IconButton(
      tooltip: 'أضف للشاشة الرئيسية',
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(
        addSchoolShortcut(ScaffoldMessenger.maybeOf(context), code: _code, name: widget.name, logo: widget.logo),
      ),
      icon: Icon(Icons.add_to_home_screen_rounded, size: 19, color: widget.color),
    );
  }
}
