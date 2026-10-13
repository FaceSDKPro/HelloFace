# HiFace HarmonyOS 集成 Demo

Demo 的应用标识为 `com.hiface.sdk.public`。

SDK 版本：0.0.1，以 `libs/hiface-0.0.1.har` 交付。
本工程演示实时检测、人脸采集、活体检测、动态/静态 1:1 比对以及 1:N/M:N 人脸搜索。
Demo 负责 CameraKit、权限、页面和示例数据；算法、流程状态机和搜索库能力由 HAR 提供。

## 运行

1. 使用 DevEco Studio 26 打开本目录并同步 ohpm 依赖。
2. 配置自己的 App Bundle Name 和 HAP 签名；本工程不含开发者签名材料。
3. 选择 `demo` 模块并部署到 arm64 真机。App 最低兼容 API 20。

API 26 x86_64 模拟器只适合安装、ArkTS 和 N-API 冒烟。CameraKit、活体、方向、切摄、性能和功耗
必须在真机验收。

## 工程内容

- `demo/src/main/ets/`：可修改的 ArkTS 示例源码。
- `libs/hiface-0.0.1.har`：版本化 Release SDK，不包含 SDK/Core 源码。
- `AppScope/`：Demo 的 Bundle Name、版本、应用名称和图标，打包时保留并按业务修改。
- `hvigor/`：构建配置，需保留；与可清理的 `.hvigor/` 构建缓存不同。
- `export-info.json`：SDK 版本、HAR SHA-256、模型和发布校验状态。

`oh_modules/` 和 `demo/oh_modules/` 是同步后生成的依赖目录，不随 Demo 交付；清理后使用 DevEco
Sync 或在工程根目录执行 `ohpm install --all` 恢复。`.hvigor/` 和模块内 `build/` 也可清理后重建。

SDK 名称与 import 保持 `hiface`，密文模型由 HAR 内 Native 库自带，不需要配置模型目录。
应用初始化时复用一个 `HiFaceSdk`，并等待 `whenReady()` 成功；页面退出前取消流程或关闭搜索 Session，
业务容器销毁时调用 `close()`。

完整使用与示例指南见 [demo/README.md](demo/README.md)，公开 API 见 [SDK.md](SDK.md)。
SDK 开发维护文档不随客户工程交付。

## 接入要点

- 相机代码位于 `demo/src/main/ets/camera/`。HAR 不申请权限，也不创建 CameraKit 会话。
- 每条相机链使用一个 `FaceRealtimeProcessor`；忙时丢弃当前帧，不能建立无界 Promise 队列。
- CameraKit `Image` 释放前复制所需 YUV 平面，并保留副本到 SDK Promise 完成。
- SDK 返回旋转后、未镜像的像素坐标。宿主按预览缩放/裁剪映射，并只在 Overlay 层处理一次前摄镜像。
- ArkUI 子组件用普通字段或 `@Require` 传 SDK/句柄，不要使用会复制状态的 `@Prop`。
- 可在送入 SDK 前自行分析已复制的帧数据，不能跨异步边界持有已释放的 CameraKit `Image`。

主要示例入口：

| 能力 | 文件 |
| --- | --- |
| SDK 所有权与首页 | `demo/src/main/ets/pages/Index.ets` |
| 实时相机与流程 | `demo/src/main/ets/pages/RealtimeCameraDemo.ets` |
| CameraKit 适配 | `demo/src/main/ets/camera/CameraPreviewController.ets` |
| 静态 1:1 | `demo/src/main/ets/comparison/StaticFaceComparisonDemo.ets` |
| 搜索库管理 | `demo/src/main/ets/search/FaceSearchLibraryDemo.ets` |

## 上线前处理

`demo/src/main/resources/rawfile/face_search/` 内的 JSON 只用于演示，不进入 `hiface` HAR。上线前替换
演示图片 URL、特征和测试身份，并实现用户同意、访问控制、搜索库保护、数据保留与删除策略。
人脸图片、HF1 特征、搜索结果和密钥不应写入普通日志或分析平台。

当前测试版到北京时间 2026-12-25 全天可用，12-26 零点起停止初始化和工作并记录升级提示。
商业使用和示例源码使用范围按正式协议确认。
SDK 搜索库使用普通 SQLite，HF1 是特征编码；工作区有修改的导出不能作为正式发布证据。

请核对正式 HAR 的版本与 SHA-256，并在目标 API 设备验证权限拒绝恢复、前后台、连续切页、切摄、
全部能力流程、长时间内存、帧率、温升和耗电，再把 Demo 改造成业务页面。

本次更新：2026-10-13，SDK / Demo 均为 0.0.1 Beta。三端公开 API 兼容检查与独立 Release 工程编译已通过；
App 签名由接入方配置，真机相机、活体和长期性能仍需在目标设备验收。
