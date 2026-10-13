# HiFace HarmonyOS SDK 使用与 Demo 指南

开发 Demo 的应用标识为 `com.hiface.sdk.public`。

<!-- SDK-USER-GUIDE:BEGIN -->
## 支持与安装

当前为内测 Beta 版；北京时间 2026-12-26 零点起停止初始化和工作。
到期日志为“请升级SDK，详情见https://github.com/FaceSDKPro/”。

| 项目 | 当前范围 |
|---|---|
| 最低系统 | HarmonyOS API 20 |
| ABI | `arm64-v8a` |
| 入口 | ArkTS `HiFaceSdk` |

直接交付时，把版本化 HAR 复制到应用（例如 `libs/hiface-0.0.1.har`），在模块
`oh-package.json5` 中声明：

```json5
{
  "dependencies": {
    "hiface": "file:./libs/hiface-0.0.1.har"
  }
}
```

同一版本通过 OpenHarmony 三方库中心仓审核后，可执行：

```shell
ohpm install hiface@0.0.1
```

也可以在 `oh-package.json5` 中声明 `"hiface": "0.0.1"`。直接交付和中心仓应使用同一版本、
同一 SHA-256 的 HAR，不能覆盖已经交付的版本。

## 初始化与错误处理

```typescript
import { common } from '@kit.AbilityKit';
import { FaceCaptureResult, HiFaceResult, HiFaceSdk } from 'hiface';

async function createHiFaceSdk(context: common.UIAbilityContext): Promise<HiFaceSdk> {
  const sdk: HiFaceSdk = HiFaceSdk.create(context);
  const ready: HiFaceResult<boolean> = await sdk.whenReady();
  if (ready.isFailure()) {
    const message: string = ready.requireError().message;
    sdk.close();
    throw new Error(`HiFace 初始化失败: ${message}`);
  }
  return sdk;
}
```

公开业务调用用 `HiFaceResult<T>` 表示可预期失败：先检查 `isSuccess()` 或 `isFailure()`，再调用
`requireValue()` 或 `requireError()`。无效构造参数会直接抛出 `Error`；相机、文件和页面异常由宿主处理。
按 Ability 或业务容器复用实例；退出前停止送帧、取消流程，再关闭 SDK。
`close()` 幂等并立即屏蔽新请求/旧回调，Native 在后台释放；在途帧像素仍须保留到 Promise 完成。

ArkUI 子组件通过普通字段（可加 `@Require`）接收 SDK 引用。不要用 `@Prop` 传递 `HiFaceSdk`：
其深拷贝会复制内部 Promise 外壳但丢失运行时状态，导致 `Then: thisValue is not promise!`。
SDK、请求句柄和数据库连接不作为可复制的页面状态；页面只观察展示结果。

## 公开能力

| 分组 | 入口 | 用途 |
|---|---|---|
| 检测 | `processFrame()`、`processRgba()` | YUV/RGBA 单帧人脸框、五点及可选轮廓/头姿 |
| 实时检测 | `createRealtimeProcessor()` | 单帧在途门禁；忙时返回 `undefined`，由宿主丢弃该帧 |
| 采集 | `capture()` | 静态图提取 HF1/对齐预览，或启动相机引导采集 |
| 活体 | `liveness()` | 启动动作与静默活体相机流程 |
| 验证 | `verification()` | HF1 或静态图 1:1 比较，以及相机动态验证 |
| 搜索 | `search()` | 启动连续 1:N/M:N 相机搜索 |
| 人脸库 | `HiFaceSdk.openSearchDatabase()` | 独立 SQLite 人脸库的增删查改、预热和 Top-K 查询 |

只从 `hiface` 导入 `Index.ets` 的公开符号；internal、N-API 字段与 Native 符号不属于兼容承诺。
`getApiVersion()` 仅用于 ABI 诊断，基础能力是否就绪以 `whenReady()` 为准。

采集、活体、验证、搜索和实时处理器是公开接口，由 `HiFaceSdk` 返回实例；接入方不构造或实现这些能力对象。
首发检测结果承诺人脸框、置信度、五点及可选头姿/468 点。EAR/MAR、闭眼/张嘴指标仅用于 Core 内部流程，
不作为公开返回值或兼容承诺；业务放行依据最终流程结果。

静态图片使用已归一化方向的 `RgbaImage`：

```typescript
const feature: HiFaceResult<string> = await sdk.capture().extractFeature(image);
const capture: HiFaceResult<FaceCaptureResult> = await sdk.capture().fromRgba(image);
const similarity: HiFaceResult<number> = sdk.verification().compare(leftHF1, rightHF1);
```

静态入口选最大脸，`fromRgba` 额外返回 333×333 对齐预览。异步调用立即建立像素快照，队列最多
一个运行请求和四个等待请求；批量逐张等待完成。HF1 是 Q7/Base64URL 表示，不是加密。

## 实时帧与坐标

- `Yuv420Frame` 的 Y/U/V 数据借用到处理 Promise 完成；在此之前不能释放、覆盖或复用底层缓冲。
- 分析尺寸必须是正偶数，长边不超过 1920、短边不超过 1080，并显式提供行跨度、像素跨度、
  色彩范围、色彩矩阵和 0/90/180/270 度旋转。
- 每条相机链创建一个 `FaceRealtimeProcessor`。`tryProcessFrame()` 返回 `undefined` 表示当前忙，宿主应
  立即释放新帧；不要把帧排成无界 Promise 队列。
- 检测和搜索坐标属于“旋转后、未镜像”的结果图像像素空间。宿主依据结果的 `imageWidth`、
  `imageHeight`，统一应用预览缩放、居中裁剪和前摄镜像。
- `frameId` 只关联同一采样的检测、评分与终态，不表示跨帧人脸跟踪。
- 模型准备、忙或待机跳帧返回 `NOT_READY`；继续送入最新帧。连续 10 秒无人脸后按 200 ms 目标节奏分析，
  检出人脸后恢复；相机实际帧率由宿主和设备决定。

## 相机流程生命周期

采集、活体、验证和搜索共享同一 SDK 相机处理槽，同一时刻只能运行一种流程：

1. 创建监听器并调用对应的 `startCamera...()`。
2. 启动成功后保存返回的 `FaceRequest` 或 `FaceSearchSession`。
3. 相机每帧仍通过同一 `FaceRealtimeProcessor.tryProcessFrame()` 送入 SDK。
4. 页面退出、切摄或切换能力时，先 `cancel()` / `close()`，再停止相机并释放页面资源。

`FaceFlowListener.onResult()` 是采集、活体和验证的业务终态；`onError()` 表示流程错误。
搜索业务必须先检查 `FaceSearchResult.endReason`，`SPOOF_DETECTED` 即使携带达标身份也不能放行。
`search().startCameraSearch(config, listener)` 会自动打开并预热应用人脸库；准备期间的相机帧返回
`NOT_READY`。`FaceSearchSession.pause()` 保留搜索槽位、模型和数据库连接，但释放图库范围缓存；
`resume()` 在重新接收帧前预热当前范围。技术错误暂停采用同一释放规则，只有 `close()` 才释放连接和槽位。
后续启动等待先前 Native 启停任务结束，启停期间丢帧，旧帧/过期启动不影响新流程。
Native 停止失败时应关闭并重新创建 SDK。

`FaceLivenessConfig` 的空 `actions` 表示不执行动作挑战，仍会执行七帧双模型静默活体；
可用 `hasActions()` 区分两种模式。最终回正阶段的默认保持时间和绝对截止时间分别由
`DEFAULT_FRONTAL_HOLD_MILLIS` 和 `DEFAULT_FINAL_CAPTURE_TIMEOUT_MILLIS` 公开，与 Android SDK 参数一致。

## 人脸库生命周期

`openSearchDatabase(context)` 不依赖推理模型，SDK 自动使用应用私有目录中的固定文件名。
该管理句柄独立于 `HiFaceSdk`：关闭 SDK 不会自动关闭已经显式打开的 `FaceSearchDatabase`，调用方必须
自行 `close()`；连续相机搜索的连接则由 Session 自动管理。批量写入每批支持 1 到 1000 条并保证
原子性；`saveFeature`/`saveFeatures` 使用按 Face ID 覆盖语义，批量参数使用轻量的
`FaceSearchFeatureEntry`，人工新增若要提示重复应先调用 `contains`。
数据库直接保存 HF1 中的原始 450 字节 Q7 内容；`get` 与搜索结果的 `feature` 原样返回完整 HF1。
`list` / `listRecent` 返回不含特征的 `FaceSearchMetadata`，`listFeatures` 用于完整特征分页导出。
`contains` 仅查主键。`updateMetadata(faceId, group, tag, time)` 只改元数据，undefined 保留、空串清空。
`FaceFeatureFormat.FEATURE_SPACE_ID` 提供模型/预处理兼容标识，可传给 `FaceSearchFeatureEntry` 校验服务器数据。
开发期测试库不迁移，测试设备需清理旧库并重新导入。
三种分页接口的 `offset` 范围为 `0..2147483647`，`limit` 为 `1..1000`。
直接搜索和连续搜索的阈值统一到 Core 的 `float32` 精度。
`close()` 立即拒绝新请求，在后台等待已开始的操作结束并清理 SQLite 与特征缓存；
尚未开始的排队操作返回 `CLOSED`。需要确认写入结果时，先等待保存成功，再调用 `close()`。

SDK 创建的 SQLite 数据库当前不提供包内加密。人脸特征和搜索库属于生物识别数据，接入方负责采集授权、
访问控制、加密存储、保留期限、删除和备份策略。

## 许可与发布文件

- `LICENSE`：HiFace SDK 与模型商业许可说明，商业使用需要书面授权。
- `CHANGELOG.md`：当前版本的公开变化。
- `src/main/resources/rawfile/THIRD_PARTY_NOTICES.txt`：第三方组件版权及许可证。

客户交付时应记录版本号和 HAR 校验值。宿主 HAP/APP 使用接入方自己的签名；HAR 不应携带 Demo、
客户签名文件或私钥。
<!-- SDK-USER-GUIDE:END -->

## Demo 能力与代码入口

| 能力 | 示例入口 | 集成时重点 |
| --- | --- | --- |
| 首页与 SDK 所有权 | [Index.ets](src/main/ets/pages/Index.ets) | 初始化、能力入口、返回栈和关闭 |
| 共享实时相机 | [RealtimeCameraDemo.ets](src/main/ets/pages/RealtimeCameraDemo.ets) | 相机帧、流程句柄、页面代次和生命周期 |
| CameraKit | [CameraPreviewController.ets](src/main/ets/camera/CameraPreviewController.ets) | 权限、双路输出、规格回退、背压和切摄 |
| 静态 1:1 | [StaticFaceComparisonDemo.ets](src/main/ets/comparison/StaticFaceComparisonDemo.ets) | 授权 URI、方向、RGBA 和最大脸比较 |
| 人脸搜索库 | [FaceSearchLibraryDemo.ets](src/main/ets/search/FaceSearchLibraryDemo.ets) | 录入、分页、查询、删除和批量导入 |

检测、采集、活体、动态 1:1、搜索和搜索录入共用 `RealtimeCameraDemo`，首页入口决定固定能力模式。
业务工程可以复用其接入方式，无需复制 Demo 的页面布局、文案或存储策略。
实时搜索页只持有一份已校验的配置快照；设置弹窗只保存独立输入文本，取消/重置不修改运行配置，
应用时统一交给 SDK 校验。父页面保留 SDK 的阈值精度，不在重新进入时额外取整。
静态 1:1 两个照片槽位复用同一布局，但各自保留 PixelMap 所有权、特征和异步代次，
布局内部直接读取对应的 ArkUI 状态，不复制 SDK 或图片资源句柄。

## CameraKit、帧与坐标

HAR 不申请相机权限，也不创建 CameraKit 会话。宿主负责权限告知、预览、分析输出、镜头切换和帧生命周期。
Demo 的关键处理方式如下：

- 每条相机链创建一个 `FaceRealtimeProcessor`，同一时间只允许一帧在途。
- 每次 `imageArrival` 使用 `readNextImage()` 读取一张图；暂停/限流帧在读取分量前释放。
  需处理的图按 NV21 行跨度复制独立 Y/U/V 后立即释放原图，推理期间至多保留一份最新等待帧。
- `Yuv420Frame` 的平面必须保留到处理 Promise 完成，在此之前不能释放、覆盖或复用。
- `tryProcessFrame()` 返回 `undefined` 表示当前忙，应立即丢弃该帧，不能建立无界 Promise 队列。
- 输入尺寸必须为正偶数，长边不超过 1920、短边不超过 1080，并提供实际跨度、色彩信息和旋转。
- SDK 坐标属于“旋转后、未镜像”的像素空间；宿主统一处理预览缩放、裁剪和前摄镜像。

ImageReceiver 的分量读取入口使用 `image.ComponentType.JPEG`，相机实际生产格式是
`NATIVEBUFFER_PIXEL_FMT_YCRCB_420_SP`（NV21），不是 JPEG 编码；
`CameraFrameAdapter` 校验格式、尺寸和跨度。图库 fd 解码与该相机缓冲路径不同，不能互相套用。

业务若要在送入 SDK 前自行读取或分析帧，可以在复制阶段完成；跨异步边界时继续使用自己的缓冲区，不能持有
CameraKit 已释放的 `Image`。

## 人脸搜索与演示数据

`src/main/resources/rawfile/face_search/` 包含：

- `features_10000.json`：新模型从 `face1W_333` 的 10,000 张真实人脸 PNG 提取的 HF1 特征，可离线导入；Face ID 对应图片文件名去掉 `.png`。
- `images_1000.json`：需要联网下载并提取特征的 1,000 个 HTTPS 图片 URL。

当前模型使用 `hiface-feature-new-v1`，加密快照 参考特征按空间隔离，旧空间数据不参与比对。
本次名称清理未改变模型或一万条特征值；其他模型的旧特征不能混用。
JSON 保留 `group_test` / `group_A` / `group_B` 分组，数据来源与模型哈希记录在 `source`；
识别效果需使用对应人员的独立照片或重新采集验证，不能仅凭入库图片自匹配判断。

两份 JSON 仅属于 `entry` Demo，不进入 `hiface` HAR。生产 App 必须使用已获授权的数据、自己的服务器
和可恢复的同步任务，并由业务定义 Face ID、分组、标签、阈值、保留期限与删除策略。

连续搜索的数据库连接由 `FaceSearchSession` 管理；通过 `HiFaceSdk.openSearchDatabase()` 独立打开的
管理连接必须由调用方关闭。SDK 当前不提供搜索库包内加密，业务方需要完成访问控制、文件保护、备份策略和
用户删除能力。

## 数据安全

Demo 的 1:1 参考特征使用 HUKS 托管密钥并加密保存，这是示例基线。生产 App 仍需实现明确的用户同意、
最小权限、密钥轮换、数据保留、撤销删除和审计。人脸图片、HF1 特征、搜索结果和密钥不应进入普通日志、
崩溃上报或分析平台。

## 常见问题

| 现象 | 排查方式 |
| --- | --- |
| `Then: thisValue is not promise!` | 检查是否通过 `@Prop` 传递了 `HiFaceSdk` 或句柄，改为普通字段或 `@Require` |
| 预览正常但没有分析结果 | 检查 ImageReceiver 是否出帧、YUV 平面是否正确复制、实际尺寸/跨度/旋转是否准确 |
| 检测框左右颠倒或偏移 | 使用结果图像尺寸映射，并且只在 Overlay 层处理一次前摄镜像 |
| 流程无法启动或一直未就绪 | 等待 `whenReady()` 和相机真正出帧，确认上一请求/Session 已取消或关闭 |
| 搜索没有身份结果 | 先确认人脸库已有 HF1，再检查模式、分组、阈值和活体终态 |
| 模拟器通过但真机失败 | 使用 arm64 正式 HAR 在目标 API 真机重新验证权限、CameraKit 规格、方向和性能 |
