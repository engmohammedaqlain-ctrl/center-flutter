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
  String birthCertificate = '';
  bool attachmentsLoaded = false;

  static const _gap = SizedBox(height: 12);

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
    // «male»/«female» تصل أحياناً من السحابة؛ تُعرض مختارة وتُحفظ بالعربية كما في Center
    gender = genderLabel(s?.gender);
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
                birthCertificate: birthCertificate,
              )
            : null,
      );
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
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
    if (!store.can('students.edit')) {
      return Scaffold(
        appBar: AppBar(title: Text(editing ? 'تعديل بيانات الطالب' : 'تسجيل طالب جديد')),
        body: NoAccess(section: 'students', roleName: store.roleName),
      );
    }
    final studentLen = phoneTargetLength(phonePrefix);
    final parentLen = phoneTargetLength(parentPhonePrefix);
    final studentComplete = isPhoneComplete(phoneNumber, phonePrefix);
    final parentComplete = isPhoneComplete(parentPhoneNumber, parentPhonePrefix);
    final fullStudentPhone = combinePhoneAndPrefix(phoneNumber, phonePrefix);
    final matchingSections = store.rooms.where((r) => r.gradeLevel.trim().isEmpty || r.gradeLevel.trim() == (grade == 'أخرى (إدخال يدوي)' ? customGrade.text.trim() : grade).trim()).toList();
    final canSave = idDuplicateError == null && phoneDuplicateError == null;
    final idLen = nationalId.text.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(editing ? 'تعديل بيانات الطالب' : 'تسجيل طالب جديد'),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
      bottomNavigationBar: _actionBar(editing: editing, canSave: canSave),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // ── ١. البيانات الأساسية ──────────────────────────────────────────
            _section(Icons.badge_outlined, 'البيانات الأساسية', note: 'الحقول ذات * مطلوبة'),
            const FieldLabel('الاسم الرباعي للطالب', requiredField: true),
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'مثال: محمد أحمد النجار'),
            ),
            _gap,
            _pair(
              [
                const FieldLabel('رقم الهوية', requiredField: true),
                TextField(
                  controller: nationalId,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  style: const TextStyle(fontSize: 13, letterSpacing: 0.5),
                  decoration: InputDecoration(
                    hintText: '9 أرقام',
                    counterText: '',
                    fillColor: idDuplicateError != null
                        ? const Color(0xFFFFF1F2)
                        : (idLen == 9 ? const Color(0xFFF0FDF4) : Colors.white),
                    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _counter(idLen, 9),
                  ),
                ),
              ],
              [
                const FieldLabel('رمز البوابة'),
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
                      onPressed: () => setState(() => portalCode.text = AppStore.instance.newPortalCode()),
                    ),
                  ),
                ),
              ],
            ),
            if (idDuplicateError != null) _message(idDuplicateError!, AppColors.danger),
            _gap,
            _pair(
              [
                const FieldLabel('المرحلة', requiredField: true),
                AppDropdown<String>(
                  value: grade,
                  items: gradeLevels.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => grade = v ?? grade),
                ),
              ],
              [
                const FieldLabel('الشعبة'),
                TextField(
                  controller: sectionCtl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: matchingSections.isEmpty ? 'مثال: أ' : matchingSections.first.name,
                  ),
                ),
              ],
            ),
            if (grade == 'أخرى (إدخال يدوي)') ...[
              const SizedBox(height: 8),
              TextField(controller: customGrade, decoration: const InputDecoration(hintText: 'اكتب اسم الصف الدراسي يدوياً...')),
            ],
            if (matchingSections.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in matchingSections) _sectionChip(r.name),
                ],
              ),
            ],
            _gap,
            const FieldLabel('جوال وواتساب الطالب', requiredField: true),
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
              okText: 'رقم صالح: $fullStudentPhone',
            ),

            // ── ٢. ولي الأمر والسكن ──────────────────────────────────────────
            _section(Icons.family_restroom_outlined, 'ولي الأمر والسكن'),
            _pair(
              [
                const FieldLabel('اسم ولي الأمر'),
                TextField(controller: parentName, decoration: const InputDecoration(hintText: 'الاسم الثلاثي')),
              ],
              [
                const FieldLabel('صلة القرابة'),
                AppDropdown<String>(
                  value: relation,
                  items: guardianRelations.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setState(() => relation = v ?? relation),
                ),
              ],
              startFlex: 3,
              endFlex: 2,
            ),
            _gap,
            const FieldLabel('جوال ولي الأمر'),
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

            // ── ٣. التسجيل ────────────────────────────────────────────────────
            _section(Icons.event_note_outlined, 'التسجيل'),
            _pair(
              [
                const FieldLabel('تاريخ التسجيل', requiredField: true),
                _selectField(
                  text: isoDate(enrollmentDate),
                  icon: Icons.calendar_today_outlined,
                  onTap: () => _pickDate(birth: false),
                ),
              ],
              [
                const FieldLabel('من أين عرفتنا؟'),
                AppDropdown<String>(
                  value: referralSources.contains(referral) ? referral : referralSources.last,
                  items: referralSources.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => referral = v ?? referral),
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

            // ── ٤. بيانات إضافية (اختيارية) ──────────────────────────────────
            _extraHeader(),
            if (extra) ..._extraFields(),
          ],
        ),
      ),
    );
  }

  List<Widget> _extraFields() {
    return [
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
            value: housingTypes.contains(housing) ? housing : housingTypes.last,
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
                  'أقر أنا ولي أمر الطالب بصحة كافة البيانات المدخلة، وأوافق على سياسات ولوائح المركز التعليمي ونظام الدفع والدوام.',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// عنوان قسم: أيقونة واسم وخط رفيع — بديل البطاقة التي كانت تحبس الحقول.
  Widget _section(IconData icon, String title, {String? note}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.heading)),
              ),
              if (note != null) Text(note, style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.line),
        ],
      ),
    );
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
                        const Text('الميلاد والسكن والصحة والمرفقات — اختيارية', style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
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

  /// حقلان متجاوران بعنوانيهما — للحقول القصيرة التي تهدر سطراً كاملاً وحدها.
  Widget _pair(List<Widget> start, List<Widget> end, {int startFlex = 1, int endFlex = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: startFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: start)),
        const SizedBox(width: 10),
        Expanded(flex: endFlex, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: end)),
      ],
    );
  }

  /// حقل اختيار يُفتح بلمسة (تاريخ، حي) بشكل الحقول النصية نفسه.
  Widget _selectField({required String text, required IconData icon, required VoidCallback onTap, bool placeholder = false}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 20),
          suffixIcon: Icon(icon, size: 16, color: AppColors.faint),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: placeholder ? AppColors.faint : AppColors.text),
        ),
      ),
    );
  }

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

  Widget _sectionChip(String label) {
    final on = sectionCtl.text == label;
    return InkWell(
      onTap: () => setState(() => sectionCtl.text = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.amberSoft : Colors.white,
          border: Border.all(color: on ? AppColors.amber : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? AppColors.amber : AppColors.muted),
        ),
      ),
    );
  }

  Widget _actionBar({required bool editing, required bool canSave}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PrimaryButton(
                label: editing ? 'حفظ التعديل' : 'تسجيل الطالب',
                icon: Icons.check,
                height: 44,
                onPressed: canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool on, Color color, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          border: Border.all(color: on ? color : AppColors.line),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: on ? Colors.white : AppColors.muted, fontWeight: FontWeight.w800, fontSize: 11.5),
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
        decoration: BoxDecoration(
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
