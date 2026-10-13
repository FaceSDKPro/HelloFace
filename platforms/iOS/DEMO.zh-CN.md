[English](DEMO.md) | 简体中文

# HiFace iOS SDK 使用与 Demo 指南

开发 Demo 的应用标识为 `com.hiface.sdk.public`。

<!-- SDK-USER-GUIDE:BEGIN -->
## 支持与安装

当前为内测 Beta 版；北京时间 2026-12-26 零点起停止初始化和工作。
到期日志为“请升级SDK，详情见https://github.com/FaceSDKPro/”。

| 项目 | 当前范围 |
|---|---|
| 最低系统 | iOS 15 |
| ABI | 真机 `arm64`；模拟器 `arm64`、`x86_64` |
| 入口 | Swift `HiFaceSDK` |

业务 App 在 Xcode 添加已发布的二进制 SPM 仓库和固定版本，选择 `HiFace` product；
保留 `HiFace`、`HiFaceNative` 两个 binary targets。在 Info.plist 配置 `NSCameraUsageDescription`。

```swift
import HiFace
let sdk = HiFaceSDK()
```

## 实时检测

SDK 仅接受带 BT.601 或 BT.709 matrix attachment 的 `420v` / `420f` 双平面 NV12：

```swift
let frame = try HiFaceCameraFrame(
    pixelBuffer: pixelBuffer,
    rotation: .degrees90,
    isMirrored: usingFrontCamera
)

let result = sdk.processFrame(
    frame,
    configuration: try FaceDetectionConfiguration(
        maxFaces: 5,
        includesDetailedLandmarks: true
    )
)
```

`processFrame` 是同步调用。SDK 只在调用期间借用并锁定 `CVPixelBuffer`；调用返回后宿主可以复用缓冲区。
初始化、按需能力切换或 Native 正忙时返回 `.notReady`，相机循环应丢弃该帧并继续送入最新帧。

结果坐标属于旋转后、未镜像的像素空间。前摄镜像、`resizeAspect` 留边以及 Overlay 坐标变换均由宿主处理。
宿主选择相机格式时应同时满足：

```swift
HiFaceCameraFrame.maximumLongSidePixels   // 1920
HiFaceCameraFrame.maximumShortSidePixels  // 1080
```

## 静态图片与 HF1

```swift
let capture = await sdk.capture(cgImage)
let feature = await sdk.extractFeature(from: cgImage)
let similarity = await sdk.compare(feature: leftHF1, with: rightHF1)
let imageSimilarity = await sdk.compare(leftCGImage, with: rightCGImage)
```

静态入口选择图片中的最大脸。`capture` 返回 HF1 和可选 333×333 对齐预览；`extractFeature` 不生成预览。
已有 HF1 时应调用 `compare(feature:with:)`，避免重复运行检测和特征模型。

`HiFaceRGBAImage` 在初始化时复制像素，之后宿主可以修改或释放原缓冲区。每个 SDK 实例的静态图片入口
共享串行队列，最多容纳一个运行中和四个等待中的请求；继续提交返回 `.busy`，避免大尺寸 RGBA 快照
无限积压。双图比较作为一个请求执行，两张图不会与其他静态请求交错。

`CGImage` 入口不会读取 `UIImage.imageOrientation`，宿主必须先完成 EXIF 方向归一化。奇数宽高只裁掉最右列
或最下行，不缩放整张图；输入最终必须是 2...4096 范围内的偶数尺寸 RGBA8888。

## 相机采集、活体和验证

三种流程共用相机处理槽，回调统一异步交付到 `MainActor`；以下入口分别使用，一次只启动一种：

```swift
let captureRequest = sdk.startCameraCapture(
    callbacks: FaceCaptureCallbacks(
        onProgress: { progress in /* 更新引导 */ },
        onResult: { capture in /* 用户确认后保存 capture.feature */ },
        onError: { error in /* 处理技术错误 */ }
    )
)

let flowCallbacks = FaceFlowCallbacks(
    onProgress: { progress in /* 更新动作或静默活体引导 */ },
    onResult: { result in /* 根据 result.outcome 展示终态 */ },
    onError: { error in /* 处理技术错误 */ }
)

let livenessRequest = sdk.startCameraLiveness(
    configuration: try FaceLivenessConfiguration(
        actions: [.blink, .shakeHead]
    ),
    callbacks: flowCallbacks
)

let verificationRequest = sdk.startCameraVerification(
    configuration: try FaceVerificationConfiguration(
        referenceFeature: referenceHF1,
        requiresSilentLiveness: true,
        actions: [.blink, .shakeHead]
    ),
    callbacks: flowCallbacks
)
```

`onResult` 表示流程正常结束，既可能通过也可能拒绝；先检查 `FaceFlowResult.outcome`。
`livenessScore == nil` 表示本轮没有形成静默活体判定，`similarity == nil` 表示没有进入 1:1 比对，
两者都不能按 0 分解释。配置、模型、生命周期和 Native 处理失败才进入 `onError`。
静默活体由共享 Core 判定：分数大于等于 0.90 通过，小于 0.90 为 `.spoofDetected`；应用层不要重复比较。
`FaceLivenessConfiguration.hasActions == false` 只表示不执行动作挑战，七帧双模型静默活体仍会执行。
活体与 1:1 配置的默认时限、门限和最大动作数均以 `default...` / `maximumActionCount`
静态属性公开，与 Android SDK 的公开参数保持一致。

请求离开页面时应显式取消：

```swift
captureRequest.cancel()
livenessRequest.cancel()
verificationRequest.cancel()
sdk.close()
```

`cancel()` 和 `close()` 会立即禁止新回调，但不阻塞正在执行的 Native 调用。SDK 会在在途调用结束后按序释放资源。

## 人脸库与连续搜索

人脸库独立于推理 Session，所有数据库操作在 actor 上串行执行：

```swift
let database = try HiFaceSDK.openSearchDatabase()
let exists = try await database.contains(faceID: "user-1")
try await database.saveFeature(faceID: "user-1", feature: hf1, group: "staff")
try await database.saveFeatures(featureBatch)
let matches = try await database.search(feature: hf1)
let record = try await database.entry(faceID: "user-1") // record.feature 为完整原始 HF1
let metadata = try await database.recentEntries() // 不读取特征
let exportPage = try await database.featureEntries(offset: 0, limit: 100)
try await database.updateMetadata(faceID: "user-1", group: "building-A") // 保留 tag 和特征
await database.close()
```

SDK 自动使用 Application Support 下的固定私有库并排除云备份；接入方不传路径或文件名。Face ID 为
1...1024 个 UTF-8 字节，group/tag 最多 1024 个 UTF-8 字节，且都不能包含 NUL。人工新增如需提示覆盖，
先调用 `contains`；单条服务器同步使用 `saveFeature`，批量 HF1 使用每批最多 1000 条的 `saveFeatures`。
数据库直接保存 HF1 中的原始 450 字节 Q7 内容，完整查询与搜索结果原样返回 HF1 字符串。
`entries` / `recentEntries` 返回不含特征的 `FaceSearchMetadata`；`featureEntries` 用于完整特征分页导出。
`contains` 仅查主键。`updateMetadata` 的 nil 保留原字段、空串清空，至少提供 group/tag 之一。
`FaceFeatureFormat.featureSpaceID` 提供模型/预处理兼容标识，可传给 `FaceSearchFeatureEntry` 校验服务器数据。
开发期测试库不迁移，测试设备需清理旧库并重新导入。压缩与 iOS 文件保护不等同于数据库加密。

连续相机搜索自动打开、预热并关闭独立数据库连接，与采集、活体、验证流程互斥：

```swift
let search = sdk.startCameraSearch(
    configuration: .default,
    callbacks: FaceSearchCallbacks(
        onFrame: { frame in /* 更新框和当前评分 */ },
        onProgress: { progress in /* 更新引导 */ },
        onResult: { result in /* 先检查 endReason */ },
        onError: { error in /* 可修复后 resume */ }
    )
)

search.pause()
search.update(configuration: newConfiguration)
search.resume()
search.close()
```

`pause()` 保留模型、数据库连接和搜索槽位，但在 Native 队列等待在途调用结束后释放所选范围的
特征缓存；错误暂停也执行相同清理。`resume()` 在接收新帧前重新预热，不重新加载模型。
运行中的配置更新和帧几何变化继续复用同范围缓存。独立数据库的 `releaseMemory()` 可用于
后台切换或内存压力；容器归还内存不保证进程 RSS 立即下降。

`onFrame` 可只包含尚未评分的检测结果，`similarity == nil` 不表示未匹配。应用应通过 `frameID` 对应同一次采样，
并以最终 `endReason` 为准；即使身份达到门限，`.spoofDetected` 仍是拒绝结果。

无人脸待机固定启用：连续 10 秒无人脸后，Core 按 200 ms 目标节奏分析（约 5 FPS），检出人脸后恢复。
跳帧返回 `.notReady`，宿主丢弃当前帧并继续送入最新帧；
`searchIntervalMilliseconds` 仅控制匹配成功后的下一轮等待，不控制相机或无人脸检测频率。

## 生命周期和错误处理

- 创建 `HiFaceSDK` 后检测模型异步初始化；实时接口用 `.notReady` 表达可重试背压。
- 静态任务进入串行 worker；所有相机流程共享一个互斥槽，冲突时返回 `.busy`。
- `FaceFlowOutcome` 和 `FaceSearchEndReason` 是业务结论；`HiFaceErrorCode` 是技术失败，两者不要混用。
- 业务逻辑只依赖稳定的 `HiFaceError.code`；`message` 仅用于诊断，可随版本补充。
- 页面进入后台、相机中断或离开导航栈时，宿主应停止送帧并取消当前请求。
- SDK 不保存相机帧；对齐图、HF1、人脸库和业务照片的保存、加密、删除与授权由宿主决定。

<!-- SDK-USER-GUIDE:END -->

## 运行 Demo

用 Xcode 打开 `HiFaceDemo.xcodeproj`，配置自己的 Team 和 Bundle ID，在 iPhone 运行 `HiFaceDemo`。开发工程使用 `../sdk/Artifacts` 内的二进制 SDK。首页提供七项能力，并显示系统版本与设备型号。

| 模块 | 示例入口 |
|---|---|
| 相机 | [CameraPipeline](HiFaceDemo/Camera/CameraPipeline.swift) |
| 相机流程 | [CameraDemoModel](HiFaceDemo/Camera/CameraDemoModel.swift) |
| 人脸库 | [SearchLibraryView](HiFaceDemo/Search/SearchLibraryView.swift) |

分辨率自动适配镜头，相机页显示实际尺寸与倍率。修改设置后重新进入页面。模拟器和 My Mac 不能替代 iPhone 相机验收。

## 语言与导入

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启 Demo。SDK 诊断保持中文，Demo 按错误码显示中英文提示。系统权限弹窗遵循系统设置。

`features_10000.json` 为 1 万条离线 HF1 特征；`images_1000.json` 为 1 千张网络图片清单，仅供演示。 这些文件不进入 `HiFace.framework` 或 XCFramework/SPM 包。图片最多并发下载 5 张，串行提取，每 100 条成功特征保存一次；特征导入每 1000 条保存一次。

进度区分已处理和已保存数量。导入时返回，可选择“继续导入”或“停止并退出”。停止后完成当前操作、保存尾批，再显示已保存和失败数量。单张失败跳过；写库失败保留之前已保存的批次。关闭 SDK 或数据库前等待导入收尾。

## 数据安全

上线前替换演示身份、特征和图片地址。HF1 是编码，SDK SQLite 未加密；宿主负责数据保护、保留和删除。1:1 基准使用 Keychain 保存，并按特征空间隔离。

模型加载失败时检查 SDK 模型资源；相机尺寸不支持时选择实际可用的偶数尺寸，且不超过 1920×1080。在目标手机验证权限恢复、旋转、前后台切换和各功能流程。
