/// السندات المالية كما في الويب حرفياً: `ReceiptModal.tsx` و `ExpenseVoucherModal.tsx`.
///
/// المستند نفسه يُعرض على الشاشة ويُلتقط صورةً لملف PDF (`captureDocumentPdf`)،
/// فما يراه الموظف هو ما يصل ولي الأمر — كان للجوال تصميمٌ على الشاشة وثانٍ في
/// الملف، وكلاهما غير سند الويب.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart' show currency;
import 'zoomable_image.dart';

// ألوان Tailwind slate كما في الويب — السند وثيقة رسمية بالأسود والرمادي،
// لا بألوان هوية المنشأة
const _s950 = Color(0xFF020617);
const _s900 = Color(0xFF0F172A);
const _s800 = Color(0xFF1E293B);
const _s700 = Color(0xFF334155);
const _s600 = Color(0xFF475569);
const _s500 = Color(0xFF64748B);
const _s400 = Color(0xFF94A3B8);
const _s300 = Color(0xFFCBD5E1);
const _s200 = Color(0xFFE2E8F0);
const _s100 = Color(0xFFF1F5F9);
const _s50 = Color(0xFFF8FAFC);
const _emerald700 = Color(0xFF047857);
const _amber800 = Color(0xFF92400E);
const _red700 = Color(0xFFB91C1C);
const _blue900 = Color(0xFF1E3A8A);

// عزل الأرقام اللاتينية داخل سطر عربي (LRI … PDI) — كما يعزلها الويب
final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

/// المبلغ كما يكتبه الويب (`formatCurrency`): فواصل الآلاف ثم العملة — «1,250 شيكل».
String webMoney(num value) {
  final negative = value < 0;
  final abs = value.abs();
  // toLocaleString('en-US'): حتى ثلاث خانات عشرية بلا أصفار زائدة
  var text = abs.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = text.split('.');
  final whole = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  text = parts.length > 1 ? '$whole.${parts[1]}' : whole;
  return '${negative ? '-' : ''}$text $currency';
}

Uint8List? _decode(String data) {
  if (data.trim().isEmpty) return null;
  try {
    return base64Decode(data.split(',').last);
  } catch (_) {
    return null;
  }
}

/// بيانات سند القبض بعد حلّها من المتجر — المستند نفسه لا يقرأ المتجر.
class ReceiptView {
  const ReceiptView({
    required this.institutionName,
    required this.logo,
    required this.stamp,
    required this.title,
    required this.receiptNumber,
    required this.date,
    required this.amount,
    required this.outgoing,
    required this.reversal,
    required this.showLedger,
    required this.payerName,
    required this.gradeLevel,
    required this.methodLabel,
    required this.amountWords,
    required this.purposeText,
    required this.receiverName,
    required this.advance,
    required this.dueRemaining,
    this.senderName = '',
    this.reference = '',
    this.discountAmount = 0,
    this.originalAmount = 0,
    this.discountReason = '',
    this.notice,
    this.cancelled = false,
    this.cancelReason = '',
  });

  final String institutionName;
  final String logo;
  final String stamp;
  final String title;
  final String receiptNumber;
  final String date;

  /// المبلغ بإشارته: سالبٌ في سند الرد والعكس.
  final double amount;
  final bool outgoing;
  final bool reversal;

  /// جدول الموقف المالي — لا يظهر في الإيراد العام ولا في الرد.
  final bool showLedger;
  final String payerName;
  final String gradeLevel;
  final String methodLabel;
  final String amountWords;
  final String purposeText;
  final String receiverName;
  final double advance;
  final double dueRemaining;
  final String senderName;
  final String reference;
  final double discountAmount;
  final double originalAmount;
  final String discountReason;
  final Uint8List? notice;
  final bool cancelled;
  final String cancelReason;
}

/// سند القبض — `ReceiptModal.tsx`: ترويسة رسمية، صندوق المبلغ، جدول مسطّر،
/// الإشعار المرفق، الموقف المالي، التوقيع والختم، شريط توثيقي.
class ReceiptDocument extends StatelessWidget {
  const ReceiptDocument({super.key, required this.view});

  final ReceiptView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final logo = _decode(v.logo);
    final stamp = _decode(v.stamp);
    final abs = v.amount.abs();

    return DefaultTextStyle.merge(
      style: const TextStyle(color: _s900, fontSize: 12, height: 1.35),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(14),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _s800, width: 2)),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. الترويسة الرسمية
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _s800, width: 2))),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (logo != null) ...[
                            Image.memory(logo, width: 40, height: 40, fit: BoxFit.contain, gaplessPlayback: true),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              v.institutionName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _s900, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: _s50, border: Border.all(color: _s800)),
                      child: Text(v.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _s950)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'رقم السند: '),
                              TextSpan(
                                text: '$_lri${v.receiptNumber}$_pdi',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: _s950),
                              ),
                            ]),
                            textAlign: TextAlign.left,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _s900),
                          ),
                          Text('التاريخ: ${v.date}', style: const TextStyle(fontSize: 10.5, color: _s600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. صندوق المبلغ وطريقة السداد
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _s50, border: Border.all(color: _s300)),
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              decoration: const BoxDecoration(border: BorderDirectional(end: BorderSide(color: _s300))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.outgoing ? 'المبلغ المردود:' : 'المبلغ المقبوض:',
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _s600)),
                                  const SizedBox(height: 2),
                                  Text(webMoney(abs),
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _s950)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('طريقة السداد:',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _s600)),
                                const SizedBox(height: 2),
                                Text(v.methodLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _s900)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (v.discountAmount.abs() > 0) ...[
                      const SizedBox(height: 8),
                      const _Dashed(),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: 'المبلغ الأصلي: '),
                                TextSpan(
                                  text: webMoney(v.originalAmount),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: _s800),
                                ),
                              ]),
                              style: const TextStyle(fontSize: 10.5, color: _s600),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              'قيمة الخصم: -${webMoney(v.discountAmount.abs())}${v.discountReason.isEmpty ? '' : ' (${v.discountReason})'}',
                              textAlign: TextAlign.left,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _red700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 3. الجدول المسطّر
              Container(
                decoration: BoxDecoration(border: Border.all(color: _s400)),
                child: Column(
                  children: [
                    _TableRow(
                      label: v.outgoing ? (v.reversal ? 'عكس لحساب:' : 'رُدّ إلى ولي أمر:') : 'وصلنا من:',
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: v.payerName, style: const TextStyle(fontWeight: FontWeight.bold, color: _s950)),
                          if (v.gradeLevel.trim().isNotEmpty)
                            TextSpan(
                              text: '  (${v.gradeLevel.trim()})',
                              style: const TextStyle(fontSize: 10, color: _s500, fontWeight: FontWeight.normal),
                            ),
                        ]),
                      ),
                    ),
                    if (v.senderName.isNotEmpty)
                      _TableRow(
                        label: 'اسم المحوّل:',
                        child: Text(v.senderName, style: const TextStyle(fontWeight: FontWeight.w600, color: _blue900)),
                      ),
                    _TableRow(
                      label: 'وقدره كتابةً:',
                      background: const Color(0xFFFCFDFD),
                      child: Text(v.amountWords, style: const TextStyle(fontWeight: FontWeight.w500, color: _s800)),
                    ),
                    _TableRow(
                      label: 'وذلك عن:',
                      last: v.reference.isEmpty,
                      child: Text(v.purposeText, style: const TextStyle(fontWeight: FontWeight.w500, color: _s900, height: 1.5)),
                    ),
                    if (v.reference.isNotEmpty)
                      _TableRow(
                        label: 'الرقم المرجعي:',
                        last: true,
                        child: Text('$_lri${v.reference}$_pdi',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: _s950)),
                      ),
                  ],
                ),
              ),

              // صورة إشعار التحويل المرفقة
              if (v.notice != null) ...[
                const SizedBox(height: 10),
                const Text('إشعار التحويل المرفق:',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _s700)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: _s50, border: Border.all(color: _s300)),
                  child: Center(child: ZoomableImage(bytes: v.notice!)),
                ),
              ],

              // 4. الموقف المالي — المستحق حالياً فقط دون المجدول
              if (v.showLedger) ...[
                const SizedBox(height: 10),
                Table(
                  border: TableBorder.all(color: _s400),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: _s100),
                      children: [
                        const _Cell('المبلغ المسدد', header: true),
                        _Cell(v.advance > 0 ? 'رصيد مقدم' : 'المستحق حالياً', header: true),
                        const _Cell('الحالة المالية', header: true),
                      ],
                    ),
                    TableRow(
                      children: [
                        _Cell(webMoney(v.amount), bold: true),
                        _Cell(webMoney(v.advance > 0 ? v.advance : v.dueRemaining), bold: true),
                        v.advance > 0
                            ? const _Cell('رصيد مقدم', color: _emerald700, bold: true)
                            : v.dueRemaining <= 0.01
                                ? const _Cell('مسدد حتى تاريخه', color: _emerald700, bold: true)
                                : const _Cell('مستمر (متأخرات)', color: _amber800, bold: true),
                      ],
                    ),
                  ],
                ),
              ],

              if (v.cancelled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(border: Border.all(color: _red700)),
                  child: Text(
                    'هذا السند ملغى${v.cancelReason.isEmpty ? '' : ' — ${v.cancelReason}'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _red700, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],

              // 5. التوقيع والختم
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('المستلم:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _s700)),
                            const SizedBox(width: 6),
                            Flexible(child: _Boxed(v.receiverName)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(width: 144, child: _Dashed(color: _s400, dotted: true)),
                        const SizedBox(height: 3),
                        const Text('التوقيع والاعتماد', style: TextStyle(fontSize: 9.5, color: _s500)),
                      ],
                    ),
                  ),
                  _Stamp(stamp: stamp),
                ],
              ),

              // 6. شريط توثيقي
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _s200))),
                child: const Text(
                  'سند مالي رسمي معتمد — يُرجى الاحتفاظ بهذا الوصل كإثبات سداد رسمي',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9.5, color: _s500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بيانات سند الصرف بعد حلّها.
class VoucherView {
  const VoucherView({
    required this.institutionName,
    required this.logo,
    required this.stamp,
    required this.title,
    required this.number,
    required this.date,
    required this.amount,
    required this.methodLabel,
    required this.paidTo,
    required this.amountWords,
    required this.aboutLine,
    required this.issuedBy,
    this.notice,
  });

  final String institutionName;
  final String logo;
  final String stamp;
  final String title;
  final String number;
  final String date;
  final double amount;
  final String methodLabel;
  final String paidTo;
  final String amountWords;
  final String aboutLine;
  final String issuedBy;
  final Uint8List? notice;
}

/// سند الصرف — `ExpenseVoucherModal.tsx`.
class VoucherDocument extends StatelessWidget {
  const VoucherDocument({super.key, required this.view});

  final VoucherView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final logo = _decode(v.logo);
    final stamp = _decode(v.stamp);

    Widget line(String label, Widget value) => Container(
          padding: const EdgeInsets.only(bottom: 4),
          margin: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: _s700)),
                  const SizedBox(width: 6),
                  Expanded(child: value),
                ],
              ),
              const SizedBox(height: 4),
              const _Dashed(dotted: true),
            ],
          ),
        );

    return DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.black, fontSize: 11, height: 1.35),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(14),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _s800, width: 2)),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الترويسة
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _s800))),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (logo != null) ...[
                            Image.memory(logo, width: 36, height: 36, fit: BoxFit.contain, gaplessPlayback: true),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.institutionName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                                Text(v.title, style: const TextStyle(fontSize: 10, color: _s600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: _s50, border: Border.all(color: _s700)),
                      child: const Text('سند صرف معتمد', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'رقم السند: '),
                              TextSpan(text: '$_lri${v.number}$_pdi'),
                            ]),
                            textAlign: TextAlign.left,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          Text(v.date, style: const TextStyle(fontSize: 10, color: _s600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // المبلغ وطريقة الصرف
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _s50, border: Border.all(color: _s300)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('المبلغ المصروف:', style: TextStyle(fontSize: 10, color: _s600)),
                          Text(webMoney(v.amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('طريقة الصرف:', style: TextStyle(fontSize: 10, color: _s600)),
                        Text(v.methodLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // التفاصيل
              line('صُرف إلى:', Text(v.paidTo, style: const TextStyle(fontWeight: FontWeight.bold))),
              line('وقدره كتابة:', Text(v.amountWords, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: _s800))),
              line('وذلك عن:', Text(v.aboutLine, style: const TextStyle(fontWeight: FontWeight.w500))),

              if (v.notice != null) ...[
                const SizedBox(height: 4),
                const Text('إشعار التحويل المرفق:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _s700)),
                const SizedBox(height: 4),
                Center(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: _s300)),
                    child: ZoomableImage(bytes: v.notice!, height: 160),
                  ),
                ),
              ],

              // التوقيع والختم
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('الصارف:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _s700)),
                            const SizedBox(width: 6),
                            Flexible(child: _Boxed(v.issuedBy, fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(width: 112, child: _Dashed(color: _s400)),
                      ],
                    ),
                  ),
                  const Column(
                    children: [
                      Text('المستلم', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _s700)),
                      SizedBox(height: 12),
                      SizedBox(width: 96, child: _Dashed(color: _s400)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  _Stamp(stamp: stamp),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.label, required this.child, this.background, this.last = false});

  final String label;
  final Widget child;
  final Color? background;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: _s300))),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 104,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: const BoxDecoration(color: _s100, border: BorderDirectional(end: BorderSide(color: _s300))),
              child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _s700)),
            ),
            Expanded(
              child: Container(
                color: background,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 11), child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.header = false, this.bold = false, this.color});

  final String text;
  final bool header;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: header || bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? (header ? _s800 : _s950),
          ),
        ),
      );
}

class _Boxed extends StatelessWidget {
  const _Boxed(this.text, {this.fontSize = 11});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: _s50, border: Border.all(color: _s300)),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: _s950)),
      );
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.stamp});

  final Uint8List? stamp;

  @override
  Widget build(BuildContext context) {
    final s = stamp;
    if (s != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 64, maxWidth: 130),
        child: Image.memory(s, fit: BoxFit.contain, gaplessPlayback: true),
      );
    }
    return Container(
      width: 96,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _s50.withValues(alpha: 0.5), border: Border.all(color: _s400)),
      child: const Text('الختم الرسمي', style: TextStyle(fontSize: 10, color: _s400)),
    );
  }
}

/// خطٌّ متقطّع أو منقّط بعرض حاويه.
class _Dashed extends StatelessWidget {
  const _Dashed({this.color = _s300, this.dotted = false});

  final Color color;
  final bool dotted;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: LayoutBuilder(
          builder: (context, box) {
            final dash = dotted ? 1.5 : 4.0;
            final gap = dotted ? 2.5 : 3.0;
            final count = (box.maxWidth / (dash + gap)).floor().clamp(1, 1000);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(count, (_) => SizedBox(width: dash, height: 1, child: ColoredBox(color: color))),
            );
          },
        ),
      );
}

/// المستند المعروض كما هو في ملف PDF: يُلتقط صورةً بدقة عالية ويُوضع في صفحة A4
/// بعرض [widthMm] كطباعة الويب (140مم لسند القبض، 130مم لسند الصرف).
Future<Uint8List?> captureDocumentPdf(GlobalKey key, {double widthMm = 140, String title = ''}) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final image = await boundary.toImage(pixelRatio: 3);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  final png = data.buffer.asUint8List();

  final doc = pw.Document(title: title);
  final width = widthMm * PdfPageFormat.mm;
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
      build: (_) => pw.Align(
        alignment: pw.Alignment.topCenter,
        child: pw.SizedBox(width: width, child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
      ),
    ),
  );
  return doc.save();
}
