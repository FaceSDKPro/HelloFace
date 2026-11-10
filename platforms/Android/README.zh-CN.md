# HiFace Android 集成 Demo

[English](README.md) | 简体中文

SDK / Demo：**0.8.11 Beta**

支持检测、采集、活体、1:1 比对、1:N/M:N 搜索和人脸库管理，算法在设备端运行。

**模型适用范围：当前模型不支持12周岁以下儿童人脸识别，不能用于金融相关场景。**

指南：[SDK](docs/SDK.zh-CN.md) · [Demo](docs/DEMO.zh-CN.md)。

## 运行

用 Android Studio 打开本目录，使用 JDK 17、Android SDK 36 / Build Tools 36.0.0，在 ARM 手机运行 `demo`。最低 Android 6.0 / API 23；支持 `arm64-v8a`、`armeabi-v7a`，构建 Demo 无需 NDK。

Demo 直接读取已核验的 UVCAndroidCamera 0.6.5 本地交付 `demo/libs/uvc-android-camera-0.6.5.aar`。相邻 `.txt` 绑定产物与源码快照摘要，并明确是否为本地开发候选；[上游基准提交](https://github.com/FaceSDKPro/UVCAndroidCamera/tree/abda469aca1cb87107f61eb8e1aeac7609a558ad) 不一定包含本地候选的完整源码，不代表该版本已公开发布。AAR 保留第三方许可与 JNI keep 规则。分辨率与帧率是期望值，相机会匹配邻近 MJPEG 模式，启动后使用 `actualConfig()` 获取实际尺寸与帧率。Demo 设置可为各角色选择 640×480 / 1280×720、15 / 30 FPS；搜索默认双路 15 FPS，单独打开 RGB 录入默认 30 FPS；从搜索页进入录入时沿用已选 RGB 分辨率与帧率。需确认 RGB/IR 角色，并按目标相机模块标定归一化映射。

```sh
./gradlew :demo:assembleDebug
```

APK 位于 `demo/build/outputs/apk/debug/`。

## 集成到自己的 App

复制交付包的 `maven-repository/` 并配置仓库：

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

宿主 App 模块添加依赖和模型打包配置：

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

保留 consumer R8 规则，动态申请 `CAMERA`；网络导入需 `INTERNET`。

配套保留同一 AAR 中的 `libhiface_core.so` 和 `libhiface_opencv.so`，不要单独改名、删除或混用版本。后者是私有 NCNN 运行库，其文件名不表示增加 OpenCV 依赖或接口。

相机示例：[CameraPreviewFragment](demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java)。帧与生命周期要求见 SDK 指南。

## 应用签名

Debug 签名仅供测试；Release APK 使用自己的证书。保留 [LICENSE](LICENSE) 和交付信息。

SDK正在Beta 迭代公测中，请及时升级SDK版本。[更新与说明](https://github.com/FaceSDKPro/) · [问题反馈](https://github.com/FaceSDKPro/HelloFace/issues)。
