# HiFace iOS 集成 Demo

[English](README.md) | 简体中文

SDK：**0.0.1 Beta** · Bundle ID：`com.hiface.sdk.public`

支持检测、采集、活体、1:1 比对、1:N/M:N 搜索和人脸库管理，算法在设备端运行。

## 运行

1. 用 Xcode 打开 `HiFaceDemo.xcodeproj`，选择 `HiFaceDemo`。
2. 在 Signing & Capabilities 配置自己的 Team 和 Bundle ID。
3. 在 iOS 15+ 的 iPhone 运行并允许相机权限。

模拟器和 My Mac 适合界面或编译检查；相机和性能需在 iPhone 验证。

## 工程

| 目录 | 用途 |
|---|---|
| `HiFaceDemo/` | 可修改的 SwiftUI / AVFoundation 示例 |
| `SDK/` | 二进制 SPM；保留 HiFace 和 HiFaceNative 两个目标 |
| `export-info.json` | SDK 版本与依赖信息 |

使用 `HiFaceSDK()` 默认模型配置。保留完整 `Info.plist` 并补充业务权限；不要覆盖为仅含权限说明的文件。

接入说明：[SDK 中文](SDK/README.zh-CN.md) · [SDK English](SDK/README.md) · [Demo 中文](DEMO.zh-CN.md) · [Demo English](DEMO.md)。

## 语言与数据

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启。SDK 诊断保持中文。

导入时返回可继续或停止。停止后保存已完成的尾批，再显示已保存和失败数量；写库失败保留此前已保存的批次。

上线前替换测试身份、图片地址和特征。1:1 基准由 Demo 使用 Keychain 保存；HF1 是编码，SDK SQLite 未加密。宿主负责数据保护与删除。

Beta 于 **2026-12-26 00:00（北京时间）** 到期。保留许可与第三方声明，在目标手机验证各功能和生命周期。[更新与说明](https://github.com/FaceSDKPro/)。
