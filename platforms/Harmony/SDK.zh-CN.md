[English](SDK.md) | **简体中文**

# HiFace HarmonyOS SDK API 指南

## 快速开始

使用 HarmonyOS API 20 或更高版本的 ARM64 设备。在 DevEco Studio 新建 ArkTS Empty Ability 项目，将 HAR 放入项目根目录的 `libs/`，在入口模块的 `oh-package.json5` 添加依赖：

```json5
{
  "dependencies": {
    "hiface": "file:../libs/hiface-0.8.14.har"
  }
}
```

在项目根目录运行 `ohpm install`。同版本在仓库上架后，可改用 `ohpm install hiface@0.8.14`，或把依赖改为 `"hiface": "0.8.14"`。用下面的代码替换入口页 `pages/Index.ets`，签名并在设备上运行应用。点击 **Run HiFace**，空白图应显示 `1201`（`IMAGE_NO_FACE`）。

```typescript
import { common } from '@kit.AbilityKit';
import { HiFaceSdk, RgbaImage } from 'hiface';

@Entry
@Component
struct Index {
  @State status: string = 'Ready';
  private sdk?: HiFaceSdk;

  private async extractFeature(): Promise<void> {
    if (this.sdk !== undefined) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const sdk = HiFaceSdk.create(context);
    this.sdk = sdk;
    try {
      const ready = await sdk.whenReady();
      if (this.sdk !== sdk) {
        return;
      }
      if (ready.isFailure()) {
        this.status = String(ready.requireError().code);
        return;
      }
      const image = new RgbaImage(new ArrayBuffer(256 * 256 * 4), 256, 256);
      const result = await sdk.capture().extractFeature(image);
      if (this.sdk === sdk) {
        this.status = result.isSuccess() ? 'Feature extracted' : String(result.requireError().code);
      }
    } finally {
      if (this.sdk === sdk) {
        this.closeSdk();
      }
    }
  }

  private closeSdk(): void {
    this.sdk?.close();
    this.sdk = undefined;
  }

  aboutToDisappear(): void {
    this.closeSdk();
  }

  build() {
    Column() {
      Button('Run HiFace').onClick(() => { this.extractFeature(); })
      Text(this.status)
    }
  }
}
```

`create(context)` 需要当前 `UIAbilityContext`，SDK 不创建相机或申请权限。实时页面用普通字段持有同一实例，不放进 `@State`。`whenReady()` 必须检查 `isSuccess()`；重复调用等待同一初始化结果，初始化失败时先修复原因，再关闭旧实例并重新创建。

## API 参考

### 人脸检测

调用 `sdk.processFrame(frame, config)` / `sdk.processRgba(image, config)`。成功返回人脸框、置信度和关键点，无人脸时返回空列表。坐标以旋转后、未镜像的画面为准。

| `FaceDetectionConfig` 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `maxFaces` | 1–10，默认 1 | 限制返回的人脸数。 |
| `detailedLandmarks` | 布尔值，默认关闭 | 开启后附带详细轮廓和头部角度。 |

相机分析帧要求偶数宽高，长边不超过 1920、短边不超过 1080，旋转为 0°、90°、180° 或 270°。
相机帧填写实际 Y/U/V 步长、色彩范围和矩阵及旋转角度。Promise 完成前保持缓冲区有效。每路相机使用一个 `createRealtimeProcessor()`，`tryProcessFrame()` 返回 `undefined` 时丢弃本帧。

`YuvPlane.rowStride` 和 `pixelStride` 为正整数字节数，Y 的像素步长须为 1，U/V 的像素步长须相同。`range` 为 `VIDEO` / `FULL`，`matrix` 为 `BT601` / `BT709`，按实际采集元数据设置。`mirrored` 不负责镜像预览。`headPose` 与 `mesh` 即使开启详细关键点仍可能为 `undefined`，须分别检查。

`tryProcessFrame()` 返回 `undefined` 表示未接受，可立即释放本帧；返回 Promise 后须等待完成再释放，即使结果为 `NOT_READY`。处理器 `close()` 只停止该处理器接收新帧，不会中断在途 Promise，也不会关闭 SDK 或相机。

### 人脸录入与照片采集

| 接口 | 返回结果 |
|---|---|
| `await sdk.capture().extractFeature(image)` | 提取最大人脸的特征，无人脸返回 `IMAGE_NO_FACE`，人脸宽或高不足 100 像素返回 `IMAGE_FACE_TOO_SMALL`。 |
| `await sdk.capture().fromRgba(image)` | 返回 `feature` 和可选对齐预览 `alignedRgba`。应用确认录入后再保存特征。 |
| `await sdk.capture().facesFromRgba(image)` | 返回最多 10 张脸的位置及各自的采集结果。没有人脸时成功返回空列表，小脸只影响对应条目。 |
| `capture().startCameraCapture(listener)` | 引导用户采集人脸，通过回调交付结果。启动时先等待 Promise，成功后保留 `FaceRequest`。 |

照片调用前先处理图像方向。每个 SDK 的静态队列可同时处理一个任务，另有四个等待名额。批量处理时逐张提交。照片接口无需相机权限，无活体判定。

`RgbaImage` 表示连续 RGBA8888，`data` 至少有 `width * height * 4` 字节。构造图片对象不复制像素；提交到静态图片接口后，SDK 会在返回 Promise 前固定输入快照。严格单人录入须确认 `facesFromRgba` 恰好一条且该条 `capture.isSuccess()`；最大脸接口不会拒绝多人照片。`alignedRgba` 是 RGBA 字节而非 `PixelMap`，显示时使用 `alignedSide` 作为宽、高。

### 活体与 1:1 验证

分别使用 `liveness().startCameraLiveness(config, listener)` 和 `verification().startCameraVerification(config, listener)` 启动流程，再持续送入相机帧。已有两份特征时，`verification().compare(left, right)` 返回 0–1 的相似度。相似度仅反映特征接近程度。

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `referenceFeature` | 1:1 验证必填 | 传入已录入的人脸特征。 |
| `threshold` | 建议 0.75–0.85，默认 0.80 | 1:1 相似度门槛。低于门槛时，完成比对的流程返回身份不匹配。 |
| `actions` | 0–4 步，默认空 | 活体接口空动作时执行静默活体。 |
| `silentLivenessEnabled` | 布尔值，1:1 验证默认关闭 | 开启后还要求静默活体通过。 |
| `allowMultipleFaces` | 布尔值，默认关闭 | 控制流程是否允许画面中出现多人。 |
| `actionTimeoutMillis` | 2,000–30,000 ms，默认 3,000 ms | 每步动作时限。 |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms，默认 10,000 ms | 首次取脸时限。 |

`actions` 按顺序执行，允许重复，支持 `SHAKE_HEAD`、`NOD_HEAD`、`BLINK`、`MOUTH_OPEN`。1:1 动作为空且 `silentLivenessEnabled=false` 时只验证身份，不包含活体。`FaceFlowResult.isPassed()` 表示通过；未产生的 `similarity`、`livenessScore` 为 `undefined`，不能当作 0。对齐图与 `frameJpeg` 均可缺失，`frameWidth` / `frameHeight` 是 JPEG 像素尺寸，无图为 0。

相似度建议范围为 0.75–0.85，默认配置值为 0.80；1:1 验证和按特征查库的 API 实际允许 0–1，相机连续搜索仅允许 0.75–0.85。

RGB/IR 活体建议门槛为 0.80–0.99，建议值为 0.90。当前 RGB 静默活体固定使用 0.90，未开放门槛设置；IR 门槛须显式传入，没有隐式默认值。活体和验证的 `onResult` 会交付通过或拒绝的结果，先读 `outcome`。只有本轮执行了对应步骤才会返回相似度或活体分数。独立近红外活体使用 `await sdk.liveness().evaluateInfrared(frame, threshold)`，传入真实 GRAY8 红外帧、图中人脸框和按设备标定的阈值（建议 0.80–0.99，初始值 0.90，API 实际允许大于 0 且不超过 1）。阈值必填。

等待启动接口返回成功的 `HiFaceResult<FaceRequest>` 后继续送帧。

### 人脸库与搜索

用 `await HiFaceSdk.openSearchDatabase(context)` 打开独立人脸库。通过 `saveFeature` 或 `saveFeatures` 按 Face ID 新增或更新，单批可保存 1–1,000 条。用 `search` 按特征查库。`list` / `listRecent` 返回元数据，`listFeatures` 分页读取含特征的记录。由调用方关闭显式打开的人脸库。等待写入完成再关闭人脸库。

单库最多 50,000 条。批量保存全部成功或全部回滚，重复 ID 以本批最后一条为准。`contains` 返回是否存在，`get` 不存在时返回 `NOT_FOUND`，`delete` 返回是否实际删除。

分页 `offset` 为 0–2,147,483,647，默认 0；`limit` 为 1–1,000，默认 100。`list` / `listFeatures` 按 Face ID 排序，`listRecent` 按更新时间倒序。`updateTimeMillis` 为非负安全整数的 Unix 毫秒时间，默认 0 使用当前时间。`updateMetadata` 传 `undefined` 保留分组或标签，空串清空，至少指定一项。独立连接须由调用方 `close()`，SDK 关闭不代替该操作。

**人脸记录与筛选**

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| Face ID | 必填，1–1024 个 UTF-8 字节，不允许 NUL，无默认值 | 应用指定的记录标识。保存相同 ID 会更新该记录；不是分组或标签筛选条件。 |
| `group` | 可选，最多 1024 个 UTF-8 字节，不允许 NUL；默认不筛选 | 人脸所属分组。查询时精确匹配该分组，空串表示不限分组。 |
| `tag` | 可选，最多 1024 个 UTF-8 字节，不允许 NUL；默认不筛选 | 应用自定义的业务标签。查询时精确匹配该标签，空串表示不限标签。 |

同时指定分组和标签时，两项都必须匹配；均不指定时搜索全库。

**按已有特征查库（`FaceSearchConfig`）**

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `topK` | 1–100，默认 1 | 最多返回的匹配数。 |
| `threshold` | 建议 0.75–0.85，默认 0.80 | 仅用于按已有特征查库。返回相似度达到门槛的记录，无匹配时返回空列表；相机连续搜索使用下表的范围。 |

连续搜索使用 `search().startCameraSearch(config, listener)`，它自行管理人脸库连接。

| 连续搜索参数 | 范围与默认值 | 用途 |
|---|---|---|
| `mode` | `SINGLE_FACE` / `MULTI_FACE`，默认 `SINGLE_FACE` | 单人模式只处理最大人脸；多人模式按 `maxFacesPerFrame` 限制处理人数。 |
| `needsLiveness` | `true` / `false`；单人默认 `true`，多人默认 `false` | 是否开启 RGB 静默活体；多人模式不能设为 `true`。 |
| `threshold` | 0.75–0.85（含端点），默认 0.80 | 相机连续搜索的身份匹配门槛；相似度大于等于该值才算身份匹配，活体仍须单独通过。 |
| `searchIntervalMillis` | 0–3,000 ms，默认 0 | 匹配成功后到下一轮的间隔。 |
| `searchTimeoutMillis` | 1,000–3,000 ms，默认 3,000 ms | 从首次选中人脸开始计算的单轮时限。 |
| `maxFacesPerFrame` | 1–5，默认 3 | 多人模式处理上限。单人模式仅处理最大脸。 |

启动流程和搜索均须先等待 Promise、检查结果，再保存 `FaceRequest` 或 `FaceSearchSession`。等待中页面可能已退出；成功返回后仍须确认页面/SDK 有效，否则立即取消或关闭返回句柄。搜索的 `pause()` 保留流程占用，切换功能前应 `close()`；`setConfig()` 更新配置并作废旧结果，`resume()` 恢复。`onFrame` 用于显示，业务读取 `onResult`；运行中的技术错误会暂停会话，修复后再恢复。

先看 `endReason`。即使达到相似度门槛，`SPOOF_DETECTED` 也表示拒绝。`frameId` 标识同一次采样。`frameJpeg` 是可选的结束帧整图，绘制人脸框时按原始帧尺寸换算。

人脸特征应原样保存。更换为不兼容的模型时，从原照片重新提取并导入。应用负责取得用户同意，以及保护和删除照片和特征。

等待启动接口返回成功的 `HiFaceResult<FaceSearchSession>`，用该会话暂停、恢复或关闭搜索。

## 错误处理与资源释放

创建后等待 `whenReady()`。通过 `HiFaceResult.isSuccess()` 判断后再读取 `requireValue()` 或 `requireError().code`。构造参数无效会抛出 `Error`。使用普通字段持有 SDK，页面退出时调用 `close()`。

| 情况 | 处理方式 |
|---|---|
| `NOT_READY` | 模型初始化、运行时正忙或相机跳帧时，丢弃当前帧，继续送入最新帧。 |
| `BUSY` | 等静态任务完成，或先结束当前相机流程。 |
| `INVALID_ARGUMENT` | 检查参数、帧格式与缓冲区。 |
| `LICENSE_EXPIRED` | 核对授权有效期，必要时联系 SDK 支持。 |
| `CLOSED` | 停止向此实例继续提交任务。 |
| `RESOURCE_EXHAUSTED` | 减少并发任务并检查内存、磁盘和容量，处理后再重试。 |
| `DATABASE_ERROR` | 检查人脸库路径、权限及存储状态；保留原数据，避免自动删库。 |
| `INTERNAL_ERROR` | 停止本次请求，记录 SDK 版本及错误码并联系支持。 |

采集、活体、验证和连续搜索共用一个相机流程槽。切换功能或退出页面时，先停止送帧，再取消请求或关闭搜索，然后关闭 SDK。`onError` 用于技术失败，业务结果读取对应结论。

YUV 输入保留到送帧 Promise 完成；静态 RGBA 的快照时机见上文。相机 `FaceRequest.cancel()` 只取消 SDK 流程，不释放 CameraKit、预览或帧缓冲；静态任务返回 Promise，不提供取消句柄，页面须丢弃过期结果。退出时先停止送帧、取消/关闭流程及处理器，等待已提交帧完成后释放相机资源；关闭 SDK，独立人脸库另行关闭。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。室外人脸搜索使用宽动态范围大于 100 dB 的相机。
