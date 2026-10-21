/// فحص الاسم تحت الأيقونة على حزمة مبنية فعلاً (Check build): يكتب اسماً
/// تجريبياً في بيانها ويحفظها بلا توقيع، ثم يقرؤه `aapt2 dump badging` كما
/// يقرؤه أندرويد. الاستعمال: `dart run tool/school_label_check.dart <in.apk> <out.apk> <name>`
library;

import 'dart:io';

import 'school_apk.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: school_label_check.dart <in.apk> <out.apk> <name>');
    exit(2);
  }
  final apk = File(args[0]).readAsBytesSync();
  final manifest = readZipEntries(apk).firstWhere((e) => e.name == manifestEntry);
  final before = manifestLabel(entryContent(apk, manifest));
  final labeled = setManifestLabel(entryContent(apk, manifest), args[2]);
  File(args[1]).writeAsBytesSync(rewriteZip(apk, {manifestEntry: labeled}));
  stdout.writeln('label: "$before" -> "${manifestLabel(labeled)}"');
}
