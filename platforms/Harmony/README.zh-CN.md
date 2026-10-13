# HiFace HarmonyOS 集成 Demo

[English](README.md) | 简体中文

SDK：**0.0.1 Beta** · Bundle Name：`com.hiface.sdk.public`

支持检测、采集、活体、1:1 比对、1:N/M:N 搜索和人脸库管理，算法在设备端运行。

## 运行

1. 用 DevEco Studio 26 打开本目录并同步依赖。
2. 配置自己的 Bundle Name、签名证书和设备 Profile。
3. 在 API 20+ 的 arm64 手机运行 `demo`。未签名 HAP 无法安装到手机。

## 工程

| 目录 | 用途 |
|---|---|
| `demo/` | 可修改的 ArkTS 示例 |
| `libs/hiface-0.0.1.har` | SDK 二进制 |
| `AppScope/`、`hvigor/` | 应用信息和构建配置，需保留 |
| `export-info.json` | SDK 版本、依赖和校验信息 |

`oh_modules/`、`.hvigor/` 和 `build/` 可清理后重建。模型已内置；复用 `HiFaceSdk` 并等待 `whenReady()`。关闭页面前取消流程或关闭搜索会话。

接入说明：[SDK 中文](SDK.zh-CN.md) · [SDK English](SDK.md) · [Demo 中文](demo/README.zh-CN.md) · [Demo English](demo/README.md)。

## 语言与数据

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启。SDK 诊断保持中文。

导入时返回可继续或停止。停止后保存已完成的尾批，再显示已保存和失败数量；写库失败保留此前已保存的批次。

上线前替换测试身份、图片地址和特征。HF1 是编码，SDK SQLite 未加密；宿主负责数据保护与删除，签名材料需保密。

Beta 于 **2026-12-26 00:00（北京时间）** 到期。保留许可与第三方声明，在目标手机验证各功能和生命周期。[更新与说明](https://github.com/FaceSDKPro/)。
