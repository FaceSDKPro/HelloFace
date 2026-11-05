<p align="left">
  <img src="images/technology-badges.svg" alt="On-device · Native SDKs · 5 platforms" width="382" height="20">
</p>

<div align="center">
  <h1>
    <a href="https://www.helloface.dev/">
      <img src="images/hello-face-icon.webp" alt="" width="64" height="64">
      <img src="images/helloface-wordmark.svg" alt="HelloFace" width="170" height="64">
    </a>
  </h1>
  <p><strong>Offline face detection, capture, liveness, 1:1 verification and 1:N/M:N search.</strong></p>
  <p><strong>0.8.6 Beta</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a></p>
  <p>
    <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
    &nbsp; / &nbsp;
    <a href="#get-the-code">Quick start</a> · <a href="#platforms">SDK guides</a>
  </p>
</div>

<table>
  <tr>
    <th align="left" nowrap>Capability</th>
    <th align="left">Description</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Offline &amp; Private</strong></td>
    <td align="left">Process face data locally, without uploading images or face features to the cloud.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Face Toolkit</strong></td>
    <td align="left">Face detection, feature extraction, liveness detection, 1:1 verification, and 1:N/M:N search.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Real-Time Processing</strong></td>
    <td align="left">Live face detection, verification, and search.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Cross-Platform Support</strong></td>
    <td align="left">Android · iOS · HarmonyOS · Windows · Linux.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Easy Integration</strong></td>
    <td align="left">Get started with SDK APIs, integration guides, and customizable demos.</td>
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
