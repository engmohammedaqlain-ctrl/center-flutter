import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/phone.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

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
  late final parentName = TextEditingController(text: widget.student?.parentName ?? '');
  late final notes = TextEditingController(text: widget.student?.notes ?? '');
  late final detailedAddress = TextEditingController(text: widget.student?.detailedAddress ?? '');
  late final customGrade = TextEditingController();
  late final customNeighborhood = TextEditingController();
  late final birthPlace = TextEditingController(text: widget.student?.birthPlace.isNotEmpty == true ? widget.student!.birthPlace : 'غزة');
  late final nationality = TextEditingController(text: widget.student?.nationality.isNotEmpty == true ? widget.student!.nationality : 'فلسطينية');
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
  String parentIdPhoto = '';
  String birthCertificate = '';
  bool attachmentsLoaded = false;

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    final inList = s != null && gradeLevels.contains(s.gradeLevel);
    grade = inList ? s.gradeLevel : (s == null ? 'عاشر' : 'أخرى (إدخال يدوي)');
    if (s != null && !inList && s.gradeLevel.isNotEmpty) customGrade.text = s.gradeLevel;

    relation = s?.relation ?? 'أب';
    neighborhood = (s?.neighborhood ?? '').isNotEmpty && neighborhoods.contains(s!.neighborhood) ? s.neighborhood : ((s?.neighborhood ?? '').isNotEmpty ? 'أخرى' : '');
    if (neighborhood == 'أخرى' && s != null) customNeighborhood.text = s.neighborhood;
    gender = s?.gender ?? 'ذكر';
    referral = (s?.referralSource ?? '').isNotEmpty ? s!.referralSource : referralSources.first;
    housing = (s?.housingStatus ?? '').isNotEmpty ? s!.housingStatus : 'ملك';
    health = s?.healthStatus ?? 'سليم';
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
  }

  Future<void> _loadAttachments() async {
    final s = widget.student;
    if (s == null) {
      setState(() => attachmentsLoaded = true);
      return;
    }
    final att = StoreScope.of(context).attachmentsOf(s.id);
    if (!mounted) return;
    setState(() {
      studentIdPhoto = att?.studentIdPhoto ?? '';
      parentIdPhoto = att?.parentIdPhoto ?? '';
      birthCertificate = att?.birthCertificate ?? '';
      attachmentsLoaded = true;
    });
  }

  @override
  void dispose() {
    name.dispose();
    nationalId.dispose();
    portalCode.dispose();
    parentName.dispose();
    notes.dispose();
    detailedAddress.dispose();
    customGrade.dispose();
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
    super.dispose();
  }

  void _onNationalIdChanged() {
    final clean = digitsOnly(nationalId.text).substring(0, digitsOnly(nationalId.text).length.clamp(0, 9));
    if (nationalId.text != clean) {
      nationalId.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    if (clean.length == 9) {
      final dup = StoreScope.of(context).findByNationalId(clean, exclude: widget.student?.id);
      setState(() {
        idDuplicateError = dup == null ? null : 'رقم الهوية ($clean) مسجل مسبقاً للطالب "${dup.fullName}" ولا يمكن تكراره.';
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
    });
  }

  void _checkPhoneDup() {
    if (!isPhoneComplete(phoneNumber, phonePrefix)) {
      phoneDuplicateError = null;
      return;
    }
    final full = combinePhoneAndPrefix(phoneNumber, phonePrefix);
    final dup = StoreScope.of(context).findByPhone(full, exclude: widget.student?.id);
    phoneDuplicateError = dup == null ? null : 'رقم الجوال ($full) مسجل مسبقاً للطالب: ${dup.fullName}';
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
        if (mounted) showAppSnack(context, 'حجم الملف كبير جداً، يرجى اختيار ملف بحجم أقل من 5 ميجابايت', error: true);
        return;
      }
      final mime = file.mimeType ?? 'image/jpeg';
      setState(() => setVal('data:$mime;base64,${base64Encode(bytes)}'));
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر اختيار الملف', error: true);
    }
  }

  void _save() {
    final store = StoreScope.of(context);
    final trimmedFullName = name.text.trim();
    if (trimmedFullName.isEmpty) {
      showAppSnack(context, 'يرجى إدخال اسم الطالب الرباعي', error: true);
      return;
    }
    final cleanNatId = digitsOnly(nationalId.text);
    if (cleanNatId.isEmpty) {
      showAppSnack(context, 'يرجى إدخال رقم هوية الطالب (9 أرقام)', error: true);
      return;
    }
    if (!isValidNationalId(cleanNatId)) {
      showAppSnack(context, 'رقم الهوية غير صالح! يجب أن يتكون من 9 أرقام (المُدخل حالياً: ${cleanNatId.length} أرقام).', error: true);
      return;
    }
    if (idDuplicateError != null) {
      showAppSnack(context, idDuplicateError!, error: true);
      return;
    }
    if (phoneNumber.trim().isEmpty) {
      showAppSnack(context, 'يرجى إدخال رقم واتساب وجوال الطالب', error: true);
      return;
    }
    if (!isPhoneComplete(phoneNumber, phonePrefix)) {
      showAppSnack(
        context,
        'رقم جوال الطالب غير مكتمل! يجب إدخال ${phoneTargetLength(phonePrefix)} أرقام بعد المقدمة ($phonePrefix) - المُدخل حالياً: ${phoneNumber.trim().length} أرقام.',
        error: true,
      );
      return;
    }
    if (phoneDuplicateError != null) {
      showAppSnack(context, phoneDuplicateError!, error: true);
      return;
    }
    if (parentPhoneNumber.trim().isNotEmpty && !isPhoneComplete(parentPhoneNumber, parentPhonePrefix)) {
      showAppSnack(
        context,
        'رقم جوال ولي الأمر غير مكتمل! يجب إدخال ${phoneTargetLength(parentPhonePrefix)} أرقام بعد المقدمة ($parentPhonePrefix).',
        error: true,
      );
      return;
    }

    final parts = trimmedFullName.split(RegExp(r'\s+'));
    final firstName = parts.isEmpty ? '' : parts.first;
    final lastName = parts.length <= 1 ? firstName : parts.skip(1).join(' ');
    final selectedNeighborhood = neighborhood == 'أخرى' && customNeighborhood.text.trim().isNotEmpty
        ? customNeighborhood.text.trim()
        : neighborhood;
    final finalGrade = grade == 'أخرى (إدخال يدوي)' && customGrade.text.trim().isNotEmpty ? customGrade.text.trim() : grade;
    final existing = widget.student;
    final id = existing?.id ?? store.newId();

    try {
      store.upsertStudent(
        Student(
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
          neighborhood: selectedNeighborhood,
          relation: relation,
          gender: gender,
          notes: notes.text.trim(),
          balance: existing?.balance ?? 0,
          enrolledAt: enrollmentDate,
          detailedAddress: detailedAddress.text.trim(),
          referralSource: referral,
          schoolName: previousSchool.text.trim().isNotEmpty ? previousSchool.text.trim() : (existing?.schoolName ?? ''),
          status: existing?.status ?? 'active',
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
          academicDiscountApplied: existing?.academicDiscountApplied ?? false,
          academicDiscountRate: existing?.academicDiscountRate ?? 0,
          hasException: existing?.hasException ?? false,
          exceptionReason: existing?.exceptionReason ?? '',
          customMonthlyFee: existing?.customMonthlyFee,
        ),
        isNew: existing == null,
        attachments: attachmentsLoaded
            ? StudentAttachments(
                id: id,
                studentIdPhoto: studentIdPhoto,
                parentIdPhoto: parentIdPhoto,
                birthCertificate: birthCertificate,
              )
            : null,
      );
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final editing = widget.student != null;
    final studentLen = phoneTargetLength(phonePrefix);
    final parentLen = phoneTargetLength(parentPhonePrefix);
    final studentComplete = isPhoneComplete(phoneNumber, phonePrefix);
    final parentComplete = isPhoneComplete(parentPhoneNumber, parentPhonePrefix);
    final fullStudentPhone = combinePhoneAndPrefix(phoneNumber, phonePrefix);
    final matchingSections = store.rooms.where((r) => r.gradeLevel.trim().isEmpty || r.gradeLevel.trim() == (grade == 'أخرى (إدخال يدوي)' ? customGrade.text.trim() : grade).trim()).toList();
    final canSave = idDuplicateError == null && phoneDuplicateError == null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(editing ? 'تعديل بيانات الطالب' : 'تسجيل طالب جديد'),
        backgroundColor: AppColors.amberSoft,
        foregroundColor: AppColors.heading,
        titleTextStyle: const TextStyle(color: AppColors.heading, fontWeight: FontWeight.w800, fontSize: 14),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: AppColors.amber),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('البيانات الأساسية للطالب والتواصل', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading))),
                    Text('الحقول ذات علامة * مطلوبة', style: TextStyle(color: AppColors.muted, fontSize: 10)),
                  ],
                ),
                const Divider(height: 18),
                const FieldLabel('الاسم الرباعي للطالب', requiredField: true),
                TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: محمد أحمد النجار')),
                const SizedBox(height: 10),
                const FieldLabel('رقم هوية الطالب', requiredField: true),
                TextField(
                  controller: nationalId,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  decoration: InputDecoration(
                    hintText: '9 أرقام',
                    counterText: '${nationalId.text.length} / 9',
                    filled: true,
                    fillColor: idDuplicateError != null
                        ? const Color(0xFFFFF1F2)
                        : (nationalId.text.length == 9 ? const Color(0xFFF0FDF4) : null),
                  ),
                ),
                if (idDuplicateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(idDuplicateError!, style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 10),
                // رمز دخول الطالب إلى بوابته
                const FieldLabel('رمز الدخول للبوابة'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: portalCode,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: const InputDecoration(hintText: 'رمز من 6 أرقام', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GhostButton(
                      label: 'توليد',
                      icon: Icons.autorenew,
                      onPressed: () => setState(() {
                        portalCode.text = AppStore.instance.newPortalCode();
                      }),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'رمز الدخول الخاص بالطالب لبوابته.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5),
                  ),
                ),
                const SizedBox(height: 10),
                const FieldLabel('آخر صف دراسي / المرحلة', requiredField: true),
                AppDropdown<String>(
                  value: grade,
                  items: gradeLevels.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setState(() => grade = v ?? grade),
                ),
                if (grade == 'أخرى (إدخال يدوي)') ...[
                  const SizedBox(height: 8),
                  TextField(controller: customGrade, decoration: const InputDecoration(hintText: 'اكتب اسم الصف الدراسي يدوياً...')),
                ],
                const SizedBox(height: 10),
                const FieldLabel('الشعبة الدراسية'),
                TextField(
                  controller: sectionCtl,
                  decoration: InputDecoration(
                    hintText: matchingSections.isEmpty ? 'مثال: شعبة 1، أو أ' : 'مثال: ${matchingSections.first.name}',
                  ),
                ),
                if (matchingSections.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in matchingSections)
                          InkWell(
                            onTap: () => setState(() => sectionCtl.text = r.name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: sectionCtl.text == r.name ? AppColors.amberSoft : Colors.white,
                                border: Border.all(color: sectionCtl.text == r.name ? AppColors.amber : AppColors.line),
                              ),
                              child: Text(r.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                const FieldLabel('رقم واتساب وجوال الطالب (بالمقدمة)', requiredField: true),
                _phoneRow(
                  prefix: phonePrefix,
                  controller: phoneCtl,
                  target: studentLen,
                  complete: studentComplete,
                  error: phoneDuplicateError != null,
                  onPrefix: (v) => setState(() {
                    phonePrefix = v;
                    phoneNumber = '';
                    phoneCtl.clear();
                    phoneDuplicateError = null;
                  }),
                  onNumber: _applyStudentPhone,
                ),
                _phoneHint(
                  complete: studentComplete,
                  error: phoneDuplicateError,
                  length: phoneNumber.length,
                  target: studentLen,
                  okText: 'رقم جوال صالح ($fullStudentPhone)',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('اسم ولي الأمر'),
                TextField(controller: parentName, decoration: const InputDecoration(hintText: 'مثال: محمد علي النجار')),
                const SizedBox(height: 10),
                const FieldLabel('صلة القرابة'),
                AppDropdown<String>(
                  value: relation,
                  items: guardianRelations.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setState(() => relation = v ?? relation),
                ),
                const SizedBox(height: 10),
                const FieldLabel('رقم جوال / واتساب ولي الأمر (بالمقدمة)'),
                _phoneRow(
                  prefix: parentPhonePrefix,
                  controller: parentPhoneCtl,
                  target: parentLen,
                  complete: parentComplete,
                  error: false,
                  onPrefix: (v) => setState(() {
                    parentPhonePrefix = v;
                    parentPhoneNumber = '';
                    parentPhoneCtl.clear();
                  }),
                  onNumber: _applyParentPhone,
                ),
                _phoneHint(
                  complete: parentComplete && parentPhoneNumber.isNotEmpty,
                  error: null,
                  length: parentPhoneNumber.length,
                  target: parentLen,
                  okText: 'رقم ولي أمر مكتمل (${combinePhoneAndPrefix(parentPhoneNumber, parentPhonePrefix)})',
                ),
                const SizedBox(height: 10),
                const FieldLabel('الحي الأساسي (ابحث أو اختر)'),
                InkWell(
                  onTap: () => _pickNeighborhood(),
                  child: InputDecorator(
                    decoration: const InputDecoration(),
                    child: Text(
                      neighborhood.isEmpty ? 'اختر الحي أو ابحث عنه...' : neighborhood,
                      style: TextStyle(color: neighborhood.isEmpty ? AppColors.muted : AppColors.heading, fontSize: 13),
                    ),
                  ),
                ),
                if (neighborhood == 'أخرى') ...[
                  const SizedBox(height: 8),
                  TextField(controller: customNeighborhood, decoration: const InputDecoration(hintText: 'اكتب اسم الحي...')),
                ],
                const SizedBox(height: 10),
                const FieldLabel('العنوان المفصل حسب أقرب معلم (كتابي)'),
                TextField(controller: detailedAddress, decoration: const InputDecoration(hintText: 'مثال: شارع النفق، بجوار مسجد الهدى، عمارة الأمل')),
                const SizedBox(height: 10),
                const FieldLabel('تاريخ التسجيل', requiredField: true),
                InkWell(
                  onTap: () => _pickDate(birth: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(),
                    child: Text(isoDate(enrollmentDate), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 10),
                const FieldLabel('من أين عرفتنا؟'),
                AppDropdown<String>(
                  value: referralSources.contains(referral) ? referral : referralSources.last,
                  items: referralSources.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => referral = v ?? referral),
                ),
                const SizedBox(height: 10),
                const FieldLabel('ملاحظات سريعة'),
                TextField(controller: notes, decoration: const InputDecoration(hintText: 'أي ملاحظة أو طلبات خاصة للملف...')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => extra = !extra),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.amberSoft, border: Border.all(color: AppColors.amberBorder)),
              child: Row(
                children: [
                  Icon(extra ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.amber, size: 18),
                  const SizedBox(width: 6),
                  Text(extra ? 'طي البيانات الإضافية' : 'توسيع', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 12.5)),
                ],
              ),
            ),
          ),
          if (extra) ...[
            const SizedBox(height: 8),
            AppCard(
              color: const Color(0xFFFAFCF7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('تاريخ الميلاد'),
                  InkWell(
                    onTap: () => _pickDate(birth: true),
                    child: InputDecorator(
                      decoration: const InputDecoration(),
                      child: Text(birthDate == null ? 'اختر التاريخ' : isoDate(birthDate!), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('الجنس'),
                  Row(
                    children: [
                      Expanded(child: _toggle('ذكر', gender == 'ذكر', AppColors.amber, () => setState(() => gender = 'ذكر'))),
                      const SizedBox(width: 8),
                      Expanded(child: _toggle('أنثى', gender == 'أنثى', AppColors.navy, () => setState(() => gender = 'أنثى'))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('مكان الولادة'),
                  TextField(controller: birthPlace, decoration: const InputDecoration(hintText: 'مثال: غزة')),
                  const SizedBox(height: 10),
                  const FieldLabel('الجنسية'),
                  TextField(controller: nationality, decoration: const InputDecoration(hintText: 'مثال: فلسطينية')),
                  const SizedBox(height: 10),
                  const FieldLabel('المدرسة السابقة'),
                  TextField(controller: previousSchool, decoration: const InputDecoration(hintText: 'اسم المدرسة السابقة')),
                  const SizedBox(height: 10),
                  const FieldLabel('المعدل'),
                  TextField(controller: gpa, decoration: const InputDecoration(hintText: 'مثال: 92.5%')),
                  const SizedBox(height: 10),
                  const FieldLabel('طبيعة السكن الحالي'),
                  AppDropdown<String>(
                    value: housingTypes.contains(housing) ? housing : housingTypes.last,
                    items: housingTypes.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                    onChanged: (v) => setState(() => housing = v ?? housing),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('المناطق الأصلية'),
                  TextField(controller: originalArea, decoration: const InputDecoration(hintText: 'البلدة الأصلية (مثال: يافا، حمامة...)')),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('الحالة الصحية'),
                        Row(
                          children: [
                            Expanded(child: _toggle('سليم', health == 'سليم', const Color(0xFF9A4F05), () => setState(() { health = 'سليم'; medicalCondition.clear(); }))),
                            const SizedBox(width: 8),
                            Expanded(child: _toggle('مريض / يعاني من مرض', health == 'مريض', AppColors.danger, () => setState(() => health = 'مريض'))),
                          ],
                        ),
                        if (health == 'مريض') ...[
                          const SizedBox(height: 8),
                          const FieldLabel('نوع المرض أو الحالة الصحية بالتفصيل'),
                          TextField(controller: medicalCondition, decoration: const InputDecoration(hintText: 'يرجى ذكر نوع المرض أو أي أدوية يحتاجها الطالب...')),
                        ] else
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('لا توجد أمراض مسجلة، الطالب بصحة جيدة والحمد لله.', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('مهنة ولي الأمر'),
                  TextField(controller: parentJob, decoration: const InputDecoration(hintText: 'مثال: معلم، تاجر، موظف...')),
                  const SizedBox(height: 10),
                  const FieldLabel('رقم جوال بديل لولي الأمر (بالمقدمة)'),
                  Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: AppDropdown<String>(
                          value: secondaryPrefix,
                          items: phonePrefixes.map((p) => DropdownMenuItem(value: p, child: Text(p, textDirection: TextDirection.ltr))).toList(),
                          onChanged: (v) => setState(() => secondaryPrefix = v ?? secondaryPrefix),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            controller: parentSecondaryNumber,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(hintText: 'رقم إضافي'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('البريد الإلكتروني'),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'student@example.com')),
                  const SizedBox(height: 12),
                  const Text('المرفقات والوثائق الرسمية (صور أو مستندات)', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy, fontSize: 12)),
                  const SizedBox(height: 8),
                  _attachBox('مرفق: صورة هوية الطالب', studentIdPhoto, () => _pickAttachment((v) => studentIdPhoto = v), () => setState(() => studentIdPhoto = '')),
                  const SizedBox(height: 8),
                  _attachBox('مرفق: صورة هوية ولي الأمر', parentIdPhoto, () => _pickAttachment((v) => parentIdPhoto = v), () => setState(() => parentIdPhoto = '')),
                  const SizedBox(height: 8),
                  _attachBox('مرفق: شهادة الميلاد', birthCertificate, () => _pickAttachment((v) => birthCertificate = v), () => setState(() => birthCertificate = '')),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('تقييم الطالب المبدئي (5 نجوم)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                              Text('تقييم المستوى أو المقابلة المبدئية عند التسجيل', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            for (var star = 1; star <= 5; star++)
                              InkWell(
                                onTap: () => setState(() => initialRating = initialRating == star ? 0 : star),
                                child: Icon(initialRating >= star ? Icons.star : Icons.star_border, color: initialRating >= star ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB), size: 22),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (initialRating > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('$initialRating / 5 نجوم', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.amberBorder)),
                    child: InkWell(
                      onTap: () => setState(() => guardianDeclaration = !guardianDeclaration),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(guardianDeclaration ? Icons.check_box : Icons.check_box_outline_blank, color: AppColors.amber, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'زر صح إقرار ولي الأمر: أقر أنا ولي أمر الطالب بصحة كافة البيانات والمعلومات المدخلة أعلاه، وأوافق على سياسات ولوائح المركز التعليمي ونظام الدفع والدوام.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: editing ? 'حفظ التعديل' : 'تسجيل الطالب',
                  icon: Icons.check,
                  onPressed: canSave ? _save : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool on, Color color, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          border: Border.all(color: on ? color : AppColors.line),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: on ? Colors.white : AppColors.muted, fontWeight: FontWeight.w800, fontSize: 11.5)),
      ),
    );
  }

  Widget _phoneRow({
    required String prefix,
    required TextEditingController controller,
    required int target,
    required bool complete,
    required bool error,
    required ValueChanged<String> onPrefix,
    required ValueChanged<String> onNumber,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AppDropdown<String>(
              value: prefix,
              items: phonePrefixes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => onPrefix(v ?? prefix),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              maxLength: target,
              onChanged: onNumber,
              decoration: InputDecoration(
                hintText: '$target أرقام',
                counterText: '',
                filled: true,
                fillColor: error ? const Color(0xFFFFF1F2) : (complete ? const Color(0xFFF0FDF4) : null),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneHint({required bool complete, required String? error, required int length, required int target, required String okText}) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
      );
    }
    if (length > 0 && !complete) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(child: Text('يجب إدخال $target أرقام بعد المقدمة', style: const TextStyle(color: Color(0xFFB45309), fontSize: 11))),
            Text('$length / $target', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
          ],
        ),
      );
    }
    if (complete) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(child: Text(okText, style: const TextStyle(color: Color(0xFF166534), fontSize: 11, fontWeight: FontWeight.w700))),
            Text('$length / $target', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF166534))),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(child: Text('اختر المقدمة واكتب الـ $target أرقام', style: const TextStyle(color: AppColors.muted, fontSize: 10))),
          Text('0 / $target', style: const TextStyle(fontSize: 10, color: AppColors.faint)),
        ],
      ),
    );
  }

  Widget _attachBox(String title, String data, VoidCallback pick, VoidCallback clear) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.amberBorder, style: BorderStyle.solid)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
          const SizedBox(height: 8),
          if (data.isNotEmpty) ...[
            if (_bytesOf(data) != null) Image.memory(_bytesOf(data)!, height: 80, fit: BoxFit.cover),
            TextButton(onPressed: clear, child: const Text('حذف المرفق', style: TextStyle(color: AppColors.danger, fontSize: 11))),
          ] else
            InkWell(
              onTap: pick,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Icon(Icons.upload_file, color: AppColors.amber),
                    SizedBox(height: 4),
                    Text('اختر صورة', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                                  trailing: on ? const Icon(Icons.check, color: AppColors.amber, size: 16) : null,
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
