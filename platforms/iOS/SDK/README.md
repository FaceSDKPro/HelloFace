# HiFace iOS SDK 0.0.1

## 安装与支持范围

当前 Demo 使用随工程附带的本地二进制 SPM 包，版本为 `0.0.1 Beta`。
在自己的工程中选择 **Add Package Dependencies → Add Local**，添加本目录，
并把 `HiFace` product 加入 App target；保留两个 binary targets。
正式远程 SPM 地址与版本以发布记录为准。

| 项目 | 首版范围 |
| --- | --- |
| 系统 | iOS 15 及以上 |
| 架构 | 真机 arm64；模拟器 arm64/x86_64 |
| 语言 | Swift 6；候选包构建与接入验证使用 Xcode 26.6 / iOS 26.5 SDK |
| 分发 | SPM；`HiFace` 与 `HiFaceNative` 两个 binary targets |
| 能力 | 检测、特征提取、采集、动作/静默活体、1:1、SQLite 人脸库、连续 1:N/M:N 搜索 |

SPM 从本地包链接两套 Framework 和包内密文模型。保留两个 binary targets，不单独复制其中一个
Framework。默认无需手动复制模型，也无需设置 `modelDirectoryURL`。
其他 Xcode 版本需要完成消费验证后再作支持承诺；My Mac（Designed for iPhone）的 Demo 验证不构成
原生 macOS SDK 支持声明。模拟器适合编译和界面验证，真人相机流程使用真机验收。

## 初始化与实时检测

```swift
import HiFace
import CoreVideo

let sdk = HiFaceSDK(configuration: HiFaceConfiguration(cpuThreads: .automatic))

// 示例假设 AVFoundation 已把输出转为正立方向；否则按原始帧方向设置 rotation。
func analyze(_ pixelBuffer: CVPixelBuffer, frontCamera: Bool) throws
    -> Result<FaceDetectionResult, HiFaceError> {
    let frame = try HiFaceCameraFrame(
        pixelBuffer: pixelBuffer,
        rotation: .degrees0,
        isMirrored: frontCamera
    )
    return sdk.processFrame(frame, configuration: .default)
}
```

创建实例后模型异步初始化；实时检测返回 `.notReady` 或 `.busy` 时跳过当前帧，继续送入最新帧。
`processFrame` 同步执行，应从相机分析队列调用。初始化期间的一次性静态任务会等待模型就绪。
进程内所有实例使用相同的 `cpuThreads`；首个 Native Session 创建后不能切换线程策略。

宿主负责 AVFoundation、相机授权和 UI。在 App 的 Info.plist 配置 `NSCameraUsageDescription`。
输入必须是带 BT.601/BT.709 色彩矩阵 attachment 的 `420v`/`420f` 双平面 NV12，尺寸为偶数，
长边不超过 1920、短边不超过 1080。摄像头不支持目标采集帧率时，使用可用帧率并在送帧前节流；
不要向设备写入不支持的帧率。输出坐标属于旋转后、未镜像的像素空间，预览裁剪和镜像由宿主处理。

## 人脸库与连续搜索

`HiFaceSDK.openSearchDatabase()` 打开 SDK 管理的 Application Support 私有库，自动排除云备份，
不要求业务传入数据库路径。数据库方法通过 actor 串行执行；使用完毕后 `await database.close()`。
已有 HF1 可用 `saveFeature` 写入；批量使用 `saveFeatures`，每批最多 1000 条。完整示例见 [API.md](API.md)。

```swift
let searchConfiguration = try FaceSearchSessionConfiguration(
    mode: .singleFace,
    needsLiveness: true
)
let search = sdk.startCameraSearch(
    configuration: searchConfiguration,
    callbacks: FaceSearchCallbacks(
        onFrame: { frame in /* 根据 frameID 更新人脸框和当前评分 */ },
        onProgress: { progress in /* 更新引导 */ },
        onResult: { result in /* 根据 endReason 处理本轮结论 */ },
        onError: { error in /* 显示技术错误，处理后可恢复会话 */ }
    )
)

// 宿主继续通过 sdk.processFrame 送入相机帧。
search.pause()
search.resume()
search.close()
```

连续搜索使用 `FaceSearchSessionConfiguration`，单次特征查询使用 `FaceSearchConfiguration`。
单人模式默认开启静默活体，多人模式不能开启静默活体。`.spoofDetected` 为拒绝结果，不能因相似度较高
而改判通过；尚未评分的 `nil` 分数不能当作 0。搜索间隔控制成功后的等待时间，不控制摄像头帧率。

## 生命周期与错误

相机采集、活体、动态验证和连续搜索共用一个互斥槽；不要同时启动。相机流程回调异步交付到 `MainActor`。
离开页面、进入后台或相机中断时，宿主停止送帧，取消采集/活体/验证请求或暂停搜索。
页面释放时关闭搜索会话和 SDK：

```swift
search.close()
sdk.close()
```

`cancel()`/`close()` 会立即禁止新回调，在途 Native 调用结束后再释放资源，不阻塞主线程等待推理。
业务代码依据 `HiFaceError.code` 判断技术失败，`message` 用于诊断；
依据 `FaceFlowOutcome`/`FaceSearchEndReason` 判断业务通过、拒绝和超时。

| 技术错误 | 宿主处理 |
| --- | --- |
| `.notReady` / `.busy` | 实时输入丢帧重试；避免重复启动互斥流程 |
| `.invalidArgument` / `.unsupportedFormat` | 检查尺寸、色彩矩阵、配置与 HF1 格式 |
| `.modelLoadFailed` | 检查 Framework 模型资源和自定义模型目录，拒绝继续推理 |
| `.closed` / `.cancelled` | 清理页面状态；需要新实例时重新创建 |
| `.databaseError` / `.resourceExhausted` | 检查数据库访问、剩余空间和内存，提示用户重试 |

静态 `CGImage` 接入先归一化 EXIF 方向。详细公开 API、图片限制、回调与取消约定见 [API.md](API.md)。

## 隐私、许可与版本升级

SDK 在设备内处理，不联网、不跟踪、不上传人脸或特征；包内包含 SDK 隐私清单。
宿主负责用户同意、业务图片/HF1/数据库的保存、访问保护、删除及任何上传。
首版人脸库使用普通 SQLite，备份排除不等于数据库加密。提交宿主 App 前检查 Archive 的汇总隐私报告。

SDK 和模型仅按已取得的授权使用，第三方 NOTICE 不授予 HiFace 或模型权重许可。
授权说明见 [LICENSING.md](LICENSING.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。
0.0.x 属于早期版本，接入方应固定已验收版本；升级前检查 API、阈值和 HF1/人脸库兼容性并回归业务流程。
