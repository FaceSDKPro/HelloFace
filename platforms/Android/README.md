# HiFace Android Integration Demo

English | [简体中文](README.zh-CN.md)

SDK / Demo: **0.8.11 Beta**.

On-device detection, capture, liveness, 1:1 comparison, 1:N/M:N search and face-library management.

**Model scope: The current model does not support face recognition for people under 12 and must not be used in financial scenarios.**

Guides: [SDK](docs/SDK.md) · [Demo](docs/DEMO.md).

## Build and run

Use Android Studio, JDK 17, Android SDK 36 / Build Tools 36.0.0, and Java source level 11. Minimum Android version is 6.0 / API 23. The AAR includes native libraries for `arm64-v8a` and `armeabi-v7a`; this Demo does not require an NDK installation. Camera validation requires an ARM phone.

The Demo loads `demo/libs/uvc-android-camera-0.6.5.aar` from the reviewed UVCAndroidCamera 0.6.5 local delivery. The adjacent `.txt` binds exact artifact/source snapshot checksums and states whether the source is a local development candidate. The [upstream base](https://github.com/FaceSDKPro/UVCAndroidCamera/tree/abda469aca1cb87107f61eb8e1aeac7609a558ad) is not necessarily the complete source of a local candidate; no public release is implied. The AAR retains third-party licenses and JNI keep rules. Capture size and FPS are preferences; cameras may negotiate a nearby MJPEG mode. Use `actualConfig()` after startup for dimensions and FPS. Demo Settings offer 640×480 / 1280×720 and 15 / 30 FPS for each role. Search defaults to 15 FPS per camera; standalone RGB enrollment defaults to 30 FPS. Enrollment opened from search inherits the requested RGB size and FPS. Confirm RGB/IR roles and calibrate their normalized mapping for your camera module.

Open this directory, sync dependencies, select `demo`, and run it on a phone. Grant camera access when requested. The application ID is `com.hiface.sdk.public`.

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
    implementation("io.github.facesdkpro:hiface-android:0.8.11")
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

Keep `libhiface_core.so` and `libhiface_opencv.so` from the same AAR together. Do not rename, remove, or mix individual native libraries. The latter is the private NCNN runtime; its name does not add an OpenCV dependency or API.

Camera example: [CameraPreviewFragment](demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java). See the SDK guide for frame ownership and lifecycle.

## App signing

Sign Release APKs with your certificate. Retain [LICENSE](LICENSE).

The SDK is in iterative public Beta testing. Please keep the SDK version up to date. [Updates](https://github.com/FaceSDKPro/) · [Issues](https://github.com/FaceSDKPro/HelloFace/issues).
