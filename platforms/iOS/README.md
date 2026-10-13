# HiFace iOS 集成 Demo

SDK 版本：0.0.1。此导出使用本地编译产物。正式交付前请替换为验收、签名后的发布产物。
Demo Bundle Identifier：`com.hiface.sdk.public`。

本工程演示实时检测、人脸采集、活体检测、动态/静态 1:1 比对以及 1:N/M:N 人脸搜索。
Demo 负责相机、权限、页面和示例数据；算法、流程状态机和搜索库能力由二进制 SDK 提供。

## 运行

1. 使用 Xcode 打开 `HiFaceDemo.xcodeproj`，选择 `HiFaceDemo` Scheme。
2. 在 Signing & Capabilities 中设置自己的 Team 和唯一 Bundle Identifier。
3. 选择已解锁的 iPhone 并运行。支持 iOS 15+；相机和性能必须在真机验收。

模拟器只适合检查编译、导航和不依赖真实相机的页面。工程的 `Info.plist` 已包含相机用途说明，
请基于它补充业务权限，不要用只含权限文案的 plist 整体覆盖。

## 工程内容

- `HiFaceDemo/`：可修改的 SwiftUI/AVFoundation 示例源码。
- `SDK/`：二进制 SPM Package 和 SDK 文档，不包含 SDK/Core 源码。
- `export-info.json`：本次导出的 SDK 版本与依赖方式。

`HiFace` 与 `HiFaceNative` 两个 XCFramework 共同组成 SDK 产品，不能只保留其中一个。
密文模型和隐私清单由 `HiFace.framework` 自带。请使用 `HiFaceSDK()` 默认配置，不要改为
`Bundle.main/HiFaceModels`，否则会出现 `kcehc.bphfm` 等模型找不到。公开 API、许可和版本变化见
[`SDK/README.md`](SDK/README.md)、[`SDK/LICENSING.md`](SDK/LICENSING.md) 和
[`SDK/CHANGELOG.md`](SDK/CHANGELOG.md)。

完整使用与示例指南见 [DEMO.md](DEMO.md)，SDK 开发维护文档不随工程交付。

## 接入要点

- 相机和送帧代码位于 `HiFaceDemo/Camera/`，使用带色彩矩阵的双平面 NV12（`420v` / `420f`）。
- `processFrame` 同步借用 `CVPixelBuffer`；调用返回前不能复用缓冲区。`.notReady` 时丢弃当前帧并继续送入最新帧。
- SDK 返回旋转后、未镜像的像素坐标。宿主按预览缩放/裁剪映射，并只在 Overlay 层处理一次前摄镜像。
- 相机真正出帧后再启动采集、活体、验证或搜索。离开页面、进入后台和切摄前取消请求或关闭 Session。
- 可在送入 SDK 前自行读取帧；跨异步边界使用时先复制业务所需数据。

主要示例入口：

| 能力 | 文件 |
| --- | --- |
| 首页与导航 | `HiFaceDemo/App/DemoHomeView.swift` |
| 相机、帧和流程 | `HiFaceDemo/Camera/CameraPipeline.swift`、`CameraDemoModel.swift` |
| 实时检测 | `HiFaceDemo/Detection/FaceDetectionView.swift` |
| 人脸采集与活体 | `HiFaceDemo/Capture/FaceCaptureView.swift`、`Liveness/FaceLivenessView.swift` |
| 动态/静态 1:1 | `HiFaceDemo/Verification/FaceVerificationView.swift`、`Comparison/StaticFaceComparisonView.swift` |
| 搜索与人脸库 | `HiFaceDemo/Search/FaceSearchView.swift`、`SearchLibraryView.swift` |

首页只创建导航入口；相机页的 SDK 由 `CameraDemoModel` 持有，静态 1:1 由
`StaticFaceComparisonModel` 持有。各能力退出时取消在途任务，业务容器销毁时关闭 SDK。

## 上线前处理

`HiFaceDemo/Resources/FaceSearch/` 内的 JSON 只用于演示，不进入 SDK。上线前替换演示图片 URL、
特征和测试身份，并实现业务需要的用户同意、访问控制、数据保留与删除策略。人脸图片、HF1 特征、
搜索结果和密钥不应写入普通日志或分析平台。

当前测试版到北京时间 2026-12-25 全天可用，12-26 零点起停止初始化和工作并记录升级提示。
商业使用和示例源码使用范围按正式协议确认。
SDK 搜索库使用普通 SQLite，HF1 是特征编码；宿主负责数据保护。工作区有修改的导出不能作为正式发布证据。

请在目标 iPhone 验证首次授权、拒绝后恢复、四方向、前后台、系统中断、连续切摄、全部能力流程、
长时间内存、帧率、温升和耗电，再把 Demo 改造成业务页面。

本次更新：2026-10-13，SDK / Demo 均为 0.0.1 Beta。应用标识为 com.hiface.sdk.public，桌面名称为 HiFace演示。
独立 Release 工程构建和公开 API 兼容检查已通过；签名由接入方配置，真机相机、活体和长期性能仍需目标设备验收。
