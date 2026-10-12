# HiFace Android 集成 Demo

本工程演示 HiFace SDK 的实时人脸检测、特征录入、静态与动态 1:1 比对、活体检测、1:N / M:N 搜索及人脸库管理。
当前 SDK / Demo 版本为 **0.0.1 Beta**，依赖坐标为 `io.github.facesdkpro:hiface-android:0.0.1`。

算法在设备端执行，本地人脸库支持离线查询；网络图片导入和首次下载构建依赖需要联网。
详细 API 见 [SDK 接入指南](docs/SDK.md)，页面流程和存储示例见 [Demo 指南](docs/DEMO.md)。

## 功能与示例入口

| 功能 | 说明 | 示例代码 |
| --- | --- | --- |
| 实时人脸检测 | 人脸框、五点、可选多人和详细关键点 | [FaceDetectionActivity](demo/src/main/java/com/hiface/sdk/demo/detection/FaceDetectionActivity.java) |
| 静态 1:1 比对 | 选择两张图片，提取特征并比较 | [FaceComparisonActivity](demo/src/main/java/com/hiface/sdk/demo/comparison/FaceComparisonActivity.java) |
| 引导采集与录入 | 相机引导、对齐预览、确认后保存参考特征 | [FaceEnrollmentActivity](demo/src/main/java/com/hiface/sdk/demo/verification/FaceEnrollmentActivity.java) |
| 动态 1:1 验证 | 参考身份比对，可组合动作和静默活体 | [FaceVerificationActivity](demo/src/main/java/com/hiface/sdk/demo/verification/FaceVerificationActivity.java) |
| 活体检测 | 静默活体；眨眼、张嘴、摇头、点头 | [FaceLivenessActivity](demo/src/main/java/com/hiface/sdk/demo/liveness/FaceLivenessActivity.java) |
| 连续人脸搜索 | 1:N / M:N、分组、阈值、结果与暂停恢复 | [FaceSearchActivity](demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchActivity.java) |
| 搜索库录入 | Face ID、特征、分组及覆盖确认 | [FaceSearchEnrollmentActivity](demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchEnrollmentActivity.java) |
| 搜索库管理 | 分页、查询、删除和批量导入 | [FaceSearchLibraryActivity](demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchLibraryActivity.java) |

## 环境要求

| 项目 | 当前配置 |
| --- | --- |
| 最低系统 | Android 6.0 / API 23，包含 Android 7 |
| CPU ABI | `arm64-v8a`、`armeabi-v7a`；相机体验使用 ARM 真机 |
| 构建 JDK | 17 |
| Android SDK / Build Tools | 36 / 36.0.0 |
| Java 源码级别 | 11 |

SDK AAR 已包含 Native 库，构建本 Demo 无需安装 NDK。

## 运行 Demo

1. 使用 Android Studio 打开本目录，与 `settings.gradle.kts` 同级。
2. 在 Gradle 设置中选择 JDK 17，准备上述 Android SDK，完成项目同步。
3. 连接 ARM 真机，选择 `demo` 运行；首次进入相机页面时允许相机权限。
4. 在首页选择检测、比对、录入、验证、活体或人脸搜索入口。

```bash
./gradlew :demo:assembleDebug
adb install -r demo/build/outputs/apk/debug/demo-debug.apk
```

Demo 默认使用本地 `maven-repository/` 中的 SDK，当前导出依赖方式为 `embedded-maven`。
首次同步 Gradle 和 AndroidX 等依赖仍需网络；已有完整缓存后可以使用 Gradle 离线模式。

## 集成到自己的 App

当前 Demo 自带候选 SDK 二进制。复制本目录的 `maven-repository/` 到自己的工程根目录，
在宿主工程的 `settings.gradle.kts` 中加入仓库：

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        maven {
            url = uri("maven-repository")
            content {
                includeModule("io.github.facesdkpro", "hiface-android")
            }
        }
        mavenCentral()
    }
}
```

在 App 模块的 `build.gradle.kts` 中加入：

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

`noCompress` 应配置在宿主 App，使模型保持未压缩；JNI 保留规则由 SDK AAR 提供。
候选版本是否已上线 Maven Central，以实际发布记录为准。使用正式远端版本时，保留 `mavenCentral()`，
按正式版本坐标更新依赖，并移除本地 SDK 仓库配置。

相机功能需声明 `android.permission.CAMERA` 并完成运行时授权；使用网络图片导入时还需
`android.permission.INTERNET`。CameraX 接入示例见
[CameraPreviewFragment](demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java)。

## API 使用示例

在 Activity 中创建页面级 SDK 实例；绑定 `LifecycleOwner` 后，页面销毁时自动释放：

```java
HiFaceSdk sdk = HiFaceSdk.builder(this)
        .lifecycleOwner(this)
        .build();

// bitmap 为待识别图片，异步结果在主线程交付。
sdk.capture().extractFeature(bitmap, result -> {
    if (result.isSuccess()) {
        String feature = result.requireValue();
        // 用户确认后保存特征，或用于 1:1 比对和人脸库查询。
    } else {
        HiFaceError error = result.requireError();
        // 根据错误码提示或重试。
    }
});
```

相机能力需要持续通过 `processFrame()` 送帧；初始化期间的 `NOT_READY` 表示继续等待模型就绪。
完整监听器、配置及线程规则见 [SDK 接入指南](docs/SDK.md)。

## 工程目录

| 目录 / 文件 | 用途 |
| --- | --- |
| `demo/` | 客户 App 示例、界面和测试 |
| `demo/src/main/java/com/hiface/sdk/demo/` | 各项 SDK 接入代码 |
| `demo/src/main/assets/face_search/` | 测试特征及网络图片导入清单 |
| `maven-repository/` | 当前版本 SDK AAR 与 Maven 依赖元数据 |
| `docs/SDK.md` | API、数据格式、线程和错误处理 |
| `docs/DEMO.md` | 页面流程、相机设置、演示数据和常见问题 |
| `LICENSE` | SDK 使用范围和第三方许可声明 |

## APK、签名与测试版有效期

Debug APK 位于 `demo/build/outputs/apk/debug/`，由本机调试证书签名，只用于测试。
也可从 [Android Demo 构建记录](https://github.com/FaceSDKPro/HelloFace/actions/workflows/android-demo.yml)
下载成功运行的 `HelloFace-Android-test-apk` 附件；需要登录 GitHub，附件保留 30 天。

```bash
./gradlew :demo:assembleRelease
```

Release APK 默认未签名，分发前使用自己的发布证书。`demo/build.gradle.kts` 支持读取本机
`demo/signing.properties`；发布私钥和密码文件不进入 Git，也不随 Demo 分发。

当前版本为 Beta 测试版，可使用至**北京时间 2026-12-25 全天**；从 **2026-12-26 00:00** 起
停止初始化和工作，日志提示“请升级SDK，详情见https://github.com/FaceSDKPro/”。请在到期前升级 SDK。

## 测试数据与问题反馈

Demo 的一万条 HF1 特征用于离线批量导入，一千个 HTTPS 图片 URL 用于演示网络图片导入。
HF1 是编码，生产应用应使用获授权的数据，并配置自己的存储保护、密钥管理及删除流程。
固定 MMKV 示例密钥仅用于展示 API；相似度阈值和最终放行规则需用目标设备及独立样本验证。

SDK 使用范围和第三方声明见 [LICENSE](LICENSE)。版本、设备、相机或构建问题请提交到
[Issues](https://github.com/FaceSDKPro/HelloFace/issues)，附上环境、复现步骤及脱敏后的错误日志。
