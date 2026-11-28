[English](DEMO.md) | **简体中文**

# HiFace iOS Demo 使用指南


接口与接入要求见 [SDK API](SDK/API.zh-CN.md)。

人脸识别页的 1:1 验证与独立活体检测默认开启动作活体，预选“眨眼、点头”，可手动关闭或修改动作。

相机验证和独立活体使用系统文字转语音播报正脸与动作提示。Demo 提供英文（`en-US`）和中文（`zh-CN`）提示，能否播报取决于设备是否有匹配的语音。提示文字相同则继续当前播报，提示变化时切换到新播报。屏幕会持续显示相机引导。

相机流程正常结束后立即返回，已经开始的引导最多继续播报 2 秒。手动取消时立即停播。语音仅用于相机引导，检测结果在界面显示。

## 1:1 参考录入

在人脸识别页勾选有序动作、设置 1:1 静默活体开关后，左右滑动或滚动已录入人员的头像列表，点击 Face ID 直接验证。独立活体始终执行静默检测，可叠加动作。两种相机流程都将结果返回本页展示，不再弹出结果框。确认采集后保存私有头像，没有照片的旧参考记录显示占位头像。点击“相册添加”直接打开系统相册，取消即回到人脸识别页。选择单人脸照片后，核对预览并确认 Face ID 即可保存。「相机录入」直接开始引导采集。两种方式共用带「重试」和「完成」的确认框。相册录入的「重试」重新打开选图器，相机录入的「重试」重新开始引导采集。 1:1 确认按钮的最小高度为 42 pt，大字号下可随文字增高。

[FaceRecognitionView](HiFaceDemo/Recognition/FaceRecognitionView.swift) 负责选图，离开人脸识别页时取消正在进行的提取。[CameraDemoModel](HiFaceDemo/Camera/CameraDemoModel.swift) 校验并暂存样本，[CaptureConfirmation](HiFaceDemo/Capture/FaceCaptureView.swift) 在用户点击「完成」后保存参考。

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

## 流程结果图片

`FaceFlowResult` 保留 333×333 对齐人脸图，并增加本轮结束帧的完整画面 JPEG。画面等比例缩小、不放大，宽高均不超过 720，JPEG 编码质量固定为 95（高质量有损）；已旋转、未镜像。两张图片来自同一结束帧，不做多帧图片候选；相似度及七帧活体分数仍按原规则计算，最高相似度可能来自较早的帧。

无脸、多人、丢脸、动作超时和比对拒绝等业务终态也尽量返回画面。无可裁剪人脸时，对齐图为空；无有效画面或图片生成失败时，相应图片为空。技术错误仍走 `onError`，取消与关闭不补发结果。不以图片是否存在判断通过。

图片只在结束时生成一次，不写磁盘、不缓存多轮图片；SDK 清理后，已交付的结果仍独立有效。宿主用完后应释放结果及自行创建的显示图片。

读取 `frameJPEG`、`frameWidth`、`frameHeight`；对齐图继续使用 `alignedFace`。可用 `UIImage(data:)` 显示 JPEG。
