# HiFace iOS 0.0.1

首个 iOS SDK 版本，最低 iOS 15，Swift 6，采用 SPM 二进制分发。

- 提供检测、五点/可选 Face Mesh 与头姿、HF1 特征提取、引导采集、动作/静默活体、动态及静态 1:1。
- 提供 SQLite 人脸库、单次特征查询及连续单人/多人搜索；连续搜索使用 `FaceSearchSessionConfiguration`。
- 相机流程共用互斥槽，支持请求取消和幂等关闭；相机回调在 `MainActor` 交付。
- 打包 `HiFace.xcframework` 和 `HiFaceNative.xcframework`，包含 device arm64 与 simulator arm64/x86_64。
- SDK 包内包含 BPHFM1/HFM2 密文模型和隐私清单，保留公开 Swift interface，内部崩溃符号单独存档。
- Demo 搜索相机支持固定采集帧率的回退，通过送帧节流实现 15/5 FPS 分析目标。
- Demo 使用 SDK 自带的 Framework 模型，不再覆盖为 App Bundle 路径；模型文件读取失败统一返回 `modelLoadFailed`。
- Native 打包读取 CMake 当前目标路径，防止目录重组后误选旧 Framework 缓存；Demo 版本统一为 0.0.1。
- 公开 API 已冻结，并验证既有集成示例对更新后二进制 SDK 的编译兼容。

限制：首版 CPU 推理；宿主负责相机、权限和 UI；多人搜索不支持静默活体；人脸库未加密。
当前 0.0.1 Beta 可使用至北京时间 2026-12-25 全天，2026-12-26 零点起停止初始化和工作；
客户绑定和撤销机制尚未提供。真实性、识别精度和设备性能以目标场景的验收记录为准。
