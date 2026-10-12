<p align="center">
  <img src="platforms/Android/demo/src/main/res/drawable-nodpi/hello_face_logo.webp" alt="HelloFace" width="96">
</p>

# HelloFace · HiFace SDK 集成 Demo

HiFace 在设备端完成相机人脸检测、特征提取、身份比对、活体检测和人脸搜索。
HelloFace 提供可运行的集成工程，帮助接入方了解 API、相机送帧、流程回调和人脸库管理。

检测、比对、活体和本地搜索无需连接算法服务器；Demo 的网络图片导入需要联网。
本仓库包含 Demo 源码与 SDK 二进制依赖，SDK 实现源码不在本仓库中。

## 功能介绍

| 能力 | Demo 演示内容 |
| --- | --- |
| 人脸检测 | 实时人脸框、五点关键点，可选多人检测、详细关键点和头部姿态 |
| 特征提取与录入 | 从图片提取 HF1 特征；相机引导采集、对齐预览、用户确认后保存 |
| 静态 1:1 比对 | 两张图片比对，或比较两份已有特征 |
| 动态 1:1 验证 | 相机采集与参考身份比对，可组合动作和静默活体 |
| 活体检测 | 静默活体；眨眼、张嘴、摇头、点头四种动作挑战 |
| 1:N / M:N 搜索 | 持续识别单人或多人，支持分组、标签、阈值和 Top-K 配置 |
| 人脸库管理 | 录入、查询、分页、删除、批量导入与元数据更新 |
| 相机适配 | CameraX 预览和分析，分辨率、前后摄像头、坐标镜像及前后台处理示例 |

## 使用场景

| 场景 | 可参考的能力 |
| --- | --- |
| 刷脸登录、授权与身份复核 | 动态 1:1 验证、活体检测 |
| 考勤、门禁与访客识别 | 引导录入、1:N 搜索、人脸库管理 |
| 多人到场识别 | M:N 搜索、分组和标签过滤 |
| 本地图片身份比对 | 图片特征提取、静态 1:1 比对 |

实际业务需使用目标设备和独立样本验证识别效果，并按场景设置阈值、活体要求及最终放行规则。

## 平台与版本

| 平台 | 当前状态 | 工程与文档 |
| --- | --- | --- |
| Android | `0.0.1 Beta`，已提供集成 Demo | [运行与集成](platforms/Android/README.md) · [SDK API 指南](platforms/Android/docs/SDK.md) · [Demo 详细指南](platforms/Android/docs/DEMO.md) |
| iOS | `0.0.1 Beta`，本地二进制 SPM Demo | [运行与集成](platforms/iOS/README.md) · [SDK API 指南](platforms/iOS/SDK/README.md) · [Demo 指南](platforms/iOS/DEMO.md) |
| HarmonyOS | `0.0.1 Beta`，版本化 HAR Demo | [运行与集成](platforms/Harmony/README.md) · [SDK API 指南](platforms/Harmony/SDK.md) · [Demo 指南](platforms/Harmony/demo/README.md) |

Android 最低系统为 **Android 6.0 / API 23**，支持 `arm64-v8a`、`armeabi-v7a`。
相机体验使用 ARM 真机；首次构建需准备 Gradle、Android SDK 和依赖缓存。
iOS 基线为 iOS 15，使用 Xcode 26.6；鸿蒙基线为 API 20 / arm64-v8a，使用 DevEco Studio 26。
三端独立 Demo 已进行构建验证；客户需配置自己的 App 签名，真机相机、活体及长期性能验收仍待完成。

当前测试版可使用至**北京时间 2026-12-25 全天**，从 **2026-12-26 00:00** 起停止初始化和工作。
请在到期前升级到新的 SDK 版本，正式发布状态以发布记录为准。

## 快速运行 Android Demo

1. 下载本仓库，使用 Android Studio 打开 `platforms/Android`。
2. 使用 JDK 17，安装 Android SDK 36 和 Build Tools 36.0.0。
3. 同步项目，在 ARM 真机上运行 `demo`，允许相机权限后选择要体验的功能。

也可以在终端构建：

```bash
cd platforms/Android
./gradlew :demo:assembleDebug
```

SDK 二进制已放在工程的 `maven-repository/` 中，构建 Demo 无需 NDK。
自己的 App 如何添加 SDK 依赖和模型打包配置，见 [Android 集成说明](platforms/Android/README.md#集成到自己的-app)。

## 安装包与签名

打开 [Android Demo 构建记录](https://github.com/FaceSDKPro/HelloFace/actions/workflows/android-demo.yml)，
选择一次成功的运行，在 **Artifacts** 中下载 `HelloFace-Android-test-apk`，解压后安装测试 APK。
下载 Actions 附件需要登录 GitHub；附件有效期为 30 天。

本地 Debug APK 位于 `platforms/Android/demo/build/outputs/apk/debug/`。
Debug 签名只用于测试；Release APK 默认未签名，正式分发前使用自己的发布证书。
iOS 在 Xcode 中配置自己的 Team 和 Bundle Identifier 后部署；鸿蒙在 DevEco 配置自己的
Bundle Name、证书及设备 Profile 后部署。两端演示工程均不包含开发者签名材料。

## 数据与许可

Demo 附带测试特征和网络图片清单，用于演示批量导入。网络图片导入会访问清单指定的服务。
生产应用应使用获授权的业务数据；HF1 是特征编码，生产数据的保护、保留期限和删除由接入方实现。
详细说明见 [Demo 数据与存储](platforms/Android/docs/DEMO.md#数据安全)。

SDK `0.0.1` 为 Beta 测试版本，使用范围见 [LICENSE 与第三方声明](platforms/Android/LICENSE)。

## 问题反馈

在 [Issues](https://github.com/FaceSDKPro/HelloFace/issues) 中提供 SDK 版本、设备型号、系统版本、CPU ABI、
复现步骤和相关错误码。提交日志前删除人脸图片、特征、用户身份和凭据等敏感信息。
