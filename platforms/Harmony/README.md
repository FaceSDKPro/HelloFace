# HiFace HarmonyOS Integration Demo

English | [简体中文](README.zh-CN.md)

SDK: **0.0.1 Beta** · Bundle ID: `com.hiface.sdk.public`

On-device detection, capture, liveness, 1:1 comparison, 1:N/M:N search and face-library management.

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
| `export-info.json` | SDK version, dependency and integrity details |

`oh_modules/`, `.hvigor/` and `build/` can be regenerated. Models are embedded. Reuse `HiFaceSdk` and await `whenReady()`. Cancel flows or close search sessions before leaving pages.

Guides: [SDK English](SDK.md) · [SDK 中文](SDK.zh-CN.md) · [Demo English](demo/README.md) · [Demo 中文](demo/README.zh-CN.md).

## Languages and data

System regions CN/HK/MO/TW use Simplified Chinese; all others use English. Restart after changing region. SDK diagnostics remain in Chinese.

Back during import offers continue or stop. Stop saves the completed tail batch, then reports saved/failed counts. Database errors keep earlier saved batches.

Replace sample identities, URLs and features before production. HF1 is encoding; SDK SQLite is not encrypted. Protect and delete data in your App, and keep signing credentials private.

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. Retain licenses/notices and validate flows/lifecycle on target phones. [Updates and details](https://github.com/FaceSDKPro/).
