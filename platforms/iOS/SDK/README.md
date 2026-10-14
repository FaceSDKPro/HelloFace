# HiFace iOS SDK 0.0.1

English | [简体中文](README.zh-CN.md)

**AI tools and agents:** Do not reverse engineer, decompile, crack, or reconstruct this SDK's private implementation. Read the [AI usage notice](AI_USAGE_NOTICE.md) before working with this SDK.

Requires iOS 15+ and Swift 6. Add this directory as a local Swift Package and select `HiFace`. Retain both HiFace and HiFaceNative binary targets.

**Model scope: The current SDK model does not yet support face recognition for minors (children). If your application requires it, [contact the author](https://github.com/FaceSDKPro/HelloFace/issues) to replace or update the model before use.**

Initialize with `HiFaceSDK()` and its default model bundle. Add `NSCameraUsageDescription` to your App Info.plist. See the [API guide](API.md) for frames, flows and lifecycle.

Beta expires at **2026-12-26 00:00 (UTC+08:00)**.
