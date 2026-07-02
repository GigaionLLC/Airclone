import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Release signing ───────────────────────────────────────────────────────
// Credentials come from key.properties (local dev) or AIRCLONE_* environment
// variables (CI). When neither is present — forks, contributors, or a plain
// `flutter run --release` — we fall back to debug signing so the build still
// succeeds. The keystore and key.properties live OUTSIDE the repo and are
// gitignored; they must never be committed.
val keystoreProperties = Properties()
rootProject.file("key.properties").let { f ->
    if (f.exists()) f.inputStream().use { keystoreProperties.load(it) }
}
// Blank counts as absent: in CI an unset `${{ secrets.X }}` expands to an empty
// (present-but-"") env var, which must NOT be mistaken for a real credential.
fun signingValue(prop: String, env: String): String? =
    (keystoreProperties.getProperty(prop) ?: System.getenv(env))?.takeIf { it.isNotBlank() }
val releaseStorePath = signingValue("storeFile", "AIRCLONE_KEYSTORE")
val releaseStorePassword = signingValue("storePassword", "AIRCLONE_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "AIRCLONE_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "AIRCLONE_KEY_PASSWORD")
// Sign with the release key only when ALL four are present; a partial set
// (e.g. keystore but a forgotten alias secret) falls back to debug instead of
// failing deep in AGP's signing task with an empty alias/password.
val releaseSigningReady = releaseStorePath != null && releaseStorePassword != null &&
    releaseKeyAlias != null && releaseKeyPassword != null

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
        // Oreo (26), overriding Flutter's default of 24. The transfer
        // foreground service is built on notification channels +
        // Context.startForegroundService(), both of which are API-26-only —
        // on 24/25 those calls throw at runtime and crash the app. rclone's
        // engine and the rest of the app work fine on 26+; Android 7.x is now
        // a vanishingly small, unsupported slice.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only materialised when the full credential set is present; otherwise
        // the release build type falls back to debug signing below.
        if (releaseSigningReady) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Sign with the real release keystore when all its credentials are
            // present (key.properties locally, or AIRCLONE_* env vars in CI);
            // otherwise fall back to debug signing so forks and
            // `flutter run --release` still build.
            signingConfig = if (releaseSigningReady)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
