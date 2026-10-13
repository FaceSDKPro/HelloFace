# HiFace Android Integration Demo

English | [简体中文](README.zh-CN.md)

SDK / Demo version: **0.0.1 Beta**. Dependency: `io.github.facesdkpro:hiface-android:0.0.1`. Export dependency mode: `embedded-maven`.

This project demonstrates live face detection, capture/enrollment, action and passive liveness, static/dynamic 1:1 comparison, 1:N/M:N search, and face-library management. Processing runs on device. Image import and first-time build dependency downloads require a network connection.

Read the [SDK guide](docs/SDK.md) and [Demo guide](docs/DEMO.md), or their [Chinese SDK](docs/SDK.zh-CN.md) and [Chinese Demo](docs/DEMO.zh-CN.md) versions.

## Build and run

Use Android Studio, JDK 17, Android SDK 36 / Build Tools 36.0.0, and Java source level 11. Minimum Android version is 6.0 / API 23. The AAR includes native libraries for `arm64-v8a` and `armeabi-v7a`; this Demo does not require an NDK installation. Camera validation requires an ARM phone.

Open this directory, sync dependencies, select `demo`, and run it on a phone. Grant camera access when requested. Application ID: `com.hiface.sdk.public`.

```sh
./gradlew :demo:assembleDebug
```

Install the APK shown in the Gradle output. For an updated beta artifact, refresh dependencies before rebuilding. SDK availability on Maven Central is defined by the actual release record.

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

For a published remote version, use Maven Central and remove the local SDK repository. Retain the AAR's consumer R8 rules. Declare `CAMERA` and request it at runtime; network image import also needs `INTERNET`.

The camera adapter is [CameraPreviewFragment](demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java). Create a page-scoped `HiFaceSdk`, keep sending latest frames, and treat `NOT_READY` as a skipped frame. Cancel active flows on teardown; explicitly opened databases must be closed by their owner.

## Languages and test data

The Demo uses Simplified Chinese for system regions CN/HK/MO/TW and English elsewhere, including unknown regions. System language alone does not decide the Demo language. Restart after changing the region. SDK logs and internal messages are not localized; the Demo maps error codes to bilingual UI messages.

Both language resources are included in `demo/src/main/res`. Keep saved Face IDs, groups, features, and workflow state independent of translated labels.

The bundled 10,000 HF1 features and 1,000 HTTPS image URLs are test data. Replace them with authorized data before production. Import progress distinguishes processed and saved counts. Back during an import asks whether to continue or stop. Stop saves the completed tail batch before showing the saved/failed counts. Previously committed batches remain after a write failure.

HF1 is an encoding, not encryption. Replace the Demo's fixed MMKV key with your own protected key strategy. The host owns biometric data protection and deletion.

## Signing, beta expiry, and delivery

Debug builds use the local debug certificate. Release APKs require your signing certificate; private signing files/passwords must remain local. Keep [LICENSE](LICENSE), release metadata, and `SHA256SUMS` with the delivery.

This beta works through **2026-12-25, UTC+08:00** and stops at **2026-12-26 00:00**. Original SDK upgrade logs remain in Chinese. Upgrade before expiry. [Updates](https://github.com/FaceSDKPro/) and [issue reporting](https://github.com/FaceSDKPro/HelloFace/issues) are available publicly; include device/version information and sanitized reproduction logs.
