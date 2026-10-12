# HiFace Android 集成 Demo

SDK 与 Demo 版本：0.0.1。依赖坐标：`io.github.facesdkpro:hiface-android:0.0.1`。
本工程只包含 Demo 源码、Gradle Wrapper 与二进制依赖，不需要 HiFace SDK/Core 源码。

## 运行

1. 使用 JDK 17 和 Android Studio 打开本目录，安装 Android SDK 36 与 Build Tools 36.0.0；SDK AAR 已包含 Native 库，无需安装 NDK。
2. 同步依赖；本导出的依赖方式为 `embedded-maven`。Maven Central 模式须等对应版本上线后使用。
3. 运行 `./gradlew :demo:assembleDebug :demo:assembleRelease`，选择 ARM 真机体验相机能力。

最低 Android API 23，ABI 为 arm64-v8a / armeabi-v7a。Java 源码级别为 11，构建 JDK 为 17。
`demo/build.gradle.kts` 固定 Debug/Release 的 SDK 版本；不要换用 SNAPSHOT。离线 HAR/AAR 的“离线”指 SDK 推理无需网络，
首次同步 Gradle/CameraX 等依赖仍需要网络或预先准备缓存。

## 签名与验收

Debug APK 由本机生成的调试密钥签名，只供测试。Release APK 默认未签名，直接安装或分发前使用
自己的发布证书签名并验证；本工程不含发布私钥、开发者 local.properties 或 Central 凭据。
需修改自己的 applicationId，并验证权限拒绝恢复、前后台、取消、全部能力、长时间内存和性能。

## 文档与数据

公开 API 见 `docs/SDK.md`，完整使用与示例指南见 `docs/DEMO.md`，交付文件完整性见 `SHA256SUMS`。
两份说明均来自 Demo 使用方指南，不包含 SDK 开发维护或 Maven 发布文档。
`export-info.json` 记录版本、源码提交与工作区状态；工作区有修改的导出不能当作正式发布证据。

当前测试版到北京时间 2026-12-25 全天可用，12-26 零点起停止初始化和工作并记录升级提示。
商业使用和示例源码使用范围须按正式协议确认，保留 LICENSE 与第三方声明。
Demo 内的人脸数据、图片 URL 和固定 MMKV 示例密钥只供集成演示；上线前替换测试数据并通过
Keystore 管理密钥，实现用户同意、数据保护和删除。SDK 搜索库使用普通 SQLite，HF1 不等于加密。
