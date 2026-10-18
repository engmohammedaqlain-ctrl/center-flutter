import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // إشعارات الجوال: إعداد Firebase من google-services.json (فيه com.center.center_mobile وcom.noonschool.app)
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// نسخة Google Play (com.noonschool.app) تُبنى بـ NOON_STORE=play
// (.github/workflows/play-store.yml). بدونه يُبنى ما كان يُبنى قبلها حرفاً بحرف:
// نسخ GitHub (com.center.center_mobile) بمفتاحها وتحديثها الذاتي.
// لا productFlavors: إضافتها تغيّر مسارات المخرجات وإعداد Shorebird لنسخ GitHub.
val playStore = System.getenv("NOON_STORE") == "play"

// مفتاح التوقيع: أندرويد يرفض تثبيت تحديث موقّع بمفتاح غير مفتاح المثبَّت،
// فالمفتاح نفسه يلازم التطبيق مدى عمره. بياناته في `android/key.properties`
// خارج المستودع؛ وبغيابه يُوقَّع بمفتاح التصحيح ليبقى `flutter run --release`
// عاملاً على أجهزة التطوير — لكن نسخةً كهذه لا تصلح للتوزيع.
val keystoreProperties = Properties().apply {
    // نسخة المتجر بمفتاح رفعٍ منفصل (Google يدير مفتاح توقيع التطبيق)
    val file = rootProject.file(if (playStore) "play-key.properties" else "key.properties")
    // يُقرأ بـ UTF-8 صراحةً: `load(InputStream)` يفكّ الترميز بـ ISO-8859-1، فكلمة
    // سرٍّ غير لاتينية تصل إلى المُوقِّع محرَّفة، ويفشل التغليف بخطأٍ يقول
    // «كلمة السر خاطئة» ولا يقول لماذا.
    if (file.exists()) file.reader(Charsets.UTF_8).use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

// بياناتٌ ناقصة تُوقِف البناء هنا بكلامٍ مفهوم، بدل أن تفشل بعد عشر دقائق
// في `packageRelease` بخطأٍ عن مخزنٍ «عُبث به».
if (hasReleaseKey) {
    val missing = listOf("storePassword", "keyAlias", "keyPassword")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    require(missing.isEmpty()) { "android/${if (playStore) "play-key" else "key"}.properties: حقول ناقصة: ${missing.joinToString()}" }
    require(rootProject.file(keystoreProperties.getProperty("storeFile")).exists()) {
        "android/${if (playStore) "play-key" else "key"}.properties: لا يوجد مفتاح على المسار ${keystoreProperties.getProperty("storeFile")} " +
            "(المسار نسبةً إلى مجلد android)"
    }
}

android {
    namespace = "com.center.center_mobile"
    // المتجر يطلب للتطبيقات الجديدة والتحديثات targetSdk 36 (Android 16) منذ 31 آب 2026
    compileSdk = if (playStore) maxOf(flutter.compileSdkVersion, 36) else flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (playStore) "com.noonschool.app" else "com.center.center_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = if (playStore) maxOf(flutter.targetSdkVersion, 36) else flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // تصغير كود جافا/كوتلن وحذف الموارد غير المشار إليها.
            // بلا هذين يخرج الإصدار بكامل شيفرة الإضافات ومواردها.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        // StoreReferrer: كود المدرسة من رابط المتجر، أو فارغ في نسخ GitHub
        getByName("main").java.srcDir(if (playStore) "src/play/kotlin" else "src/github/kotlin")
        if (playStore) getByName("release").manifest.srcFile("src/play/AndroidManifest.xml")
    }

    packaging {
        resources {
            // ملفات ترخيص وبيانات وصفية لا يحتاجها التطبيق وقت التشغيل
            excludes += setOf(
                "META-INF/*.kotlin_module",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "**/*.version",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider: تسليم السندات لواتساب وعارض الملفات (DocumentsBridge)
    implementation("androidx.core:core-ktx:1.13.1")
    // نسخة المتجر: رابط التنزيل يحمل كود المدرسة (StoreReferrer)
    if (playStore) implementation("com.android.installreferrer:installreferrer:2.2")
}
