pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pinned to AGP 8.9.1 + Gradle 8.11.1 (see gradle-wrapper.properties): cargokit's
    // Gradle plugin — bundled in super_native_extensions / irondash_engine_context
    // for the Android Rust build — calls Project.exec(), which Gradle 9 removed.
    // Flutter 3.44's template defaults to AGP 9 / Gradle 9, which breaks the APK
    // build until cargokit ships a Gradle-9-compatible plugin. 8.9.1 is the minimum
    // AGP that still has exec() yet supports compileSdk 36 (androidx.core 1.17.0
    // needs 8.9.1 + API 36). Android module only.
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
