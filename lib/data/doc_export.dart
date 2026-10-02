/// ما يُفعل بمستندٍ صدّره التطبيق (سند، كشف): تنزيله على الجهاز أو إرساله بواتساب.
///
/// كان «تنزيل» على الجوال يفتح ورقة المشاركة فقط فلا يُحفظ شيء، و«واتساب» يرسل
/// نص رسالة بدل السند. الآن: التنزيل يحفظ في مجلد التنزيلات ويعرض فتحه، وواتساب
/// يرسل الملف نفسه في محادثة الرقم مباشرة (`DocumentsBridge.kt`).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'phone.dart';
import 'printing.dart';

class DocExport {
  static const _channel = MethodChannel('center/documents');

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// حفظ المستند في مجلد التنزيلات، ثم رسالة بها زر «فتح».
  static Future<void> download(BuildContext context, Uint8List bytes, String name, {String mime = 'application/pdf'}) async {
    final file = PdfKit.fileName(name);
    if (!_android) {
      await PdfKit.saveOrShare(bytes, file, mimeType: mime);
      return;
    }
    try {
      final uri = await _channel.invokeMethod<String>('save', {'bytes': bytes, 'name': file, 'mime': mime});
      if (!context.mounted) return;
      if (uri == 'needs_permission') {
        showAppSnack(context, 'اسمح للتطبيق بحفظ الملفات، ثم اضغط «تنزيل» مرة أخرى');
        return;
      }
      if (uri == null || uri.isEmpty) throw StateError('no uri');
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        showAppSnack(context, 'حُفظ في التنزيلات: $file');
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('حُفظ في التنزيلات: $file'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'فتح',
            onPressed: () => _channel.invokeMethod<bool>('open', {'uri': uri, 'mime': mime}),
          ),
        ));
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر حفظ الملف', error: true);
    }
  }

  /// إرسال الملف نفسه بواتساب: إلى محادثة [phone] مباشرة إن وُجد، وإلا يختار
  /// المستخدم المحادثة. بلا واتساب على الجهاز: ورقة المشاركة.
  static Future<void> whatsapp(
    BuildContext context,
    Uint8List bytes,
    String name, {
    String phone = '',
    String caption = '',
    String mime = 'application/pdf',
  }) async {
    final file = PdfKit.fileName(name);
    if (!_android) {
      await PdfKit.saveOrShare(bytes, file, mimeType: mime);
      return;
    }
    try {
      final status = await _channel.invokeMethod<String>('whatsapp', {
        'bytes': bytes,
        'name': file,
        'mime': mime,
        'phone': getWhatsAppPhone(phone),
        'caption': caption,
      });
      if (status == 'not_installed') {
        if (context.mounted) showAppSnack(context, 'واتساب غير مثبّت — اختر طريقة أخرى للإرسال');
        await PdfKit.saveOrShare(bytes, file, mimeType: mime);
      }
    } catch (_) {
      if (context.mounted) showAppSnack(context, 'تعذّر الإرسال بواتساب', error: true);
    }
  }

  /// ورقة الإجراءات بعد تجهيز مستند: تنزيل، واتساب، مشاركة أخرى.
  /// [phone] رقم ولي الأمر إن كان المستند لطالبٍ بعينه.
  static Future<void> showActions(BuildContext context, Uint8List bytes, String name, {String phone = '', String caption = ''}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                PdfKit.fileName(name).replaceAll('_', ' '),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.heading),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.download_outlined,
                label: 'تنزيل على الجهاز',
                onTap: () {
                  Navigator.pop(sheet);
                  download(context, bytes, name);
                },
              ),
              _ActionTile(
                icon: Icons.chat_outlined,
                label: phone.trim().isEmpty ? 'إرسال بواتساب' : 'إرسال لولي الأمر بواتساب',
                onTap: () {
                  Navigator.pop(sheet);
                  whatsapp(context, bytes, name, phone: phone, caption: caption);
                },
              ),
              _ActionTile(
                icon: Icons.share_outlined,
                label: 'مشاركة بطريقة أخرى',
                onTap: () {
                  Navigator.pop(sheet);
                  PdfKit.saveOrShare(bytes, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(icon, color: AppColors.navy),
        title: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
        onTap: onTap,
      );
}
