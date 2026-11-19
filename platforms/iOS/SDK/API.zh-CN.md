# HiFace iOS 0.8.14 SDK API 指南

[English](API.md) | 简体中文

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

## API 参考

### 人脸检测

调用 `sdk.processFrame(frame, configuration: config)`。成功返回人脸框、置信度和关键点，无人脸时返回空列表。坐标以旋转后、未镜像的画面为准。

| `FaceDetectionConfiguration` 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `maxFaces` | 1–10，默认 1 | 限制返回的人脸数。 |
| `includesDetailedLandmarks` | 布尔值，默认关闭 | 开启后附带详细轮廓和头部角度。 |

相机分析帧要求偶数宽高，长边不超过 1920、短边不超过 1080，旋转为 0°、90°、180° 或 270°。
用附带 BT.601/709 矩阵信息的双平面 NV12（`420v` 或 `420f`）创建 `HiFaceCameraFrame`，填写实际旋转角度。同步调用返回前保持像素缓冲区有效。

### 人脸录入与照片采集

| 接口 | 返回结果 |
|---|---|
| `await sdk.extractFeature(from: image)` | 提取最大人脸的特征，无人脸返回 `.imageNoFace`，人脸宽或高不足 100 像素返回 `.imageFaceTooSmall`。 |
| `await sdk.capture(image)` | 返回 `feature` 和可选对齐预览 `alignedFace`。应用确认录入后再保存特征。 |
| `await sdk.captureFaces(image)` | 返回最多 10 张脸的位置及各自的采集结果。没有人脸时成功返回空列表，小脸只影响对应条目。 |
| `sdk.startCameraCapture(callbacks:)` | 引导用户采集人脸，通过回调交付结果。 |

照片调用前先处理图像方向。每个 SDK 的静态队列可同时处理一个任务，另有四个等待名额。批量处理时逐张提交。照片接口无需相机权限，无活体判定。

### 活体与 1:1 验证

分别使用 `sdk.startCameraLiveness(configuration:callbacks:)` 和 `sdk.startCameraVerification(configuration:callbacks:)` 启动流程，再持续送入相机帧。已有两份特征时，`await sdk.compare(feature:with:)` 返回 0–1 的相似度。相似度仅反映特征接近程度。

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `referenceFeature` | 1:1 验证必填 | 传入已录入的人脸特征。 |
| `threshold` | 0–1，默认 0.80 | 1:1 相似度门槛。低于门槛时，完成比对的流程返回身份不匹配。 |
| `actions` | 0–4 步，默认空 | 活体接口空动作时执行静默活体。 |
| `requiresSilentLiveness` | 布尔值，1:1 验证默认关闭 | 开启后还要求静默活体通过。 |
| `allowsMultipleFaces` | 布尔值，默认关闭 | 控制流程是否允许画面中出现多人。 |
| `actionTimeoutMilliseconds` | 2,000–30,000 ms，默认 3,000 ms | 每步动作时限。 |
| `faceAcquisitionTimeoutMilliseconds` | 1,000–60,000 ms，默认 10,000 ms | 首次取脸时限。 |

RGB 静默活体使用 SDK 固定门槛 0.90。活体和验证的 `onResult` 会交付通过或拒绝的结果，先读 `outcome`。只有本轮执行了对应步骤才会返回相似度或活体分数。独立近红外活体使用 `await sdk.evaluateInfraredLiveness(_:realThreshold:)`，传入真实 GRAY8 红外帧、图中人脸框和按设备标定的 0–1 阈值。阈值必填。

### 人脸库与搜索

用 `HiFaceSDK.openSearchDatabase()` 打开独立人脸库。通过 `saveFeature` 或 `saveFeatures` 按 Face ID 新增或更新，单批可保存 1–1,000 条。用 `search` 按特征查库。`entries` / `recentEntries` 返回元数据，`featureEntries` 分页读取含特征的记录。由调用方关闭显式打开的人脸库。人脸库由 actor 管理，按需使用 `try await` 调用。

| 查库参数 | 范围与默认值 | 用途 |
|---|---|---|
| Face ID、`group`、`tag` | Face ID 为 1–1024 个 UTF-8 字节，分组和标签各最多 1024 字节，均不允许 NUL | 精确按分组和标签筛选，两项均指定时同时匹配，均未指定时搜索全库。 |
| `topK` | 1–100，默认 1 | 最多返回的匹配数。 |
| `threshold` | 0–1，默认 0.80 | 精确查库的相似度下限，低于门槛的记录不会返回。没有匹配时返回空列表。 |

连续搜索使用 `sdk.startCameraSearch(configuration:callbacks:)`，它自行管理人脸库连接。

| 连续搜索参数 | 范围与默认值 | 用途 |
|---|---|---|
| `mode`、`needsLiveness` | 默认单人且开启活体，多人模式不支持活体 | 决定每帧处理最大人脸还是多人。 |
| `threshold` | 0.75–0.85，默认 0.80 | 连续搜索的身份门槛。 |
| `searchIntervalMilliseconds` | 0–3,000 ms，默认 0 | 匹配成功后到下一轮的间隔。 |
| `searchTimeoutMilliseconds` | 1,000–3,000 ms，默认 3,000 ms | 从首次选中人脸开始计算的单轮时限。 |
| `maxFacesPerFrame` | 1–5，默认 3 | 多人模式处理上限。单人模式仅处理最大脸。 |

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

采集、活体、验证和连续搜索共用一个相机流程槽。切换功能或退出页面时，先停止送帧，再取消请求或关闭搜索，然后关闭 SDK。`onError` 用于技术失败，业务结果读取对应结论。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。室外人脸搜索使用宽动态范围大于 100 dB 的相机。
