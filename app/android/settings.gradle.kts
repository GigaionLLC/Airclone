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
    // Pinned to AGP 8.11.1 + Gradle 8.14.3 (see gradle-wrapper.properties), which is
    // exactly Flutter 3.47's stated minimum for both — and no higher. Cargokit's
    // Gradle plugin — bundled in super_native_extensions / irondash_engine_context
    // for the Android Rust build — calls Project.exec(), which Gradle 9 removed, and
    // AGP 9 additionally reads only the new DSL, which the Flutter Gradle plugin does
    // not yet speak. So: stay on the 8.x line of both until cargokit and the Flutter
    // plugin catch up, and raise these two together with the Flutter pin in
    // .github/workflows/release.yml. (Was AGP 8.9.1 + Gradle 8.11.1 for Flutter
    // 3.44; compileSdk 36 still needs AGP >= 8.9.1 for androidx.core 1.17.0.)
    id("com.android.application") version "8.11.1" apply false
    // Flutter 3.47's minimum. Raise it with the Flutter pin, like the two above.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
