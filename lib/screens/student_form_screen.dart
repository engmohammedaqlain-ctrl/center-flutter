import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/academic_matching.dart';
import '../data/phone.dart';
import '../data/fee_plan.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_plan_rows.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';
import 'return_to_grade_plan_sheet.dart';

class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({super.key, this.student});
  final Student? student;

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  late final name = TextEditingController(text: widget.student?.fullName ?? '');
  late final nationalId = TextEditingController(text: widget.student?.nationalId ?? '');
  late final portalCode = TextEditingController(
    text: widget.student?.portalCode ?? AppStore.instance.newPortalCode(),
  );

  /// كلمة ولي الأمر: تُولَّد للطالب الجديد مختلفةً عن كلمته، كما في StudentForm.tsx.
  /// رقم هوية وليّ الأمر — مفتاح ربط الإخوة.
  late final parentNationalId = TextEditingController(text: widget.student?.parentNationalId ?? '');

  /// أخٌ وُجد بالرقم نفسه: اسمه وكلمة وليّ أمره.
  ({String name, String code})? sibling;

  /// كلمة كتبها الموظف بيده لا تُدهس بكلمة الأخ.
  bool _parentCodeTouched = false;

  late final parentPortalCode = TextEditingController(
    text: widget.student?.parentPortalCode ?? AppStore.instance.newDistinctPortalCode(portalCode.text),
  );
  late final parentName = TextEditingController(text: widget.student?.parentName ?? '');
  late final notes = TextEditingController(text: widget.student?.notes ?? '');
  late final detailedAddress = TextEditingController(text: widget.student?.detailedAddress ?? '');
  late final customNeighborhood = TextEditingController();
  late final birthPlace = TextEditingController(text: widget.student?.birthPlace ?? '');
  late final nationality = TextEditingController(text: widget.student?.nationality ?? '');
  late final previousSchool = TextEditingController(text: (widget.student?.previousSchool.isNotEmpty == true ? widget.student!.previousSchool : widget.student?.schoolName) ?? '');
  late final gpa = TextEditingController(text: widget.student?.gpa ?? '');
  late final originalArea = TextEditingController(text: widget.student?.originalArea ?? '');
  late final medicalCondition = TextEditingController(text: widget.student?.medicalCondition ?? '');
  late final parentJob = TextEditingController(text: widget.student?.parentJob ?? '');
  late final email = TextEditingController(text: widget.student?.email ?? '');
  late final sectionCtl = TextEditingController(text: widget.student?.section ?? '');
  late final parentSecondaryNumber = TextEditingController();
  late final phoneCtl = TextEditingController();
  late final parentPhoneCtl = TextEditingController();

  late String grade;

  /// حالة الطالب: `active | pending | withdrawn | archived`.
  late String status;

  // ── الخصم الشهري: المقابل لحالة `hasCustomDiscount` في StudentForm.tsx ──
  late bool hasDiscount;

  /// للتسجيل الجديد فقط: خطة كاملة أو من تاريخ الالتحاق — `EnrollmentPlanMode`.
  EnrollmentPlanMode enrollmentMode = EnrollmentPlanMode.full;

  /// مصدر أقساط التسجيل: خطة المرحلة أو خطة مخصصة — كويب `planSource`.
  String planSource = 'grade'; // grade | custom
  final customRows = <CustomPlanRow>[];
  final scrollCtl = ScrollController();

  /// `percentage` نسبة، `fixed` مبلغ مقطوع — كالويب (بلا «رسم محدد»).
  late String discountType;
  final discountRate = TextEditingController(text: '10');
  final discountFixed = TextEditingController(text: '20');
  final discountReason = TextEditingController();
  late String relation;
  late String neighborhood;
  late String gender;
  late String referral;
  late String housing;
  late String health;
  late DateTime enrollmentDate;
  DateTime? birthDate;
  late String phonePrefix;
  late String phoneNumber;
  late String parentPhonePrefix;
  late String parentPhoneNumber;
  late String secondaryPrefix;
  String? idDuplicateError;
  String? phoneDuplicateError;
  bool extra = false;
  int initialRating = 0;
  bool guardianDeclaration = false;
  String studentIdPhoto = '';
  String birthCertificate = '';
  bool attachmentsLoaded = false;
  final errors = FieldErrors();

  static const _gap = SizedBox(height: 12);

  /// حقول تحت «بيانات إضافية» المطويّة.
  static const _extraFieldKeys = {'parentPhone', 'parentCode'};

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    // لا مرحلة افتراضية: المرحلة اختيار صريح من مراحل المنشأة
    grade = s?.gradeLevel.trim() ?? '';

    // `inactive` القديمة تُقرأ «منسحب» كما بعد ترقية v9
    status = s == null ? 'active' : (s.status == 'inactive' ? 'withdrawn' : s.status);

    // الخصم القائم يُقرأ للعرض فقط: عند التعديل الحقول معطّلة كالويب
    hasDiscount = s != null && (s.academicDiscountApplied || s.planDiscountValue > 0 || (s.customMonthlyFee ?? 0) > 0);
    if (s?.planDiscountType == 'fixed') {
      discountType = 'fixed';
      if (s!.planDiscountValue > 0) discountFixed.text = trimNum(s.planDiscountValue);
    } else {
      discountType = 'percentage';
      final rate = (s?.academicDiscountRate ?? 0) > 0
          ? s!.academicDiscountRate
          : (s?.planDiscountType == 'percentage' ? s!.planDiscountValue : 0.0);
      if (rate > 0) discountRate.text = trimNum(rate);
    }
    discountReason.text =
        (s?.planDiscountReason.isNotEmpty == true ? s!.planDiscountReason : s?.exceptionReason) ?? '';

    relation = s?.relation ?? '';
    neighborhood = (s?.neighborhood ?? '').isNotEmpty && neighborhoods.contains(s!.neighborhood) ? s.neighborhood : ((s?.neighborhood ?? '').isNotEmpty ? 'أخرى' : '');
    if (neighborhood == 'أخرى' && s != null) customNeighborhood.text = s.neighborhood;
    // «male»/«female» تصل أحياناً من السحابة؛ تُعرض مختارة وتُحفظ بالعربية كما في Center.
    // طالبٌ جديد بلا اختيار: القيم المفترضة كانت تُحفظ عمّن لم يُسأل عنه أصلاً
    gender = s == null ? '' : genderLabel(s.gender);
    referral = s?.referralSource ?? '';
    housing = s?.housingStatus ?? '';
    health = s?.healthStatus ?? '';
    enrollmentDate = s?.enrolledAt ?? DateTime.now();
    birthDate = parseIsoDate(s?.birthDate);
    initialRating = s?.initialRating ?? 0;
    guardianDeclaration = s?.guardianDeclaration ?? false;

    final parsed = parsePhoneAndPrefix(s?.phone);
    phonePrefix = (s?.phonePrefix.isNotEmpty == true) ? s!.phonePrefix : parsed.prefix;
    phoneNumber = parsed.number;
    phoneCtl.text = phoneNumber;
    final parentParsed = parsePhoneAndPrefix(s?.parentPhone);
    parentPhonePrefix = (s?.parentPhonePrefix.isNotEmpty == true) ? s!.parentPhonePrefix : parentParsed.prefix;
    parentPhoneNumber = parentParsed.number;
    parentPhoneCtl.text = parentPhoneNumber;
    final secParsed = parsePhoneAndPrefix(s?.parentSecondaryPhone);
    secondaryPrefix = secParsed.prefix;
    parentSecondaryNumber.text = secParsed.number;

    nationalId.addListener(_onNationalIdChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAttachments());
    _initial = _snapshot();
  }

  /// صورة القيم كما فُتح بها النموذج — للمقارنة قبل الخروج.
  late String _initial;

  String _snapshot() => [
        name.text, nationalId.text, portalCode.text, parentPortalCode.text, parentName.text,
        notes.text, detailedAddress.text, customNeighborhood.text, birthPlace.text, nationality.text,
        previousSchool.text, gpa.text, originalArea.text, medicalCondition.text, parentJob.text,
        email.text, sectionCtl.text, parentSecondaryNumber.text, phoneCtl.text, parentPhoneCtl.text,
        discountRate.text, discountFixed.text, discountReason.text,
        grade, status, relation, neighborhood, gender, referral, housing, health,
        '$hasDiscount', discountType, '$initialRating', '$guardianDeclaration',
        isoDate(enrollmentDate), birthDate == null ? '' : isoDate(birthDate!),
        phonePrefix, parentPhonePrefix, secondaryPrefix, studentIdPhoto, birthCertificate,
        planSource, customRows.map((r) => '${r.title}:${r.amount}:${r.dueDate}').join(';'),
      ].join('|');

  bool get _hasChanges => _snapshot() != _initial;

  /// الخروج ببيانات لم تُحفظ يسأل أولاً — نموذج طويل يضيع بلمسة رجوع واحدة.
  Future<bool> _confirmExit() async {
    if (!_hasChanges) return true;
    return confirmSheet(
      context,
      title: 'تجاهل ما أُدخل؟',
      message: 'البيانات التي كتبتها لن تُحفظ.',
      confirmLabel: 'تجاهل',
    );
  }

  Future<void> _loadAttachments() async {
    final s = widget.student;
    if (s == null) {
      setState(() => attachmentsLoaded = true);
      return;
    }
    final store = StoreScope.of(context);
    if (!store.features.enableStudentAttachments) {
      setState(() => attachmentsLoaded = true);
      return;
    }
    final att = await store.loadAttachments(s.id);
    if (!mounted) return;
    setState(() {
      studentIdPhoto = att?.studentIdPhoto ?? '';
      birthCertificate = att?.birthCertificate ?? '';
      attachmentsLoaded = true;
    });
  }

  /// أخٌ مسجَّل بالرقم نفسه: كلمة وليّ أمره تُنسخ للطالب الجديد، فيدخل الأب
  /// مرة واحدة ويرى ابنيه. بلا ذلك تُولَّد لكل ابن كلمة، فلا يصل إلا لأحدهما.
  void _findSibling() {
    final clean = parentNationalId.text.trim();
    if (clean.isEmpty) {
      if (sibling != null) setState(() => sibling = null);
      return;
    }
    final found = AppStore.instance.siblingByParentNationalId(clean, exclude: widget.student?.id);
    if (found == null) {
      if (sibling != null) setState(() => sibling = null);
      return;
    }
    setState(() {
      sibling = (name: found.fullName, code: found.parentPortalCode);
      if (!_parentCodeTouched) parentPortalCode.text = found.parentPortalCode;
      if (parentName.text.trim().isEmpty) parentName.text = found.parentName;
    });
  }

  @override
  void dispose() {
    name.dispose();
    nationalId.dispose();
    portalCode.dispose();
    parentPortalCode.dispose();
    parentNationalId.dispose();
    parentName.dispose();
    notes.dispose();
    detailedAddress.dispose();
    customNeighborhood.dispose();
    birthPlace.dispose();
    nationality.dispose();
    previousSchool.dispose();
    gpa.dispose();
    originalArea.dispose();
    medicalCondition.dispose();
    parentJob.dispose();
    email.dispose();
    sectionCtl.dispose();
    parentSecondaryNumber.dispose();
    phoneCtl.dispose();
    parentPhoneCtl.dispose();
    discountRate.dispose();
    discountFixed.dispose();
    discountReason.dispose();
    scrollCtl.dispose();
    super.dispose();
  }

  void _onNationalIdChanged() {
    final clean = digitsOnly(nationalId.text).substring(0, digitsOnly(nationalId.text).length.clamp(0, 9));
    if (nationalId.text != clean) {
      nationalId.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    errors.clear('nationalId');
    if (clean.length == 9) {
      final dup = StoreScope.of(context).findByNationalId(clean, exclude: widget.student?.id);
      setState(() {
        idDuplicateError = dup == null ? null : 'رقم الهوية مسجَّل للطالب ${dup.fullName}';
      });
    } else {
      setState(() => idDuplicateError = null);
    }
  }

  void _applyStudentPhone(String raw) {
    var clean = digitsOnly(raw);
    var prefix = phonePrefix;
    if (clean.startsWith('059')) {
      prefix = '059';
      clean = clean.substring(3);
    } else if (clean.startsWith('056')) {
      prefix = '056';
      clean = clean.substring(3);
    } else if (clean.startsWith('59')) {
      prefix = '059';
      clean = clean.substring(2);
    } else if (clean.startsWith('56')) {
      prefix = '056';
      clean = clean.substring(2);
    }
    clean = clean.substring(0, clean.length.clamp(0, phoneTargetLength(prefix)));
    if (phoneCtl.text != clean) {
      phoneCtl.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    setState(() {
      phonePrefix = prefix;
      phoneNumber = clean;
      errors.clear('phone');
      _checkPhoneDup();
    });
  }

  void _applyParentPhone(String raw) {
    var clean = digitsOnly(raw);
    var prefix = parentPhonePrefix;
    if (clean.startsWith('059')) {
      prefix = '059';
      clean = clean.substring(3);
    } else if (clean.startsWith('056')) {
      prefix = '056';
      clean = clean.substring(3);
    } else if (clean.startsWith('59')) {
      prefix = '059';
      clean = clean.substring(2);
    } else if (clean.startsWith('56')) {
      prefix = '056';
      clean = clean.substring(2);
    }
    clean = clean.substring(0, clean.length.clamp(0, phoneTargetLength(prefix)));
    if (parentPhoneCtl.text != clean) {
      parentPhoneCtl.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    setState(() {
      parentPhonePrefix = prefix;
      parentPhoneNumber = clean;
      errors.clear('parentPhone');
    });
  }

  void _checkPhoneDup() {
    if (!isPhoneComplete(phoneNumber, phonePrefix)) {
      phoneDuplicateError = null;
      return;
    }
    final full = combinePhoneAndPrefix(phoneNumber, phonePrefix);
    final dup = StoreScope.of(context).findByPhone(full, exclude: widget.student?.id);
    // تنبيه لا خطأ يمنع الحفظ: إخوة صغار يُسجَّلون برقم ولي أمرهم
    phoneDuplicateError = dup == null
        ? null
        : 'رقم الجوال ($full) مسجل للطالب «${dup.fullName}» — يمكن المتابعة بنفس الرقم';
  }

  void _setPlanSource(String next) {
    final top = scrollCtl.hasClients ? scrollCtl.offset : 0.0;
    setState(() {
      planSource = next;
      if (next == 'custom' && customRows.isEmpty) {
        final fee = _gradeFeeOf(context);
        customRows.add(
          CustomPlanRow(
            title: 'قسط 1',
            amount: fee > 0 ? trimNum(fee) : '',
            dueDate: isoDate(enrollmentDate),
          ),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtl.hasClients) scrollCtl.jumpTo(top.clamp(0.0, scrollCtl.position.maxScrollExtent));
    });
  }

  /// بنود الخطة المخصصة من صفوف المحرّر — للحفظ والمعاينة.
  List<PlanItem>? _customPlanSchedule() {
    if (planSource != 'custom' || widget.student != null) return null;
    if (customRows.isEmpty) return null;
    return [
      for (var i = 0; i < customRows.length; i++)
        if (customRows[i].dueDate.trim().isNotEmpty)
          PlanItem(
            id: 'slot_${i + 1}',
            title: customRows[i].title.trim().isEmpty ? 'قسط ${i + 1}' : customRows[i].title.trim(),
            amount: customRows[i].amountValue,
            dueDate: customRows[i].dueDate.trim(),
          ),
    ];
  }

  /// معاينة الأقساط قبل التسجيل — `planPreview` في StudentForm.tsx.
  List<StudentPlanRow> _planPreview(BuildContext context) {
    if (widget.student != null) return const [];
    final store = StoreScope.of(context);
    final custom = _customPlanSchedule();
    final List<PlanItem> source;
    if (planSource == 'custom') {
      source = custom ?? const [];
    } else {
      source = store.planItemsOf(store.feeFor(grade));
    }
    if (source.isEmpty) return const [];
    return buildStudentPlan(
      source,
      'preview',
      seatFee: store.seatReservationFee,
      deductSeat: store.deductsSeatFee,
      discount: _planDiscountOf(_gradeFeeOf(context)),
      enrollmentDate: isoDate(enrollmentDate),
      enrollmentMode: planSource == 'custom' ? EnrollmentPlanMode.full : enrollmentMode,
      customIds: planSource == 'custom',
    );
  }

  Future<void> _pickDate({required bool birth}) async {
    final initial = birth ? (birthDate ?? DateTime(2010, 1, 1)) : enrollmentDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (birth) {
        birthDate = picked;
      } else {
        enrollmentDate = picked;
      }
    });
  }

  Future<void> _pickAttachment(void Function(String) setVal) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 72);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) showAppSnack(context, 'الملف أكبر من 5 ميجابايت', error: true);
        return;
      }
      final mime = file.mimeType ?? 'image/jpeg';
      setState(() => setVal('data:$mime;base64,${base64Encode(bytes)}'));
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر اختيار الملف', error: true);
    }
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    final trimmedFullName = name.text.trim();
    final cleanNatId = digitsOnly(nationalId.text);

    // كل الحقول الناقصة دفعة واحدة، كلٌّ تحت حقله — لا رسالة واحدة تُخفي ما بعدها
    setState(() {
      errors
        ..reset()
        ..check('name', trimmedFullName.isEmpty, 'اسم الطالب مطلوب')
        ..check(
          'grade',
          grade.trim().isEmpty,
          _gradeOptions(store).isEmpty ? 'أضف المراحل أولاً من «الإعدادات ← المراحل والرسوم»' : 'المرحلة مطلوبة',
        )
        ..check('nationalId', cleanNatId.isEmpty, 'رقم الهوية مطلوب (9 أرقام)')
        ..check(
          'nationalId',
          !isValidNationalId(cleanNatId),
          'رقم الهوية غير صالح: يجب أن يتكون من 9 أرقام (المُدخل: ${cleanNatId.length})',
        )
        ..check('nationalId', idDuplicateError != null, idDuplicateError ?? '')
        ..check('phone', phoneNumber.trim().isEmpty, 'جوال الطالب مطلوب')
        ..check(
          'phone',
          !isPhoneComplete(phoneNumber, phonePrefix),
          'الرقم غير مكتمل: يجب إدخال ${phoneTargetLength(phonePrefix)} أرقام بعد المقدمة ($phonePrefix)',
        )
        ..check(
          'parentPhone',
          parentPhoneNumber.trim().isNotEmpty && !isPhoneComplete(parentPhoneNumber, parentPhonePrefix),
          'الرقم غير مكتمل: يجب إدخال ${phoneTargetLength(parentPhonePrefix)} أرقام بعد المقدمة ($parentPhonePrefix)',
        );
      final parentCode = parentPortalCode.text.trim();
      final studentCode = portalCode.text.trim();
      errors.check(
        'parentCode',
        parentCode.isNotEmpty && parentCode == studentCode,
        'كلمة مرور ولي الأمر يجب أن تختلف عن كلمة مرور الطالب',
      );
      if (widget.student == null && planSource == 'custom') {
        errors
          ..check('customPlan', customRows.isEmpty, 'خطة مخصصة: أضف قسطاً واحداً على الأقل')
          ..check(
            'customPlan',
            customRows.isNotEmpty && customRows.any((r) => r.dueDate.trim().isEmpty),
            'خطة مخصصة: حدّد تاريخ استحقاق لكل قسط',
          );
      }
    });
    // حقل ناقص تحت «بيانات إضافية» يُفتح قسمه قبل التمرير إليه
    if (errors.report(context, reveal: (field) {
      if (_extraFieldKeys.contains(field)) setState(() => extra = true);
    })) {
      return;
    }

    if (phoneDuplicateError != null) {
      final full = combinePhoneAndPrefix(phoneNumber, phonePrefix);
      final dup = store.findByPhone(full, exclude: widget.student?.id);
      final ok = await confirmSheet(
        context,
        title: 'رقم جوال مكرر',
        message:
            'رقم الجوال ($full) مسجل للطالب «${dup?.fullName ?? 'طالب آخر'}». هل تريد المتابعة بنفس الرقم؟',
        confirmLabel: 'متابعة',
      );
      if (!ok || !mounted) return;
    }

    final parts = trimmedFullName.split(RegExp(r'\s+'));
    final firstName = parts.isEmpty ? '' : parts.first;
    final lastName = parts.length <= 1 ? firstName : parts.skip(1).join(' ');
    final selectedNeighborhood = neighborhood == 'أخرى' && customNeighborhood.text.trim().isNotEmpty
        ? customNeighborhood.text.trim()
        : neighborhood;
    final finalGrade = grade.trim();
    final existing = widget.student;
    final id = existing?.id ?? store.newId();
    final gradeFee = _gradeFeeOf(context);
    final customSchedule = () {
      final raw = _customPlanSchedule();
      if (raw == null) return null;
      final discount = _planDiscountOf(gradeFee);
      if (discount == null || discount.value <= 0) return raw;
      // كالويب `planRowsForSave`: الخصم يُطبَّق على البنود قبل الحفظ
      final discounted = applyPlanDiscount(
        [for (final i in raw) StudentPlanRow(id: i.id, title: i.title, amount: i.amount, dueDate: i.dueDate)],
        discount,
      );
      return [
        for (final r in discounted) PlanItem(id: r.id, title: r.title, amount: r.amount, dueDate: r.dueDate),
      ];
    }();

    try {
      final isNew = existing == null;
      // الخصم يُطبَّق عند بناء الأقساط للتسجيل الجديد فقط — كالويب
      final applyDiscount = isNew && hasDiscount;
      final planDiscount = isNew ? _planDiscountOf(gradeFee) : null;
      final oldGrade = existing?.gradeLevel.trim() ?? '';
      final gradeChanged =
          !isNew && oldGrade.isNotEmpty && finalGrade.isNotEmpty && oldGrade.toLowerCase() != finalGrade.toLowerCase();

      final draft = Student(
        id: id,
        firstName: firstName,
        lastName: lastName,
        fullName: trimmedFullName,
        gradeLevel: finalGrade,
        section: sectionCtl.text.trim(),
        phone: combinePhoneAndPrefix(phoneNumber, phonePrefix),
        phonePrefix: phonePrefix,
        parentName: parentName.text.trim(),
        parentPhone: combinePhoneAndPrefix(parentPhoneNumber, parentPhonePrefix),
        parentPhonePrefix: parentPhonePrefix,
        nationalId: cleanNatId,
        portalCode: portalCode.text.trim(),
        parentPortalCode: parentPortalCode.text.trim(),
        parentNationalId: parentNationalId.text.trim(),
        neighborhood: selectedNeighborhood,
        relation: relation,
        gender: gender,
        notes: notes.text.trim(),
        balance: existing?.balance ?? 0,
        enrolledAt: enrollmentDate,
        detailedAddress: detailedAddress.text.trim(),
        referralSource: referral,
        schoolName: previousSchool.text.trim().isNotEmpty ? previousSchool.text.trim() : (existing?.schoolName ?? ''),
        status: status,
        birthDate: birthDate == null ? '' : isoDate(birthDate!),
        birthPlace: birthPlace.text.trim(),
        nationality: nationality.text.trim(),
        previousSchool: previousSchool.text.trim(),
        gpa: gpa.text.trim(),
        housingStatus: housing,
        originalArea: originalArea.text.trim(),
        healthStatus: health,
        medicalCondition: health == 'مريض' ? medicalCondition.text.trim() : '',
        parentJob: parentJob.text.trim(),
        parentSecondaryPhone: combinePhoneAndPrefix(parentSecondaryNumber.text.trim(), secondaryPrefix),
        email: email.text.trim(),
        guardianDeclaration: guardianDeclaration,
        initialRating: initialRating,
        seatReservationPaid: existing?.seatReservationPaid ?? false,
        seatReservationDiscounted: existing?.seatReservationDiscounted ?? false,
        paymentPlan: existing?.paymentPlan ?? 'full',
        paymentStatus: existing?.paymentStatus ?? 'unpaid',
        academicDiscountApplied: isNew ? applyDiscount : existing.academicDiscountApplied,
        academicDiscountRate: isNew
            ? (applyDiscount && discountType == 'percentage' ? _discountRateValue : 0)
            : existing.academicDiscountRate,
        hasException: existing?.hasException ?? false,
        exceptionReason: customSchedule != null
            ? 'خطة مخصصة'
            : (isNew
                ? (applyDiscount ? discountReason.text.trim() : '')
                : existing.exceptionReason),
        customMonthlyFee: existing?.customMonthlyFee,
        planDiscountType: isNew ? null : existing.planDiscountType,
        planDiscountValue: isNew ? 0 : existing.planDiscountValue,
        planDiscountReason: isNew ? '' : existing.planDiscountReason,
        planDiscountFrom: isNew ? '' : existing.planDiscountFrom,
        usesCustomPlan: customSchedule != null || (existing?.usesCustomPlan ?? false),
        academicYearId: existing?.academicYearId ?? '',
        createdAt: existing?.createdAt,
      );

      final attachments = attachmentsLoaded
          ? StudentAttachments(
              id: id,
              studentIdPhoto: studentIdPhoto,
              birthCertificate: birthCertificate,
            )
          : null;

      // تغيّر المرحلة عند التعديل: حفظ البيانات ثم نقل مالي بنطاق الخطة (SD-R03 / ST-19)
      if (gradeChanged) {
        final transferred = await showReturnToGradePlanSheet(
          context: context,
          studentIds: [id],
          studentGrades: [finalGrade],
          mode: ReturnToGradePlanMode.transfer,
          fixedGradeName: finalGrade,
          onPrepare: () async {
            store.upsertStudent(
              draft,
              isNew: false,
              allowDuplicatePhone: phoneDuplicateError != null,
              attachments: attachments,
            );
          },
        );
        if (transferred && mounted) Navigator.pop(context);
        return;
      }

      store.upsertStudent(
        draft,
        isNew: isNew,
        discount: planDiscount,
        enrollmentMode: isNew && planSource == 'grade' ? enrollmentMode : EnrollmentPlanMode.full,
        allowDuplicatePhone: phoneDuplicateError != null,
        customPlanItems: customSchedule,
        attachments: attachments,
      );
      if (mounted) Navigator.pop(context);
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  // ═══ الواجهة ══════════════════════════════════════════════════════════════
  //
  // الحقول على الصفحة مباشرة لا داخل بطاقات؛ الأقسام يفصلها عنوان وخط. الحقول
  // القصيرة متجاورة في صفّ، والعدّاد وزر التوليد داخل حقليهما، والحفظ ثابت
  // أسفل الشاشة فلا حاجة للنزول إلى آخر النموذج.

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final editing = widget.student != null;
    if (!store.can('students')) {
      return Scaffold(
        appBar: AppBar(title: Text(editing ? 'تعديل بيانات الطالب' : 'تسجيل طالب جديد')),
        body: NoAccess(section: 'students', roleName: store.roleName),
      );
    }
    final studentLen = phoneTargetLength(phonePrefix);
    final studentComplete = isPhoneComplete(phoneNumber, phonePrefix);
    final fullStudentPhone = combinePhoneAndPrefix(phoneNumber, phonePrefix);
    final grades = _gradeOptions(store);
    // شعب المرحلة المختارة وحدها، ومعها شعبة الطالب القائمة إن لم تعد موجودة
    final matchingSections = store.roomsInViewedYear.where((r) => isSameGrade(r.gradeLevel, grade)).toList();
    final sectionNames = <String>[
      for (final r in matchingSections)
        if (r.name.trim().isNotEmpty) r.name,
      if (sectionCtl.text.trim().isNotEmpty && !matchingSections.any((r) => r.name == sectionCtl.text)) sectionCtl.text,
    ];
    final idLen = nationalId.text.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmExit();
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(editing ? 'تعديل بيانات الطالب' : 'تسجيل طالب جديد'),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
      bottomNavigationBar: _actionBar(editing: editing, canSave: true),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          controller: scrollCtl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // ── ١. الأساسي: ما يُسأل عنه عند التسجيل وحده، بصفوف بعمودين ──────
            _section(Icons.badge_outlined, 'البيانات الأساسية', note: 'الحقول ذات * مطلوبة'),
            FieldLabel('اسم الطالب الرباعي', key: errors.key('name'), requiredField: true),
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (errors.clear('name')) setState(() {});
              },
              decoration: InputDecoration(hintText: 'مثال: محمد أحمد النجار', errorText: errors['name']),
            ),
            _gap,
            _pair(
              [
                FieldLabel('رقم الهوية', key: errors.key('nationalId'), requiredField: true),
                TextField(
                  controller: nationalId,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  style: const TextStyle(fontSize: 13, letterSpacing: 0.5),
                  decoration: InputDecoration(
                    hintText: '9 أرقام',
                    counterText: '',
                    errorText: errors['nationalId'] ?? idDuplicateError,
                    fillColor: idDuplicateError != null
                        ? const Color(0xFFFFF1F2)
                        : (idLen == 9 ? const Color(0xFFF0FDF4) : Colors.white),
                    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _counter(idLen, 9),
                  ),
                ),
              ],
              [
                FieldLabel('المرحلة', key: errors.key('grade'), requiredField: true),
                AppDropdown<String>(
                  value: grades.contains(grade) ? grade : null,
                  hint: grades.isEmpty ? 'لا مراحل معرّفة' : 'اختر المرحلة',
                  errorText: errors['grade'],
                  items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() {
                    grade = v ?? grade;
                    errors.clear('grade');
                    // شعبة المرحلة السابقة لا تبقى تحت مرحلة لا تملكها
                    final kept = store.roomsInViewedYear.any((r) => isSameGrade(r.gradeLevel, grade) && r.name == sectionCtl.text);
                    if (!kept) sectionCtl.text = '';
                  }),
                ),
              ],
            ),
            _gap,
            _pair(
              [
                const FieldLabel('الشعبة'),
                AppDropdown<String>(
                  value: sectionNames.contains(sectionCtl.text) ? sectionCtl.text : null,
                  // الكتابة اليدوية كانت تُنشئ شعباً لا وجود لها في المنشأة
                  hint: grade.trim().isEmpty
                      ? 'اختر المرحلة أولاً'
                      : (sectionNames.isEmpty ? 'لا شعب لهذه المرحلة' : 'اختر الشعبة'),
                  items: sectionNames
                      .map((n) => DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: sectionNames.isEmpty ? (_) {} : (v) => setState(() => sectionCtl.text = v ?? sectionCtl.text),
                ),
              ],
              [
                const FieldLabel('تاريخ التسجيل', requiredField: true),
                _selectField(
                  text: isoDate(enrollmentDate),
                  icon: Icons.calendar_today_outlined,
                  onTap: () => _pickDate(birth: false),
                ),
              ],
            ),
            _gap,
            FieldLabel('جوال وواتساب الطالب', key: errors.key('phone'), requiredField: true),
            _phoneRow(
              prefix: phonePrefix,
              controller: phoneCtl,
              target: studentLen,
              complete: studentComplete,
              error: errors['phone'] != null,
              onPrefix: (v) => setState(() {
                phonePrefix = v;
                phoneNumber = '';
                phoneCtl.clear();
                phoneDuplicateError = null;
              }),
              onNumber: _applyStudentPhone,
            ),
            if (phoneDuplicateError != null && errors['phone'] == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  phoneDuplicateError!,
                  style: TextStyle(color: AppColors.amber, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              )
            else
              _phoneHint(
                complete: studentComplete,
                error: errors['phone'],
                length: phoneNumber.length,
                target: studentLen,
                okText: 'رقم صالح: $fullStudentPhone',
              ),
            _gap,
            _pair(
              [
                const FieldLabel('من أين عرفتنا؟'),
                AppDropdown<String>(
                  value: referral.trim().isEmpty ? null : referral,
                  hint: 'اختر',
                  items: [
                    // قيمة قديمة خارج القائمة تبقى ظاهرة حتى لا تنقسم الإحصائيات بصمت
                    if (referral.trim().isNotEmpty && !referralSources.contains(referral))
                      DropdownMenuItem(
                        value: referral,
                        child: Text(referral, overflow: TextOverflow.ellipsis),
                      ),
                    for (final r in referralSources)
                      DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => referral = v ?? referral),
                ),
              ],
              [
                const FieldLabel('حالة الطالب'),
                AppDropdown<String>(
                  value: status,
                  items: [
                    // «بانتظار التأكيد» و«أنهى السنة» يضعهما النظام، فلا تُعرض إلا لمن هو فيها
                    for (final e in studentStatusLabels.entries)
                      if ((e.key != 'pending' && e.key != 'completed') || status == e.key)
                        DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => status = v ?? status),
                ),
              ],
            ),
            _gap,
            const FieldLabel('ملاحظات'),
            TextField(
              controller: notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'أي ملاحظة أو طلبات خاصة للملف...'),
            ),

            // ── ٤. الرسوم والخصم ─────────────────────────────────────────────
            if (widget.student == null) ...[
              const FormSection(icon: Icons.account_balance_wallet_outlined, title: 'نوع خطة الأقساط'),
              // ثلاثة خيارات في صفّ واحد: «خطة المرحلة» كاملةً، أو منها من شهر
              // التسجيل، أو خطة يكتبها المستخدم — بدل سؤالين متتاليين
              Row(
                children: [
                  Expanded(
                    child: _toggle(
                      'خطة المرحلة',
                      planSource == 'grade' && enrollmentMode == EnrollmentPlanMode.full,
                      AppColors.amber,
                      () {
                        _setPlanSource('grade');
                        setState(() => enrollmentMode = EnrollmentPlanMode.full);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _toggle(
                      'من شهر التسجيل',
                      planSource == 'grade' && enrollmentMode == EnrollmentPlanMode.fromEnrollment,
                      AppColors.amber,
                      () {
                        _setPlanSource('grade');
                        setState(() => enrollmentMode = EnrollmentPlanMode.fromEnrollment);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _toggle(
                      'خطة مخصصة',
                      planSource == 'custom',
                      AppColors.amber,
                      () => _setPlanSource('custom'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (planSource == 'custom') ...[
                Text(
                  errors['customPlan'] ?? 'لكل قسط اسمه ومبلغه وموعده — أضف أو احذف كما يلزم.',
                  style: TextStyle(
                    color: errors['customPlan'] != null ? AppColors.danger : AppColors.muted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                _gap,
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(Corner.box),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'أقساط الطالب المخصصة',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                          ),
                          const Spacer(),
                          const Text(
                            'لكل قسط اسمه ومبلغه وموعده',
                            style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CustomPlanRowsEditor(
                        rows: customRows,
                        fallbackDue: isoDate(enrollmentDate),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ] else
                const SizedBox(height: 8),
              if (planSource == 'grade') ...[
                Text(
                  enrollmentMode == EnrollmentPlanMode.fromEnrollment
                      ? 'لن تُحتسب أقساط الأشهر السابقة لشهر التسجيل (${isoDate(enrollmentDate).substring(0, 7)}).'
                      : 'كل أقساط الخطة بتواريخها كما هي معرّفة للمرحلة.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
                ),
              ],
              _gap,
            ],
            ..._discountSection(context),
            if (widget.student == null) ...[
              _gap,
              _planPreviewSection(context),
            ],

            // ── ٥. بيانات إضافية (اختيارية) ──────────────────────────────────
            _extraHeader(),
            if (extra) ..._extraFields(),
          ],
        ),
      ),
    ),
    );
  }

  /// خصم على الأقساط — المقابل لقسم الخصم في StudentForm.tsx.
  ///
  /// للطالب القائم: القسم معطّل (يُعدَّل من ملفه). عند التسجيل: نسبة أو مبلغ مقطوع فقط.
  List<Widget> _discountSection(BuildContext context) {
    final store = StoreScope.of(context);
    final canDiscount = store.can('finance.discount');
    final editing = widget.student != null;
    final gradeFee = _gradeFeeOf(context);
    final rules = store.discountRules;
    final gpaValue = double.tryParse(gpa.text.trim()) ?? 0;
    final suggestExcellence =
        !editing && canDiscount && rules.autoSuggestExcellence && !hasDiscount && gpaValue >= rules.excellenceMinGpa;

    return [
      _section(
        Icons.sell_outlined,
        'الرسوم والخصم',
        note: gradeFee > 0 ? 'رسم المرحلة: ${money(gradeFee)}' : 'لا رسم محدد لهذه المرحلة',
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              'خصم على الأقساط',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.heading),
            ),
          ),
          Switch.adaptive(
            value: hasDiscount && (editing || canDiscount),
            activeThumbColor: AppColors.amber,
            onChanged: editing || !canDiscount
                ? null
                : (v) => setState(() => hasDiscount = v),
          ),
        ],
      ),
      if (editing)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '— لتعديل الخصم استخدم «خصم للطالب» من ملفه',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
        )
      else if (!canDiscount)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '— لا تملك صلاحية الخصم: سجّل الطالب ثم اطلب الخصم من ملفه',
            style: TextStyle(fontSize: 11.5, color: AppColors.amber, fontWeight: FontWeight.w600),
          ),
        ),
      if (suggestExcellence)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: GhostButton(
            label: 'اقتراح خصم التفوق (${trimNum(rules.excellenceDiscountRate)}%)',
            icon: Icons.auto_awesome_outlined,
            onPressed: () => setState(() {
              hasDiscount = true;
              discountType = 'percentage';
              discountRate.text = trimNum(rules.excellenceDiscountRate);
              discountReason.text = 'خصم تفوق دراسي';
            }),
          ),
        ),
      if (hasDiscount && !editing && canDiscount) ...[
        _gap,
        const FieldLabel('نوع الخصم'),
        Row(
          children: [
            Expanded(
              child: _toggle('نسبة مئوية (%)', discountType == 'percentage', AppColors.amber,
                  () => setState(() => discountType = 'percentage')),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toggle('مبلغ مقطوع (شيكل)', discountType == 'fixed', AppColors.amber,
                  () => setState(() => discountType = 'fixed')),
            ),
          ],
        ),
        _gap,
        if (discountType == 'percentage') ...[
          const FieldLabel('نسبة الخصم (%)'),
          TextField(
            key: const Key('discountRate'),
            controller: discountRate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '10'),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final preset in ['10', '15', '20', '25', '50'])
                ActionChip(
                  label: Text('$preset%', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  onPressed: () => setState(() => discountRate.text = preset),
                ),
            ],
          ),
        ] else ...[
          FieldLabel('مبلغ الخصم ($currency)'),
          TextField(
            controller: discountFixed,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: 'monospace'),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '20'),
          ),
          const SizedBox(height: 4),
          const Text(
            'يُخصم هذا المبلغ من كل قسط بنفس القيمة (مثال: 20 ← كل قسط ينقص 20 شيكل)',
            style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.35),
          ),
        ],
        _gap,
        const FieldLabel('سبب الخصم'),
        TextField(
          controller: discountReason,
          decoration: const InputDecoration(hintText: 'تفوق دراسي، إخوة، منحة...'),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final reason in ['تفوق دراسي', 'إخوة', 'أبناء كادر', 'شؤون اجتماعية', 'منحة', 'إعفاء استثنائي'])
              ActionChip(
                label: Text(reason, style: const TextStyle(fontSize: 11)),
                onPressed: () => setState(() => discountReason.text = reason),
              ),
          ],
        ),
      ],
    ];
  }

  /// معاينة أقساط التسجيل قبل الحفظ — SF-05 / `planPreview` في الويب.
  Widget _planPreviewSection(BuildContext context) {
    final store = StoreScope.of(context);
    final preview = _planPreview(context);
    final gradeItems = store.planItemsOf(store.feeFor(grade));

    if (planSource == 'grade' && grade.trim().isEmpty) {
      return const Text(
        'اختر المرحلة لعرض أقساطها',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted),
      );
    }
    if (planSource == 'grade' && gradeItems.isEmpty && preview.isEmpty) {
      return const Text(
        'لا أقساط لهذه المرحلة بعد — عرّفها من الإعدادات ← المراحل والرسوم',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
      );
    }
    if (planSource == 'custom' && preview.isEmpty) {
      return const Text(
        'أضف أقساطاً أعلاه لمعاينتها قبل الحفظ',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
      );
    }
    if (planSource == 'grade' && gradeItems.isNotEmpty && preview.isEmpty) {
      return const Text(
        'لا أقساط تُحتسب بوضع التسجيل الحالي — جرّب «الخطة كاملة» أو غيّر تاريخ التسجيل',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
      );
    }
    if (preview.isEmpty) return const SizedBox.shrink();

    final discountSum = preview.fold<double>(0, (sum, row) {
      final orig = row.originalAmount;
      if (orig == null || !(orig > row.amount)) return sum;
      return sum + (orig - row.amount);
    });
    final total = planTotal([
      for (final r in preview) PlanItem(id: r.id, title: r.title, amount: r.amount, dueDate: r.dueDate),
    ]);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(Corner.box)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    planSource == 'custom'
                        ? (hasDiscount ? 'بعد الخصم (${preview.length})' : 'أقساط مخصصة (${preview.length})')
                        : 'أقساط المرحلة (${preview.length})',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.heading),
                  ),
                ),
                if (discountSum > 0.004) ...[
                  Text(
                    'خصم ${money(discountSum)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: AppColors.amber),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  'المطلوب ${money(total)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, fontFamily: 'monospace', color: AppColors.heading),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: preview.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (_, i) {
                final row = preview[i];
                final orig = row.originalAmount;
                final struck = orig != null && orig != row.amount;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (struck) ...[
                        Text(
                          money(orig),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppColors.muted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        money(row.amount),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 88,
                        child: Text(
                          row.dueDate,
                          textAlign: TextAlign.left,
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _extraFields() {
    return [
      _pair(
        [
          const FieldLabel('كلمة مرور الطالب'),
          TextField(
            controller: portalCode,
            keyboardType: TextInputType.number,
            maxLength: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: '6 أرقام',
              counterText: '',
              suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              suffixIcon: IconButton(
                tooltip: 'توليد رمز جديد',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.autorenew, size: 18, color: AppColors.amber),
                onPressed: () => setState(
                  () => portalCode.text = AppStore.instance.newDistinctPortalCode(parentPortalCode.text),
                ),
              ),
            ),
          ),
        ],
        [
          const FieldLabel('كلمة مرور ولي الأمر'),
          TextField(
            controller: parentPortalCode,
            keyboardType: TextInputType.number,
            maxLength: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            onChanged: (_) {
              _parentCodeTouched = true;
              setState(() {
                errors.clear('parentCode');
                final parent = parentPortalCode.text.trim();
                final student = portalCode.text.trim();
                errors.check(
                  'parentCode',
                  parent.isNotEmpty && parent == student,
                  'لا تطابق كلمة مرور الطالب',
                );
              });
            },
            decoration: InputDecoration(
              hintText: '6 أرقام',
              counterText: '',
              errorText: errors['parentCode'],
              suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              suffixIcon: IconButton(
                tooltip: 'توليد كلمة جديدة',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.autorenew, size: 18, color: AppColors.amber),
                onPressed: () => setState(() {
                  errors.clear('parentCode');
                  parentPortalCode.text = AppStore.instance.newDistinctPortalCode(portalCode.text);
                }),
              ),
            ),
          ),
        ],
      ),
      _gap,
      _pair(
        [
          const FieldLabel('اسم ولي الأمر'),
          TextField(controller: parentName, decoration: const InputDecoration(hintText: 'الاسم الثلاثي')),
        ],
        [
          const FieldLabel('صلة القرابة'),
          AppDropdown<String>(
            value: guardianRelations.contains(relation) ? relation : null,
            hint: 'اختر',
            items: guardianRelations
                .map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => relation = v ?? relation),
          ),
        ],
      ),
      _gap,
      // رقم هوية وليّ الأمر: يدخل به البوابة فيرى أبناءه كلهم. كلمة المرور
      // تُولَّد لكل طالب على حدة، فبدون هذا الرقم لا يصل الأب إلا لأحدهم.
      const FieldLabel('رقم هوية ولي الأمر'),
      TextField(
        controller: parentNationalId,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(hintText: 'يربط إخوة الطالب في بوابة واحدة'),
        onChanged: (_) => _findSibling(),
      ),
      if (sibling != null) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.successSoft,
            borderRadius: BorderRadius.circular(Corner.box),
            border: Border.all(color: AppColors.successBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.family_restroom, size: 15, color: AppColors.success),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'أخوه ${sibling!.name} — وحّدنا كلمة ولي الأمر',
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
      _gap,
      FieldLabel('جوال ولي الأمر', key: errors.key('parentPhone')),
      _phoneRow(
        prefix: parentPhonePrefix,
        controller: parentPhoneCtl,
        target: phoneTargetLength(parentPhonePrefix),
        complete: isPhoneComplete(parentPhoneNumber, parentPhonePrefix),
        error: errors['parentPhone'] != null,
        onPrefix: (v) => setState(() {
          parentPhonePrefix = v;
          parentPhoneNumber = '';
          parentPhoneCtl.clear();
        }),
        onNumber: _applyParentPhone,
      ),
      _phoneHint(
        complete: isPhoneComplete(parentPhoneNumber, parentPhonePrefix) && parentPhoneNumber.isNotEmpty,
        error: errors['parentPhone'],
        length: parentPhoneNumber.length,
        target: phoneTargetLength(parentPhonePrefix),
        okText: 'رقم صالح: ${combinePhoneAndPrefix(parentPhoneNumber, parentPhonePrefix)}',
      ),
      _gap,
      const FieldLabel('الحي الأساسي'),
      _selectField(
        text: neighborhood.isEmpty ? 'اختر الحي أو ابحث عنه...' : neighborhood,
        placeholder: neighborhood.isEmpty,
        icon: Icons.search,
        onTap: _pickNeighborhood,
      ),
      if (neighborhood == 'أخرى') ...[
        const SizedBox(height: 8),
        TextField(controller: customNeighborhood, decoration: const InputDecoration(hintText: 'اكتب اسم الحي...')),
      ],
      _gap,
      const FieldLabel('العنوان المفصل'),
      TextField(
        controller: detailedAddress,
        decoration: const InputDecoration(hintText: 'الشارع وأقرب معلم — مثال: بجوار مسجد الهدى'),
      ),
      _gap,
      _pair(
        [
          const FieldLabel('تاريخ الميلاد'),
          _selectField(
            text: birthDate == null ? 'اختر التاريخ' : isoDate(birthDate!),
            placeholder: birthDate == null,
            icon: Icons.calendar_today_outlined,
            onTap: () => _pickDate(birth: true),
          ),
        ],
        [
          const FieldLabel('الجنس'),
          Row(
            children: [
              Expanded(child: _toggle('ذكر', gender == 'ذكر', AppColors.amber, () => setState(() => gender = 'ذكر'))),
              const SizedBox(width: 6),
              Expanded(child: _toggle('أنثى', gender == 'أنثى', AppColors.navy, () => setState(() => gender = 'أنثى'))),
            ],
          ),
        ],
      ),
      _gap,
      _pair(
        [
          const FieldLabel('مكان الولادة'),
          TextField(controller: birthPlace, decoration: const InputDecoration(hintText: 'غزة')),
        ],
        [
          const FieldLabel('الجنسية'),
          TextField(controller: nationality, decoration: const InputDecoration(hintText: 'فلسطينية')),
        ],
      ),
      _gap,
      _pair(
        [
          const FieldLabel('المدرسة السابقة'),
          TextField(controller: previousSchool, decoration: const InputDecoration(hintText: 'اسم المدرسة')),
        ],
        [
          const FieldLabel('المعدل'),
          TextField(controller: gpa, decoration: const InputDecoration(hintText: '92.5%')),
        ],
        startFlex: 3,
        endFlex: 2,
      ),
      _gap,
      _pair(
        [
          const FieldLabel('طبيعة السكن'),
          AppDropdown<String>(
            value: housingTypes.contains(housing) ? housing : null,
            hint: 'اختر',
            items: housingTypes.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => housing = v ?? housing),
          ),
        ],
        [
          const FieldLabel('البلدة الأصلية'),
          TextField(controller: originalArea, decoration: const InputDecoration(hintText: 'يافا، حمامة...')),
        ],
      ),
      _gap,
      const FieldLabel('الحالة الصحية'),
      Row(
        children: [
          Expanded(
            child: _toggle('سليم', health == 'سليم', AppColors.success, () => setState(() {
                  health = 'سليم';
                  medicalCondition.clear();
                })),
          ),
          const SizedBox(width: 6),
          Expanded(child: _toggle('يعاني من مرض', health == 'مريض', AppColors.danger, () => setState(() => health = 'مريض'))),
        ],
      ),
      if (health == 'مريض') ...[
        const SizedBox(height: 8),
        TextField(
          controller: medicalCondition,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'نوع المرض أو الأدوية التي يحتاجها الطالب...'),
        ),
      ],
      _gap,
      _pair(
        [
          const FieldLabel('مهنة ولي الأمر'),
          TextField(controller: parentJob, decoration: const InputDecoration(hintText: 'معلم، تاجر...')),
        ],
        [
          const FieldLabel('البريد الإلكتروني'),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'name@mail.com'),
          ),
        ],
      ),
      _gap,
      const FieldLabel('جوال بديل لولي الأمر'),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: AppDropdown<String>(
                value: secondaryPrefix,
                items: phonePrefixes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => secondaryPrefix = v ?? secondaryPrefix),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: parentSecondaryNumber,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 13.5, letterSpacing: 0.8),
                decoration: const InputDecoration(hintText: 'رقم إضافي'),
              ),
            ),
          ],
        ),
      ),
      // المرفقات ميزة تُفعَّل من إعدادات المطور: صور ثقيلة لا تُخزَّن لكل منشأة
      if (StoreScope.of(context).features.enableStudentAttachments) ...[
        _gap,
        const FieldLabel('المرفقات والوثائق'),
        Row(
          children: [
            Expanded(
              child: _attachBox('صورة هوية الطالب', studentIdPhoto, () => _pickAttachment((v) => studentIdPhoto = v),
                  () => setState(() => studentIdPhoto = '')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _attachBox('شهادة الميلاد', birthCertificate, () => _pickAttachment((v) => birthCertificate = v),
                  () => setState(() => birthCertificate = '')),
            ),
          ],
        ),
      ],
      _gap,
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('التقييم المبدئي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
                const Text('مستوى الطالب في مقابلة التسجيل', style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
              ],
            ),
          ),
          for (var star = 1; star <= 5; star++)
            InkWell(
              onTap: () => setState(() => initialRating = initialRating == star ? 0 : star),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  initialRating >= star ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: initialRating >= star ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                  size: 26,
                ),
              ),
            ),
        ],
      ),
      _gap,
      InkWell(
        onTap: () => setState(() => guardianDeclaration = !guardianDeclaration),
        child: Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.amberSoft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(guardianDeclaration ? Icons.check_box : Icons.check_box_outline_blank, color: AppColors.amber, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'أقرّ ولي الأمر بصحة البيانات وبالموافقة على لوائح المدرسة ونظام الدفع.',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _section(IconData icon, String title, {String? note}) => FormSection(icon: icon, title: title, note: note);

  double get _discountRateValue => double.tryParse(discountRate.text.trim()) ?? 0;

  /// مراحل القائمة — `gradeOptions` في StudentForm.tsx: مراحل المنشأة التي
  /// أضافتها. مرحلة طالب قائم لم تعد في القائمة تبقى ظاهرة حتى لا تتبدل بصمت
  /// عند فتح التعديل.
  List<String> _gradeOptions(AppStore store) {
    final current = widget.student?.gradeLevel.trim() ?? '';
    final own = store.gradeOptions;
    return current.isNotEmpty && !own.contains(current) ? [current, ...own] : own;
  }

  /// رسم المرحلة المختارة — أساس الخصم كما في `currentGradeFee`.
  double _gradeFeeOf(BuildContext context) {
    final store = StoreScope.of(context);
    return store.feeFor(grade)?.monthlyFee ?? 0;
  }

  /// خصم خطة الأقساط عند التسجيل — مطابق لما يمرّره `StudentForm` إلى `buildStudentPlan`.
  PlanDiscount? _planDiscountOf(double gradeFee) {
    if (!hasDiscount) return null;
    final reason = discountReason.text.trim();
    switch (discountType) {
      case 'percentage':
        final rate = _discountRateValue;
        return rate > 0 ? PlanDiscount.percent(rate, reason: reason) : null;
      case 'fixed':
        final fixed = double.tryParse(discountFixed.text.trim()) ?? 0;
        return fixed > 0 ? PlanDiscount.fixed(fixed, reason: reason) : null;
      default:
        return null;
    }
  }

  Widget _extraHeader() {
    // الهوامش خارج منطقة اللمس: أثر الضغط يغطي سطر العنوان وحده، لا الفراغ
    // فوقه وتحته، وبرمادي خافت جداً بلا تموّج
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => extra = !extra),
            highlightColor: AppColors.bg,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.post_add_outlined, size: 18, color: AppColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('بيانات إضافية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.heading)),
                        const Text('كلمات المرور وولي الأمر والسكن والمرفقات', style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  Text(extra ? 'إخفاء' : 'عرض', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 12)),
                  Icon(extra ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.amber, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(height: 1, color: AppColors.line),
        ],
      ),
    );
  }

  Widget _pair(List<Widget> start, List<Widget> end, {int startFlex = 1, int endFlex = 1}) =>
      FieldPair(start: start, end: end, startFlex: startFlex, endFlex: endFlex);

  Widget _selectField({required String text, required IconData icon, required VoidCallback onTap, bool placeholder = false}) =>
      SelectField(text: text, icon: icon, onTap: onTap, placeholder: placeholder);

  /// عدّاد الأرقام داخل طرف الحقل بدل سطر مستقل تحته.
  Widget _counter(int length, int target) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Text(
        '$length/$target',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: length == target ? AppColors.success : AppColors.faint,
        ),
      ),
    );
  }

  Widget _message(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _actionBar({required bool editing, required bool canSave}) => FormActionBar(
        label: editing ? 'حفظ التعديل' : 'تسجيل الطالب',
        onSave: canSave ? _save : null,
        onCancel: () async {
          final leave = await _confirmExit();
          if (leave && mounted) Navigator.pop(context);
        },
      );

  Widget _toggle(String label, bool on, Color color, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: on ? color : Colors.white,
          border: Border.all(color: on ? color : AppColors.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(color: on ? Colors.white : AppColors.muted, fontWeight: FontWeight.w800, fontSize: 11.5),
          ),
        ),
      ),
    );
  }

  /// رقم الجوال يُقرأ من اليسار: المقدمة أولاً ثم بقية الرقم — مطابق لـ
  /// `dir="ltr"` في StudentForm.tsx. في صفّ عربي كانت المقدمة تقع يميناً بعد الرقم.
  Widget _phoneRow({
    required String prefix,
    required TextEditingController controller,
    required int target,
    required bool complete,
    required bool error,
    required ValueChanged<String> onPrefix,
    required ValueChanged<String> onNumber,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: AppDropdown<String>(
              value: prefix,
              items: phonePrefixes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => onPrefix(v ?? prefix),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: target,
              onChanged: onNumber,
              style: const TextStyle(fontSize: 13.5, letterSpacing: 0.8),
              decoration: InputDecoration(
                hintText: '$target أرقام',
                counterText: '',
                fillColor: error ? const Color(0xFFFFF1F2) : (complete ? const Color(0xFFF0FDF4) : Colors.white),
                suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: _counter(controller.text.length, target),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// سطر الحالة تحت الجوال يظهر فقط حين يقول شيئاً: خطأ، أو رقم ناقص، أو رقم صالح.
  Widget _phoneHint({required bool complete, required String? error, required int length, required int target, required String okText}) {
    if (error != null) return _message(error, AppColors.danger);
    if (length > 0 && !complete) return _message('يجب إدخال $target أرقام بعد المقدمة', const Color(0xFFB45309));
    if (complete) return _message(okText, const Color(0xFF166534));
    return const SizedBox.shrink();
  }

  /// مرفق مربّع: لمسة للاختيار، ثم معاينة بزر حذف فوقها.
  Widget _attachBox(String title, String data, VoidCallback pick, VoidCallback clear) {
    final bytes = data.isEmpty ? null : _bytesOf(data);
    return InkWell(
      onTap: data.isEmpty ? pick : null,
      child: Container(
        height: 96,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.box),
          color: AppColors.bg,
          border: Border.all(color: data.isEmpty ? AppColors.line : AppColors.amberBorder),
        ),
        child: data.isEmpty
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, color: AppColors.amber, size: 24),
                  const SizedBox(height: 5),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(bytes, fit: BoxFit.cover)
                  else
                    const Center(child: Icon(Icons.insert_drive_file_outlined, color: AppColors.muted)),
                  PositionedDirectional(
                    bottom: 0,
                    start: 0,
                    end: 0,
                    child: Container(
                      color: const Color(0x99000000),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: InkWell(
                      onTap: clear,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        color: const Color(0x99000000),
                        child: const Icon(Icons.close, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Uint8List? _bytesOf(String dataUrl) {
    final i = dataUrl.indexOf('base64,');
    if (i < 0) return null;
    try {
      return base64Decode(dataUrl.substring(i + 7));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickNeighborhood() async {
    final search = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final q = search.text.trim();
            final list = neighborhoods.where((n) => q.isEmpty || n.contains(q)).toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
              child: SizedBox(
                height: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الحي الأساسي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(controller: search, onChanged: (_) => setSt(() {}), decoration: const InputDecoration(hintText: 'اكتب للبحث السريع في الأحياء...')),
                    const SizedBox(height: 8),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('لم يتم العثور على الحي', style: TextStyle(color: AppColors.muted)))
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) {
                                final n = list[i];
                                final on = neighborhood == n;
                                return ListTile(
                                  dense: true,
                                  title: Text(n, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
                                  trailing: on ? Icon(Icons.check, color: AppColors.amber, size: 16) : null,
                                  tileColor: on ? AppColors.amberSoft : null,
                                  onTap: () {
                                    setState(() => neighborhood = n);
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    search.dispose();
  }
}
