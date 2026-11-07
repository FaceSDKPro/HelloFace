<h3 align="left">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a> · <a href="docs/readme/README.es.md">Español</a> · <a href="docs/readme/README.pt-BR.md">Português (Brasil)</a><br>
  <a href="docs/readme/README.fr.md">Français</a> · <a href="docs/readme/README.de.md">Deutsch</a> · <a href="docs/readme/README.ja.md">日本語</a> · <a href="docs/readme/README.ko.md">한국어</a> · <a href="docs/readme/README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="images/technology-badges.svg" alt="On-device · Native SDKs · 5 platforms" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.8 Beta</strong>
  </p>
  <p><strong>Offline face detection, capture, liveness, 1:1 verification and 1:N/M:N search.</strong></p>
  <p>🌍 <strong>Official Website</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>GitHub Integration Code</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>Capability</th>
    <th align="left">Description</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Offline &amp; Private</strong></td>
    <td align="left">Process face data locally, without uploading images or face features to the cloud. <a href="docs/privacy/DATA_PROCESSING_AND_PRIVACY.md"><strong>More</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Face Toolkit</strong></td>
    <td align="left">Face detection, feature extraction, liveness detection, 1:1 verification, and 1:N/M:N search.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Cross-Platform Support</strong></td>
    <td align="left">Supports Android · iOS · HarmonyOS · Windows · Linux. Stay tuned for more platforms, or <a href="https://github.com/FaceSDKPro/HelloFace/issues">open an issue</a> to describe your needs.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Easy Integration</strong></td>
    <td align="left">Get started with SDK APIs, integration guides, and customizable demos.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Real-Time Processing</strong></td>
    <td align="left">Real-time face detection, verification, and search in milliseconds.</td>
  </tr>
</table>

<details>
  <summary><strong>Explore the product overview</strong></summary>
  <p align="center"><img src="images/AboutHelloFace-EN.png" alt="HelloFace product overview and application scenarios" width="100%"></p>
</details>

## Platforms

| Platform | Requirements | Integration |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7/X86 · JDK 11 | [Demo](platforms/Android/README.md) · [SDK](platforms/Android/docs/SDK.md) |
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
