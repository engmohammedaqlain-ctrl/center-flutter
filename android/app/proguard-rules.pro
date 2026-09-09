# قواعد الإبقاء عند تفعيل R8.
#
# Flutter تُبقي ما تحتاجه بنفسها؛ ما يلي للإضافات التي تصل إليها
# منصةُ أندرويد بالانعكاس، فلا يراها المحلّل الساكن ويحذفها.

# الجسر بين Dart وأندرويد
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# تُستدعى من نظام الطباعة عبر الانعكاس
-keep class net.nfet.flutter.printing.** { *; }

# مكتبة عرض PDF الأصلية
-keep class com.shockwave.** { *; }

# اختيار الصور والملفات
-keep class androidx.lifecycle.DefaultLifecycleObserver

# تحذيرات مكتبات اختيارية غير مستعملة
-dontwarn org.slf4j.**
-dontwarn javax.annotation.**
