[English](API.md) | **简体中文**

# HiFace iOS 0.8.16 SDK API 指南

## 快速开始

使用支持 Swift 6 的 Xcode 和 iOS 15+ 真机。在 Xcode 中将交付的 `SDK` 目录添加为本地 Swift Package，也可选择已发布的二进制 Swift Package 及版本。链接 `HiFace` product，其中同时包含 `HiFace` 和 `HiFaceNative`。

新建 SwiftUI iOS 应用并替换 `ContentView.swift`，在 iPhone 上运行。空白图应显示 `imageNoFace`。Apple Silicon 模拟器可编译和启动应用，推理需使用真机。接入相机流程时再配置 `NSCameraUsageDescription`。

```swift
import Foundation
import HiFace
import SwiftUI

struct ContentView: View {
    @State private var status = "Running…"

    var body: some View {
        Text(status).task { await extractFeature() }
    }

    private func extractFeature() async {
        let sdk = HiFaceSDK()
        defer { sdk.close() }
        do {
            let image = try HiFaceRGBAImage(
                rgba: Data(repeating: 0, count: 256 * 256 * 4),
                width: 256, height: 256
            )
            switch await sdk.extractFeature(from: image) {
            case .success:
                status = "Feature extracted"
            case .failure(let error):
                status = String(describing: error.code)
            }
        } catch {
            status = String(describing: error)
        }
    }
}
```

`HiFaceSDK()` 自动在后台初始化；静态调用会等待就绪，相机初始化期间的 `.notReady` 只需丢弃本帧。SDK 不管理相机或权限。单次图片可按上例创建后关闭；实时页面应持有同一实例，避免每帧创建。

| `HiFaceConfiguration` 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `cpuThreads` | `.automatic` / `.two` / `.four`，默认 `.automatic` | 同一进程的实例须使用相同策略；首个会话创建后不能切换。 |
| `modelDirectoryURL` | 本地文件目录 URL，默认 `nil` | 默认使用 SDK 随附资源。自定义时保留完整模型目录；手动集成须保留两份 Framework 及其资源。 |

## API 参考

### 人脸检测

调用 `sdk.processFrame(frame, configuration: config)`。成功返回人脸框、置信度和关键点，无人脸时返回空列表。坐标以旋转后、未镜像的画面为准。

| `FaceDetectionConfiguration` 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `maxFaces` | 1–10，默认 1 | 限制返回的人脸数。 |
| `includesDetailedLandmarks` | 布尔值，默认关闭 | 开启后附带详细轮廓和头部角度。 |

相机分析帧要求偶数宽高，长边不超过 1920、短边不超过 1080，旋转为 0°、90°、180° 或 270°。
用附带 BT.601/709 矩阵信息的双平面 NV12（`420v` 或 `420f`）创建 `HiFaceCameraFrame`，填写实际旋转角度。同步调用返回前保持像素缓冲区有效。

`isMirrored` 只描述预览，不会镜像识别输入或结果；应用自行转换画框坐标。`includesDetailedLandmarks` 开启后，`mesh` 和 `headPose` 仍需分别判空；角度单位为度。

### 人脸录入与照片采集

| 接口 | 返回结果 |
|---|---|
| `await sdk.extractFeature(from: image)` | 提取最大人脸的特征，无人脸返回 `.imageNoFace`，人脸宽或高不足 100 像素返回 `.imageFaceTooSmall`。 |
| `await sdk.capture(image)` | 返回 `feature` 和可选对齐预览 `alignedFace`。应用确认录入后再保存特征。 |
| `await sdk.captureFaces(image)` | 返回最多 10 张脸的位置及各自的采集结果。没有人脸时成功返回空列表，小脸只影响对应条目。 |
| `sdk.startCameraCapture(callbacks:)` | 引导用户采集人脸，通过回调交付结果。 |

照片调用前先处理图像方向。每个 SDK 的静态队列可同时处理一个任务，另有四个等待名额。批量处理时逐张提交。照片接口无需相机权限，无活体判定。

`HiFaceRGBAImage(rgba:width:height:)` 接受连续 RGBA8888，字节数须等于 `width * height * 4`，构造时固定像素快照；也可直接传 `CGImage`。展示对齐图用 `alignedFace?.makeCGImage()`。严格单人录入须检查 `captureFaces` 恰好一条且该条 `capture` 成功，最大脸接口不会拒绝多人照片。

### 活体与 1:1 验证

分别使用 `sdk.startCameraLiveness(configuration:callbacks:)` 和 `sdk.startCameraVerification(configuration:callbacks:)` 启动流程，再持续送入相机帧。已有两份特征时，`await sdk.compare(feature:with:)` 返回 0–1 的相似度。相似度仅反映特征接近程度。

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `referenceFeature` | 1:1 验证必填 | 传入已录入的人脸特征。 |
| `threshold` | 建议 0.75–0.85，默认 0.80 | 1:1 相似度门槛。低于门槛时，完成比对的流程返回身份不匹配。 |
| `actions` | 0–4 步，默认空 | 活体接口空动作时执行静默活体。 |
| `requiresSilentLiveness` | 布尔值，1:1 验证默认关闭 | 开启后还要求静默活体通过。 |
| `allowsMultipleFaces` | 布尔值，默认关闭 | 控制流程是否允许画面中出现多人。 |
| `actionTimeoutMilliseconds` | 2,000–30,000 ms，默认 3,000 ms | 每步动作时限。 |
| `faceAcquisitionTimeoutMilliseconds` | 1,000–60,000 ms，默认 10,000 ms | 首次取脸时限。 |

`actions` 顺序执行并允许重复，取值为 `.shakeHead`、`.nodHead`、`.blink`、`.openMouth`。1:1 动作为空且 `requiresSilentLiveness=false` 时只验证身份，不包含活体。`FaceFlowResult.passed` 才表示通过；`similarity`、`livenessScore` 为 `nil` 表示未产生，不能当作 0；图片存在不表示通过。`frameWidth`、`frameHeight` 是 JPEG 像素尺寸，无图时为 0。

相似度建议范围为 0.75–0.85，默认配置值为 0.80；1:1 验证和按特征查库的 API 实际允许 0–1，相机连续搜索仅允许 0.75–0.85。

RGB/IR 活体建议门槛为 0.80–0.99，建议值为 0.90。当前 RGB 静默活体固定使用 0.90，未开放门槛设置；IR 门槛须显式传入，没有隐式默认值。活体和验证的 `onResult` 会交付通过或拒绝的结果，先读 `outcome`。只有本轮执行了对应步骤才会返回相似度或活体分数。独立近红外活体使用 `await sdk.evaluateInfraredLiveness(_:realThreshold:)`，传入真实 GRAY8 红外帧、图中人脸框和按设备标定的阈值（建议 0.80–0.99，初始值 0.90，API 实际允许大于 0 且不超过 1）。阈值必填。

### 人脸库与搜索

用 `HiFaceSDK.openSearchDatabase()` 打开独立人脸库。通过 `saveFeature` 或 `saveFeatures` 按 Face ID 新增或更新，单批可保存 1–1,000 条。用 `search` 按特征查库。`entries` / `recentEntries` 返回元数据，`featureEntries` 分页读取含特征的记录。由调用方关闭显式打开的人脸库。人脸库由 actor 管理，按需使用 `try await` 调用。

单库最多 50,000 条。批量保存全部成功或全部回滚，重复 ID 以本批最后一条为准。`contains(faceID:)` 返回是否存在，`entry(faceID:)` 不存在时抛出 `.notFound`，`delete(faceID:)` 返回是否实际删除。

分页 `offset` 为 0…`Int32.max`，默认 0；`limit` 为 1–1,000，默认 100。`entries` / `featureEntries` 按 Face ID 排序，`recentEntries` 按更新时间倒序。`updateTimeMilliseconds` 使用 Unix 毫秒，默认 0 表示当前时间，负数无效。`updateMetadata` 的分组或标签传 `nil` 保留、空串清空，至少指定一项。关闭连接使用 `await database.close()`；关闭 SDK 不会关闭独立打开的连接。

**人脸记录与筛选**

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| Face ID | 必填，1–1024 个 UTF-8 字节，不允许 NUL，无默认值 | 应用指定的记录标识。保存相同 ID 会更新该记录；不是分组或标签筛选条件。 |
| `group` | 可选，最多 1024 个 UTF-8 字节，不允许 NUL；默认不筛选 | 人脸所属分组。查询时精确匹配该分组，`nil` 或空串表示不限分组。 |
| `tag` | 可选，最多 1024 个 UTF-8 字节，不允许 NUL；默认不筛选 | 应用自定义的业务标签。查询时精确匹配该标签，`nil` 或空串表示不限标签。 |

同时指定分组和标签时，两项都必须匹配；均不指定时搜索全库。

**按已有特征查库（`FaceSearchConfiguration`）**

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `topK` | 1–100，默认 1 | 最多返回的匹配数。 |
| `threshold` | 建议 0.75–0.85，默认 0.80 | 仅用于按已有特征查库。返回相似度达到门槛的记录，无匹配时返回空列表；相机连续搜索使用下表的范围。 |

连续搜索使用 `sdk.startCameraSearch(configuration:callbacks:)`，它自行管理人脸库连接。

| 连续搜索参数 | 范围与默认值 | 用途 |
|---|---|---|
| `mode` | `.singleFace` / `.multiFace`，默认 `.singleFace` | 单人模式只处理最大人脸；多人模式按 `maxFacesPerFrame` 限制处理人数。 |
| `needsLiveness` | `true` / `false`；单人默认 `true`，多人默认 `false` | 是否开启 RGB 静默活体；多人模式不能设为 `true`。 |
| `threshold` | 0.75–0.85（含端点），默认 0.80 | 相机连续搜索的身份匹配门槛；相似度大于等于该值才算身份匹配，活体仍须单独通过。 |
| `searchIntervalMilliseconds` | 0–3,000 ms，默认 0 | 匹配成功后到下一轮的间隔。 |
| `searchTimeoutMilliseconds` | 1,000–3,000 ms，默认 3,000 ms | 从首次选中人脸开始计算的单轮时限。 |
| `maxFacesPerFrame` | 1–5，默认 3 | 多人模式处理上限。单人模式仅处理最大脸。 |

`startCameraSearch` 立即返回会话，准备期间继续送入新帧。`pause()` 保留相机流程占用，切换采集或验证前先 `close()`；`resume()` 恢复，`update(configuration:)` 替换配置并作废旧结果。`onFrame` 只更新显示，业务读取 `onResult`；技术错误会暂停会话，修复后可 `resume()`，已关闭会话不能复用。

先看 `endReason`。即使达到相似度门槛，`.spoofDetected` 也表示拒绝。`frameID` 标识同一次采样。`frameJPEG` 是可选的结束帧整图，绘制人脸框时按原始帧尺寸换算。

人脸特征应原样保存。更换为不兼容的模型时，从原照片重新提取并导入。应用负责取得用户同意，以及保护和删除照片和特征。

## 错误处理与资源释放

静态图和实时接口返回 Swift `Result`，配置初始化和人脸库接口可能抛错。按 `HiFaceError.code` 处理。相机回调在 `MainActor` 交付。功能页复用同一个 SDK，用完调用 `close()`。

| 情况 | 处理方式 |
|---|---|
| `.notReady` | 模型初始化、运行时正忙或相机跳帧时，丢弃当前帧，继续送入最新帧。 |
| `.busy` | 等静态任务完成，或先结束当前相机流程。 |
| `.invalidArgument` | 检查参数、帧格式与缓冲区。 |
| `.licenseExpired` | 核对授权有效期，必要时联系 SDK 支持。 |
| `.closed` | 停止向此实例继续提交任务。 |
| `.resourceExhausted` | 减少并发任务并检查内存、磁盘和容量，处理后再重试。 |
| `.databaseError` | 检查人脸库路径、权限及存储状态；保留原数据，避免自动删库。 |
| `.internalError` | 停止本次请求，记录 SDK 版本及错误码并联系支持。 |

采集、活体、验证和连续搜索共用一个相机流程槽。切换功能或退出页面时，先停止送帧，再取消请求或关闭搜索，然后关闭 SDK。`onError` 用于技术失败，业务结果读取对应结论。

相机输入须在同步送帧调用返回前保持有效；静态图任务在 `await` 返回前保留输入。结果图片可能为空，不代表失败或通过。取消与关闭不会补发终态回调。

相机方法返回的 `FaceRequest` 可用 `cancel()` 取消，不补发终态回调。静态图片的 `async` 调用不提供该句柄，取消 Swift `Task` 不等于中止 SDK 作业；`await` 返回后先检查任务是否取消或页面是否仍有效。`close()` 不等待在途调用结束，不要再向旧实例提交任务。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。室外人脸搜索使用宽动态范围大于 100 dB 的相机。
