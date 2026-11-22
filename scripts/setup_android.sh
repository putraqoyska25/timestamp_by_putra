#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
APP_DIR="$ANDROID_DIR/app"
SRC_MAIN_DIR="$APP_DIR/src/main"
KOTLIN_PKG_DIR="$SRC_MAIN_DIR/kotlin/com/example/timestamp_by_putra"

mkdir -p "$ANDROID_DIR" "$APP_DIR" "$SRC_MAIN_DIR" "$KOTLIN_PKG_DIR"

# 1. Tulis gradle.properties agar kompatibel dengan JVM / Gradle / Kotlin stabil
cat <<'EOF' > "$ANDROID_DIR/gradle.properties"
org.gradle.jvmargs=-Xmx4096M -XX:MaxMetaspaceSize=1024m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF

# 2. Tulis settings.gradle.kts dengan versi plugin & Kotlin stabil (menghindari 2.3.20 yang gagal di-resolve)
cat <<'EOF' > "$ANDROID_DIR/settings.gradle.kts"
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropsFile = file("local.properties")
        if (localPropsFile.exists()) {
            localPropsFile.inputStream().use { properties.load(it) }
        }
        val envSdk = System.getenv("FLUTTER_ROOT")
        val sdkPath = properties.getProperty("flutter.sdk") ?: envSdk
        require(sdkPath != null && sdkPath.isNotBlank()) {
            "flutter.sdk not set in local.properties or FLUTTER_ROOT"
        }
        sdkPath
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
    id("com.android.application") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "timestamp_by_putra"
include(":app")
EOF

# 3. Tulis root build.gradle.kts
cat <<'EOF' > "$ANDROID_DIR/build.gradle.kts"
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
EOF

# 4. Tulis app/build.gradle.kts
cat <<'EOF' > "$APP_DIR/build.gradle.kts"
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.timestamp_by_putra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.timestamp_by_putra"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
EOF

# 5. Pastikan MainActivity.kt tersedia bila belum ada
if [ ! -f "$KOTLIN_PKG_DIR/MainActivity.kt" ]; then
cat <<'EOF' > "$KOTLIN_PKG_DIR/MainActivity.kt"
package com.example.timestamp_by_putra

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
EOF
fi

# 6. Pastikan AndroidManifest.xml ada bila belum ada
if [ ! -f "$SRC_MAIN_DIR/AndroidManifest.xml" ]; then
cat <<'EOF' > "$SRC_MAIN_DIR/AndroidManifest.xml"
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />

    <application
        android:label="Timestamp by Putra"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
EOF
fi

echo "setup_android.sh selesai dijalankan."
