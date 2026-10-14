# HiFace HarmonyOS Integration Demo

English | [简体中文](README.zh-CN.md)

SDK: **0.0.1 Beta**

On-device detection, capture, liveness, 1:1 comparison, 1:N/M:N search and face-library management.

**Model scope: The current SDK model does not yet support face recognition for minors (children). If your application requires it, [contact the author](https://github.com/FaceSDKPro/HelloFace/issues) to replace or update the model before use.**

## Run

1. Open this directory in DevEco Studio 26 and sync dependencies.
2. Configure your bundle name, signing certificate and device profile.
3. Run `demo` on an API 20+ arm64 phone. Phones require a signed HAP.

## Project

| Path | Purpose |
|---|---|
| `demo/` | Editable ArkTS examples |
| `libs/hiface-0.0.1.har` | Binary SDK |
| `AppScope/`, `hvigor/` | Required App and build configuration |

Models are embedded in the HAR. Await `whenReady()` before using the SDK.

Guides: [SDK](SDK.md) · [Demo](demo/README.md).

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. [Updates](https://github.com/FaceSDKPro/).
