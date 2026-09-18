/// إعدادات المنشأة المشتركة بين أجهزتها — المقابل لـ `types/settings.ts`.
///
/// مكانها عمود `settings` في سجل `institution_settings`، لا إعدادات الجهاز: ما
/// يضبطه المدير على سطح المكتب يجب أن يراه الجوال. كانت تُحمَل داخل كائن
/// `colors` بمفاتيح `__*`، وهو مكان ألوان الهوية لا مكان قواعد العمل.
///
/// ما لا تعرفه هذه النسخة يبقى كما وصل في [extra]: النسخة المكتبية تحفظ في
/// العمود نفسه إعداداتٍ أخرى، والكتابة فوقه بما نعرفه وحده كانت تمسحها من السحابة.
library;

import 'grading.dart';
import '../models/models.dart';

/// رسم الحجز يُقتطع من أول الأقساط.
const seatFeeModeDeduct = 'deduct';

/// رسم الحجز مطالبة مستقلة فوق الأقساط.
const seatFeeModeSeparate = 'separate';

/// جهاز مسجّل لترقيم السندات — `receipt_devices` في إعدادات المنشأة.
class ReceiptDeviceEntry {
  const ReceiptDeviceEntry({
    required this.deviceId,
    required this.registeredAt,
    this.label = '',
  });

  final String deviceId;
  final String registeredAt;
  final String label;

  Map<String, dynamic> toMap() => {
        'device_id': deviceId,
        'registered_at': registeredAt,
        if (label.isNotEmpty) 'label': label,
      };

  factory ReceiptDeviceEntry.fromMap(Map<String, dynamic> m) => ReceiptDeviceEntry(
        deviceId: '${m['device_id'] ?? ''}',
        registeredAt: '${m['registered_at'] ?? ''}',
        label: '${m['label'] ?? ''}',
      );
}

class AppSettings {
  const AppSettings({
    this.seatFee = 0,
    this.seatFeeMode = seatFeeModeDeduct,
    this.feeItems = const [],
    this.grading = GradingSettings.empty,
    this.gradingByYear = const {},
    this.receiptDevices = const {},
    this.extra = const {},
  });

  static const empty = AppSettings();

  /// رسم حجز المقعد. صفرٌ حتى تعتمد الإدارة رقماً صراحةً — تثبيته في الكود
  /// قاعدة عمل مخترعة.
  final double seatFee;

  /// [seatFeeModeDeduct] أو [seatFeeModeSeparate].
  final String seatFeeMode;

  final List<FeeItem> feeItems;

  /// نظام الرصد — `settings.grading` في الويب.
  final GradingSettings grading;

  /// لقطات نظام العلامات لكل عام مغلق.
  final Map<String, GradingSettings> gradingByYear;

  /// رموز أجهزة الترقيم — `receipt_devices`.
  final Map<String, ReceiptDeviceEntry> receiptDevices;

  /// مفاتيح العمود التي لا تقرؤها هذه النسخة، تُعاد كما وصلت.
  final Map<String, dynamic> extra;

  bool get deductsSeatFee => seatFeeMode != seatFeeModeSeparate;

  AppSettings copyWith({
    double? seatFee,
    String? seatFeeMode,
    List<FeeItem>? feeItems,
    GradingSettings? grading,
    Map<String, GradingSettings>? gradingByYear,
    Map<String, ReceiptDeviceEntry>? receiptDevices,
    Map<String, dynamic>? extra,
  }) =>
      AppSettings(
        seatFee: seatFee ?? this.seatFee,
        seatFeeMode: seatFeeMode ?? this.seatFeeMode,
        feeItems: feeItems ?? this.feeItems,
        grading: grading ?? this.grading,
        gradingByYear: gradingByYear ?? this.gradingByYear,
        receiptDevices: receiptDevices ?? this.receiptDevices,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toMap() => {
        ...extra,
        'seat_fee': seatFee,
        'seat_fee_mode': seatFeeMode,
        'fee_items': [for (final i in feeItems) i.toMap()],
        'grading': grading.toMap(),
        if (gradingByYear.isNotEmpty)
          'grading_by_year': {
            for (final e in gradingByYear.entries) e.key: e.value.toMap(),
          },
        if (receiptDevices.isNotEmpty)
          'receipt_devices': {
            for (final e in receiptDevices.entries) e.key: e.value.toMap(),
          },
      };

  /// قراءة آمنة: رقمٌ سالب أو نصٌّ مكان قائمة لا يُعطّل بقية الإعدادات.
  factory AppSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return empty;
    final fee = (m['seat_fee'] as num?)?.toDouble() ?? 0;
    final items = m['fee_items'];
    final byYearRaw = m['grading_by_year'];
    final byYear = <String, GradingSettings>{};
    if (byYearRaw is Map) {
      for (final e in byYearRaw.entries) {
        byYear['${e.key}'] = GradingSettings.normalize(e.value);
      }
    }
    final devicesRaw = m['receipt_devices'];
    final devices = <String, ReceiptDeviceEntry>{};
    if (devicesRaw is Map) {
      for (final e in devicesRaw.entries) {
        if (e.value is Map) {
          devices['${e.key}'] = ReceiptDeviceEntry.fromMap(Map<String, dynamic>.from(e.value as Map));
        }
      }
    }
    return AppSettings(
      seatFee: fee > 0 ? fee : 0,
      seatFeeMode: m['seat_fee_mode'] == seatFeeModeSeparate ? seatFeeModeSeparate : seatFeeModeDeduct,
      feeItems: [
        for (final e in (items is List ? items : const []))
          if (e is Map) FeeItem.fromMap(Map<String, dynamic>.from(e)),
      ],
      grading: GradingSettings.normalize(m['grading']),
      gradingByYear: byYear,
      receiptDevices: devices,
      extra: {
        for (final entry in m.entries)
          if (!_known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  static const _known = {
    'seat_fee',
    'seat_fee_mode',
    'fee_items',
    'grading',
    'grading_by_year',
    'receipt_devices',
  };
}
