/// العمل الثقيل خارج خيط الواجهة: خيط منفصل على الجوال والكمبيوتر، والخيط نفسه في المتصفح.
///
/// `Isolate.run` غير مدعوم في المتصفح ويرمي فوراً: كان سحب الجداول الكبيرة (الطلاب والسندات
/// والأقساط والحضور) يفشل بصمت في نسخة الويب، فتظهر المصروفات والمعلمون وحدهم.
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

Future<T> offThread<T>(T Function() work) => kIsWeb ? Future<T>(work) : Isolate.run(work);
