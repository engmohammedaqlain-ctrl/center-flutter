import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// مفتاح التوقيع: أندرويد يرفض تثبيت تحديث موقّع بمفتاح غير مفتاح المثبَّت،
// فالمفتاح نفسه يلازم التطبيق مدى عمره. بياناته في `android/key.properties`
// خارج المستودع؛ وبغيابه يُوقَّع بمفتاح التصحيح ليبقى `flutter run --release`
// عاملاً على أجهزة التطوير — لكن نسخةً كهذه لا تصلح للتوزيع.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
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
    require(missing.isEmpty()) { "android/key.properties: حقول ناقصة: ${missing.joinToString()}" }
    require(rootProject.file(keystoreProperties.getProperty("storeFile")).exists()) {
        "android/key.properties: لا يوجد مفتاح على المسار ${keystoreProperties.getProperty("storeFile")} " +
            "(المسار نسبةً إلى مجلد android)"
    }
}

android {
    namespace = "com.center.center_mobile"
    compileSdk = flutter.compileSdkVersion
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
        applicationId = "com.center.center_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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
