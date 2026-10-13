# HiFace Android 集成 Demo

[English](README.md) | 简体中文

SDK / Demo：**0.0.1 Beta** · 依赖方式：`embedded-maven`

支持检测、采集、活体、1:1 比对、1:N/M:N 搜索和人脸库管理，算法在设备端运行。网络图片导入和首次下载构建依赖需联网。

指南：[SDK 中文](docs/SDK.zh-CN.md) · [SDK English](docs/SDK.md) · [Demo 中文](docs/DEMO.zh-CN.md) · [Demo English](docs/DEMO.md)。

## 运行

用 Android Studio 打开本目录，使用 JDK 17、Android SDK 36 / Build Tools 36.0.0，在 ARM 手机运行 `demo`。最低 Android 6.0 / API 23；支持 `arm64-v8a`、`armeabi-v7a`，构建 Demo 无需 NDK。

```sh
./gradlew :demo:assembleDebug
```

应用 ID：`com.hiface.sdk.public`。同版本 Beta 更新后先刷新依赖再构建。Maven Central 是否可用，以发布记录为准。

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

保留 AAR 的 consumer R8 规则。声明并动态申请 `CAMERA`；网络导入另需 `INTERNET`。远端正式版本可改用 Maven Central。

相机示例见 [CameraPreviewFragment](demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java)。使用页面级 SDK、持续送入最新帧；`NOT_READY` 表示跳过当前帧。退出时取消流程，独立打开的数据库由调用方关闭。

## 语言与数据

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启。SDK 诊断保持中文。

内置 1 万条 HF1 特征和 1 千张网络图片清单仅供演示。导入时返回可继续或停止；停止后保存尾批并显示已保存/失败数量，写库失败保留之前已保存的批次。

上线前替换测试数据和固定 MMKV 演示密钥。HF1 是编码，SDK SQLite 未加密；宿主负责数据保护和删除。

## 签名与期限

Debug 签名仅供测试；Release APK 使用自己的证书。保留 [LICENSE](LICENSE) 和交付信息。

Beta 于 **2026-12-26 00:00（北京时间）** 到期，请提前升级。[更新与说明](https://github.com/FaceSDKPro/) · [问题反馈](https://github.com/FaceSDKPro/HelloFace/issues)。
