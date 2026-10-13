<p align="center">
  <img src="platforms/Android/demo/src/main/res/drawable-nodpi/hello_face_logo.webp" alt="HelloFace" width="96">
</p>

# HelloFace SDK 集成 Demo

[English](README.md) | 简体中文

**SDK 0.0.1 Beta** · 提供 Android、iOS、鸿蒙的可运行 Demo 源码与 SDK 依赖。

检测、采集、活体、1:1 比对和 1:N/M:N 搜索均在设备端运行。Demo 还演示相机设置、人脸库管理与批量导入。网络图片导入需联网。

## 快速运行

| 平台 | 环境 | 打开与运行 |
|---|---|---|
| Android | Android 6.0+；arm64/armv7；JDK 17、SDK 36 | Android Studio 打开 `platforms/Android`，运行 `demo` |
| iOS | iOS 15+；支持 Swift 6 的 Xcode | 打开 `platforms/iOS/HiFaceDemo.xcodeproj`，设置自己的 Team，在 iPhone 运行 |
| 鸿蒙 | API 20+；arm64；DevEco Studio 26 | 打开 `platforms/Harmony`，配置 HAP 签名，运行 `demo` |

在手机允许相机权限。Android 使用内置 Maven 仓库，iOS 使用二进制 SPM，鸿蒙使用内置 HAR。接入与签名说明：

- [Android](platforms/Android/README.zh-CN.md) · [SDK API](platforms/Android/docs/SDK.zh-CN.md)
- [iOS](platforms/iOS/README.zh-CN.md) · [SDK API](platforms/iOS/SDK/API.zh-CN.md)
- [鸿蒙](platforms/Harmony/README.zh-CN.md) · [SDK API](platforms/Harmony/SDK.zh-CN.md)

## 语言与导入

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启。SDK 诊断保持中文。

人脸库附带 1 万条测试特征和 1 千张图片地址。导入时返回可继续或停止；停止后保存尾批并显示已保存/失败数量，出错时保留此前已保存的批次。上线前替换演示数据。

## 安装包与期限

[Android 构建记录](https://github.com/FaceSDKPro/HelloFace/actions/workflows/android-demo.yml) 提供 `HelloFace-Android-test-apk` 附件。本地 Debug APK 位于 `platforms/Android/demo/build/outputs/apk/debug/`。正式分发使用自己的签名；iOS 和鸿蒙也需配置自己的应用签名。

Beta 于 **2026-12-26 00:00（北京时间）** 到期，请提前升级。在目标手机验证各功能及生命周期恢复。HF1 是编码，并非加密；宿主负责生物识别数据保护和删除。保留各平台许可与第三方声明。

[更新与说明](https://github.com/FaceSDKPro/) · [问题反馈](https://github.com/FaceSDKPro/HelloFace/issues)。请提供 SDK 版本、设备、系统、错误码和复现步骤，提交前清理日志中的敏感数据。
