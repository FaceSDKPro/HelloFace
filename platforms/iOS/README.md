# HiFace iOS Integration Demo

English | [简体中文](README.zh-CN.md)

SDK: **0.0.1 Beta**

On-device detection, capture, liveness, 1:1 comparison, 1:N/M:N search and face-library management.

**Model scope: The current SDK model does not yet support face recognition for minors (children). If your application requires it, [contact the author](https://github.com/FaceSDKPro/HelloFace/issues) to replace or update the model before use.**

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

Use `HiFaceSDK()` with its default model bundle. Add `NSCameraUsageDescription` to your App Info.plist.

Guides: [SDK](SDK/README.md) · [Demo](DEMO.md).

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. [Updates](https://github.com/FaceSDKPro/).
