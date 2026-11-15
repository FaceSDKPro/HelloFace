# HiFace Android Demo 使用指南

[English](DEMO.md) | 简体中文

接口与接入要求见 [SDK 指南](SDK.zh-CN.md)。

## 示例代码

| 模块 | 示例入口 |
|---|---|
| 相机 | [CameraPreviewFragment](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java) |
| 搜索 | [FaceSearchActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchActivity.java) |
| 人脸库 | [FaceSearchLibraryActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchLibraryActivity.java) |

## 演示数据

`features_10000.json` 提供 1 万条离线特征；`images_1000.json` 提供 1 千张网络图片地址。它们不进入 SDK AAR。

导入时返回可选择继续或停止。停止后保存已完成数据，并显示保存和失败数量；单张图片失败跳过，写库失败保留此前保存的数据。

1:1 基准使用 MMKV 保存；业务接入时替换固定演示密钥。 SDK 人脸库使用未加密的 SQLite，HF1 是特征编码。上线前替换测试数据，并实现业务的数据保护和删除策略。

## 流程结果图片

`FaceFlowResult` 保留 333×333 对齐人脸图，并增加本轮结束帧的完整画面 JPEG。画面等比例缩小、不放大，宽高均不超过 720，JPEG 编码质量固定为 95（高质量有损）；已旋转、未镜像。两张图片来自同一结束帧，不做多帧图片候选；相似度及七帧活体分数仍按原规则计算，最高相似度可能来自较早的帧。

无脸、多人、丢脸、动作超时和比对拒绝等业务终态也尽量返回画面。无可裁剪人脸时，对齐图为空；无有效画面或图片生成失败时，相应图片为空。技术错误仍走 `onError`，取消与关闭不补发结果。不以图片是否存在判断通过。

图片只在结束时生成一次，不写磁盘、不缓存多轮图片；SDK 清理后，已交付的结果仍独立有效。宿主用完后应释放结果及自行创建的显示图片。

读取 `getFrameJpeg()`、`getFrameWidth()`、`getFrameHeight()`；对齐图继续使用 `getAlignedFace()`。`getFrameJpeg()` 每次返回独立字节副本。
