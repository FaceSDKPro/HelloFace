[English](DEMO.md) | **简体中文**

# HiFace Android Demo 使用指南


接口与接入要求见 [SDK API](SDK.zh-CN.md)。

人脸识别页的 1:1 验证与独立活体检测默认开启动作活体，预选“眨眼、点头”，可手动关闭或修改动作。

相机验证和独立活体使用系统文字转语音播报正脸与动作提示。Demo 提供英文（`en-US`）和中文（`zh-CN`）提示，能否播报取决于设备是否有匹配的语音。提示文字相同则继续当前播报，提示变化时切换到新播报。屏幕会持续显示相机引导。

## 1:1 参考录入

在人脸识别页选择有序动作与 1:1 静默活体开关后再进入相机。左右滑动已录入人员的头像列表，点击 Face ID 直接验证。独立活体始终执行静默检测，可叠加动作。验证与活体结果返回本页展示，不再弹出结果对话框。确认采集后保存私有头像，只有特征的旧参考记录显示占位头像。点击「相册添加」直接打开系统相册，点击「相机录入」进入引导采集。所选照片须恰好检测到一张人脸。两种方式共用确认框，核对对齐头像并确认 Face ID 后才保存。

[FaceRecognitionActivity](../demo/src/main/java/com/hiface/sdk/demo/recognition/FaceRecognitionActivity.java) 打开相册并调用 SDK 提取照片中的人脸。[CameraFlowActivity](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraFlowActivity.java) 检查相机是否就绪，并在页面停止时取消请求。两种参考录入方式都通过 [ReferenceConfirmation](../demo/src/main/java/com/hiface/sdk/demo/verification/ReferenceConfirmation.java) 保存特征，并尝试保存对齐头像。

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
