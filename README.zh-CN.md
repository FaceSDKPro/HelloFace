<div align="center">
  <p><samp>本地计算 &nbsp; · &nbsp; 原生 SDK &nbsp; · &nbsp; 五个平台</samp></p>
  <h1>HelloFace</h1>
  <p>离线人脸检测、采集、活体、1:1 比对及 1:N/M:N 搜索。</p>
  <p><strong>0.8.6 Beta</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a></p>
  <p>
    <a href="README.md">English</a> · <strong>简体中文</strong>
    &nbsp; / &nbsp;
    <a href="#获取代码">快速开始</a> · <a href="#平台接入">SDK 指南</a>
  </p>
</div>

| 功能 | 说明 |
|---|---|
| 🔒 **离线与隐私** | 在本地处理人脸数据，无需将图像或人脸特征上传至云端。 |
| 🎯 **完整人脸功能** | 支持人脸检测、特征提取、活体检测、1:1 验证及 1:N/M:N 搜索。 |
| ⚡ **实时处理** | 支持实时相机视频流中的人脸检测、验证与搜索。 |
| 🌍 **跨平台支持** | 提供 Android、iOS、HarmonyOS、Windows 和 Linux SDK。 |
| 🧩 **便捷接入** | 通过 SDK API、接入指南和可自定义的 Demo 快速开始开发。 |

<details>
  <summary><strong>展开产品概览与应用场景</strong></summary>
  <p align="center"><img src="images/AboutHelloFace.png" alt="HelloFace 产品概览与应用场景" width="100%"></p>
</details>

## 平台接入

| 平台 | 环境 | 接入说明 |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7 · JDK 17 · SDK 36 | [Demo](platforms/Android/README.zh-CN.md) · [SDK](platforms/Android/docs/SDK.zh-CN.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](platforms/iOS/README.zh-CN.md) · [SDK](platforms/iOS/SDK/API.zh-CN.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](platforms/Harmony/README.zh-CN.md) · [SDK](platforms/Harmony/SDK.zh-CN.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](platforms/Linux/README.zh-CN.md) · [SDK](platforms/Linux/runtimes/x86_64/sdk/README.zh-CN.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](platforms/Windows/README.zh-CN.md) · [SDK](platforms/Windows/sdk/README.zh-CN.md) |
| Web 人脸录入 | 浏览器 | [在线体验](https://hiface-mdp.pages.dev/face/) |

**更多平台（计划）：** 将支持微信小程序、ChromeOS、uni-app、Flutter 插件、React Native（RN）插件等。

## 获取代码

本仓库使用 Git LFS 管理 SDK 二进制等大文件，若只需默认分支的最新提交，建议使用浅克隆以跳过历史提交：

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## 部署须知

- 各平台Demo UI仅供演示SDK，你可以自由定制你的UI交互。
- SDK正在Beta 迭代公测中，请及时升级SDK版本。
- 当前模型不支持12周岁以下儿童人脸识别，不能用于金融相关场景。
- 人脸搜索识别要求摄像头成像清晰；室外环境下，摄像头宽动态范围须大于 100 dB。
- Windows/Linux 桌面与摄像头待真机摄像头验证；移动端运行需配置自己的应用签名。

数据处理与隐私：[中文说明](docs/DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [English](docs/DATA_PROCESSING_AND_PRIVACY.md)

## 联系我们

其他平台在完善支持中，有问题请提 issues。

邮箱联系：[FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Android APK 下载</th>
    <th align="center">微信联系</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="images/AndroidAPK.png" alt="Android APK 下载二维码" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">点击或扫码下载</a>
    </td>
    <td align="center">
      <img src="images/WeChat.jpg" alt="微信二维码" width="180"><br>
      扫码联系
    </td>
  </tr>
</table>
