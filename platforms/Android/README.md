# HiFace Android Integration Demo

English | [简体中文](README.zh-CN.md)

SDK / Demo: **0.0.1 Beta**.

On-device detection, capture, liveness, 1:1 comparison, 1:N/M:N search and face-library management.

**Model scope: The current SDK model does not yet support face recognition for minors (children). If your application requires it, [contact the author](https://github.com/FaceSDKPro/HelloFace/issues) to replace or update the model before use.**

Guides: [SDK](docs/SDK.md) · [Demo](docs/DEMO.md).

## Build and run

Use Android Studio, JDK 17, Android SDK 36 / Build Tools 36.0.0, and Java source level 11. Minimum Android version is 6.0 / API 23. The AAR includes native libraries for `arm64-v8a` and `armeabi-v7a`; this Demo does not require an NDK installation. Camera validation requires an ARM phone.

Open this directory, sync dependencies, select `demo`, and run it on a phone. Grant camera access when requested. Application ID: `com.hiface.sdk.public`.

```sh
./gradlew :demo:assembleDebug
```

APK output: `demo/build/outputs/apk/debug/`.

## Integrating in your App

If this export contains `maven-repository/`, copy it into your project and add:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        maven {
            url = uri("maven-repository")
            content { includeModule("io.github.facesdkpro", "hiface-android") }
        }
        mavenCentral()
    }
}
```

Use the SDK dependency and model compression configuration in the host App module:

```kotlin
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.0.1")
}
android {
    defaultConfig {
        minSdk = 23
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    androidResources { noCompress += "bphfm" }
}
```

Retain the AAR consumer R8 rules. Request `CAMERA` at runtime; online image import needs `INTERNET`.

Camera example: [CameraPreviewFragment](demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java). See the SDK guide for frame ownership and lifecycle.

## Signing and expiry

Sign Release APKs with your certificate. Retain [LICENSE](LICENSE).

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. [Updates](https://github.com/FaceSDKPro/) · [Issues](https://github.com/FaceSDKPro/HelloFace/issues).
