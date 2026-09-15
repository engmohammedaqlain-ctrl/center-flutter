/// إعدادات المنشأة المشتركة بين أجهزتها — المقابل لـ `types/settings.ts`.
///
/// مكانها عمود `settings` في سجل `institution_settings`، لا إعدادات الجهاز: ما
/// يضبطه المدير على سطح المكتب يجب أن يراه الجوال. كانت تُحمَل داخل كائن
/// `colors` بمفاتيح `__*`، وهو مكان ألوان الهوية لا مكان قواعد العمل.
///
/// ما لا تعرفه هذه النسخة يبقى كما وصل في [extra]: النسخة المكتبية تحفظ في
/// العمود نفسه إعداداتٍ أخرى (نظام الرصد ومكوّناته)، والكتابة فوقه بما نعرفه
/// وحده كانت تمسحها من السحابة.
library;

import '../models/models.dart';

/// رسم الحجز يُقتطع من أول الأقساط.
const seatFeeModeDeduct = 'deduct';

/// رسم الحجز مطالبة مستقلة فوق الأقساط.
const seatFeeModeSeparate = 'separate';

class AppSettings {
  const AppSettings({
    this.seatFee = 0,
    this.seatFeeMode = seatFeeModeDeduct,
    this.feeItems = const [],
    this.extra = const {},
  });

  static const empty = AppSettings();

  /// رسم حجز المقعد. صفرٌ حتى تعتمد الإدارة رقماً صراحةً — تثبيته في الكود
  /// قاعدة عمل مخترعة.
  final double seatFee;

  /// [seatFeeModeDeduct] أو [seatFeeModeSeparate].
  final String seatFeeMode;

  final List<FeeItem> feeItems;

  /// مفاتيح العمود التي لا تقرؤها هذه النسخة، تُعاد كما وصلت.
  final Map<String, dynamic> extra;

  bool get deductsSeatFee => seatFeeMode != seatFeeModeSeparate;

  AppSettings copyWith({
    double? seatFee,
    String? seatFeeMode,
    List<FeeItem>? feeItems,
    Map<String, dynamic>? extra,
  }) =>
      AppSettings(
        seatFee: seatFee ?? this.seatFee,
        seatFeeMode: seatFeeMode ?? this.seatFeeMode,
        feeItems: feeItems ?? this.feeItems,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toMap() => {
        ...extra,
        'seat_fee': seatFee,
        'seat_fee_mode': seatFeeMode,
        'fee_items': [for (final i in feeItems) i.toMap()],
      };

  /// قراءة آمنة: رقمٌ سالب أو نصٌّ مكان قائمة لا يُعطّل بقية الإعدادات.
  factory AppSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return empty;
    final fee = (m['seat_fee'] as num?)?.toDouble() ?? 0;
    final items = m['fee_items'];
    return AppSettings(
      seatFee: fee > 0 ? fee : 0,
      seatFeeMode: m['seat_fee_mode'] == seatFeeModeSeparate ? seatFeeModeSeparate : seatFeeModeDeduct,
      feeItems: [
        for (final e in (items is List ? items : const []))
          if (e is Map) FeeItem.fromMap(Map<String, dynamic>.from(e)),
      ],
      extra: {
        for (final entry in m.entries)
          if (!_known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  static const _known = {'seat_fee', 'seat_fee_mode', 'fee_items'};
}
