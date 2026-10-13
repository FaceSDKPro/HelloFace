# HiFace iOS Integration Demo

English | [简体中文](README.zh-CN.md)

SDK: **0.0.1 Beta** · Bundle ID: `com.hiface.sdk.public`

On-device detection, capture, liveness, 1:1 comparison, 1:N/M:N search and face-library management.

## Run

1. Open `HiFaceDemo.xcodeproj` in Xcode and select `HiFaceDemo`.
2. Set your Team and bundle ID in Signing & Capabilities.
3. Run on an iOS 15+ iPhone and allow camera access.

Simulators and My Mac support UI/build checks. Validate camera behavior and performance on iPhone.

## Project

| Path | Purpose |
|---|---|
| `HiFaceDemo/` | Editable SwiftUI / AVFoundation examples |
| `SDK/` | Binary SPM; retain both HiFace and HiFaceNative targets |
| `export-info.json` | SDK version and dependency details |

Use the default models in `HiFaceSDK()`. Keep the complete Info.plist when adding permissions; do not replace it with a permissions-only file.

Guides: [SDK English](SDK/README.md) · [SDK 中文](SDK/README.zh-CN.md) · [Demo English](DEMO.md) · [Demo 中文](DEMO.zh-CN.md).

## Languages and data

System regions CN/HK/MO/TW use Simplified Chinese; all others use English. Restart after changing region. SDK diagnostics remain in Chinese.

Back during import offers continue or stop. Stop saves the completed tail batch, then reports saved/failed counts. Database errors keep earlier saved batches.

Replace sample identities, URLs and features before production. Demo 1:1 references use Keychain. HF1 is encoding; SDK SQLite is not encrypted. Protect and delete data in your App.

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. Retain licenses/notices and validate flows/lifecycle on target phones. [Updates and details](https://github.com/FaceSDKPro/).
