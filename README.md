<div align="center">
  <p><samp>ON-DEVICE FACE AI</samp></p>
  <h1>HelloFace</h1>
  <p>Offline face detection, capture, liveness, 1:1 verification and 1:N/M:N search.</p>
  <p><strong>0.8.6 Beta</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a></p>
  <p>
    <img src="https://img.shields.io/badge/COMPUTE-ON--DEVICE-06B6D4?style=flat-square&amp;labelColor=0B1220" alt="Compute: on-device">
    <img src="https://img.shields.io/badge/SDK-NATIVE-3B82F6?style=flat-square&amp;labelColor=0B1220" alt="SDK: native">
    <img src="https://img.shields.io/badge/PLATFORMS-5-8B5CF6?style=flat-square&amp;labelColor=0B1220" alt="Platforms: 5">
  </p>
  <p>
    <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
    &nbsp; / &nbsp;
    <a href="#get-the-code">Quick start</a> · <a href="#platforms">SDK guides</a>
  </p>
</div>

<table width="100%">
  <tr>
    <td colspan="2" align="center">
      <h3>🔒 Offline &amp; Private</h3>
      <p>Process face data locally, without uploading images or face features to the cloud.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🎯 Complete Face Toolkit</h3>
      <p>Face detection, feature extraction, liveness detection, 1:1 verification, and 1:N/M:N search.</p>
    </td>
    <td width="50%" valign="top">
      <h3>⚡ Real-Time Processing</h3>
      <p>Detect, verify, and search faces in live camera streams.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🌍 Cross-Platform Support</h3>
      <p>SDKs for Android, iOS, HarmonyOS, Windows, and Linux.</p>
    </td>
    <td width="50%" valign="top">
      <h3>🧩 Easy Integration</h3>
      <p>Get started with SDK APIs, integration guides, and customizable demos.</p>
    </td>
  </tr>
</table>

<details>
  <summary><strong>Explore the product overview</strong></summary>
  <p align="center"><img src="images/AboutHelloFace-EN.png" alt="HelloFace product overview and application scenarios" width="100%"></p>
</details>

## Platforms

| Platform | Requirements | Integration |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7 · JDK 17 · SDK 36 | [Demo](platforms/Android/README.md) · [SDK](platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](platforms/iOS/README.md) · [SDK](platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](platforms/Harmony/README.md) · [SDK](platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](platforms/Linux/README.md) · [SDK](platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](platforms/Windows/README.md) · [SDK](platforms/Windows/sdk/README.md) |
| Web Face Enrollment | Browser | [Try online](https://hiface-mdp.pages.dev/face/) |

**More platforms (planned):** WeChat Mini Programs, ChromeOS, uni-app, Flutter plugins, React Native (RN) plugins, and more.

## Get the code

This repository uses Git LFS to manage large files such as SDK binaries. If you only need the latest commit from the default branch, use a shallow clone to skip the commit history:

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## Before you deploy

- The Demo UI on each platform is for SDK demonstration only; you can freely customize the UI and interactions.
- The SDK is in iterative public Beta testing. Please keep the SDK version up to date.
- The current model does not support face recognition for people under 12 and must not be used in financial scenarios.
- Face search requires clear camera images; outdoor deployments require a camera with a wide dynamic range greater than 100 dB.
- Windows/Linux desktop and camera workflows await testing with real cameras; mobile apps require your own application signing.

Data processing and privacy: [English](docs/DATA_PROCESSING_AND_PRIVACY.md) · [中文说明](docs/DATA_PROCESSING_AND_PRIVACY.zh-CN.md)

## Connect

Support for other platforms is being improved. If you encounter a problem, please open an issue.

Email: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Download Android APK</th>
    <th align="center">WeChat contact</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="images/AndroidAPK.png" alt="Android APK download QR code" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">Click or scan to download</a>
    </td>
    <td align="center">
      <img src="images/WeChat.jpg" alt="WeChat QR code" width="180"><br>
      Scan to contact
    </td>
  </tr>
</table>
