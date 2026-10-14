# HiFace iOS Demo 使用指南

[English](DEMO.md) | 简体中文

接口与接入要求见 [SDK 指南](SDK/README.zh-CN.md)。

## 示例代码

| 模块 | 示例入口 |
|---|---|
| 相机 | [CameraPipeline](HiFaceDemo/Camera/CameraPipeline.swift) |
| 相机流程 | [CameraDemoModel](HiFaceDemo/Camera/CameraDemoModel.swift) |
| 人脸库 | [SearchLibraryView](HiFaceDemo/Search/SearchLibraryView.swift) |

## 演示数据

`features_10000.json` 提供 1 万条离线特征；`images_1000.json` 提供 1 千张网络图片地址。它们不进入 `HiFace.framework` 或 XCFramework/SPM 包。

导入时返回可选择继续或停止。停止后保存已完成数据，并显示保存和失败数量；单张图片失败跳过，写库失败保留此前保存的数据。

1:1 基准使用 Keychain 保存。 SDK 人脸库使用未加密的 SQLite，HF1 是特征编码。上线前替换测试数据，并实现业务的数据保护和删除策略。
