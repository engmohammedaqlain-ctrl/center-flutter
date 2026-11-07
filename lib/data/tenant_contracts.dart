/// عقود الاشتراك في لوحة المطور — المقابل لـ `contractDoc.ts` وقسم العقود في `devService.ts`.
/// الحقل الفارغ يُرسم خطاً منقطاً فيُعبّأ باليد. نص العقد مطابق لنسخة الويب: أي تعديل يكون في الموضعين.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'printing.dart';
import 'supabase.dart';

const contractsBucket = 'contracts';

const emptyContract = <String, String>{
  'date': '',
  'owner_name': '',
  'owner_title': '',
  'owner_id': '',
  // رقم نون المعتاد
  'owner_phone': '0599024136',
  'school_name': '',
  'school_address': '',
  'rep_name': '',
  'rep_title': '',
  'rep_phone': '',
  'price': '',
  'price_words': '',
  'period': '',
  'students': '',
  'duration': '',
  'start_date': '',
};

class TenantContract {
  TenantContract({required this.id, this.tenantId, required this.fields, this.images = const []});

  factory TenantContract.fromMap(Map<String, dynamic> m) {
    final raw = m['fields'];
    return TenantContract(
      id: '${m['id']}',
      tenantId: m['tenant_id']?.toString(),
      fields: {
        ...emptyContract,
        if (raw is Map)
          for (final e in raw.entries) '${e.key}': '${e.value ?? ''}',
      },
      images: [
        if (m['images'] is List)
          for (final p in m['images'] as List) '$p',
      ],
    );
  }

  final String id;
  String? tenantId;
  Map<String, String> fields;
  List<String> images;
}

class ContractsService {
  ContractsService._();

  /// `null` إن لم تُجب السحابة.
  static Future<List<TenantContract>?> list() async {
    final rows = await supabaseSelect(
      'tenant_contracts',
      columns: 'id,tenant_id,fields,images,created_at,updated_at',
      order: 'created_at.desc',
    );
    return rows == null ? null : [for (final r in rows) TenantContract.fromMap(r)];
  }

  /// جديد أو تعديل: المعرّف من الجهاز، والصور لا تُمس.
  static Future<void> save(TenantContract c) => supabaseUpsert('tenant_contracts', [
        {
          'id': c.id,
          'tenant_id': c.tenantId,
          'fields': c.fields,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      ]);

  static Future<void> delete(TenantContract c) async {
    if (c.images.isNotEmpty) await storageRemove(contractsBucket, c.images);
    await supabaseDelete('tenant_contracts', {'id': 'eq.${c.id}'});
  }

  /// صور النسخة الموقّعة: تُرفع لمجلد العقد ثم تُضاف لقائمته، وفشل الحفظ يحذف ما رُفع.
  static Future<List<String>> addImages(TenantContract c, List<Uint8List> files) async {
    final added = <String>[];
    try {
      for (final bytes in files) {
        final path = '${c.id}/${DateTime.now().millisecondsSinceEpoch}-${added.length}.jpg';
        await storageUpload(contractsBucket, path, bytes, 'image/jpeg');
        added.add(path);
      }
      final images = [...c.images, ...added];
      await supabaseUpdate('tenant_contracts', {'id': 'eq.${c.id}'}, {'images': images});
      return images;
    } catch (_) {
      if (added.isNotEmpty) await storageRemove(contractsBucket, added);
      rethrow;
    }
  }

  static Future<List<String>> removeImage(TenantContract c, String path) async {
    final images = c.images.where((p) => p != path).toList();
    await supabaseUpdate('tenant_contracts', {'id': 'eq.${c.id}'}, {'images': images});
    await storageRemove(contractsBucket, [path]);
    return images;
  }
}

/// اسم الملف: عقد نون - اسم المدرسة.
String contractFileName(Map<String, String> f) {
  final school = (f['school_name'] ?? '').trim();
  return 'عقد نون - ${school.isEmpty ? 'فارغ' : school}';
}

const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// جزء من سطر: نص عادي أو قيمة بخط عريض.
class _Part {
  const _Part(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

_Part _t(String text) => _Part(text);

/// القيمة إن وُجدت، وإلا خط منقط للتعبئة باليد.
_Part _fill(String? value, [int dots = 18]) {
  final v = (value ?? '').trim();
  return v.isEmpty ? _Part('.' * dots) : _Part(v, bold: true);
}

/// 2026-10-23 ← 23 أكتوبر 2026م، والفارغ فراغات — `contractDate`.
_Part _date(String? iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch((iso ?? '').trim());
  if (m == null) return const _Part('     /      /            م');
  return _Part('${int.parse(m[3]!)} ${_months[int.parse(m[2]!) - 1]} ${m[1]}م', bold: true);
}

_Part _box(bool on) => _Part(on ? '☑ ' : '☐ ');

/// عقد الاشتراك A4 — `contractPages`.
Future<Uint8List> buildContractPdf(Map<String, String> f) async {
  const size = 11.5;
  const height = 1.5;
  pw.Widget line(List<_Part> parts, {double bottom = 5}) => pw.Padding(
        padding: pw.EdgeInsets.only(bottom: bottom),
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: size, lineSpacing: height * 2),
              children: [
                for (final p in parts)
                  pw.TextSpan(text: p.text, style: p.bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
              ],
            ),
          ),
        ),
      );
  pw.Widget text(String s) => line([_t(s)]);
  pw.Widget heading(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Text(s, style: pw.TextStyle(fontSize: size + 0.5, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
        ),
      );
  pw.Widget item(int n, List<_Part> parts) => line([_t('$n. '), ...parts], bottom: 3);
  List<pw.Widget> items(List<List<_Part>> list) => [for (var i = 0; i < list.length; i++) item(i + 1, list[i])];

  final priceValue = (f['price'] ?? '').trim();
  final words = (f['price_words'] ?? '').trim();
  final price = <_Part>[
    if (priceValue.isNotEmpty) ...[
      _fill(priceValue),
      _t(' شيكل، '),
      if (words.isNotEmpty) _Part(words, bold: true) else ...[_t('فقط '), _fill('', 30), _t(' شيكلاً لا غير')],
    ] else ...[
      _t('('),
      _fill('', 10),
      _t(') شيكل، فقط '),
      _fill('', 30),
      _t(' شيكلاً لا غير'),
    ],
  ];

  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/logo.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    logo = null;
  }

  final doc = pw.Document(title: 'عقد اشتراك نون');
  final theme = await PdfKit.theme();
  final signLabel = pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold);
  pw.Widget signCell(List<_Part> parts, {double? height, bool head = false}) => pw.Container(
        height: height,
        color: head ? const PdfColor.fromInt(0xFFEEEEEE) : null,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: line(parts, bottom: 0),
      );
  String v(String key) => (f[key] ?? '').trim();

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
      footer: (ctx) => pw.Center(
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
      ),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 5),
          margin: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.5))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              line([_t('التاريخ: '), _date(f['date'])], bottom: 0),
              pw.Row(
                children: [
                  pw.Directionality(
                    textDirection: pw.TextDirection.rtl,
                    child: pw.Text('نون للإدارة المدرسية', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  ),
                  if (logo != null) ...[pw.SizedBox(width: 6), pw.SizedBox(width: 28, height: 28, child: pw.Image(logo))],
                ],
              ),
            ],
          ),
        ),
        pw.Center(
          child: pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text('بسم الله الرحمن الرحيم', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Text('عقد اشتراك في نظام نون للإدارة المدرسية', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        line([
          const _Part('الطرف الأول: ', bold: true),
          _t('فريق «نون» للإدارة المدرسية، ويمثّله '),
          _fill(f['owner_name'], 30),
          _t(' بصفته/ا '),
          _fill(f['owner_title']),
          _t('، هوية رقم ('),
          _fill(f['owner_id']),
          _t(')، جوال ('),
          _fill(f['owner_phone']),
          _t(')، ويُسمّى في هذا العقد «نون».'),
        ]),
        line([
          const _Part('الطرف الثاني: ', bold: true),
          _t('مدرسة '),
          _fill(f['school_name'], 30),
          _t('، عنوانها '),
          _fill(f['school_address']),
          _t('، ويمثّلها '),
          _fill(f['rep_name'], 30),
          _t(' بصفته/ا '),
          _fill(f['rep_title']),
          _t('، جوال ('),
          _fill(f['rep_phone']),
          _t(')، وتُسمّى في هذا العقد «المدرسة».'),
        ]),
        text('اتفق الطرفان على اشتراك المدرسة في نظام نون وفق البنود التالية:'),
        heading('أولاً: موضوع العقد'),
        text('يمنح نون المدرسة حق استخدام النظام لإدارة شؤونها طوال مدة العقد، ويشمل ذلك تجهيز النظام وتدريب موظفيها عند البدء، والتحديثات، والدعم الفني. ويطوّر نون النظام ويحدّثه باستمرار، وتبقى حقوقه لنون وبيانات المدرسة لها. والاشتراك خاص بالمدرسة ولا يُنقل لغيرها.'),
        heading('ثانياً: المدة'),
        line([
          _t('مدة العقد ('),
          _fill(f['duration'], 10),
          _t(') تبدأ في '),
          _date(f['start_date']),
          _t('، وتتجدد تلقائياً لمدة مماثلة إلا إذا أبلغ أحد الطرفين الآخر بعدم التجديد قبل انتهائها بخمسة عشر يوماً.'),
        ]),
        heading('ثالثاً: التزامات نون'),
        ...items([
          [_t('تشغيل النظام وصيانته وبذل العناية المعقولة لاستمراره.')],
          [_t('الدعم الفني في أيام وساعات العمل.')],
          [_t('حفظ سرية بيانات المدرسة، فلا يبيعها ولا يعطيها لأي جهة إلا بأمر قانوني.')],
        ]),
        heading('رابعاً: الاشتراك والدفع'),
        ...items([
          [
            _t('قيمة الاشتراك '),
            ...price,
            _t('، '),
            _box(f['period'] == 'monthly'),
            _t('شهرياً '),
            _box(f['period'] == 'yearly'),
            _t('سنوياً، لعدد طلاب حتى ('),
            _fill(f['students'], 10),
            _t(') طالب.'),
          ],
          [_t('يُدفع مقدّماً: الشهري حتى اليوم الخامس من كل شهر، والسنوي عند بداية العقد، نقداً أو بتحويل إلى الحساب الذي يحدده نون.')],
          [_t('السعر ثابت طوال مدة العقد. وعند التجديد تُبلَّغ المدرسة بأي تغيير قبل 30 يوماً، ويُعدَّل السعر بقدر الزيادة إن زاد عدد الطلاب عن المتفق عليه.')],
          [_t('عند التأخر في السداد أكثر من 7 أيام تُوقف الخدمة مؤقتاً حتى السداد، وإن تجاوز 30 يوماً جاز إنهاء العقد، وتبقى المبالغ المستحقة واجبة الأداء. وما دُفع عن مدة بدأت لا يُسترد.')],
        ]),
        heading('خامساً: التزامات المدرسة'),
        ...items([
          [_t('الدفع في موعده.')],
          [_t('صحة البيانات التي تُدخلها، وهي المسؤولة عنها وعن حقها في إدخال بيانات طلابها وأولياء أمورهم.')],
          [_t('الحفاظ على كلمات المرور، وإيقاف حساب أي موظف يترك العمل.')],
          [_t('عدم نسخ النظام أو بيعه أو تأجيره، أو محاولة اختراقه أو الوصول إلى شيفرته.')],
        ]),
        heading('سادساً: البيانات'),
        ...items([
          [_t('بيانات المدرسة ملك لها، وتأخذ نسخة منها من النظام في أي وقت، وما تحذفه بنفسها لا يلتزم نون باسترجاعه.')],
          [_t('يستخدمها نون لتشغيل الخدمة ودعمها وتحسينها لدى مزوّدين يختارهم، وقد يستخدم إحصاءات عامة لا تكشف اسم المدرسة ولا أحداً من طلابها.')],
          [_t('تُحفظ البيانات 30 يوماً بعد انتهاء العقد ثم تُحذف.')],
        ]),
        heading('سابعاً: الظروف الطارئة والتعويض'),
        ...items([
          [_t('إذا توقفت الخدمة بسبب ظرف خارج عن إرادة الطرفين، كالحرب أو انقطاع الكهرباء أو الإنترنت العام، فلا يُحسب ذلك تقصيراً من أحد، وتُمدَّد مدة اشتراك المدرسة مجاناً بقدر مدة التوقف الكامل.')],
          [_t('في غير ذلك، لا يضمن نون خلو الخدمة من الانقطاع، ولا يزيد أي تعويض منه للمدرسة عن قيمة اشتراك آخر 3 أشهر.')],
        ]),
        heading('ثامناً: أحكام عامة'),
        ...items([
          [_t('يجوز لنون ذكر اسم المدرسة ضمن عملائه ما لم تطلب غير ذلك كتابةً.')],
          [_t('أي تعديل على العقد يكون كتابةً وبموافقة الطرفين.')],
          [_t('لكل طرف إنهاء العقد بإبلاغ الآخر قبل 30 يوماً، وإذا أنهاه نون يعيد للمدرسة قيمة الأشهر الكاملة المتبقية مما دفعته. ولأي طرف إنهاؤه فوراً إذا أخلّ الآخر بالتزام جوهري ولم يعالجه خلال 15 يوماً من إبلاغه.')],
          [_t('يجوز لأي طرف تغيير ممثله بإبلاغ الآخر، ويبقى العقد قائماً بين نون والمدرسة.')],
          [_t('الرسائل على أرقام الجوال أعلاه تُعتبر إبلاغاً رسمياً.')],
          [_t('أي خلاف يُحل بالتفاهم، فإن لم يُحل خلال 15 يوماً فالمرجع المحاكم الفلسطينية المختصة.')],
          [_t('العقد من نسختين، لكل طرف نسخة.')],
        ]),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          children: [
            // الجدول يبدأ من اليسار في المستند: «عن المدرسة» يساراً كما في نسخة الويب
            pw.TableRow(children: [
              signCell([const _Part('عن المدرسة', bold: true)], head: true),
              signCell([const _Part('عن نون', bold: true)], head: true),
            ]),
            pw.TableRow(children: [
              signCell([_t('الاسم: '), _Part(v('rep_name'), bold: true), _t('\nالصفة: '), _Part(v('rep_title'), bold: true)]),
              signCell([_t('الاسم: '), _Part(v('owner_name'), bold: true), _t('\nالصفة: '), _Part(v('owner_title'), bold: true)]),
            ]),
            pw.TableRow(children: [
              signCell([_t('التوقيع والختم:')], height: 44),
              signCell([_t('التوقيع:')], height: 44),
            ]),
          ],
        ),
        pw.SizedBox(height: 0, child: pw.Text('', style: signLabel)),
      ],
    ),
  );
  return doc.save();
}
