plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.airclone.airclone"
    // Some transitive androidx deps (e.g. androidx.core 1.17.0) require compiling
    // against API 36; the AGP 8.9.1 pinned in settings.gradle.kts supports it.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.airclone.airclone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // The rclone engine is a per-ABI *executable* shipped under jniLibs as
            // librclone.so (built by dev/android/build-rclone.ps1 / CI). Legacy
            // packaging makes the installer extract it to nativeLibraryDir — the
            // only location Android permits exec() from (W^X, targetSdk 29+).
            useLegacyPackaging = true
            // Don't let AGP's strip task touch it: it's a Go binary, not a JNI lib.
            keepDebugSymbols += "**/librclone.so"
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
