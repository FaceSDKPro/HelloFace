# HelloFace

HiFace SDK 客户集成 Demo，提供人脸检测、特征提取、1:1 比对、活体检测和 1:N / M:N 搜索示例。

| 平台 | 状态 | 入口 |
| --- | --- | --- |
| Android | 0.0.1 Beta，可构建运行 | [工程与运行说明](platforms/Android/README.md) · [SDK 接入](platforms/Android/docs/SDK.md) · [Demo 指南](platforms/Android/docs/DEMO.md) |
| iOS | 筹备中 | `platforms/iOS` |
| HarmonyOS | 筹备中 | `platforms/Harmony` |

使用 Android Studio 打开 `platforms/Android`，使用 JDK 17、Android SDK 36 和 Build Tools 36.0.0。
支持 Android API 23 及以上，ARM64 / ARMv7；本仓库自带 SDK 二进制 Maven 依赖，不需要 SDK 开发源码或 NDK。

```bash
cd platforms/Android
./gradlew :demo:assembleDebug :demo:assembleRelease
```

Debug APK 可用于测试；Release 默认未签名，分发前使用自己的证书签名。
本仓库仅提供 Demo 源码、SDK 二进制、示例数据和使用文档，许可与第三方声明见 Android 目录。
当前 0.0.1 为 Beta 测试版本，到北京时间 2026-12-25 全天可用，12-26 零点起停止初始化和工作。
示例数据只用于集成演示，使用范围按 [SDK 许可](platforms/Android/LICENSE) 与正式协议确认。
