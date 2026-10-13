[English](README.md) | 简体中文

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

## 运行 Demo

用 DevEco Studio 26 打开 `platforms/harmony`。`demo` 为应用模块，`sdk` 构建 `hiface` HAR。配置自己的 Bundle Name 和 HAP 签名，在 API 20+ 的 arm64 手机运行 `demo`。未签名 HAP 无法安装到手机。首页提供七项能力，并显示系统版本与设备型号。

| 模块 | 示例入口 |
|---|---|
| 导航 | [Index](src/main/ets/pages/Index.ets) |
| 相机 | [CameraPreviewController](src/main/ets/camera/CameraPreviewController.ets) |
| 相机流程 | [RealtimeCameraDemo](src/main/ets/pages/RealtimeCameraDemo.ets) |
| 人脸库 | [FaceSearchLibraryDemo](src/main/ets/search/FaceSearchLibraryDemo.ets) |

释放 CameraKit Image 前复制 YUV 数据，处理完成前保留副本。每条相机链使用一个实时处理器，忙时丢帧。将旋转后、未镜像的结果坐标映射到预览。SDK 句柄通过普通字段或 `@Require` 传递，勿用 `@Prop`。

## 语言与导入

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启 Demo。SDK 诊断保持中文，Demo 按错误码显示中英文提示。系统权限弹窗遵循系统设置。

`features_10000.json` 为 1 万条离线 HF1 特征；`images_1000.json` 为 1 千张网络图片清单，仅供演示。 这些文件不进入 `hiface` HAR。图片最多并发下载 5 张，串行提取，每 100 条成功特征保存一次；特征导入每 1000 条保存一次。

进度区分已处理和已保存数量。导入时返回，可选择“继续导入”或“停止并退出”。停止后完成当前操作、保存尾批，再显示已保存和失败数量。单张失败跳过；写库失败保留之前已保存的批次。关闭 SDK 或数据库前等待导入收尾。

## 数据安全

上线前替换演示身份、特征和图片地址。HF1 是编码，SDK SQLite 未加密；宿主负责数据保护、保留和删除。1:1 基准由 Demo 使用 HUKS 加密文件保存。

模型加载失败时检查 SDK 模型资源；相机尺寸不支持时选择实际可用的偶数尺寸，且不超过 1920×1080。在目标手机验证权限恢复、旋转、前后台切换和各功能流程。
