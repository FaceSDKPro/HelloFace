# HiFace HarmonyOS Demo 使用指南

[English](README.md) | 简体中文

接口与接入要求见 [SDK 指南](../SDK.zh-CN.md)。

## 示例代码

| 模块 | 示例入口 |
|---|---|
| 导航 | [Index](src/main/ets/pages/Index.ets) |
| 相机 | [CameraPreviewController](src/main/ets/camera/CameraPreviewController.ets) |
| 相机流程 | [RealtimeCameraDemo](src/main/ets/pages/RealtimeCameraDemo.ets) |
| 人脸库 | [FaceSearchLibraryDemo](src/main/ets/search/FaceSearchLibraryDemo.ets) |

## 演示数据

`features_10000.json` 提供 1 万条离线特征；`images_1000.json` 提供 1 千张网络图片地址。它们不进入 `hiface` HAR。

导入时返回可选择继续或停止。停止后保存已完成数据，并显示保存和失败数量；单张图片失败跳过，写库失败保留此前保存的数据。

1:1 基准使用 HUKS 加密文件保存。 SDK 人脸库使用未加密的 SQLite，HF1 是特征编码。上线前替换测试数据，并实现业务的数据保护和删除策略。
