import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// هوية المنشأة — المقابل لـ `lib/institution.ts` في النسخة المكتبية.
///
/// المفاتيح وأسماء حقول الألوان مطابقة حرفياً، لأن السجل يُحفظ في جدول
/// `institution_settings` المشترك: أي اختلاف في التسمية يجعل الهوية التي
/// يحفظها الجوال غير مقروءة على سطح المكتب والعكس.
const institutionNameKey = 'institution_name';
const institutionLogoKey = 'institution_logo';
const institutionColorsKey = 'institution_colors';
const seatReservationFeeKey = 'seat_reservation_fee';

/// الرسوم الإضافية التي تحددها الإدارة — مطابق لـ `FEE_ITEMS_KEY`.
const feeItemsKey = 'fee_items';
const receiptMigrationKey = 'receipt_numbers_migrated_v1';
const attendanceIdMigrationKey = 'attendance_ids_migrated_v1';

/// علامة إتمام التهيئة الأولية لهذا الجهاز — المقابل لـ `initial_setup_done_<tenantId>`.
String initialSetupKey(String tenantId) => 'initial_setup_done_$tenantId';

/// تجميد لقطات السندات القديمة مرة واحدة لكل جهاز — مطابق لـ
/// `SNAPSHOT_MIGRATION_FLAG` في finance.service.ts
const paymentSnapshotKey = 'payment_snapshots_frozen_v1';

/// تنقية أسماء الشعب والمجموعات القديمة مرة واحدة لكل جهاز — مطابق لـ
/// `sanitizeExistingGroupAndRoomNames` في db.ts
const sectionNameMigrationKey = 'section_names_sanitized_v1';

/// ربط التسجيلات القائمة بشعبها — مطابق لترقية v10 في db.ts
const enrollmentRoomMigrationKey = 'enrollment_room_link_v1';

/// دمج حالة «غير نشط» في «منسحب» — مطابق لترقية v9 في db.ts
const withdrawnStatusMigrationKey = 'student_status_withdrawn_v1';

/// ألوان الهوية — الحقول الخمسة نفسها الموجودة في `InstitutionColors`.
class InstitutionColors {
  const InstitutionColors({
    this.sidebarBg = '#0B2545',
    this.activeItem = '#E88C15',
    this.primaryButton = '#0B2545',
    this.actionButton = '#E88C15',
    this.appBg = '#F8FAFC',
  });

  /// 1. لون القائمة الجانبية والترويسة
  final String sidebarBg;

  /// 2. لون التحديد والتبويب النشط
  final String activeItem;

  /// 3. لون الزر الرئيسي والعناوين
  final String primaryButton;

  /// 4. لون أزرار العمليات وسندات القبض
  final String actionButton;

  /// 5. لون خلفية النظام العامة
  final String appBg;

  static const defaults = InstitutionColors();

  InstitutionColors copyWith({
    String? sidebarBg,
    String? activeItem,
    String? primaryButton,
    String? actionButton,
    String? appBg,
  }) {
    return InstitutionColors(
      sidebarBg: sidebarBg ?? this.sidebarBg,
      activeItem: activeItem ?? this.activeItem,
      primaryButton: primaryButton ?? this.primaryButton,
      actionButton: actionButton ?? this.actionButton,
      appBg: appBg ?? this.appBg,
    );
  }

  Map<String, String> toMap() => {
        'sidebarBg': sidebarBg,
        'activeItem': activeItem,
        'primaryButton': primaryButton,
        'actionButton': actionButton,
        'appBg': appBg,
      };

  factory InstitutionColors.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    String pick(String k, String fallback) {
      final v = m[k];
      if (v is String && parseHexColor(v) != null) return v;
      return fallback;
    }

    return InstitutionColors(
      sidebarBg: pick('sidebarBg', defaults.sidebarBg),
      activeItem: pick('activeItem', defaults.activeItem),
      primaryButton: pick('primaryButton', defaults.primaryButton),
      actionButton: pick('actionButton', defaults.actionButton),
      appBg: pick('appBg', defaults.appBg),
    );
  }
}

/// تشكيلات جاهزة — مطابقة لـ `COLOR_PRESETS` بالاسم والترتيب.
const colorPresets = <(String, InstitutionColors)>[
  ('بنفسجي وأخضر ليموني', InstitutionColors(sidebarBg: '#4A306D', activeItem: '#7CB342', primaryButton: '#4A306D', actionButton: '#558B2F')),
  ('كحلي ملكي وبرتقالي ذهبي', InstitutionColors(sidebarBg: '#0B2545', activeItem: '#E88C15', primaryButton: '#0B2545', actionButton: '#E88C15')),
  ('أزرق داكن وسماوي مشرق', InstitutionColors(sidebarBg: '#0F172A', activeItem: '#0284C7', primaryButton: '#0F172A', actionButton: '#0EA5E9')),
  ('عنابي فاخر وذهبي شامبانيا', InstitutionColors(sidebarBg: '#4A0E17', activeItem: '#D97706', primaryButton: '#4A0E17', actionButton: '#B45309')),
  ('بترولي زمردي وتيركواز', InstitutionColors(sidebarBg: '#134E4A', activeItem: '#0D9488', primaryButton: '#134E4A', actionButton: '#059669')),
  ('رمادي فحمي وقرمزي كلاسيكي', InstitutionColors(sidebarBg: '#1E293B', activeItem: '#DC2626', primaryButton: '#1E293B', actionButton: '#B91C1C')),
  ('كحلي عميق وأصفر خردلي', InstitutionColors(sidebarBg: '#172554', activeItem: '#EAB308', primaryButton: '#172554', actionButton: '#CA8A04')),
  ('رمادي بركاني وبنفسجي لافندر', InstitutionColors(sidebarBg: '#2D3748', activeItem: '#8B5CF6', primaryButton: '#2D3748', actionButton: '#7C3AED')),
  ('زيتي عميق وبرتقالي يوسفي', InstitutionColors(sidebarBg: '#1C3124', activeItem: '#EA580C', primaryButton: '#1C3124', actionButton: '#15803D')),
  ('كحلي بحري ووردي مرجاني', InstitutionColors(sidebarBg: '#0F2942', activeItem: '#F43F5E', primaryButton: '#0F2942', actionButton: '#E11D48')),
  ('أزرق هادئ وفستقي حيوي', InstitutionColors(sidebarBg: '#1E3A5F', activeItem: '#65A30D', primaryButton: '#1E3A5F', actionButton: '#84CC16')),
  ('إسبريسو دافئ وخوخي مشرق', InstitutionColors(sidebarBg: '#3E2723', activeItem: '#F97316', primaryButton: '#3E2723', actionButton: '#EA580C')),
];

ui.Color? parseHexColor(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return ui.Color(0xFF000000 | v);
}

String hexOf(ui.Color c) {
  int ch(double v) => (v * 255).round().clamp(0, 255);
  final r = ch(c.r).toRadixString(16).padLeft(2, '0');
  final g = ch(c.g).toRadixString(16).padLeft(2, '0');
  final b = ch(c.b).toRadixString(16).padLeft(2, '0');
  return '#${(r + g + b).toUpperCase()}';
}

String _rgbToHex(int r, int g, int b) {
  String h(int n) => n.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${h(r)}${h(g)}${h(b)}';
}

/// نتيجة اقتباس الألوان من الشعار.
class ExtractedPalette {
  const ExtractedPalette(this.colors, this.palette);
  final InstitutionColors colors;
  final List<String> palette;
}

class _ColorCluster {
  _ColorCluster(this.r, this.g, this.b, this.lightness, this.saturation)
      : totalR = r,
        totalG = g,
        totalB = b,
        count = 1;

  int r, g, b;
  int totalR, totalG, totalB;
  int count;
  double lightness;
  double saturation;

  String get hex => _rgbToHex(r, g, b);
}

/// المسافة اللونية الإدراكية — مطابقة لـ `calcDist`.
double _dist(int r1, int g1, int b1, int r2, int g2, int b2) {
  return math.sqrt(
    0.299 * math.pow(r1 - r2, 2) + 0.587 * math.pow(g1 - g2, 2) + 0.114 * math.pow(b1 - b2, 2),
  );
}

/// اقتباس لوحة ألوان الهوية من الشعار — مطابق لـ `extractColorsFromLogo`
/// بالتجميع اللوني المتمايز (perceptual clustering) بنفس العتبات.
Future<ExtractedPalette> extractColorsFromLogo(Uint8List? imageBytes) async {
  if (imageBytes == null || imageBytes.isEmpty) {
    return const ExtractedPalette(InstitutionColors.defaults, []);
  }

  try {
    // عينات بدقة 120×120 لالتقاط تفاصيل الشعار الحقيقية
    const size = 120;
    final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: size, targetHeight: size);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return const ExtractedPalette(InstitutionColors.defaults, []);

    final px = data.buffer.asUint8List();
    final clusters = <_ColorCluster>[];

    for (var i = 0; i + 3 < px.length; i += 4) {
      final a = px[i + 3];
      if (a < 70) continue; // تجاهل الشفاف وشبه الشفاف

      final r = px[i];
      final g = px[i + 1];
      final b = px[i + 2];

      final max = math.max(r, math.max(g, b));
      final min = math.min(r, math.min(g, b));
      final light = (max + min) / 510;
      final sat = max == min ? 0.0 : (max - min) / (light > 0.5 ? 510 - max - min : max + min);

      // تجاهل خلفية بيضاء تماماً
      if (light > 0.96 && sat < 0.1) continue;

      var matched = false;
      for (final cl in clusters) {
        if (_dist(r, g, b, cl.r, cl.g, cl.b) <= 26) {
          cl.totalR += r;
          cl.totalG += g;
          cl.totalB += b;
          cl.count++;
          cl.r = (cl.totalR / cl.count).round();
          cl.g = (cl.totalG / cl.count).round();
          cl.b = (cl.totalB / cl.count).round();
          final cMax = math.max(cl.r, math.max(cl.g, cl.b));
          final cMin = math.min(cl.r, math.min(cl.g, cl.b));
          cl.lightness = (cMax + cMin) / 510;
          cl.saturation = cMax == cMin ? 0.0 : (cMax - cMin) / (cl.lightness > 0.5 ? 510 - cMax - cMin : cMax + cMin);
          matched = true;
          break;
        }
      }

      if (!matched && clusters.length < 50) {
        clusters.add(_ColorCluster(r, g, b, light, sat));
      }
    }

    if (clusters.isEmpty) return const ExtractedPalette(InstitutionColors.defaults, []);

    clusters.sort((a, b) => b.count.compareTo(a.count));

    // ألوان متمايزة بمسافة لا تقل عن 38 حتى لا تتكرر الدرجات
    final distinct = <_ColorCluster>[];
    for (final cl in clusters) {
      final farEnough = distinct.every((sel) => _dist(cl.r, cl.g, cl.b, sel.r, sel.g, sel.b) >= 38);
      if (farEnough) {
        distinct.add(cl);
        if (distinct.length >= 8) break;
      }
    }

    final palette = distinct.map((c) => c.hex).toList();

    // 1. القائمة الجانبية: لون داكن حقيقي من الشعار، وإلا نُغمّق الأبرز
    final darkCandidate = distinct.where((c) => c.lightness >= 0.08 && c.lightness <= 0.38).firstOrNull ??
        clusters.where((c) => c.lightness >= 0.08 && c.lightness <= 0.38).firstOrNull;

    final String sidebarBg;
    if (darkCandidate != null) {
      sidebarBg = darkCandidate.hex;
    } else {
      final base = distinct.isNotEmpty ? distinct.first : clusters.first;
      const factor = 0.35;
      sidebarBg = _rgbToHex((base.r * factor).round(), (base.g * factor).round(), (base.b * factor).round());
    }

    // 2. العنصر النشط: لون حيوي مشبع يمثل هوية الشعار
    final activeCandidate = distinct
            .where((c) => c.saturation >= 0.28 && c.lightness >= 0.35 && c.lightness <= 0.78)
            .firstOrNull ??
        distinct.where((c) => c.hex != sidebarBg).firstOrNull ??
        distinct.first;
    final activeItem = activeCandidate.hex;

    // 3. الأزرار الرئيسية والعناوين
    final primaryButton = sidebarBg;

    // 4. أزرار العمليات وسندات القبض
    final actionCandidate = distinct
            .where((c) => c.hex != sidebarBg && c.hex != activeItem && c.saturation >= 0.25)
            .firstOrNull ??
        activeCandidate;

    return ExtractedPalette(
      InstitutionColors(
        sidebarBg: sidebarBg,
        activeItem: activeItem,
        primaryButton: primaryButton,
        actionButton: actionCandidate.hex,
      ),
      palette,
    );
  } catch (_) {
    return const ExtractedPalette(InstitutionColors.defaults, []);
  }
}
