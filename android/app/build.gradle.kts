plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI provides a stable release keystore through environment variables so
// successive releases can upgrade each other. Local builds without these
// variables keep using the debug keystore.
val qrKeystorePath: String? = System.getenv("QR_KEYSTORE_PATH")

android {
    namespace = "com.starrycognet.quotaroom"
    // notifications / home_widget pull androidx.core 1.19, which requires
    // compiling against API 37; runtime target stays on Flutter's default.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (qrKeystorePath != null) {
            create("release") {
                storeFile = file(qrKeystorePath)
                storePassword = System.getenv("QR_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("QR_KEY_ALIAS")
                keyPassword = System.getenv("QR_KEY_PASSWORD")
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.starrycognet.quotaroom"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // CI signs with the project release keystore; local builds fall
            // back to the debug keystore.
            signingConfig = if (qrKeystorePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
